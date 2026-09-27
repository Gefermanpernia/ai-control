use crate::{
    app::{App, Loading, Mode},
    status::Usage,
};
use ratatui::{
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
    Frame,
};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

fn relative(timestamp: &str, now: OffsetDateTime) -> String {
    let Ok(date) = OffsetDateTime::parse(timestamp, &Rfc3339) else {
        return "?".into();
    };
    let seconds = (date - now).whole_seconds();
    if seconds <= 0 {
        "now".into()
    } else if seconds < 3600 {
        format!("{}m", (seconds + 59) / 60)
    } else if seconds < 86400 {
        format!("{}h", (seconds + 3599) / 3600)
    } else {
        format!("{}d", (seconds + 86399) / 86400)
    }
}
fn login_line(
    prefix: String,
    selected: bool,
    usage: Option<&Usage>,
    now: OffsetDateTime,
) -> Line<'static> {
    let mut spans = vec![Span::styled(
        prefix,
        if selected {
            Style::default().fg(Color::Cyan)
        } else {
            Style::default()
        },
    )];
    if let Some(usage) = usage {
        for window in &usage.windows {
            let pct = if window.used_percent.is_finite() {
                window.used_percent.clamp(0.0, 100.0)
            } else {
                0.0
            };
            let color = if pct >= 90.0 {
                Color::Red
            } else if pct >= 75.0 {
                Color::Yellow
            } else {
                Color::Green
            };
            let filled = (pct / 20.0).round() as usize;
            spans.push(Span::raw(format!("  {} ", window.label)));
            spans.push(Span::styled(
                format!(
                    "{}{} {:.0}%",
                    "█".repeat(filled),
                    "░".repeat(5 - filled),
                    pct
                ),
                Style::default().fg(color),
            ));
            if let Some(reset) = &window.resets_at {
                spans.push(Span::raw(format!(" ↻{}", relative(reset, now))));
            }
        }
        if let Some(count) = usage.resets_available {
            spans.push(Span::raw(format!("  {count} resets")));
        }
    }
    Line::from(spans)
}
fn rows(app: &App, provider: usize, now: OffsetDateTime) -> Vec<Line<'static>> {
    if !app.status_loaded {
        return vec![Line::from("Loading…")];
    }
    let mut lines = Vec::new();
    if provider == 0 {
        if !app.status.claude.available {
            return vec![Line::from(if app.status_failed {
                "Login status could not be read; see the message below"
            } else {
                "Unavailable: Claude login switching is off or unreadable"
            })];
        }
        for (i, l) in app.status.claude.logins.iter().enumerate() {
            let mark = if app.status.claude.selected.as_deref() == Some(&l.name) {
                "●"
            } else {
                " "
            };
            let selected = provider == app.provider && i == app.positions[0];
            let line = format!(
                "{} {} {}{}",
                if selected { ">" } else { " " },
                mark,
                l.name,
                if l.needs_login {
                    " · needs sign-in"
                } else {
                    ""
                }
            );
            lines.push(login_line(line, selected, l.usage.as_ref(), now));
            if let Some(error) = &l.usage_error {
                lines.push(Line::from(Span::styled(
                    format!("  {error}"),
                    Style::default().add_modifier(Modifier::DIM),
                )));
            }
        }
    } else {
        if !app.status.codex.available {
            return vec![Line::from(if app.status_failed {
                "Login status could not be read; see the message below"
            } else {
                "Unavailable: Codex login switching is off or unreadable"
            })];
        }
        for (i, l) in app.status.codex.logins.iter().enumerate() {
            let mark = if app.status.codex.in_use.as_deref() == Some(&l.name) {
                "●"
            } else {
                " "
            };
            let selected = provider == app.provider && i == app.positions[1];
            let line = format!(
                "{} {} {}{}",
                if selected { ">" } else { " " },
                mark,
                l.name,
                l.email
                    .as_ref()
                    .map(|e| format!(" · {e}"))
                    .unwrap_or_default()
            );
            lines.push(login_line(line, selected, l.usage.as_ref(), now));
            if let Some(error) = &l.usage_error {
                lines.push(Line::from(Span::styled(
                    format!("  {error}"),
                    Style::default().add_modifier(Modifier::DIM),
                )));
            }
        }
    }
    if lines.is_empty() {
        lines.push(Line::from(
            "No saved logins · s saves the account you are signed in to, a adds another",
        ));
    }
    lines
}
pub fn draw(frame: &mut Frame, app: &App) {
    draw_at(frame, app, OffsetDateTime::now_utc());
}
pub fn draw_at(frame: &mut Frame, app: &App, now: OffsetDateTime) {
    let size = frame.area();
    if size.width < 2 || size.height < 3 {
        return;
    }
    let footer_height = size.height.min(2);
    let available = size.height - footer_height;
    let visible = app.visible();
    let desired: Vec<u16> = visible
        .iter()
        .map(|&provider| {
            u16::try_from(rows(app, provider, now).len().saturating_add(2))
                .unwrap_or(u16::MAX)
                .max(3)
        })
        .collect();
    let mut heights = vec![0; visible.len()];
    match desired[..] {
        [only] => heights[0] = only.min(available),
        [first, second] => {
            heights[0] = first.min(available);
            if first.saturating_add(second) > available {
                heights[0] = (available / 2)
                    .max(available.saturating_sub(second))
                    .min(available.saturating_sub(2));
            }
            heights[1] = second.min(available - heights[0]);
        }
        _ => {
            let area = Rect::new(size.x, size.y, size.width, available.min(3));
            if area.height >= 2 {
                frame.render_widget(
                    Paragraph::new("Install Claude Code or the Codex CLI, then press r to reload.")
                        .block(Block::default().title("AI Control").borders(Borders::ALL)),
                    area,
                );
            }
        }
    }
    let mut top = size.y;
    for (slot, &i) in visible.iter().enumerate() {
        let area = Rect::new(size.x, top, size.width, heights[slot]);
        top += heights[slot];
        let title = ["Claude", "Codex"][i];
        if area.height < 2 {
            continue;
        }
        let border = if app.provider == i {
            Style::default().fg(Color::Cyan)
        } else {
            Style::default()
        };
        let selected_line = if i == 0 {
            app.status.claude.logins.get(app.positions[i]).map(|_| {
                app.status.claude.logins[..app.positions[i]]
                    .iter()
                    .map(|login| 1 + usize::from(login.usage_error.is_some()))
                    .sum::<usize>()
            })
        } else {
            app.status.codex.logins.get(app.positions[i]).map(|_| {
                app.status.codex.logins[..app.positions[i]]
                    .iter()
                    .map(|login| 1 + usize::from(login.usage_error.is_some()))
                    .sum::<usize>()
            })
        };
        let offset = selected_line
            .unwrap_or(0)
            .saturating_add(1)
            .saturating_sub(usize::from(area.height.saturating_sub(2)));
        frame.render_widget(
            Paragraph::new(rows(app, i, now))
                .scroll((u16::try_from(offset).unwrap_or(u16::MAX), 0))
                .block(
                    Block::default()
                        .title(title)
                        .borders(Borders::ALL)
                        .border_style(border),
                ),
            area,
        );
    }
    footer(
        frame,
        Rect::new(
            size.x,
            size.bottom() - footer_height,
            size.width,
            footer_height,
        ),
        app,
        now,
    );
}
fn footer(frame: &mut Frame, area: Rect, app: &App, now: OffsetDateTime) {
    let prompt = match app.mode {
        Mode::Normal => match app.loading {
            Some(Loading::Usage) => "Loading usage…".into(),
            Some(Loading::Status) if !app.message.is_empty() => {
                format!("Loading status… · {}", app.message)
            }
            Some(Loading::Status) => "Loading status…".into(),
            None => app.message.clone(),
        },
        Mode::Confirm => "Switch login? y/n".into(),
        Mode::Rename => format!("New alias: {}", app.input),
        Mode::Save => format!("Save current login as: {}", app.input),
        Mode::AddAlias => format!("Alias: {}", app.input),
        Mode::AddEmail => format!("Claude email (optional): {}", app.input),
    };
    let updated = app
        .updated
        .map(|loaded| {
            let elapsed = (now - loaded).whole_seconds().max(0);
            if elapsed < 60 {
                "just now".to_string()
            } else if elapsed < 3600 {
                format!("{} min ago", elapsed / 60)
            } else if elapsed < 86400 {
                format!("{} h ago", elapsed / 3600)
            } else {
                format!("{} d ago", elapsed / 86400)
            }
        })
        .unwrap_or_else(|| "not yet loaded".into());
    let style = if app.mode == Mode::Normal
        && app.loading != Some(Loading::Usage)
        && app.action_success == Some(false)
    {
        Style::default().fg(Color::Red)
    } else {
        Style::default()
    };
    frame.render_widget(Paragraph::new(vec![Line::from(format!("↑↓/jk move · Tab provider · Enter switch · n rename · s save · a add · r usage · q quit · updated {updated}")), Line::from(Span::styled(prompt, style))]), area);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{app::Loading, status::parse};
    use ratatui::{backend::TestBackend, buffer::Buffer, Terminal};

    fn rendered(app: &App, width: u16, height: u16, now: OffsetDateTime) -> Buffer {
        let mut terminal = Terminal::new(TestBackend::new(width, height)).unwrap();
        terminal.draw(|frame| draw_at(frame, app, now)).unwrap();
        terminal.backend().buffer().clone()
    }

    fn row(buffer: &Buffer, y: u16) -> String {
        (0..buffer.area.width)
            .map(|x| buffer[(x, y)].symbol())
            .collect()
    }

    #[test]
    fn marked_and_unmarked_names_align() {
        let status = parse(r#"{"version":1,"claude":{"available":true,"selected":"personal","logins":[{"name":"personal","needsLogin":false},{"name":"work","needsLogin":false}]},"codex":{"available":true,"inUse":"personal","logins":[{"name":"personal"},{"name":"work"}]} }"#).unwrap();
        let app = App::new(status);
        let buffer = rendered(&app, 120, 20, OffsetDateTime::UNIX_EPOCH);
        for (marked, unmarked) in [(1, 2), (5, 6)] {
            let marked = row(&buffer, marked);
            let unmarked = row(&buffer, unmarked);
            assert_eq!(
                marked.chars().position(|c| c == 'p'),
                unmarked.chars().position(|c| c == 'w')
            );
            assert!(marked.contains("● personal"));
        }
        assert!(row(&buffer, 1).contains("> ● personal"));
    }

    #[test]
    fn footer_uses_relative_successful_load_time() {
        let now = OffsetDateTime::UNIX_EPOCH + time::Duration::days(20);
        let mut app = App::new(parse(r#"{"version":1,"claude":{"available":false,"logins":[]},"codex":{"available":false,"logins":[]}}"#).unwrap());
        assert!(row(&rendered(&app, 120, 12, now), 10).contains("updated not yet loaded"));
        for (age, expected) in [
            (time::Duration::seconds(30), "updated just now"),
            (time::Duration::minutes(5), "updated 5 min ago"),
            (time::Duration::hours(3), "updated 3 h ago"),
            (time::Duration::days(2), "updated 2 d ago"),
        ] {
            app.updated = Some(now - age);
            assert!(
                row(&rendered(&app, 120, 12, now), 10).contains(expected),
                "{expected}"
            );
        }
    }

    #[test]
    fn usage_bars_and_percentages_keep_level_color_on_selected_row() {
        let status = parse(r#"{"version":1,"claude":{"available":true,"logins":[{"name":"levels","needsLogin":false,"usage":{"windows":[{"label":"a","usedPercent":74},{"label":"b","usedPercent":75},{"label":"c","usedPercent":89},{"label":"d","usedPercent":90}],"fetchedAt":"2026-01-01T00:00:00Z"}}]},"codex":{"available":false,"logins":[]}}"#).unwrap();
        let app = App::new(status);
        let buffer = rendered(&app, 120, 12, OffsetDateTime::UNIX_EPOCH);
        let line = row(&buffer, 1);
        let name = line.find("levels").unwrap() as u16;
        assert_eq!(buffer[(name, 1)].fg, Color::Cyan);
        for (label, percent, expected) in [
            ("a", "74%", Color::Green),
            ("b", "75%", Color::Yellow),
            ("c", "89%", Color::Yellow),
            ("d", "90%", Color::Red),
        ] {
            let start = line.find(&format!("{label} ")).unwrap() + 2;
            let bar_column = line[..start].chars().count() as u16;
            let pct_column = line[..line.find(percent).unwrap()].chars().count() as u16;
            assert_eq!(buffer[(bar_column, 1)].fg, expected, "{label} bar");
            assert_eq!(buffer[(pct_column, 1)].fg, expected, "{label} percentage");
        }
    }

    #[test]
    fn provider_boxes_fit_content_and_preserve_space_below() {
        let claude = (0..3)
            .map(|i| format!(r#"{{"name":"claude-{i}","needsLogin":false}}"#))
            .collect::<Vec<_>>()
            .join(",");
        let codex = (0..2)
            .map(|i| format!(r#"{{"name":"codex-{i}"}}"#))
            .collect::<Vec<_>>()
            .join(",");
        let app = App::new(parse(&format!(r#"{{"version":1,"claude":{{"available":true,"logins":[{claude}]}},"codex":{{"available":true,"logins":[{codex}]}}}}"#)).unwrap());
        let buffer = rendered(&app, 120, 30, OffsetDateTime::UNIX_EPOCH);
        assert!(row(&buffer, 4).starts_with('└'));
        assert!(row(&buffer, 5).starts_with('┌'));
        assert!(row(&buffer, 8).starts_with('└'));
        assert_eq!(buffer[(0, 9)].symbol(), " ");
        assert!(row(&buffer, 28).contains("updated"));
    }

    #[test]
    fn cramped_boxes_stay_visible_and_scroll_selected_login() {
        let claude = (0..12)
            .map(|i| format!(r#"{{"name":"claude-{i}","needsLogin":false}}"#))
            .collect::<Vec<_>>()
            .join(",");
        let codex = (0..12)
            .map(|i| format!(r#"{{"name":"codex-{i}"}}"#))
            .collect::<Vec<_>>()
            .join(",");
        let mut app = App::new(parse(&format!(r#"{{"version":1,"claude":{{"available":true,"logins":[{claude}]}},"codex":{{"available":true,"logins":[{codex}]}}}}"#)).unwrap());
        app.positions = [11, 11];
        let buffer = rendered(&app, 80, 12, OffsetDateTime::UNIX_EPOCH);
        let lines = (0..12).map(|y| row(&buffer, y)).collect::<Vec<_>>();
        assert!(lines.iter().any(|line| line.contains("Claude")));
        assert!(lines.iter().any(|line| line.contains("Codex")));
        assert!(lines.iter().any(|line| line.contains(">   claude-11")));
        assert!(lines.iter().any(|line| line.contains("codex-11")));
    }
    #[test]
    fn failed_status_read_is_not_reported_as_switching_off() {
        let s = r#"{"version":1,"claude":{"available":false,"selected":null,"logins":[]},"codex":{"available":false,"inUse":null,"logins":[]}}"#;
        let mut app = App::new(parse(s).unwrap());
        app.status_error("AI Control engine not found (AIControl).");
        let buffer = rendered(&app, 120, 20, OffsetDateTime::UNIX_EPOCH);
        let image: String = (0..buffer.area.height).map(|y| row(&buffer, y)).collect();
        assert!(image.contains("Login status could not be read"), "{image}");
        assert!(!image.contains("switching is off"), "{image}");
    }
    #[test]
    fn only_installed_or_saved_providers_are_drawn() {
        let claude_only = parse(r#"{"version":1,"claude":{"available":true,"installed":true,"logins":[]},"codex":{"available":true,"installed":false,"logins":[]}}"#).unwrap();
        let buffer = rendered(&App::new(claude_only), 100, 12, OffsetDateTime::UNIX_EPOCH);
        let image: String = (0..buffer.area.height).map(|y| row(&buffer, y)).collect();
        assert!(
            image.contains("Claude") && !image.contains("Codex"),
            "{image}"
        );
        let none = parse(r#"{"version":1,"claude":{"available":true,"installed":false,"logins":[]},"codex":{"available":true,"installed":false,"logins":[]}}"#).unwrap();
        let buffer = rendered(&App::new(none), 100, 12, OffsetDateTime::UNIX_EPOCH);
        let image: String = (0..buffer.area.height).map(|y| row(&buffer, y)).collect();
        assert!(
            image.contains("Install Claude Code or the Codex CLI"),
            "{image}"
        );
    }
    #[test]
    fn save_is_offered_in_the_footer_and_empty_panels() {
        let s = r#"{"version":1,"claude":{"available":true,"installed":true,"logins":[]},"codex":{"available":true,"installed":false,"logins":[]}}"#;
        let mut app = App::new(parse(s).unwrap());
        let buffer = rendered(&app, 140, 12, OffsetDateTime::UNIX_EPOCH);
        let image: String = (0..buffer.area.height).map(|y| row(&buffer, y)).collect();
        assert!(
            image.contains("s saves the account you are signed in to"),
            "{image}"
        );
        assert!(image.contains("s save"), "{image}");
        app.key(crate::app::Key::Char('s'));
        app.key(crate::app::Key::Char('p'));
        let buffer = rendered(&app, 140, 12, OffsetDateTime::UNIX_EPOCH);
        let image: String = (0..buffer.area.height).map(|y| row(&buffer, y)).collect();
        assert!(image.contains("Save current login as: p"), "{image}");
    }
    #[test]
    fn snapshot_and_narrow() {
        let s = r#"{"version":1,"claude":{"available":true,"selected":"one","logins":[{"name":"one","needsLogin":false,"usage":{"windows":[{"label":"5h","usedPercent":25,"resetsAt":null}],"resetsAvailable":null,"fetchedAt":"2026-09-26T00:00:00Z"},"usageError":null}]},"codex":{"available":false,"inUse":null,"logins":[]}}"#;
        let app = App::new(parse(s).unwrap());
        let mut terminal = Terminal::new(TestBackend::new(80, 12)).unwrap();
        terminal.draw(|f| draw(f, &app)).unwrap();
        let image = terminal
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|c| c.symbol())
            .collect::<String>();
        assert!(image.contains("Claude") && image.contains("5h █░░░░ 25%"));
        assert!(image.contains("Unavailable: Codex"));
        let both = s.replace("\"needsLogin\":false", "\"needsLogin\":true")
            .replace("\"available\":false,\"inUse\":null,\"logins\":[]", "\"available\":true,\"inUse\":\"work\",\"logins\":[{\"name\":\"work\",\"email\":\"team@example.test\",\"usage\":{\"windows\":[{\"label\":\"Week\",\"usedPercent\":80,\"resetsAt\":null}],\"resetsAvailable\":3,\"fetchedAt\":\"2026-09-26T00:00:00Z\"},\"usageError\":null}]");
        let both = App::new(parse(&both).unwrap());
        let mut wide = Terminal::new(TestBackend::new(140, 12)).unwrap();
        wide.draw(|f| draw(f, &both)).unwrap();
        let image = wide
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|c| c.symbol())
            .collect::<String>();
        assert!(image.contains("needs sign-in"));
        assert!(image.contains("Week ████░ 80%") && image.contains("3 resets"));
        for width in [1, 2, 9, 20] {
            let mut narrow = Terminal::new(TestBackend::new(width, 5)).unwrap();
            narrow.draw(|f| draw(f, &app)).unwrap();
        }
    }
    fn screen(app: &App) -> (String, ratatui::buffer::Buffer) {
        let mut terminal = Terminal::new(TestBackend::new(120, 12)).unwrap();
        terminal.draw(|f| draw(f, app)).unwrap();
        let buffer = terminal.backend().buffer().clone();
        let text = buffer
            .content()
            .iter()
            .map(|c| c.symbol())
            .collect::<String>();
        (text, buffer)
    }
    fn login_screen(count: usize, errors: bool, cursor: usize) -> Vec<String> {
        let logins = (0..count)
            .map(|i| {
                format!(
                    r#"{{"name":"login-{i}","needsLogin":false,"usageError":{}}}"#,
                    if errors { r#""failed""# } else { "null" }
                )
            })
            .collect::<Vec<_>>()
            .join(",");
        let status = format!(
            r#"{{"version":1,"claude":{{"available":true,"logins":[{logins}]}},"codex":{{"available":false,"logins":[]}}}}"#
        );
        let mut app = App::new(parse(&status).unwrap());
        app.positions[0] = cursor;
        let mut terminal = Terminal::new(TestBackend::new(80, 12)).unwrap();
        terminal.draw(|f| draw(f, &app)).unwrap();
        let buffer = terminal.backend().buffer();
        (0..12)
            .map(|y| (0..80).map(|x| buffer[(x, y)].symbol()).collect())
            .collect()
    }
    #[test]
    fn selected_fifth_login_remains_visible() {
        let screen = login_screen(5, false, 4);
        assert!(screen.iter().any(|row| row.contains(">   login-4")));
    }
    #[test]
    fn selected_login_with_usage_errors_remains_visible() {
        let screen = login_screen(5, true, 4);
        assert!(screen.iter().any(|row| row.contains(">   login-4")));
    }
    #[test]
    fn inactive_provider_keeps_its_own_cursor_visible() {
        let logins = (0..5)
            .map(|i| format!(r#"{{"name":"codex-{i}"}}"#))
            .collect::<Vec<_>>()
            .join(",");
        let status = format!(
            r#"{{"version":1,"claude":{{"available":true,"logins":[]}},"codex":{{"available":true,"logins":[{logins}]}}}}"#
        );
        let mut app = App::new(parse(&status).unwrap());
        app.positions[1] = 4;
        let (text, _) = screen(&app);
        assert!(text.contains("codex-4"));
    }
    #[test]
    fn fitting_logins_start_on_first_interior_row() {
        let screen = login_screen(2, false, 1);
        assert!(screen[1].contains("  login-0"));
    }
    #[test]
    fn pending_first_status_displays_loading_not_unavailable() {
        let mut app = App::new(parse(r#"{"version":1,"claude":{"available":false,"logins":[]},"codex":{"available":false,"logins":[]}}"#).unwrap());
        app.status_loaded = false;
        app.loading = Some(Loading::Usage);
        let (text, _) = screen(&app);
        assert!(text.matches("Loading…").count() >= 2);
        assert!(!text.contains("Unavailable:"));
        app.status_error("Engine failed");
        let (text, _) = screen(&app);
        assert!(text.contains("Login status could not be read"));
    }
    #[test]
    fn footer_distinguishes_plain_status_from_usage_loading() {
        let mut app = App::new(parse(r#"{"version":1,"claude":{"available":false,"logins":[]},"codex":{"available":false,"logins":[]}}"#).unwrap());
        app.loading = Some(Loading::Status);
        let (text, _) = screen(&app);
        assert!(text.contains("Loading status…"));
        assert!(!text.contains("Loading usage…"));
        app.loading = Some(Loading::Usage);
        assert!(screen(&app).0.contains("Loading usage…"));
    }
    #[test]
    fn failed_action_message_is_red_but_success_is_not() {
        let mut app = App::new(parse(r#"{"version":1,"claude":{"available":false,"logins":[]},"codex":{"available":false,"logins":[]}}"#).unwrap());
        app.result("Blocked", false);
        let (_, buffer) = screen(&app);
        let cell = buffer.content().iter().find(|c| c.symbol() == "B").unwrap();
        assert_eq!(cell.fg, Color::Red);
        app.loading = Some(Loading::Status);
        let (text, buffer) = screen(&app);
        assert!(text.contains("Loading status… · Blocked"));
        assert_eq!(
            buffer
                .content()
                .iter()
                .find(|c| c.symbol() == "B")
                .unwrap()
                .fg,
            Color::Red
        );
        app.loading = None;
        app.result("Applied", true);
        let (_, buffer) = screen(&app);
        let cell = buffer.content().iter().find(|c| c.symbol() == "A").unwrap();
        assert_ne!(cell.fg, Color::Red);
    }
}
