use aic_tui::{
    app::{key_from, App, Effect, Loading},
    engine::{engine_path, Engine, ProcessRunner, SubprocessEngine},
    status::Status,
    ui,
};
use crossterm::{
    event::{self, Event, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::{
    collections::HashMap,
    io::{self, stdout},
    sync::mpsc,
    time::Duration,
};

type Client = SubprocessEngine<ProcessRunner>;
fn client() -> Client {
    let env: HashMap<String, String> = std::env::vars().collect();
    let exe = std::env::current_exe().unwrap_or_default();
    SubprocessEngine::new(engine_path(&exe, &env), ProcessRunner)
}
fn restore() {
    let _ = disable_raw_mode();
    let _ = execute!(stdout(), LeaveAlternateScreen);
}
struct Screen;
impl Screen {
    fn enter() -> io::Result<Self> {
        enable_raw_mode()?;
        if let Err(e) = execute!(stdout(), EnterAlternateScreen) {
            let _ = disable_raw_mode();
            return Err(e);
        }
        Ok(Self)
    }
}
impl Drop for Screen {
    fn drop(&mut self) {
        restore();
    }
}
fn initial() -> Status {
    // Empty, unavailable snapshot until the background fetch completes.
    aic_tui::status::parse(r#"{"version":1,"claude":{"available":false,"selected":null,"logins":[]},"codex":{"available":false,"inUse":null,"logins":[]}}"#).expect("static status")
}
fn spawn_status(tx: mpsc::Sender<(u64, Result<Status, String>)>, revision: u64, usage: bool) {
    std::thread::spawn(move || {
        let _ = tx.send((revision, client().status(usage)));
    });
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    if std::env::args().any(|a| a == "--help") {
        println!("aic-tui — terminal presenter for AIControl\nUsage: aic-tui [--help]\nAIC_ENGINE overrides the engine executable. Usage loads at startup and on r only.");
        return Ok(());
    }
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        restore();
        previous(info);
    }));
    let mut screen = Screen::enter()?;
    let mut terminal = Terminal::new(CrosstermBackend::new(stdout()))?;
    let mut app = App::new(initial());
    let (tx, rx) = mpsc::channel();
    app.status_loaded = false;
    app.start_usage_load(time::OffsetDateTime::now_utc());
    let mut revision = 1;
    spawn_status(tx.clone(), revision, true);
    loop {
        terminal.draw(|f| ui::draw(f, &app))?;
        while let Ok((received, result)) = rx.try_recv() {
            if received != revision {
                continue;
            }
            match result {
                Ok(status) => app.apply_status(status, app.loading == Some(Loading::Usage)),
                Err(error) => app.status_error(&error),
            }
        }
        if app.switch_check_due() {
            // The engine decides and switches through its guarded commands; the UI only shows the outcome.
            app.start_switch_check();
            terminal.draw(|f| ui::draw(f, &app))?;
            match client().lines(&["auto-switch".into(), "check".into()]) {
                Ok((lines, success)) => app.switch_check_result(&lines, success),
                Err(error) => app.result(&error, false),
            }
            app.loading = Some(Loading::Status);
            revision += 1;
            spawn_status(tx.clone(), revision, false);
            continue;
        }
        if !event::poll(Duration::from_millis(100))? {
            let now = time::OffsetDateTime::now_utc();
            if app.refresh_due(now) {
                app.start_usage_load(now);
                revision += 1;
                spawn_status(tx.clone(), revision, true);
            }
            continue;
        }
        let Event::Key(event) = event::read()? else {
            continue;
        };
        if event.kind != KeyEventKind::Press {
            continue;
        }
        let Some(key) = key_from(event) else { continue };
        match app.key(key) {
            Effect::None => {}
            Effect::Quit => break,
            Effect::Reload => {
                app.start_usage_load(time::OffsetDateTime::now_utc());
                revision += 1;
                spawn_status(tx.clone(), revision, true);
            }
            Effect::Engine { args, verb } => {
                app.start_action(verb);
                terminal.draw(|f| ui::draw(f, &app))?;
                match client().lines(&args) {
                    // `move` prints the new order; a short confirmation is enough on screen.
                    Ok((_, true)) => app.result("Priority order saved.", true),
                    Ok((lines, false)) => {
                        app.result(lines.last().map_or("Not changed.", |l| l), false)
                    }
                    Err(error) => app.result(&error, false),
                }
                app.loading = Some(Loading::Status);
                revision += 1;
                spawn_status(tx.clone(), revision, false);
            }
            Effect::Action {
                provider,
                verb,
                alias,
                extra,
            } => {
                if verb != "add" {
                    app.start_action(verb);
                    terminal.draw(|f| ui::draw(f, &app))?;
                }
                let result = if verb == "add" {
                    drop(terminal);
                    drop(screen);
                    let result = client().interactive_add(provider, &alias, extra.as_deref());
                    screen = Screen::enter()?;
                    terminal = Terminal::new(CrosstermBackend::new(stdout()))?;
                    result
                } else {
                    client().action(provider, verb, &alias, extra.as_deref())
                };
                match result {
                    Ok(outcome) => app.result(&outcome.message, outcome.success),
                    Err(error) => app.result(&error, false),
                }
                // Plain status after any action: never renew saved logins implicitly.
                app.loading = Some(Loading::Status);
                revision += 1;
                spawn_status(tx.clone(), revision, false);
            }
        }
    }
    Ok(())
}
