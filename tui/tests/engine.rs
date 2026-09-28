use aic_tui::{
    engine::{engine_path, message, Engine, Runner, SubprocessEngine},
    status::parse,
};
use std::{
    collections::HashMap,
    path::PathBuf,
    process::{ExitStatus, Output},
    sync::Mutex,
};

/// An exit status with `code`, built the way each platform encodes it.
#[cfg(unix)]
fn exit_status(code: i32) -> ExitStatus {
    std::os::unix::process::ExitStatusExt::from_raw(code << 8)
}
#[cfg(windows)]
fn exit_status(code: i32) -> ExitStatus {
    std::os::windows::process::ExitStatusExt::from_raw(code as u32)
}

const SAMPLE: &str = r#"{"version":1,"claude":{"available":true,"selected":"home","logins":[{"name":"home","needsLogin":false,"usage":{"windows":[{"label":"5h","usedPercent":25.0,"resetsAt":"2026-09-27T00:00:00Z"}],"resetsAvailable":null,"fetchedAt":"2026-09-26T00:00:00Z"},"usageError":null}]},"codex":{"available":true,"inUse":null,"logins":[{"name":"work","email":null,"usage":null,"usageError":"offline"}]}}"#;

#[test]
fn parses_full_status_and_null_fields() {
    let status = parse(SAMPLE).unwrap();
    assert_eq!(
        status.claude.logins[0].usage.as_ref().unwrap().windows[0].used_percent,
        25.0
    );
    assert_eq!(status.codex.logins[0].email, None);
    assert!(status.codex.logins[0].usage.is_none());
}
#[test]
fn rejects_unknown_version() {
    assert!(parse(&SAMPLE.replace("\"version\":1", "\"version\":2"))
        .unwrap_err()
        .contains("version"));
}
#[test]
fn location_precedence() {
    let dir = tempfile::tempdir().unwrap();
    let bundle = dir.path().join("Contents/Resources");
    std::fs::create_dir_all(&bundle).unwrap();
    let exe = bundle.join("aic-tui");
    let mut env = HashMap::new();
    env.insert("AIC_ENGINE".to_string(), "/custom/engine".to_string());
    assert_eq!(engine_path(&exe, &env), PathBuf::from("/custom/engine"));
    env.clear();
    std::fs::write(bundle.join("AIControl"), "").unwrap();
    assert_eq!(engine_path(&exe, &env), bundle.join("AIControl"));
    std::fs::remove_file(bundle.join("AIControl")).unwrap();
    std::fs::create_dir(bundle.join("../MacOS")).unwrap();
    std::fs::write(bundle.join("../MacOS/AIControl"), "").unwrap();
    assert_eq!(engine_path(&exe, &env), bundle.join("../MacOS/AIControl"));
    std::fs::remove_file(bundle.join("../MacOS/AIControl")).unwrap();
    assert_eq!(engine_path(&exe, &env), PathBuf::from("AIControl"));
}

#[derive(Default)]
struct Fake {
    calls: Mutex<Vec<(Vec<String>, bool)>>,
    code: i32,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}
impl Fake {
    fn response(code: i32, stdout: &str) -> Self {
        Self {
            code,
            stdout: stdout.as_bytes().to_vec(),
            ..Self::default()
        }
    }
    fn with_stderr(mut self, stderr: &str) -> Self {
        self.stderr = stderr.as_bytes().to_vec();
        self
    }
    fn calls(&self) -> Vec<(Vec<String>, bool)> {
        self.calls.lock().unwrap().clone()
    }
}
impl Runner for &Fake {
    fn run(
        &self,
        _: &std::path::Path,
        args: &[String],
        interactive: bool,
    ) -> std::io::Result<Output> {
        self.calls
            .lock()
            .unwrap()
            .push((args.to_vec(), interactive));
        Ok(Output {
            status: exit_status(self.code),
            stdout: self.stdout.clone(),
            stderr: self.stderr.clone(),
        })
    }
}
#[test]
fn engine_message_uses_last_nonempty_stdout_or_stderr_line() {
    assert_eq!(message(b"first\nBlocked: no\n", b"other\n"), "Blocked: no");
    assert_eq!(message(b"\n", b"last stderr\n"), "last stderr");
}
#[test]
fn action_reports_nonzero_exit_and_runs_noninteractive() {
    let fake = Fake::response(3, "heading\nBlocked: no\n");
    let engine = SubprocessEngine::new(PathBuf::from("fake"), &fake);
    let outcome = engine.action("claude-login", "use", "home", None).unwrap();
    assert!(!outcome.success);
    assert_eq!(outcome.message, "Blocked: no");
    assert_eq!(
        fake.calls(),
        vec![(
            vec!["claude-login".into(), "use".into(), "home".into()],
            false
        )]
    );
}
#[test]
fn interactive_add_passes_email_and_runs_interactive() {
    let fake = Fake::response(0, "Added\n");
    let engine = SubprocessEngine::new(PathBuf::from("fake"), &fake);
    assert!(
        engine
            .interactive_add("claude-login", "home", Some("h@example.test"))
            .unwrap()
            .success
    );
    assert_eq!(
        fake.calls(),
        vec![(
            vec![
                "claude-login".into(),
                "add".into(),
                "home".into(),
                "h@example.test".into()
            ],
            true
        )]
    );
}
#[test]
fn status_invocation_is_noninteractive_and_usage_is_opt_in() {
    let fake = Fake::response(0, SAMPLE);
    let engine = SubprocessEngine::new(PathBuf::from("fake"), &fake);
    engine.status(false).unwrap();
    engine.status(true).unwrap();
    assert_eq!(
        fake.calls(),
        vec![
            (vec!["status".into(), "--json".into()], false),
            (
                vec!["status".into(), "--json".into(), "--usage".into()],
                false
            )
        ]
    );
}
#[test]
fn status_nonzero_uses_engine_message() {
    let fake = Fake::response(3, "Blocked: test refusal\n");
    assert_eq!(
        SubprocessEngine::new(PathBuf::from("fake"), &fake)
            .status(false)
            .unwrap_err(),
        "Blocked: test refusal"
    );
}
#[test]
fn status_invalid_json_returns_error() {
    let fake = Fake::response(0, "not json");
    assert!(SubprocessEngine::new(PathBuf::from("fake"), &fake)
        .status(false)
        .unwrap_err()
        .contains("Invalid engine status"));
}
struct Missing;
impl Runner for Missing {
    fn run(&self, _: &std::path::Path, _: &[String], _: bool) -> std::io::Result<Output> {
        Err(std::io::ErrorKind::NotFound.into())
    }
}
#[test]
fn missing_engine_explains_where_it_looked_and_how_to_fix_it() {
    let engine = SubprocessEngine::new(PathBuf::from("/opt/tui/AIControl"), Missing);
    for error in [
        engine.status(false).unwrap_err(),
        engine
            .action("codex-login", "use", "work", None)
            .unwrap_err(),
        engine
            .interactive_add("codex-login", "work", None)
            .unwrap_err(),
    ] {
        assert!(
            error.contains("AI Control engine not found (/opt/tui/AIControl)"),
            "{error}"
        );
        assert!(error.contains("AIC_ENGINE"), "{error}");
    }
}
#[test]
fn installed_defaults_to_true_for_older_engines() {
    let status = parse(SAMPLE).unwrap();
    assert!(status.claude.installed && status.codex.installed);
    let status = parse(r#"{"version":1,"claude":{"available":true,"installed":false,"logins":[]},"codex":{"available":true,"installed":true,"logins":[]}}"#).unwrap();
    assert!(!status.claude.installed && status.codex.installed);
}
#[test]
fn failed_actions_keep_the_engine_line_and_add_the_stderr_detail() {
    let fake = Fake::response(3, "Blocked: no\n").with_stderr("warning\nfatal: disk full\n");
    let engine = SubprocessEngine::new(PathBuf::from("fake"), &fake);
    assert_eq!(
        engine
            .action("claude-login", "use", "home", None)
            .unwrap()
            .message,
        "Blocked: no (fatal: disk full)"
    );
    assert_eq!(
        engine.status(false).unwrap_err(),
        "Blocked: no (fatal: disk full)"
    );
    let same = Fake::response(3, "Blocked: no\n").with_stderr("Blocked: no\n");
    let engine = SubprocessEngine::new(PathBuf::from("fake"), &same);
    assert_eq!(
        engine
            .action("claude-login", "use", "home", None)
            .unwrap()
            .message,
        "Blocked: no"
    );
}
#[test]
fn successful_actions_show_only_the_engine_line() {
    let fake = Fake::response(0, "Switched\n").with_stderr("noise\n");
    let engine = SubprocessEngine::new(PathBuf::from("fake"), &fake);
    assert_eq!(
        engine
            .action("claude-login", "use", "home", None)
            .unwrap()
            .message,
        "Switched"
    );
}
#[test]
fn settings_default_to_off_for_older_engines() {
    let status = parse(SAMPLE).unwrap();
    assert!(!status.settings.refresh.enabled);
    assert_eq!(status.settings.refresh.interval_seconds, 300);
}
#[test]
fn run_passes_arguments_and_keeps_every_output_line() {
    let fake = Fake::response(
        0,
        "Claude: switched from a to b.\nCodex: automatic switching is off.\n",
    );
    let engine = SubprocessEngine::new(PathBuf::from("fake"), &fake);
    let (lines, success) = engine
        .lines(&["auto-switch".into(), "check".into()])
        .unwrap();
    assert!(success);
    assert_eq!(
        lines,
        [
            "Claude: switched from a to b.",
            "Codex: automatic switching is off."
        ]
    );
    assert_eq!(
        fake.calls(),
        vec![(vec!["auto-switch".into(), "check".into()], false)]
    );
}
#[test]
fn auto_switch_settings_default_to_off() {
    let status = parse(SAMPLE).unwrap();
    assert!(!status.settings.auto_switch.claude && !status.settings.auto_switch.codex);
    assert_eq!(status.settings.auto_switch.threshold_percent, 99);
}
