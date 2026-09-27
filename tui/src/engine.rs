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
fn forward(mut reader: impl Read, mut writer: impl Write) -> Vec<u8> {
    let mut all = Vec::new();
    let mut chunk = [0; 4096];
    while let Ok(n) = reader.read(&mut chunk) {
        if n == 0 {
            break;
        }
        let _ = writer.write_all(&chunk[..n]);
        let _ = writer.flush();
        all.extend_from_slice(&chunk[..n]);
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
        Ok(Outcome {
            success: out.status.success(),
            message: message(&out.stdout, &out.stderr),
        })
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
            return Err(message(&out.stdout, &out.stderr));
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
        Ok(Outcome {
            success: out.status.success(),
            message: message(&out.stdout, &out.stderr),
        })
    }
}
