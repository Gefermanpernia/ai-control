use aic_tui::{
    engine::{engine_path, message, Engine, Runner, SubprocessEngine},
    status::parse,
};
#[cfg(unix)]
use std::os::unix::process::ExitStatusExt;
use std::{collections::HashMap, path::PathBuf, process::Output, sync::Mutex};

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
}
impl Fake {
    fn response(code: i32, stdout: &str) -> Self {
        Self {
            code,
            stdout: stdout.as_bytes().to_vec(),
            ..Self::default()
        }
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
            status: std::process::ExitStatus::from_raw(self.code << 8),
            stdout: self.stdout.clone(),
            stderr: b"stderr fallback\n".to_vec(),
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
