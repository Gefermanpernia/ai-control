use aic_tui::{
    app::{App, Effect, Key, Mode},
    status::{parse, Status},
};

const SAMPLE: &str = r#"{"version":1,"claude":{"available":true,"selected":"home","logins":[{"name":"home","needsLogin":false,"usage":{"windows":[{"label":"5h","usedPercent":25.0,"resetsAt":"2026-09-27T00:00:00Z"}],"resetsAvailable":null,"fetchedAt":"2026-09-26T00:00:00Z"},"usageError":null}]},"codex":{"available":true,"inUse":null,"logins":[{"name":"work","email":null,"usage":null,"usageError":"offline"}]}}"#;
const TWO_LOGINS: &str = r#"{"version":1,"claude":{"available":true,"logins":[{"name":"a","needsLogin":false},{"name":"b","needsLogin":false}]},"codex":{"available":true,"logins":[{"name":"a","email":null},{"name":"b","email":null}]}}"#;
fn app() -> App {
    App::new(parse(SAMPLE).unwrap())
}
fn two_logins() -> App {
    App::new(parse(TWO_LOGINS).unwrap())
}
fn reordered() -> Status {
    let mut status = parse(TWO_LOGINS).unwrap();
    status.claude.logins.swap(0, 1);
    status.codex.logins.swap(0, 1);
    status
}
fn type_text(app: &mut App, text: &str) {
    for ch in text.chars() {
        app.key(Key::Char(ch));
    }
}

#[test]
fn movement_and_tab_keep_independent_selection() {
    let mut app = app();
    app.key(Key::Down);
    assert_eq!(app.positions[0], 0);
    app.key(Key::Tab);
    assert_eq!(app.provider, 1);
    app.key(Key::Down);
    assert_eq!(app.positions, [0, 0]);
}
#[test]
fn enter_requires_confirmation_to_switch() {
    let mut app = app();
    app.key(Key::Enter);
    assert_eq!(app.mode, Mode::Confirm);
    assert_eq!(
        app.key(Key::Char('y')),
        Effect::Action {
            provider: "claude-login",
            verb: "use",
            alias: "home".into(),
            extra: None
        }
    );
}
#[test]
fn confirm_target_survives_reorder_and_cursor_change() {
    let mut app = two_logins();
    app.key(Key::Down);
    app.key(Key::Enter);
    app.apply_status(reordered(), false);
    app.positions[0] = 1;
    assert!(
        matches!(app.key(Key::Char('y')), Effect::Action { verb: "use", alias, .. } if alias == "b")
    );
}
#[test]
fn rename_target_survives_reorder_and_cursor_change() {
    let mut app = two_logins();
    app.key(Key::Down);
    app.key(Key::Char('n'));
    type_text(&mut app, "new_b");
    app.apply_status(reordered(), false);
    app.positions[0] = 1;
    assert!(
        matches!(app.key(Key::Enter), Effect::Action { verb: "rename", alias, extra: Some(new), .. } if alias == "b" && new == "new_b")
    );
}
#[test]
fn missing_confirm_target_does_not_emit_action() {
    let mut app = two_logins();
    app.key(Key::Down);
    app.key(Key::Enter);
    let mut removed = parse(TWO_LOGINS).unwrap();
    removed.claude.logins.pop();
    app.apply_status(removed, false);
    assert_eq!(app.key(Key::Char('y')), Effect::None);
    assert_eq!(app.mode, Mode::Normal);
    assert_eq!(app.action_success, Some(false));
    assert!(app.message.contains("no longer saved"));
}
#[test]
fn status_reorder_keeps_both_provider_cursors_on_login_names() {
    let mut app = two_logins();
    app.positions = [1, 1];
    app.apply_status(reordered(), false);
    assert_eq!(app.positions, [0, 0]);
    assert_eq!(app.name(), Some("b"));
}
#[test]
fn non_yes_confirmation_cancels_without_action() {
    let mut app = app();
    app.key(Key::Enter);
    assert_eq!(app.key(Key::Char('n')), Effect::None);
    assert_eq!(app.mode, Mode::Normal);
}
#[test]
fn rename_rejects_empty_and_invalid_alias_then_accepts_valid() {
    let mut app = app();
    app.key(Key::Tab);
    app.key(Key::Char('n'));
    assert_eq!(app.key(Key::Enter), Effect::None);
    assert!(app.message.contains("Invalid alias"));
    type_text(&mut app, "Bad!");
    assert_eq!(app.key(Key::Enter), Effect::None);
    assert!(app.message.contains("Invalid alias"));
    for _ in 0..4 {
        app.key(Key::Backspace);
    }
    type_text(&mut app, "valid_1");
    assert_eq!(
        app.key(Key::Enter),
        Effect::Action {
            provider: "codex-login",
            verb: "rename",
            alias: "work".into(),
            extra: Some("valid_1".into())
        }
    );
}
#[test]
fn add_rejects_empty_and_invalid_alias_then_accepts_valid() {
    let mut app = app();
    app.key(Key::Tab);
    app.key(Key::Char('a'));
    assert_eq!(app.key(Key::Enter), Effect::None);
    type_text(&mut app, "BAD");
    assert_eq!(app.key(Key::Enter), Effect::None);
    for _ in 0..3 {
        app.key(Key::Backspace);
    }
    type_text(&mut app, "new-login");
    assert_eq!(
        app.key(Key::Enter),
        Effect::Action {
            provider: "codex-login",
            verb: "add",
            alias: "new-login".into(),
            extra: None
        }
    );
}
#[test]
fn escape_cancels_rename_and_add_and_clears_input() {
    let mut app = app();
    for start in ['n', 'a'] {
        app.key(Key::Char(start));
        type_text(&mut app, "draft");
        app.key(Key::Esc);
        assert_eq!(app.mode, Mode::Normal);
        assert!(app.input.is_empty());
    }
}
#[test]
fn claude_add_forwards_optional_email() {
    let mut app = app();
    app.key(Key::Char('a'));
    type_text(&mut app, "new");
    app.key(Key::Enter);
    assert_eq!(app.mode, Mode::AddEmail);
    type_text(&mut app, "hello@example.test");
    assert_eq!(
        app.key(Key::Enter),
        Effect::Action {
            provider: "claude-login",
            verb: "add",
            alias: "new".into(),
            extra: Some("hello@example.test".into())
        }
    );
}
#[test]
fn claude_add_skips_empty_email() {
    let mut app = app();
    app.key(Key::Char('a'));
    type_text(&mut app, "new");
    app.key(Key::Enter);
    assert_eq!(
        app.key(Key::Enter),
        Effect::Action {
            provider: "claude-login",
            verb: "add",
            alias: "new".into(),
            extra: None
        }
    );
}
#[test]
fn plain_status_carries_matching_usage_and_error_but_not_removed_logins() {
    let mut app = app();
    let plain = parse(&SAMPLE.replace("\"usage\":{\"windows\":[{\"label\":\"5h\",\"usedPercent\":25.0,\"resetsAt\":\"2026-09-27T00:00:00Z\"}],\"resetsAvailable\":null,\"fetchedAt\":\"2026-09-26T00:00:00Z\"}", "\"usage\":null").replace("\"usageError\":\"offline\"", "\"usageError\":null")).unwrap();
    app.apply_status(plain, false);
    assert_eq!(
        app.status.claude.logins[0].usage.as_ref().unwrap().windows[0].used_percent,
        25.0
    );
    assert_eq!(
        app.status.codex.logins[0].usage_error.as_deref(),
        Some("offline")
    );
    let removed = parse(&SAMPLE.replace(
        "\"logins\":[{\"name\":\"work\",\"email\":null,\"usage\":null,\"usageError\":\"offline\"}]",
        "\"logins\":[]",
    ))
    .unwrap();
    app.apply_status(removed, false);
    assert!(app.status.codex.logins.is_empty());
}
#[test]
fn usage_reload_replaces_previous_usage_and_error() {
    let mut app = app();
    let replacement = parse(
        &SAMPLE
            .replace("\"usedPercent\":25.0", "\"usedPercent\":70.0")
            .replace("\"usageError\":\"offline\"", "\"usageError\":null"),
    )
    .unwrap();
    app.apply_status(replacement, true);
    assert_eq!(
        app.status.claude.logins[0].usage.as_ref().unwrap().windows[0].used_percent,
        70.0
    );
    assert!(app.status.codex.logins[0].usage_error.is_none());
}
#[test]
fn action_progress_labels_switch_and_rename_before_running() {
    let mut app = app();
    app.start_action("use");
    assert_eq!(app.message, "Switching…");
    app.start_action("rename");
    assert_eq!(app.message, "Renaming…");
}
#[test]
fn action_result_preserves_success_or_failure() {
    let mut app = app();
    app.result("Renamed", true);
    assert_eq!(app.message, "Renamed");
    assert_eq!(app.action_success, Some(true));
    app.result("Blocked", false);
    assert_eq!(app.message, "Blocked");
    assert_eq!(app.action_success, Some(false));
}

const MONITORS: &str = r#"{"version":1,"claude":{"available":true,"logins":[]},"codex":{"available":true,"logins":[]},"monitors":[{"id":"opencode-go","name":"OpenCode Go","usage":{"windows":[{"label":"5h","usedPercent":62,"resetsAt":null}],"fetchedAt":"2026-01-01T00:00:00Z"},"models":null,"error":"old"},{"id":"nan","name":"NaN","usage":null,"models":[{"model":"glm5.3","totalTokens":1200000000,"quotaTokens":null,"usedPercent":null,"resetsAt":null}],"error":null}]}"#;

#[test]
fn parses_optional_monitors_and_model_usage() {
    assert!(parse(SAMPLE).unwrap().monitors.is_empty());
    let status = parse(MONITORS).unwrap();
    assert_eq!(status.monitors.len(), 2);
    assert_eq!(
        status.monitors[0].usage.as_ref().unwrap().windows[0].used_percent,
        62.0
    );
    assert_eq!(
        status.monitors[1].models.as_ref().unwrap()[0].total_tokens,
        1_200_000_000
    );
}

#[test]
fn plain_reload_carries_monitor_data_by_id_and_usage_reload_replaces_it() {
    let mut app = App::new(parse(MONITORS).unwrap());
    let plain = parse(r#"{"version":1,"claude":{"available":true,"logins":[]},"codex":{"available":true,"logins":[]},"monitors":[{"id":"nan","name":"renamed NaN","usage":null,"models":null,"error":null},{"id":"new","name":"New","usage":null,"models":null,"error":null},{"id":"opencode-go","name":"Go","usage":null,"models":null,"error":null}]}"#).unwrap();
    app.apply_status(plain, false);
    assert_eq!(app.status.monitors[0].name, "renamed NaN");
    assert_eq!(
        app.status.monitors[0].models.as_ref().unwrap()[0].total_tokens,
        1_200_000_000
    );
    assert!(app.status.monitors[1].models.is_none());
    assert_eq!(
        app.status.monitors[2].usage.as_ref().unwrap().windows[0].used_percent,
        62.0
    );
    assert_eq!(app.status.monitors[2].error.as_deref(), Some("old"));
    app.apply_status(parse(MONITORS).unwrap(), true);
    assert_eq!(app.status.monitors[0].name, "OpenCode Go");
    assert_eq!(
        app.status.monitors[0].usage.as_ref().unwrap().windows[0].used_percent,
        62.0
    );
    assert_eq!(app.status.monitors[0].error.as_deref(), Some("old"));
    assert!(app.status.monitors[1].error.is_none());
}

#[test]
fn tab_skips_read_only_monitors() {
    let mut app = App::new(parse(MONITORS).unwrap());
    for expected in [1, 0, 1, 0] {
        assert_eq!(app.key(Key::Tab), Effect::None);
        assert_eq!(app.provider, expected);
    }
    let mut status = parse(MONITORS).unwrap();
    status.codex.installed = false;
    let mut app = App::new(status);
    app.key(Key::Tab);
    assert_eq!(app.provider, 0);
}

const CLAUDE_ONLY: &str = r#"{"version":1,"claude":{"available":true,"installed":true,"logins":[]},"codex":{"available":true,"installed":false,"logins":[]}}"#;
const CODEX_ONLY: &str = r#"{"version":1,"claude":{"available":true,"installed":false,"logins":[]},"codex":{"available":true,"installed":true,"logins":[]}}"#;

#[test]
fn providers_without_cli_or_saved_logins_are_hidden_and_skipped_by_tab() {
    let mut app = App::new(parse(CLAUDE_ONLY).unwrap());
    assert_eq!(app.visible(), vec![0]);
    app.key(Key::Tab);
    assert_eq!(app.provider, 0);
}
#[test]
fn saved_logins_keep_a_provider_visible_without_its_cli() {
    let mut status = parse(TWO_LOGINS).unwrap();
    status.codex.installed = false;
    assert_eq!(App::new(status).visible(), vec![0, 1]);
}
#[test]
fn a_status_that_hides_the_current_provider_moves_to_a_visible_one() {
    let mut app = two_logins();
    app.key(Key::Tab);
    assert_eq!(app.provider, 1);
    app.apply_status(parse(CLAUDE_ONLY).unwrap(), false);
    assert_eq!(app.provider, 0);
    let mut app = App::new(parse(CODEX_ONLY).unwrap());
    assert_eq!(app.visible(), vec![1]);
    assert_eq!(app.provider, 1);
    app.key(Key::Tab);
    assert_eq!(app.provider, 1);
}
#[test]
fn both_providers_show_until_a_status_was_read() {
    let mut app = App::new(parse(CLAUDE_ONLY).unwrap());
    app.status_error("AI Control engine not found (AIControl).");
    assert_eq!(app.visible(), vec![0, 1]);
}
#[test]
fn nothing_to_act_on_when_no_provider_is_visible() {
    let none = r#"{"version":1,"claude":{"available":true,"installed":false,"logins":[]},"codex":{"available":true,"installed":false,"logins":[]}}"#;
    let mut app = App::new(parse(none).unwrap());
    app.key(Key::Char('a'));
    assert_eq!(app.mode, Mode::Normal);
}
#[test]
fn save_names_the_current_login_for_the_chosen_provider() {
    let mut app = App::new(parse(CLAUDE_ONLY).unwrap());
    app.key(Key::Char('s'));
    assert_eq!(app.mode, Mode::Save);
    assert_eq!(app.key(Key::Enter), Effect::None);
    assert!(app.message.contains("Invalid alias"));
    type_text(&mut app, "personal");
    assert_eq!(
        app.key(Key::Enter),
        Effect::Action {
            provider: "claude-login",
            verb: "save",
            alias: "personal".into(),
            extra: None
        }
    );
    assert_eq!(app.mode, Mode::Normal);
    let mut app = two_logins();
    app.key(Key::Tab);
    app.key(Key::Char('s'));
    type_text(&mut app, "work");
    assert_eq!(
        app.key(Key::Enter),
        Effect::Action {
            provider: "codex-login",
            verb: "save",
            alias: "work".into(),
            extra: None
        }
    );
}
#[test]
fn escape_cancels_save() {
    let mut app = app();
    app.key(Key::Char('s'));
    type_text(&mut app, "abc");
    assert_eq!(app.key(Key::Esc), Effect::None);
    assert_eq!(app.mode, Mode::Normal);
    assert!(app.input.is_empty());
}
#[test]
fn ctrl_c_quits_from_every_mode_and_is_never_typed() {
    use aic_tui::app::key_from;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
    let ctrl_c = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL);
    assert_eq!(key_from(ctrl_c), Some(Key::Interrupt));
    assert_eq!(
        key_from(KeyEvent::new(KeyCode::Char('c'), KeyModifiers::NONE)),
        Some(Key::Char('c'))
    );
    let mut app = two_logins();
    assert_eq!(app.key(Key::Interrupt), Effect::Quit);
    for enter in [Key::Char('s'), Key::Char('n'), Key::Char('a'), Key::Enter] {
        let mut app = two_logins();
        app.key(enter);
        type_text(&mut app, "ab");
        assert_eq!(app.key(Key::Interrupt), Effect::Quit, "{enter:?}");
        assert!(!app.input.contains('c'));
    }
}
