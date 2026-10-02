use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
    process::Stdio,
    sync::Arc,
    time::Duration,
};

use crate::monitor::{MonitorConfig, MonitorControlId, MonitorController, MonitorSnapshot};
use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::{io::AsyncReadExt, process::Command, time::timeout};

const PROBE_TIMEOUT: Duration = Duration::from_secs(2);
const ACTION_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_PROBE_BYTES: u64 = 64 * 1024;
const MPRIS_PATH: &str = "/org/mpris/MediaPlayer2";
const MPRIS_PLAYER: &str = "org.mpris.MediaPlayer2.Player";

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct AudioSnapshot {
    pub available: bool,
    pub volume_percent: Option<u32>,
    pub muted: Option<bool>,
    pub microphone_muted: Option<bool>,
    pub default_output_id: Option<u32>,
    pub outputs: Vec<AudioOutput>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AudioOutput {
    pub id: u32,
    pub name: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct MediaSnapshot {
    pub available: bool,
    pub player: Option<String>,
    pub identity: Option<String>,
    pub playback_status: Option<String>,
    pub title: Option<String>,
    pub artist: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StorageView {
    pub mount: String,
    pub total_bytes: u64,
    pub available_bytes: u64,
    pub used_percent: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProcessView {
    pub pid: u32,
    pub name: String,
    pub cpu_percent: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EdgeBrightnessSnapshot {
    pub available: bool,
    pub percent: Option<u32>,
    pub reason: Option<String>,
}

impl Default for EdgeBrightnessSnapshot {
    fn default() -> Self {
        Self {
            available: false,
            percent: None,
            reason: Some("Monitor capabilities have not been read".into()),
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct OmarchySnapshot {
    pub audio: AudioSnapshot,
    pub media: MediaSnapshot,
    pub dnd: Option<bool>,
    pub keepawake: Option<bool>,
    pub nightlight: Option<bool>,
    pub recording: Option<bool>,
    pub theme: Option<String>,
    pub themes: Vec<String>,
    pub power_profile: Option<String>,
    pub power_profiles: Vec<String>,
    pub storage: Vec<StorageView>,
    pub processes: Vec<ProcessView>,
    pub edge_brightness: EdgeBrightnessSnapshot,
    #[serde(default)]
    pub monitor: MonitorSnapshot,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaCommand {
    PlayPause,
    Next,
    Previous,
    Stop,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
pub enum OmarchyRequest {
    Volume {
        percent: u8,
    },
    Mute {
        muted: bool,
    },
    MicrophoneMute {
        muted: bool,
    },
    Output {
        id: u32,
    },
    Media {
        command: MediaCommand,
    },
    ToggleDnd {},
    ToggleKeepawake {},
    ToggleNightlight {},
    Screenshot {},
    StartRecording {},
    StopRecording {},
    Lock {},
    SetTheme {
        name: String,
    },
    SetPowerProfile {
        profile: String,
    },
    EdgeBrightness {
        percent: u8,
    },
    MonitorRefresh {},
    MonitorSet {
        control: MonitorControlId,
        value: u16,
    },
}

#[derive(Debug)]
pub struct OmarchyController {
    home: PathBuf,
    proc_root: PathBuf,
    previous_processes: Option<(u64, HashMap<u32, ProcessCounters>)>,
    monitor: Arc<MonitorController>,
}

pub(crate) fn brightness_projection(monitor: &MonitorSnapshot) -> EdgeBrightnessSnapshot {
    let control = monitor
        .controls
        .iter()
        .find(|v| v.id == MonitorControlId::Brightness);
    let available = monitor.available
        && monitor.identity_verified
        && control.is_some_and(|v| v.supported && v.writable);
    let percent = control
        .and_then(|v| v.current.zip(v.maximum))
        .filter(|(_, max)| *max > 0)
        .map(|(current, maximum)| u32::from(current) * 100 / u32::from(maximum));
    EdgeBrightnessSnapshot {
        available,
        percent,
        reason: if available {
            None
        } else {
            control
                .and_then(|v| v.reason.clone())
                .or_else(|| monitor.reason.clone())
        },
    }
}

#[derive(Debug, Clone, Copy)]
struct ProcessCounters {
    start_time: u64,
    ticks: u64,
}

impl Default for OmarchyController {
    fn default() -> Self {
        Self {
            home: std::env::var_os("HOME")
                .map(PathBuf::from)
                .unwrap_or_default(),
            proc_root: "/proc".into(),
            previous_processes: None,
            monitor: Arc::new(MonitorController::new(MonitorConfig::default())),
        }
    }
}

impl OmarchyController {
    pub fn with_monitor(monitor: Arc<MonitorController>) -> Self {
        Self {
            monitor,
            ..Self::default()
        }
    }

    pub async fn sample(&mut self) -> OmarchySnapshot {
        let (audio, media, dnd, idle, nightlight, recording, themes, profile, profiles, storage) = tokio::join!(
            sample_audio(),
            sample_media(),
            probe("omarchy-shell", &["notifications", "dndState"]),
            probe("omarchy", &["toggle", "idle", "--status"]),
            probe("hyprctl", &["hyprsunset", "temperature"]),
            recording_state(),
            probe("omarchy", &["theme", "list"]),
            probe("powerprofilesctl", &["get"]),
            probe("powerprofilesctl", &["list"]),
            sample_storage(&self.home),
        );
        let current_theme =
            fs::read_to_string(self.home.join(".local/state/omarchy/current/theme.name"))
                .ok()
                .and_then(|name| theme_slug(name.trim()));
        let monitor = self.monitor.snapshot().await;
        let edge_brightness = brightness_projection(&monitor);
        OmarchySnapshot {
            audio,
            media,
            dnd: dnd.ok().and_then(|value| parse_on_off(&value)),
            keepawake: idle.ok().and_then(|value| parse_enabled(&value)),
            nightlight: nightlight.ok().and_then(|value| parse_nightlight(&value)),
            recording,
            theme: current_theme,
            themes: themes
                .ok()
                .map_or_else(Vec::new, |value| parse_themes(&value)),
            power_profile: profile.ok().and_then(|value| power_profile(value.trim())),
            power_profiles: profiles
                .ok()
                .map_or_else(Vec::new, |value| parse_profiles(&value)),
            storage,
            processes: self.sample_processes(),
            edge_brightness,
            monitor,
        }
    }

    pub async fn perform(&self, request: &OmarchyRequest) -> Result<String> {
        match request {
            OmarchyRequest::MonitorRefresh {} => return self.monitor.refresh().await,
            OmarchyRequest::MonitorSet { control, value } => {
                return self.monitor.set(*control, *value).await;
            }
            OmarchyRequest::EdgeBrightness { percent } => {
                return self.monitor.brightness_percent(*percent).await;
            }
            _ => {}
        }
        // Fresh probes constrain dynamic IDs/names at the daemon boundary. No
        // QML-provided executable, argument vector, shell text, or bus name is used.
        let context = match request {
            OmarchyRequest::Output { .. } => OmarchySnapshot {
                audio: sample_audio().await,
                ..OmarchySnapshot::default()
            },
            OmarchyRequest::Media { .. } => OmarchySnapshot {
                media: sample_media().await,
                ..OmarchySnapshot::default()
            },
            OmarchyRequest::SetTheme { .. } => OmarchySnapshot {
                themes: parse_themes(&probe("omarchy", &["theme", "list"]).await?),
                ..OmarchySnapshot::default()
            },
            OmarchyRequest::SetPowerProfile { .. } => OmarchySnapshot {
                power_profiles: parse_profiles(&probe("powerprofilesctl", &["list"]).await?),
                ..OmarchySnapshot::default()
            },
            OmarchyRequest::StartRecording {} | OmarchyRequest::StopRecording {} => {
                OmarchySnapshot {
                    recording: recording_state().await,
                    ..OmarchySnapshot::default()
                }
            }
            _ => OmarchySnapshot::default(),
        };
        let specification = action_spec(request, &context)?;
        let mut command = Command::new(specification.program);
        command
            .args(&specification.args)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .kill_on_drop(true);
        let status = timeout(ACTION_TIMEOUT, command.status())
            .await
            .context("desktop control timed out; action was not retried")??;
        if !status.success() {
            bail!("desktop control failed with exit status {status}");
        }
        Ok("Desktop control completed".into())
    }

    fn sample_processes(&mut self) -> Vec<ProcessView> {
        let total = fs::read_to_string(self.proc_root.join("stat"))
            .ok()
            .and_then(|text| process_cpu_total(&text));
        let Some(total) = total else {
            self.previous_processes = None;
            return Vec::new();
        };
        let mut current = HashMap::new();
        let mut processes = Vec::new();
        let total_delta = self
            .previous_processes
            .as_ref()
            .and_then(|(previous, _)| total.checked_sub(*previous))
            .filter(|delta| *delta > 0);
        let mut entries: Vec<_> = fs::read_dir(&self.proc_root)
            .into_iter()
            .flat_map(|entries| entries.flatten())
            .filter_map(|entry| {
                let pid = entry.file_name().to_str()?.parse::<u32>().ok()?;
                Some((pid, entry.path()))
            })
            .collect();
        entries.sort_by_key(|(pid, _)| *pid);
        for (pid, path) in entries.into_iter().take(4096) {
            let Some((name, counters)) = fs::read_to_string(path.join("stat"))
                .ok()
                .and_then(|text| parse_process_stat(&text))
            else {
                continue;
            };
            if let Some((_, previous)) = &self.previous_processes
                && let Some(prior) = previous.get(&pid)
                && prior.start_time == counters.start_time
                && let Some(delta) = counters.ticks.checked_sub(prior.ticks)
                && let Some(total_delta) = total_delta
            {
                let cpu_percent = 100.0 * delta as f64 / total_delta as f64;
                if (0.0..=100.0).contains(&cpu_percent) && cpu_percent > 0.0 {
                    processes.push(ProcessView {
                        pid,
                        name,
                        cpu_percent,
                    });
                }
            }
            current.insert(pid, counters);
        }
        self.previous_processes = Some((total, current));
        processes.sort_by(|left, right| {
            right
                .cpu_percent
                .total_cmp(&left.cpu_percent)
                .then(left.pid.cmp(&right.pid))
        });
        processes.truncate(5);
        processes
    }
}

#[derive(Debug, PartialEq, Eq)]
struct CommandSpec {
    program: &'static str,
    args: Vec<String>,
}

fn specification(program: &'static str, args: &[&str]) -> CommandSpec {
    CommandSpec {
        program,
        args: args.iter().map(|arg| (*arg).into()).collect(),
    }
}

fn action_spec(request: &OmarchyRequest, current: &OmarchySnapshot) -> Result<CommandSpec> {
    Ok(match request {
        OmarchyRequest::Volume { percent } => {
            if *percent > 100 {
                bail!("volume must be between 0 and 100 percent")
            }
            specification(
                "wpctl",
                &["set-volume", "@DEFAULT_AUDIO_SINK@", &format!("{percent}%")],
            )
        }
        OmarchyRequest::Mute { muted } => specification(
            "wpctl",
            &[
                "set-mute",
                "@DEFAULT_AUDIO_SINK@",
                if *muted { "1" } else { "0" },
            ],
        ),
        OmarchyRequest::MicrophoneMute { muted } => specification(
            "wpctl",
            &[
                "set-mute",
                "@DEFAULT_AUDIO_SOURCE@",
                if *muted { "1" } else { "0" },
            ],
        ),
        OmarchyRequest::Output { id } => {
            if !current.audio.available
                || !current.audio.outputs.iter().any(|output| output.id == *id)
            {
                bail!("audio output is no longer available")
            }
            specification("wpctl", &["set-default", &id.to_string()])
        }
        OmarchyRequest::Media { command } => {
            let Some(player) = current
                .media
                .player
                .as_deref()
                .filter(|player| valid_player(player))
            else {
                bail!("media player is unavailable")
            };
            if !current.media.available {
                bail!("media player is unavailable")
            }
            let method = match command {
                MediaCommand::PlayPause => "PlayPause",
                MediaCommand::Next => "Next",
                MediaCommand::Previous => "Previous",
                MediaCommand::Stop => "Stop",
            };
            specification(
                "busctl",
                &[
                    "--user",
                    "--timeout=1",
                    "call",
                    player,
                    MPRIS_PATH,
                    MPRIS_PLAYER,
                    method,
                ],
            )
        }
        OmarchyRequest::ToggleDnd {} => {
            specification("omarchy", &["toggle", "notification-silencing"])
        }
        OmarchyRequest::ToggleKeepawake {} => specification("omarchy", &["toggle", "idle"]),
        OmarchyRequest::ToggleNightlight {} => specification("omarchy", &["toggle", "nightlight"]),
        OmarchyRequest::Screenshot {} => {
            specification("omarchy", &["capture", "screenshot", "fullscreen", "save"])
        }
        OmarchyRequest::StartRecording {} => {
            if current.recording != Some(false) {
                bail!("recording state is unavailable or already active")
            }
            specification("omarchy", &["capture", "screenrecording", "--fullscreen"])
        }
        OmarchyRequest::StopRecording {} => {
            if current.recording != Some(true) {
                bail!("recording is unavailable or not active")
            }
            specification(
                "omarchy",
                &["capture", "screenrecording", "--stop-recording"],
            )
        }
        OmarchyRequest::Lock {} => specification("omarchy", &["system", "lock"]),
        OmarchyRequest::SetTheme { name } => {
            let Some(slug) = theme_slug(name) else {
                bail!("invalid theme name")
            };
            if !current.themes.contains(&slug) {
                bail!("theme is not installed")
            }
            specification("omarchy", &["theme", "set", &slug])
        }
        OmarchyRequest::SetPowerProfile { profile } => {
            if power_profile(profile).is_none() || !current.power_profiles.contains(profile) {
                bail!("power profile is unavailable")
            }
            specification("powerprofilesctl", &["set", profile])
        }
        OmarchyRequest::EdgeBrightness { .. }
        | OmarchyRequest::MonitorRefresh {}
        | OmarchyRequest::MonitorSet { .. } => {
            bail!("monitor actions require the exact DDC controller")
        }
    })
}

async fn probe(program: &'static str, args: &[&str]) -> Result<String> {
    let (success, text) = probe_status(program, args).await?;
    if !success.success() {
        bail!("desktop probe {program} is unavailable")
    }
    Ok(text)
}

async fn probe_status(
    program: &'static str,
    args: &[&str],
) -> Result<(std::process::ExitStatus, String)> {
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .with_context(|| format!("starting desktop probe {program}"))?;
    let stdout = child.stdout.take().context("desktop probe has no stdout")?;
    let mut stdout = stdout.take(MAX_PROBE_BYTES + 1);
    let mut bytes = Vec::new();
    let (status, _) = timeout(PROBE_TIMEOUT, async {
        tokio::try_join!(child.wait(), stdout.read_to_end(&mut bytes))
    })
    .await
    .context("desktop probe timed out")??;
    if bytes.len() as u64 > MAX_PROBE_BYTES {
        bail!("desktop probe output exceeded its bound")
    }
    Ok((
        status,
        String::from_utf8(bytes).context("desktop probe returned invalid UTF-8")?,
    ))
}

async fn recording_state() -> Option<bool> {
    // Matches Omarchy's recording indicator and capture command exactly.
    probe_status("pgrep", &["--quiet", "-f", "^gpu-screen-recorder"])
        .await
        .ok()
        .and_then(|(status, _)| match status.code() {
            Some(0) => Some(true),
            Some(1) => Some(false),
            _ => None,
        })
}

async fn sample_audio() -> AudioSnapshot {
    let (status, sink, source) = tokio::join!(
        probe("wpctl", &["status"]),
        probe("wpctl", &["get-volume", "@DEFAULT_AUDIO_SINK@"]),
        probe("wpctl", &["get-volume", "@DEFAULT_AUDIO_SOURCE@"]),
    );
    let mut snapshot = status
        .ok()
        .map_or_else(AudioSnapshot::default, |text| parse_audio_outputs(&text));
    if let Some((volume, muted)) = sink.ok().and_then(|text| parse_volume(&text)) {
        snapshot.volume_percent = Some(volume);
        snapshot.muted = Some(muted);
        snapshot.available = true;
    }
    snapshot.microphone_muted = source
        .ok()
        .and_then(|text| parse_volume(&text))
        .map(|(_, muted)| muted);
    snapshot
}

fn parse_volume(text: &str) -> Option<(u32, bool)> {
    let mut fields = text.trim().strip_prefix("Volume:")?.split_whitespace();
    let volume = fields.next()?.parse::<f64>().ok()?;
    if !volume.is_finite() || !(0.0..=10.0).contains(&volume) {
        return None;
    }
    let muted = match fields.next() {
        None => false,
        Some("[MUTED]") => true,
        _ => return None,
    };
    if fields.next().is_some() {
        return None;
    }
    Some(((volume * 100.0).round() as u32, muted))
}

fn parse_audio_outputs(text: &str) -> AudioSnapshot {
    let mut snapshot = AudioSnapshot::default();
    let mut audio = false;
    let mut sinks = false;
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed == "Audio" {
            audio = true;
            continue;
        }
        if trimmed == "Video" || trimmed == "Settings" {
            audio = false;
            sinks = false;
            continue;
        }
        if !audio {
            continue;
        }
        if trimmed.contains("Sinks:") {
            sinks = true;
            continue;
        }
        if trimmed.contains("Sources:")
            || trimmed.contains("Filters:")
            || trimmed.contains("Streams:")
        {
            sinks = false;
            continue;
        }
        if !sinks {
            continue;
        }
        let Some((prefix, rest)) = trimmed.split_once('.') else {
            continue;
        };
        let Some(id) = prefix
            .split(|character: char| !character.is_ascii_digit())
            .rfind(|part| !part.is_empty())
            .and_then(|part| part.parse::<u32>().ok())
        else {
            continue;
        };
        let name = safe_text(rest.split("[vol:").next().unwrap_or_default(), 96);
        if name.is_empty() || snapshot.outputs.iter().any(|output| output.id == id) {
            continue;
        }
        if prefix.contains('*') {
            snapshot.default_output_id = Some(id);
        }
        snapshot.outputs.push(AudioOutput { id, name });
        if snapshot.outputs.len() == 32 {
            break;
        }
    }
    snapshot
}

async fn sample_media() -> MediaSnapshot {
    let Ok(names) = probe(
        "busctl",
        &["--user", "--no-pager", "--no-legend", "--list", "list"],
    )
    .await
    else {
        return MediaSnapshot::default();
    };
    let mut players: Vec<_> = names
        .lines()
        .filter_map(|line| line.split_whitespace().next())
        .filter(|name| valid_player(name))
        .map(str::to_owned)
        .collect();
    players.sort();
    players.dedup();
    let mut selected = MediaSnapshot::default();
    for player in players.into_iter().take(4) {
        let (status, identity, metadata) = tokio::join!(
            mpris_property(&player, MPRIS_PLAYER, "PlaybackStatus"),
            mpris_property(&player, "org.mpris.MediaPlayer2", "Identity"),
            mpris_property(&player, MPRIS_PLAYER, "Metadata"),
        );
        let Some(status) = status
            .and_then(|value| bus_string(&value))
            .filter(|value| matches!(value.as_str(), "Playing" | "Paused" | "Stopped"))
        else {
            continue;
        };
        let (title, artist) = metadata.as_ref().map_or((None, None), media_metadata);
        let snapshot = MediaSnapshot {
            available: true,
            player: Some(player),
            identity: identity.and_then(|value| bus_string(&value)),
            playback_status: Some(status.clone()),
            title,
            artist,
        };
        if status == "Playing" {
            return snapshot;
        }
        if !selected.available {
            selected = snapshot
        }
    }
    selected
}

async fn mpris_property(player: &str, interface: &str, property: &str) -> Option<Value> {
    let text = probe(
        "busctl",
        &[
            "--user",
            "--timeout=1",
            "--json=short",
            "get-property",
            player,
            MPRIS_PATH,
            interface,
            property,
        ],
    )
    .await
    .ok()?;
    serde_json::from_str(&text).ok()
}

fn valid_player(name: &str) -> bool {
    name.strip_prefix("org.mpris.MediaPlayer2.")
        .is_some_and(|suffix| {
            !suffix.is_empty()
                && name.len() <= 255
                && suffix.bytes().all(|byte| {
                    byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'.' || byte == b'-'
                })
        })
}

fn bus_string(value: &Value) -> Option<String> {
    if value["type"] != "s" {
        return None;
    }
    value["data"]
        .as_str()
        .map(|text| safe_text(text, 160))
        .filter(|text| !text.is_empty())
}

fn media_metadata(value: &Value) -> (Option<String>, Option<String>) {
    if value["type"] != "a{sv}" {
        return (None, None);
    }
    let data = &value["data"];
    let title = bus_string(&data["xesam:title"]);
    let artists = &data["xesam:artist"];
    let artist = if artists["type"] == "as" {
        artists["data"]
            .as_array()
            .map(|values| {
                values
                    .iter()
                    .take(4)
                    .filter_map(Value::as_str)
                    .map(|text| safe_text(text, 80))
                    .collect::<Vec<_>>()
                    .join(", ")
            })
            .filter(|text| !text.is_empty())
    } else {
        None
    };
    (title, artist)
}

fn safe_text(text: &str, maximum: usize) -> String {
    text.trim()
        .chars()
        .filter(|character| !character.is_control())
        .take(maximum)
        .collect()
}

fn parse_on_off(text: &str) -> Option<bool> {
    match text.trim() {
        "on" => Some(true),
        "off" => Some(false),
        _ => None,
    }
}

fn parse_enabled(text: &str) -> Option<bool> {
    serde_json::from_str::<Value>(text).ok()?["enabled"].as_bool()
}

fn parse_nightlight(text: &str) -> Option<bool> {
    let temperature = text.trim().parse::<u32>().ok()?;
    (1000..=25000)
        .contains(&temperature)
        .then_some(temperature < 6000)
}

fn theme_slug(name: &str) -> Option<String> {
    if name.is_empty()
        || name.len() > 80
        || !name
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b' ' || byte == b'-')
    {
        return None;
    }
    let slug = name.to_ascii_lowercase().replace(' ', "-");
    (!slug.starts_with('-') && !slug.ends_with('-')).then_some(slug)
}

fn parse_themes(text: &str) -> Vec<String> {
    let mut themes: Vec<_> = text
        .lines()
        .filter_map(|line| theme_slug(line.trim()))
        .take(64)
        .collect();
    themes.sort();
    themes.dedup();
    themes
}

fn power_profile(name: &str) -> Option<String> {
    matches!(name, "power-saver" | "balanced" | "performance").then(|| name.to_owned())
}

fn parse_profiles(text: &str) -> Vec<String> {
    let mut profiles: Vec<_> = text
        .lines()
        .filter_map(|line| {
            power_profile(
                line.trim()
                    .trim_start_matches('*')
                    .trim()
                    .strip_suffix(':')?,
            )
        })
        .collect();
    profiles.sort();
    profiles.dedup();
    profiles
}

async fn sample_storage(home: &Path) -> Vec<StorageView> {
    let Some(home) = home.to_str().filter(|path| !path.is_empty()) else {
        return Vec::new();
    };
    probe(
        "df",
        &["-B1", "--output=target,size,avail", "--", "/", home],
    )
    .await
    .ok()
    .map_or_else(Vec::new, |text| parse_storage(&text))
}

fn parse_storage(text: &str) -> Vec<StorageView> {
    let mut storage = Vec::new();
    for line in text.lines().skip(1).take(8) {
        let fields: Vec<_> = line.split_whitespace().collect();
        if fields.len() != 3 {
            continue;
        }
        let (Ok(total), Ok(available)) = (fields[1].parse::<u64>(), fields[2].parse::<u64>())
        else {
            continue;
        };
        if total == 0
            || available > total
            || !fields[0].starts_with('/')
            || storage
                .iter()
                .any(|entry: &StorageView| entry.mount == fields[0])
        {
            continue;
        }
        storage.push(StorageView {
            mount: safe_text(fields[0], 160),
            total_bytes: total,
            available_bytes: available,
            used_percent: 100.0 * (total - available) as f64 / total as f64,
        });
    }
    storage
}

fn process_cpu_total(text: &str) -> Option<u64> {
    let values: Vec<u64> = text
        .lines()
        .next()?
        .strip_prefix("cpu ")?
        .split_whitespace()
        .take(8)
        .map(str::parse)
        .collect::<std::result::Result<_, _>>()
        .ok()?;
    if values.len() < 4 {
        return None;
    }
    values.into_iter().try_fold(0_u64, u64::checked_add)
}

fn parse_process_stat(text: &str) -> Option<(String, ProcessCounters)> {
    let opening = text.find('(')?;
    let closing = text.rfind(')')?;
    if closing <= opening {
        return None;
    }
    let name = safe_text(&text[opening + 1..closing], 48);
    let fields: Vec<_> = text[closing + 1..].split_whitespace().collect();
    let ticks = fields
        .get(11)?
        .parse::<u64>()
        .ok()?
        .checked_add(fields.get(12)?.parse::<u64>().ok()?)?;
    let start_time = fields.get(19)?.parse::<u64>().ok()?;
    Some((name, ProcessCounters { start_time, ticks }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn request_schema_rejects_unknown_controls_fields_and_unbounded_values() {
        for value in [
            json!({"operation":"shell","command":"echo unsafe"}),
            json!({"operation":"lock","command":"unsafe"}),
            json!({"operation":"volume","percent":256}),
            json!({"operation":"media","command":"send_keys"}),
        ] {
            assert!(serde_json::from_value::<OmarchyRequest>(value).is_err());
        }
        assert!(
            action_spec(
                &OmarchyRequest::Volume { percent: 101 },
                &OmarchySnapshot::default()
            )
            .is_err()
        );
        assert!(
            action_spec(
                &OmarchyRequest::EdgeBrightness { percent: 10 },
                &OmarchySnapshot::default()
            )
            .is_err()
        );
    }

    #[test]
    fn controls_are_fixed_arguments_and_dynamic_targets_must_be_current() {
        let mut current = OmarchySnapshot::default();
        current.audio.available = true;
        current.audio.outputs.push(AudioOutput {
            id: 56,
            name: "Speakers".into(),
        });
        current.themes.push("tokyo-night".into());
        current.power_profiles.push("balanced".into());
        current.media.available = true;
        current.media.player = Some("org.mpris.MediaPlayer2.test".into());
        assert_eq!(
            action_spec(&OmarchyRequest::Volume { percent: 42 }, &current).unwrap(),
            specification("wpctl", &["set-volume", "@DEFAULT_AUDIO_SINK@", "42%"])
        );
        assert_eq!(
            action_spec(&OmarchyRequest::Output { id: 56 }, &current).unwrap(),
            specification("wpctl", &["set-default", "56"])
        );
        assert!(action_spec(&OmarchyRequest::Output { id: 999 }, &current).is_err());
        assert_eq!(
            action_spec(
                &OmarchyRequest::SetTheme {
                    name: "Tokyo Night".into()
                },
                &current
            )
            .unwrap(),
            specification("omarchy", &["theme", "set", "tokyo-night"])
        );
        for name in [
            "../theme",
            "$(touch /tmp/unsafe)",
            "--help",
            "not-installed",
        ] {
            assert!(
                action_spec(&OmarchyRequest::SetTheme { name: name.into() }, &current).is_err()
            );
        }
        assert!(
            action_spec(
                &OmarchyRequest::SetPowerProfile {
                    profile: "unknown".into()
                },
                &current
            )
            .is_err()
        );
        assert_eq!(
            action_spec(
                &OmarchyRequest::Media {
                    command: MediaCommand::Next
                },
                &current
            )
            .unwrap()
            .args
            .last()
            .unwrap(),
            "Next"
        );
        current.media.player = Some("org.mpris.MediaPlayer2.test;unsafe".into());
        assert!(
            action_spec(
                &OmarchyRequest::Media {
                    command: MediaCommand::Next
                },
                &current
            )
            .is_err()
        );
    }

    #[test]
    fn start_and_stop_recording_never_invert_a_known_state() {
        let mut current = OmarchySnapshot::default();
        assert!(action_spec(&OmarchyRequest::StartRecording {}, &current).is_err());
        assert!(action_spec(&OmarchyRequest::StopRecording {}, &current).is_err());
        current.recording = Some(false);
        assert!(action_spec(&OmarchyRequest::StartRecording {}, &current).is_ok());
        assert!(action_spec(&OmarchyRequest::StopRecording {}, &current).is_err());
        current.recording = Some(true);
        assert!(action_spec(&OmarchyRequest::StartRecording {}, &current).is_err());
        assert!(action_spec(&OmarchyRequest::StopRecording {}, &current).is_ok());
    }

    #[test]
    fn volume_and_output_parsers_distinguish_audio_video_and_muted_zero() {
        assert_eq!(parse_volume("Volume: 0.00 [MUTED]\n"), Some((0, true)));
        assert_eq!(parse_volume("Volume: 1.20"), Some((120, false)));
        for text in ["Volume: NaN", "Volume: -1", "Volume: 0.5 junk", "other"] {
            assert_eq!(parse_volume(text), None);
        }
        let snapshot = parse_audio_outputs(
            "Audio\n ├─ Sinks:\n │ * 56. Speakers [vol: 0.20]\n │ 60. HDMI [vol: 0.4]\n ├─ Sources:\n │ * 57. Microphone [vol: 0.9]\nVideo\n ├─ Sinks:\n │ * 99. Camera\n",
        );
        assert_eq!(snapshot.default_output_id, Some(56));
        assert_eq!(snapshot.outputs.len(), 2);
        assert_eq!(snapshot.outputs[0].name, "Speakers");
        assert_eq!(snapshot.outputs[1].id, 60);
    }

    #[test]
    fn metadata_is_a_bounded_projection_not_raw_provider_data() {
        let value = json!({"type":"a{sv}","data":{"xesam:title":{"type":"s","data":" Track\n "},"xesam:artist":{"type":"as","data":["Artist"]},"xesam:url":{"type":"s","data":"private-file-url"}}});
        assert_eq!(
            media_metadata(&value),
            (Some("Track".into()), Some("Artist".into()))
        );
        assert_eq!(bus_string(&json!({"type":"b","data":true})), None);
        assert_eq!(
            media_metadata(&json!({"type":"s","data":"unsafe"})),
            (None, None)
        );
        assert!(!valid_player("org.mpris.MediaPlayer2."));
        assert!(!valid_player("org.freedesktop.Notifications"));
    }

    #[test]
    fn feature_and_storage_parsers_fail_closed() {
        assert_eq!(parse_on_off("off"), Some(false));
        assert_eq!(parse_on_off("invalid"), None);
        assert_eq!(parse_enabled(r#"{"enabled":false}"#), Some(false));
        assert_eq!(parse_enabled(r#"{"enabled":"false"}"#), None);
        assert_eq!(parse_nightlight("4000"), Some(true));
        assert_eq!(parse_nightlight("6500"), Some(false));
        assert_eq!(parse_nightlight("Could not connect"), None);
        assert_eq!(
            parse_profiles("* performance:\n balanced:\n power-saver:\n unknown:\n"),
            ["balanced", "performance", "power-saver"]
        );
        let storage = parse_storage(
            "Mounted on 1B-blocks Avail\n/ 1000 250\n/ 1000 250\n/home 0 0\n/bad 100 200\n",
        );
        assert_eq!(storage.len(), 1);
        assert_eq!(storage[0].used_percent, 75.0);
    }

    fn stat(name: &str, ticks: u64, start: u64) -> String {
        let mut fields = vec!["0".to_owned(); 20];
        fields[0] = "S".into();
        fields[11] = ticks.to_string();
        fields[19] = start.to_string();
        format!("42 ({name}) {}", fields.join(" "))
    }

    #[test]
    fn process_projection_handles_parentheses_counter_resets_and_pid_reuse() {
        let root = tempfile::tempdir().unwrap();
        fs::create_dir_all(root.path().join("42")).unwrap();
        fs::write(root.path().join("stat"), "cpu  100 0 0 900 0 0 0 0 80 0\n").unwrap();
        fs::write(root.path().join("42/stat"), stat("worker (qa)", 10, 3)).unwrap();
        let mut controller = OmarchyController {
            home: root.path().into(),
            proc_root: root.path().into(),
            previous_processes: None,
            ..OmarchyController::default()
        };
        assert!(controller.sample_processes().is_empty());
        fs::write(root.path().join("stat"), "cpu  120 0 0 980 0 0 0 0 80 0\n").unwrap();
        fs::write(root.path().join("42/stat"), stat("worker (qa)", 25, 3)).unwrap();
        let processes = controller.sample_processes();
        assert_eq!(processes.len(), 1);
        assert_eq!(processes[0].name, "worker (qa)");
        assert_eq!(processes[0].cpu_percent, 15.0);
        fs::write(root.path().join("42/stat"), stat("worker", 500, 4)).unwrap();
        assert!(controller.sample_processes().is_empty());
        assert!(parse_process_stat("42 broken").is_none());
        assert_eq!(process_cpu_total("cpu  1 bad 3 4"), None);
    }
}
