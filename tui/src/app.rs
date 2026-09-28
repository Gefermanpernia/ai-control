use crate::status::Status;
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Loading {
    Status,
    Usage,
}

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Key {
    Up,
    Down,
    Tab,
    Enter,
    Esc,
    Backspace,
    Char(char),
    /// Ctrl+C: raw mode delivers it as a key instead of a signal.
    Interrupt,
}
/// Maps a terminal key event to the keys the UI handles.
pub fn key_from(event: KeyEvent) -> Option<Key> {
    match event.code {
        KeyCode::Char('c') if event.modifiers.contains(KeyModifiers::CONTROL) => {
            Some(Key::Interrupt)
        }
        KeyCode::Up => Some(Key::Up),
        KeyCode::Down => Some(Key::Down),
        KeyCode::Tab => Some(Key::Tab),
        KeyCode::Enter => Some(Key::Enter),
        KeyCode::Esc => Some(Key::Esc),
        KeyCode::Backspace => Some(Key::Backspace),
        KeyCode::Char(c) => Some(Key::Char(c)),
        _ => None,
    }
}
#[derive(Debug, PartialEq, Eq)]
pub enum Effect {
    None,
    Quit,
    Reload,
    Action {
        provider: &'static str,
        verb: &'static str,
        alias: String,
        extra: Option<String>,
    },
    /// Any other engine command; `verb` names it for the "working" message.
    Engine {
        args: Vec<String>,
        verb: &'static str,
    },
}
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Mode {
    Normal,
    Confirm,
    Rename,
    Save,
    AddAlias,
    AddEmail,
    /// The options screen; every change goes through `AIControl settings set`.
    Options,
    /// A number for the chosen option (refresh interval in minutes, switch threshold in percent).
    OptionInput,
    /// Turning automatic switching on, which needs the user to accept the provider-terms risk.
    ConfirmRisk,
}
/// The rows of the options screen, in display order.
pub const OPTION_COUNT: usize = 6;
pub struct App {
    pub status: Status,
    pub provider: usize,
    pub positions: [usize; 2],
    pub mode: Mode,
    pub target: Option<String>,
    pub input: String,
    pub pending_alias: String,
    pub message: String,
    pub action_success: Option<bool>,
    pub loading: Option<Loading>,
    pub status_loaded: bool,
    /// The last status read failed, so an unavailable provider may only mean the status is unknown.
    pub status_failed: bool,
    pub updated: Option<time::OffsetDateTime>,
    /// When the last usage load started, successful or not; periodic refresh counts from here.
    pub usage_requested: Option<time::OffsetDateTime>,
    /// A switch, rename, save or sign-in is running; nothing else may start meanwhile.
    pub action_running: bool,
    /// A usage load showed an account in use at its switch threshold; the engine check runs once, when idle.
    pub check_pending: bool,
    /// The chosen row of the options screen.
    pub option: usize,
    /// The engine arguments waiting for the risk confirmation.
    pending_setting: Option<Vec<String>>,
}
impl App {
    pub fn new(status: Status) -> Self {
        let mut app = Self {
            status,
            provider: 0,
            positions: [0; 2],
            mode: Mode::Normal,
            target: None,
            input: String::new(),
            pending_alias: String::new(),
            message: String::new(),
            action_success: None,
            loading: None,
            status_loaded: true,
            status_failed: false,
            updated: None,
            usage_requested: None,
            action_running: false,
            check_pending: false,
            option: 0,
            pending_setting: None,
        };
        app.status = in_priority_order(app.status);
        app.provider = app.visible().first().copied().unwrap_or(0);
        app
    }
    /// Providers to show: those whose CLI is installed or that have saved logins. Both show until a
    /// status was read, so a failed read never hides anything.
    pub fn visible(&self) -> Vec<usize> {
        if !self.status_loaded || self.status_failed {
            return vec![0, 1];
        }
        let claude = &self.status.claude;
        let codex = &self.status.codex;
        [
            (0, claude.installed || !claude.logins.is_empty()),
            (1, codex.installed || !codex.logins.is_empty()),
        ]
        .into_iter()
        .filter_map(|(provider, shown)| shown.then_some(provider))
        .collect()
    }
    pub fn name(&self) -> Option<&str> {
        if self.provider == 0 {
            self.status
                .claude
                .logins
                .get(self.positions[0])
                .map(|l| l.name.as_str())
        } else {
            self.status
                .codex
                .logins
                .get(self.positions[1])
                .map(|l| l.name.as_str())
        }
    }
    fn target_exists(&self) -> bool {
        self.target.as_deref().is_some_and(|name| {
            (self.provider == 0 && self.status.claude.logins.iter().any(|l| l.name == name))
                || (self.provider == 1 && self.status.codex.logins.iter().any(|l| l.name == name))
        })
    }
    pub fn provider_command(&self) -> &'static str {
        if self.provider == 0 {
            "claude-login"
        } else {
            "codex-login"
        }
    }
    pub fn start_action(&mut self, verb: &str) {
        self.message = match verb {
            "use" => "Switching…",
            "rename" => "Renaming…",
            "save" => "Saving…",
            "order" => "Reordering…",
            "check" => "Checking accounts…",
            _ => "Working…",
        }
        .into();
        self.action_success = None;
        self.action_running = true;
    }
    pub fn result(&mut self, text: &str, success: bool) {
        self.action_running = false;
        self.message = text.into();
        self.action_success = Some(success);
        self.mode = Mode::Normal;
        self.target = None;
        self.input.clear();
    }
    /// Automatic switching is decided by the engine; the UI only asks for a check when fresh usage shows an
    /// account in use at or above the threshold on any window, so idle checks never refetch usage.
    pub fn switch_check_due(&self) -> bool {
        self.check_pending
            && self.mode == Mode::Normal
            && !self.action_running
            && self.loading.is_none()
    }
    pub fn start_switch_check(&mut self) {
        self.check_pending = false;
        self.start_action("check");
    }
    /// Shows what the engine did for providers with switching on.
    pub fn switch_check_result(&mut self, lines: &[String], success: bool) {
        let shown: Vec<&str> = lines
            .iter()
            .map(String::as_str)
            .filter(|line| !line.ends_with("automatic switching is off."))
            .collect();
        self.result(&shown.join(" · "), success);
    }
    /// Shows the outcome of an `Effect::Engine` command; a settings change keeps the options screen open.
    pub fn engine_result(&mut self, verb: &str, lines: &[String], success: bool) {
        let text = match (verb, success) {
            ("order", true) => "Priority order saved.".to_string(),
            (_, _) if lines.is_empty() => {
                if success { "Done." } else { "Not changed." }.to_string()
            }
            ("settings", _) => lines.join(" · "),
            _ => lines.last().cloned().unwrap_or_default(),
        };
        self.result(&text, success);
        if verb == "settings" {
            self.mode = Mode::Options;
        }
    }
    fn settings_set(key: &str, value: String) -> Effect {
        Effect::Engine {
            args: vec!["settings".into(), "set".into(), key.into(), value],
            verb: "settings",
        }
    }
    /// Enter on an options row: toggles flip through the engine, numbers open a prompt, and turning automatic
    /// switching on waits for the risk confirmation.
    fn choose_option(&mut self) -> Effect {
        let settings = &self.status.settings;
        let flip = |on: bool| if on { "off" } else { "on" }.to_string();
        match self.option {
            0 => Self::settings_set("refresh", flip(settings.refresh.enabled)),
            2 | 3 => {
                let (key, on) = if self.option == 2 {
                    ("auto-switch-claude", settings.auto_switch.claude)
                } else {
                    ("auto-switch-codex", settings.auto_switch.codex)
                };
                if on {
                    return Self::settings_set(key, "off".into());
                }
                self.pending_setting = Some(vec![
                    "settings".into(),
                    "set".into(),
                    key.into(),
                    "on".into(),
                ]);
                self.mode = Mode::ConfirmRisk;
                self.message = "Providers may treat rotating accounts to get around usage limits as abuse and \
                                suspend them. Turn automatic switching on? y/n"
                    .into();
                self.action_success = None;
                Effect::None
            }
            5 => Self::settings_set("background-refresh", flip(settings.auto_switch.background)),
            _ => {
                self.mode = Mode::OptionInput;
                self.input.clear();
                self.message.clear();
                Effect::None
            }
        }
    }
    /// A numeric option: the engine validates again, this only gives early feedback.
    fn submit_option_input(&mut self) -> Effect {
        let value: Option<i64> = self.input.trim().parse().ok();
        if self.option == 1 {
            match value {
                Some(minutes) if minutes >= 5 => {
                    self.input.clear();
                    Self::settings_set("refresh-interval", (minutes * 60).to_string())
                }
                _ => {
                    self.message = "Not saved: whole minutes, 5 or more.".into();
                    Effect::None
                }
            }
        } else {
            match value {
                Some(percent) if (50..=100).contains(&percent) => {
                    self.input.clear();
                    Self::settings_set("auto-switch-threshold", percent.to_string())
                }
                _ => {
                    self.message = "Not saved: a whole percentage from 50 to 100.".into();
                    Effect::None
                }
            }
        }
    }
    fn at_threshold(&self) -> bool {
        let settings = &self.status.settings.auto_switch;
        let threshold = settings.threshold_percent as f64;
        let spent = |usage: Option<&crate::status::Usage>| {
            usage.is_some_and(|usage| usage.windows.iter().any(|w| w.used_percent >= threshold))
        };
        let claude = &self.status.claude;
        let codex = &self.status.codex;
        (settings.claude
            && spent(
                claude
                    .logins
                    .iter()
                    .find(|l| Some(&l.name) == claude.selected.as_ref())
                    .and_then(|l| l.usage.as_ref()),
            ))
            || (settings.codex
                && spent(
                    codex
                        .logins
                        .iter()
                        .find(|l| Some(&l.name) == codex.in_use.as_ref())
                        .and_then(|l| l.usage.as_ref()),
                ))
    }
    /// Marks a usage load as started, for the loading state and the refresh timer.
    pub fn start_usage_load(&mut self, now: time::OffsetDateTime) {
        self.loading = Some(Loading::Usage);
        self.usage_requested = Some(now);
    }
    /// Periodic refresh: only when the engine settings enable it, a full interval after the last usage load,
    /// and never while something loads, an action runs, or the user is answering a prompt.
    pub fn refresh_due(&self, now: time::OffsetDateTime) -> bool {
        let refresh = &self.status.settings.refresh;
        if !refresh.enabled
            || self.loading.is_some()
            || self.mode != Mode::Normal
            || self.action_running
        {
            return false;
        }
        let interval = time::Duration::seconds(
            refresh
                .interval_seconds
                .max(crate::status::minimum_interval()),
        );
        self.usage_requested
            .is_none_or(|last| now - last >= interval)
    }
    pub fn status_error(&mut self, error: &str) {
        self.loading = None;
        self.status_loaded = true;
        // After a good read, a failed refresh keeps the last status on screen with its age.
        self.status_failed = self.updated.is_none();
        self.message = error.into();
        self.action_success = Some(false);
    }
    pub fn apply_status(&mut self, status: Status, with_usage: bool) {
        let mut status = in_priority_order(status);
        if !with_usage {
            for login in &mut status.claude.logins {
                if let Some(previous) = self
                    .status
                    .claude
                    .logins
                    .iter()
                    .find(|old| old.name == login.name)
                {
                    login.usage = previous.usage.clone();
                    login.usage_error = previous.usage_error.clone();
                }
            }
            for login in &mut status.codex.logins {
                if let Some(previous) = self
                    .status
                    .codex
                    .logins
                    .iter()
                    .find(|old| old.name == login.name)
                {
                    login.usage = previous.usage.clone();
                    login.usage_error = previous.usage_error.clone();
                }
            }
            for monitor in &mut status.monitors {
                if let Some(previous) = self.status.monitors.iter().find(|old| old.id == monitor.id)
                {
                    monitor.usage = previous.usage.clone();
                    monitor.models = previous.models.clone();
                    monitor.error = previous.error.clone();
                }
            }
        }
        fn follow<T>(old: &[T], new: &[T], index: usize, name: impl Fn(&T) -> &str) -> usize {
            let selected = old.get(index).map(&name);
            new.iter()
                .position(|login| Some(name(login)) == selected)
                .unwrap_or(index.min(new.len().saturating_sub(1)))
        }
        self.positions[0] = follow(
            &self.status.claude.logins,
            &status.claude.logins,
            self.positions[0],
            |l| &l.name,
        );
        self.positions[1] = follow(
            &self.status.codex.logins,
            &status.codex.logins,
            self.positions[1],
            |l| &l.name,
        );
        self.status = status;
        self.status_loaded = true;
        self.status_failed = false;
        let visible = self.visible();
        if !visible.contains(&self.provider) {
            self.provider = visible.first().copied().unwrap_or(0);
        }
        self.loading = None;
        self.updated = Some(time::OffsetDateTime::now_utc());
        if with_usage {
            self.check_pending = self.at_threshold();
        }
    }
    pub fn key(&mut self, key: Key) -> Effect {
        if key == Key::Interrupt {
            return Effect::Quit;
        }
        match self.mode {
            Mode::Options => match key {
                Key::Esc | Key::Char('o') | Key::Char('q') => {
                    self.mode = Mode::Normal;
                    self.message.clear();
                }
                Key::Up | Key::Char('k') => self.option = self.option.saturating_sub(1),
                Key::Down | Key::Char('j') => self.option = (self.option + 1).min(OPTION_COUNT - 1),
                Key::Enter | Key::Char(' ') => return self.choose_option(),
                _ => {}
            },
            Mode::OptionInput => match key {
                Key::Esc => {
                    self.mode = Mode::Options;
                    self.input.clear();
                }
                Key::Backspace => {
                    self.input.pop();
                }
                Key::Char(c) if c.is_ascii_digit() => self.input.push(c),
                Key::Enter => {
                    let effect = self.submit_option_input();
                    if effect != Effect::None {
                        self.mode = Mode::Options;
                    }
                    return effect;
                }
                _ => {}
            },
            Mode::ConfirmRisk => {
                self.mode = Mode::Options;
                let pending = self.pending_setting.take();
                if key == Key::Char('y') {
                    if let Some(args) = pending {
                        return Effect::Engine {
                            args,
                            verb: "settings",
                        };
                    }
                }
                self.message = "Not changed.".into();
                self.action_success = None;
            }
            Mode::Confirm => {
                self.mode = Mode::Normal;
                if key == Key::Char('y') {
                    if !self.target_exists() {
                        self.message = "That login is no longer saved.".into();
                        self.action_success = Some(false);
                    } else {
                        return Effect::Action {
                            provider: self.provider_command(),
                            verb: "use",
                            alias: self.target.take().unwrap(),
                            extra: None,
                        };
                    }
                }
                self.target = None;
            }
            Mode::Rename | Mode::Save | Mode::AddAlias | Mode::AddEmail => match key {
                Key::Esc => {
                    self.mode = Mode::Normal;
                    self.target = None;
                    self.input.clear();
                }
                Key::Backspace => {
                    self.input.pop();
                }
                Key::Char(c) if !c.is_control() => {
                    self.input.push(c);
                }
                Key::Enter => {
                    if self.mode != Mode::AddEmail && !valid_alias(&self.input) {
                        self.message =
                            "Invalid alias: use lowercase a-z, digits, _ or - (1–32 chars)".into();
                    } else if self.mode == Mode::AddAlias && self.provider == 0 {
                        self.pending_alias = std::mem::take(&mut self.input);
                        self.mode = Mode::AddEmail;
                        self.message = "Email (optional; Enter to skip):".into();
                    } else {
                        if self.mode == Mode::Rename && !self.target_exists() {
                            self.mode = Mode::Normal;
                            self.target = None;
                            self.input.clear();
                            self.message = "That login is no longer saved.".into();
                            self.action_success = Some(false);
                            return Effect::None;
                        }
                        let provider = self.provider_command();
                        let (verb, alias, extra) = match self.mode {
                            Mode::Rename => (
                                "rename",
                                self.target.take().unwrap(),
                                Some(self.input.clone()),
                            ),
                            Mode::Save => ("save", self.input.clone(), None),
                            Mode::AddAlias => ("add", self.input.clone(), None),
                            _ => (
                                "add",
                                self.pending_alias.clone(),
                                if self.input.trim().is_empty() {
                                    None
                                } else {
                                    Some(self.input.trim().into())
                                },
                            ),
                        };
                        self.mode = Mode::Normal;
                        self.input.clear();
                        return Effect::Action {
                            provider,
                            verb,
                            alias,
                            extra,
                        };
                    }
                }
                _ => {}
            },
            Mode::Normal => match key {
                Key::Char('q') | Key::Esc => return Effect::Quit,
                Key::Char('r') => return Effect::Reload,
                Key::Char('o') => {
                    self.mode = Mode::Options;
                    self.message.clear();
                }
                // Without a visible provider there is no account to switch, rename or add.
                _ if self.visible().is_empty() => {}
                Key::Tab => {
                    if self.visible().len() == 2 {
                        self.provider = 1 - self.provider;
                    }
                }
                Key::Up | Key::Char('k') => {
                    self.positions[self.provider] = self.positions[self.provider].saturating_sub(1)
                }
                Key::Down | Key::Char('j') => {
                    let len = if self.provider == 0 {
                        self.status.claude.logins.len()
                    } else {
                        self.status.codex.logins.len()
                    };
                    self.positions[self.provider] =
                        (self.positions[self.provider] + 1).min(len.saturating_sub(1));
                }
                Key::Enter | Key::Char('n') if self.name().is_some() => {
                    self.target = self.name().map(str::to_owned);
                    self.mode = if key == Key::Enter {
                        Mode::Confirm
                    } else {
                        Mode::Rename
                    };
                    self.input.clear();
                }
                Key::Char(c @ ('K' | 'J')) if self.name().is_some() => {
                    return Effect::Engine {
                        args: vec![
                            "auto-switch".into(),
                            "move".into(),
                            if self.provider == 0 {
                                "claude"
                            } else {
                                "codex"
                            }
                            .into(),
                            self.name().unwrap().into(),
                            if c == 'K' { "up" } else { "down" }.into(),
                        ],
                        verb: "order",
                    };
                }
                Key::Char('s') => {
                    self.mode = Mode::Save;
                    self.input.clear();
                }
                Key::Char('a') => {
                    self.mode = Mode::AddAlias;
                    self.input.clear();
                }
                _ => {}
            },
        }
        Effect::None
    }
}
/// Lists saved accounts in the engine's priority order: listed names first, the rest in engine order.
fn in_priority_order(mut status: Status) -> Status {
    fn sort<T>(logins: &mut [T], order: &[String], name: impl Fn(&T) -> &str) {
        let rank = |login: &T| {
            order
                .iter()
                .position(|n| n == name(login))
                .unwrap_or(order.len())
        };
        logins.sort_by_key(|login| rank(login));
    }
    let settings = status.settings.auto_switch.clone();
    sort(&mut status.claude.logins, &settings.claude_order, |l| {
        &l.name
    });
    sort(&mut status.codex.logins, &settings.codex_order, |l| &l.name);
    status
}
pub fn valid_alias(alias: &str) -> bool {
    let bytes = alias.as_bytes();
    (1..=32).contains(&bytes.len())
        && bytes[0].is_ascii_lowercase()
        && bytes[1..]
            .iter()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || *b == b'_' || *b == b'-')
}
