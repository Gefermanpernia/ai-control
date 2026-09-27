use serde::Deserialize;

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Window {
    pub label: String,
    pub used_percent: f64,
    pub resets_at: Option<String>,
}
#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Usage {
    pub windows: Vec<Window>,
    pub resets_available: Option<i64>,
    pub fetched_at: String,
}
#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaudeLogin {
    pub name: String,
    pub needs_login: bool,
    pub usage: Option<Usage>,
    pub usage_error: Option<String>,
}
#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CodexLogin {
    pub name: String,
    pub email: Option<String>,
    pub usage: Option<Usage>,
    pub usage_error: Option<String>,
}
#[derive(Clone, Debug, Deserialize)]
pub struct Provider<T> {
    pub available: bool,
    /// Whether the provider's CLI is on this system; engines before 0.3.1 do not report it.
    #[serde(default = "installed_by_default")]
    pub installed: bool,
    pub logins: Vec<T>,
    #[serde(default)]
    pub selected: Option<String>,
    #[serde(default, rename = "inUse")]
    pub in_use: Option<String>,
}
#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelUsage {
    pub model: String,
    pub total_tokens: i64,
    pub quota_tokens: Option<i64>,
    pub used_percent: Option<f64>,
    pub resets_at: Option<String>,
}
#[derive(Clone, Debug, Deserialize)]
pub struct Monitor {
    pub id: String,
    pub name: String,
    pub usage: Option<Usage>,
    pub models: Option<Vec<ModelUsage>>,
    pub error: Option<String>,
}
#[derive(Clone, Debug, Deserialize)]
pub struct Status {
    pub version: u32,
    pub claude: Provider<ClaudeLogin>,
    pub codex: Provider<CodexLogin>,
    #[serde(default)]
    pub monitors: Vec<Monitor>,
}
fn installed_by_default() -> bool {
    true
}
pub fn parse(text: &str) -> Result<Status, String> {
    let status: Status =
        serde_json::from_str(text).map_err(|e| format!("Invalid engine status: {e}"))?;
    if status.version != 1 {
        return Err(format!(
            "Unsupported engine status version {} (expected 1)",
            status.version
        ));
    }
    Ok(status)
}
