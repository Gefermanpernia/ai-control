use crate::status::{parse, Status};
use std::{
    collections::HashMap,
    io::{self, Read, Write},
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
};

pub fn engine_path(exe: &Path, env: &HashMap<String, String>) -> PathBuf {
    if let Some(path) = env.get("AIC_ENGINE") {
        return PathBuf::from(path);
    }
    let dir = exe.parent().unwrap_or(Path::new("."));
    for path in [dir.join("AIControl"), dir.join("../MacOS/AIControl")] {
        if path.is_file() {
            return path;
        }
    }
    PathBuf::from("AIControl")
}

/// A missing engine is the usual setup problem (copied or source-built binaries), so name it and the fix.
fn run_error(path: &Path, error: io::Error) -> String {
    if error.kind() == io::ErrorKind::NotFound {
        format!(
            "AI Control engine not found ({}). Install the ai-control package, or set AIC_ENGINE to the AIControl binary.",
            path.display()
        )
    } else {
        format!(
            "Could not run the AI Control engine ({}): {error}",
            path.display()
        )
    }
}

pub fn message(stdout: &[u8], stderr: &[u8]) -> String {
    [stdout, stderr]
        .iter()
        .find_map(|stream| {
            String::from_utf8_lossy(stream)
                .lines()
                .rev()
                .find(|s| !s.trim().is_empty())
                .map(|s| s.trim().to_owned())
        })
        .unwrap_or_else(|| "Engine returned no message".into())
}
/// A failed command keeps the engine's own line (its result is always the last stdout line) and adds the
/// last stderr line, where a crash or a sign-in tool puts the underlying error.
fn failure_message(stdout: &[u8], stderr: &[u8]) -> String {
    let line = message(stdout, stderr);
    let detail = String::from_utf8_lossy(stderr)
        .lines()
        .rev()
        .find(|s| !s.trim().is_empty())
        .map(|s| s.trim().to_owned());
    match detail {
        Some(detail) if detail != line => format!("{line} ({detail})"),
        _ => line,
    }
}
fn outcome(out: &Output) -> Outcome {
    let success = out.status.success();
    Outcome {
        success,
        message: if success {
            message(&out.stdout, &out.stderr)
        } else {
            failure_message(&out.stdout, &out.stderr)
        },
    }
}
#[derive(Debug)]
pub struct Outcome {
    pub success: bool,
    pub message: String,
}

pub trait Runner {
    fn run(&self, executable: &Path, args: &[String], interactive: bool) -> io::Result<Output>;
}
pub struct ProcessRunner;
impl Runner for ProcessRunner {
    fn run(&self, executable: &Path, args: &[String], interactive: bool) -> io::Result<Output> {
        let mut cmd = Command::new(executable);
        cmd.args(args);
        if std::env::var_os("AI_CONTROL_CLAUDE_LIVE").is_none() {
            cmd.env("AI_CONTROL_CLAUDE_LIVE", "1");
        }
        if interactive {
            // Forward prompts immediately while retaining the engine's final human-readable line.
            cmd.stdin(Stdio::inherit())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped());
            let mut child = cmd.spawn()?;
            let out = child.stdout.take().expect("piped stdout");
            let err = child.stderr.take().expect("piped stderr");
            let stdout = std::thread::spawn(move || forward(out, io::stdout()));
            let stderr = std::thread::spawn(move || forward(err, io::stderr()));
            let status = child.wait()?;
            Ok(Output {
                status,
                stdout: stdout.join().unwrap_or_default(),
                stderr: stderr.join().unwrap_or_default(),
            })
        } else {
            cmd.output()
        }
    }
}
/// Shows the engine's output as it arrives and keeps a copy; interrupted reads are retried.
fn forward(mut reader: impl Read, mut writer: impl Write) -> Vec<u8> {
    let mut all = Vec::new();
    let mut chunk = [0; 4096];
    loop {
        match reader.read(&mut chunk) {
            Ok(0) => break,
            Ok(n) => {
                let _ = writer.write_all(&chunk[..n]);
                let _ = writer.flush();
                all.extend_from_slice(&chunk[..n]);
            }
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => {
                let note = format!("\nCould not read the engine output: {error}\n");
                let _ = writer.write_all(note.as_bytes());
                let _ = writer.flush();
                all.extend_from_slice(note.as_bytes());
                break;
            }
        }
    }
    all
}
pub trait Engine {
    fn status(&self, usage: bool) -> Result<Status, String>;
    fn action(
        &self,
        provider: &str,
        verb: &str,
        alias: &str,
        extra: Option<&str>,
    ) -> Result<Outcome, String>;
}
pub struct SubprocessEngine<R> {
    path: PathBuf,
    runner: R,
}
impl<R: Runner> SubprocessEngine<R> {
    pub fn new(path: PathBuf, runner: R) -> Self {
        Self { path, runner }
    }
    pub fn interactive_add(
        &self,
        provider: &str,
        alias: &str,
        email: Option<&str>,
    ) -> Result<Outcome, String> {
        let mut args = vec![provider.into(), "add".into(), alias.into()];
        if let Some(email) = email {
            args.push(email.into());
        }
        let out = self
            .runner
            .run(&self.path, &args, true)
            .map_err(|e| run_error(&self.path, e))?;
        Ok(outcome(&out))
    }
}
impl<R: Runner> SubprocessEngine<R> {
    /// Runs any engine command and keeps every non-empty stdout line, for commands that report per provider.
    pub fn lines(&self, args: &[String]) -> Result<(Vec<String>, bool), String> {
        let out = self
            .runner
            .run(&self.path, args, false)
            .map_err(|e| run_error(&self.path, e))?;
        let lines = String::from_utf8_lossy(&out.stdout)
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .map(str::to_owned)
            .collect();
        Ok((lines, out.status.success()))
    }
}
impl<R: Runner> Engine for SubprocessEngine<R> {
    fn status(&self, usage: bool) -> Result<Status, String> {
        let mut args = vec!["status".into(), "--json".into()];
        if usage {
            args.push("--usage".into());
        }
        let out = self
            .runner
            .run(&self.path, &args, false)
            .map_err(|e| run_error(&self.path, e))?;
        if !out.status.success() {
            return Err(failure_message(&out.stdout, &out.stderr));
        }
        parse(&String::from_utf8(out.stdout).map_err(|e| e.to_string())?)
    }
    fn action(
        &self,
        provider: &str,
        verb: &str,
        alias: &str,
        extra: Option<&str>,
    ) -> Result<Outcome, String> {
        let mut args = vec![provider.into(), verb.into(), alias.into()];
        if let Some(extra) = extra {
            args.push(extra.into());
        }
        let out = self
            .runner
            .run(&self.path, &args, false)
            .map_err(|e| run_error(&self.path, e))?;
        Ok(outcome(&out))
    }
}

#[cfg(test)]
mod tests {
    use super::forward;
    use std::io::{self, Read};

    /// Returns the queued results in order, then end of file.
    struct Script(Vec<io::Result<&'static [u8]>>);
    impl Read for Script {
        fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
            if self.0.is_empty() {
                return Ok(0);
            }
            match self.0.remove(0) {
                Ok(bytes) => {
                    buf[..bytes.len()].copy_from_slice(bytes);
                    Ok(bytes.len())
                }
                Err(error) => Err(error),
            }
        }
    }

    #[test]
    fn interrupted_reads_are_retried() {
        let mut shown = Vec::new();
        let kept = forward(
            Script(vec![
                Ok(b"one\n"),
                Err(io::ErrorKind::Interrupted.into()),
                Ok(b"two\n"),
            ]),
            &mut shown,
        );
        assert_eq!(kept, b"one\ntwo\n");
        assert_eq!(shown, b"one\ntwo\n");
    }

    #[test]
    fn other_read_errors_are_reported() {
        let mut shown = Vec::new();
        let kept = forward(
            Script(vec![Ok(b"one\n"), Err(io::Error::other("broken pipe"))]),
            &mut shown,
        );
        let kept = String::from_utf8(kept).unwrap();
        assert!(kept.starts_with("one\n"), "{kept}");
        assert!(
            kept.contains("Could not read the engine output: broken pipe"),
            "{kept}"
        );
        assert_eq!(String::from_utf8(shown).unwrap(), kept);
    }
}
