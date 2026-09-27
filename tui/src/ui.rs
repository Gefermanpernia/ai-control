use crate::{
    app::{App, Loading, Mode},
    status::Usage,
};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
    Frame,
};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

fn relative(timestamp: &str) -> String {
    let Ok(date) = OffsetDateTime::parse(timestamp, &Rfc3339) else {
        return "?".into();
    };
    let seconds = (date - OffsetDateTime::now_utc()).whole_seconds();
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
fn usage(usage: &Usage) -> String {
    let mut text = usage
        .windows
        .iter()
        .map(|w| {
            let pct = if w.used_percent.is_finite() {
                w.used_percent.clamp(0.0, 100.0)
            } else {
                0.0
            };
            let filled = (pct / 20.0).round() as usize;
            format!(
                "{} {}{} {:.0}%{}",
                w.label,
                "█".repeat(filled),
                "░".repeat(5 - filled),
                pct,
                w.resets_at
                    .as_ref()
                    .map(|t| format!(" ↻{}", relative(t)))
                    .unwrap_or_default()
            )
        })
        .collect::<Vec<_>>()
        .join("  ");
    if let Some(count) = usage.resets_available {
        text.push_str(&format!("  {count} resets"));
    }
    text
}
fn rows(app: &App, provider: usize) -> Vec<Line<'static>> {
    if !app.status_loaded {
        return vec![Line::from("Loading…")];
    }
    let mut lines = Vec::new();
    if provider == 0 {
        if !app.status.claude.available {
            return vec![Line::from(
                "Unavailable: Claude login switching is off or unreadable",
            )];
        }
        for (i, l) in app.status.claude.logins.iter().enumerate() {
            let mark = if app.status.claude.selected.as_deref() == Some(&l.name) {
                "●"
            } else {
                " "
            };
            let selected = provider == app.provider && i == app.positions[0];
            let mut line = format!(
                "{} {}{}{}",
                if selected { ">" } else { " " },
                mark,
                l.name,
                if l.needs_login {
                    " · needs sign-in"
                } else {
                    ""
                }
            );
            if let Some(u) = &l.usage {
                line.push_str(&format!("  {}", usage(u)));
            }
            lines.push(Line::from(Span::styled(
                line,
                if selected {
                    Style::default().fg(Color::Cyan)
                } else {
                    Style::default()
                },
            )));
            if let Some(error) = &l.usage_error {
                lines.push(Line::from(Span::styled(
                    format!("  {error}"),
                    Style::default().add_modifier(Modifier::DIM),
                )));
            }
        }
    } else {
        if !app.status.codex.available {
            return vec![Line::from(
                "Unavailable: Codex login switching is off or unreadable",
            )];
        }
        for (i, l) in app.status.codex.logins.iter().enumerate() {
            let mark = if app.status.codex.in_use.as_deref() == Some(&l.name) {
                "●"
            } else {
                " "
            };
            let selected = provider == app.provider && i == app.positions[1];
            let mut line = format!(
                "{} {}{}{}",
                if selected { ">" } else { " " },
                mark,
                l.name,
                l.email
                    .as_ref()
                    .map(|e| format!(" · {e}"))
                    .unwrap_or_default()
            );
            if let Some(u) = &l.usage {
                line.push_str(&format!("  {}", usage(u)));
            }
            lines.push(Line::from(Span::styled(
                line,
                if selected {
                    Style::default().fg(Color::Cyan)
                } else {
                    Style::default()
                },
            )));
            if let Some(error) = &l.usage_error {
                lines.push(Line::from(Span::styled(
                    format!("  {error}"),
                    Style::default().add_modifier(Modifier::DIM),
                )));
            }
        }
    }
    if lines.is_empty() {
        lines.push(Line::from("No saved logins"));
    }
    lines
}
pub fn draw(frame: &mut Frame, app: &App) {
    let size = frame.area();
    if size.width < 2 || size.height < 3 {
        return;
    }
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage(45),
            Constraint::Percentage(45),
            Constraint::Min(2),
        ])
        .split(size);
    for (i, title) in ["Claude", "Codex"].iter().enumerate() {
        let area = chunks[i];
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
            Paragraph::new(rows(app, i))
                .scroll((u16::try_from(offset).unwrap_or(u16::MAX), 0))
                .block(
                    Block::default()
                        .title(*title)
                        .borders(Borders::ALL)
                        .border_style(border),
                ),
            area,
        );
    }
    footer(frame, chunks[2], app);
}
fn footer(frame: &mut Frame, area: Rect, app: &App) {
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
        Mode::AddAlias => format!("Alias: {}", app.input),
        Mode::AddEmail => format!("Claude email (optional): {}", app.input),
    };
    let updated = app.updated.as_deref().unwrap_or("not yet loaded");
    let style = if app.mode == Mode::Normal
        && app.loading != Some(Loading::Usage)
        && app.action_success == Some(false)
    {
        Style::default().fg(Color::Red)
    } else {
        Style::default()
    };
    frame.render_widget(Paragraph::new(vec![Line::from(format!("↑↓/jk move · Tab provider · Enter switch · n rename · a add · r usage · q quit · updated {updated}")), Line::from(Span::styled(prompt, style))]), area);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{app::Loading, status::parse};
    use ratatui::{backend::TestBackend, Terminal};
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
        assert!(screen.iter().any(|row| row.contains(">  login-4")));
    }
    #[test]
    fn selected_login_with_usage_errors_remains_visible() {
        let screen = login_screen(5, true, 4);
        assert!(screen.iter().any(|row| row.contains(">  login-4")));
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
        assert!(text.contains("Unavailable:"));
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
