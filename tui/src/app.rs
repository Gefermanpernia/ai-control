use crate::status::Status;

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
}
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Mode {
    Normal,
    Confirm,
    Rename,
    AddAlias,
    AddEmail,
}
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
    pub updated: Option<String>,
}
impl App {
    pub fn new(status: Status) -> Self {
        Self {
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
            updated: None,
        }
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
            _ => "Working…",
        }
        .into();
        self.action_success = None;
    }
    pub fn result(&mut self, text: &str, success: bool) {
        self.message = text.into();
        self.action_success = Some(success);
        self.mode = Mode::Normal;
        self.target = None;
        self.input.clear();
    }
    pub fn status_error(&mut self, error: &str) {
        self.loading = None;
        self.status_loaded = true;
        self.message = error.into();
        self.action_success = Some(false);
    }
    pub fn apply_status(&mut self, mut status: Status, with_usage: bool) {
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
        self.loading = None;
        self.updated = Some(
            time::OffsetDateTime::now_utc()
                .format(&time::format_description::well_known::Rfc3339)
                .unwrap_or_else(|_| "unknown".into()),
        );
    }
    pub fn key(&mut self, key: Key) -> Effect {
        match self.mode {
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
            Mode::Rename | Mode::AddAlias | Mode::AddEmail => match key {
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
                Key::Tab => self.provider = 1 - self.provider,
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
pub fn valid_alias(alias: &str) -> bool {
    let bytes = alias.as_bytes();
    (1..=32).contains(&bytes.len())
        && bytes[0].is_ascii_lowercase()
        && bytes[1..]
            .iter()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || *b == b'_' || *b == b'-')
}
