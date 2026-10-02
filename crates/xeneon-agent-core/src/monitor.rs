//! Exact commissioned DRM/I2C monitor controls, independently sampled from PC health.
//! CLI wire formats follow https://www.ddcutil.com/command_getvcp/ and
//! https://www.ddcutil.com/performance_options/. No display-number fallback.
use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::Read,
    path::{Path, PathBuf},
    process::Stdio,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::{
    io::AsyncReadExt,
    process::Command,
    sync::{Mutex, Notify, RwLock},
    time::timeout,
};

const MAX_OUTPUT: u64 = 32 * 1024;
const PRESETS: &[u16] = &[1, 2, 4, 5, 6, 8, 11];

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct MonitorConfig {
    pub enabled: bool,
    /// Explicit user configuration, independent from the legacy commissioning flag.
    pub writes_enabled: bool,
    pub commissioning_file: Option<PathBuf>,
    pub refresh_ms: u64,
}
impl Default for MonitorConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            writes_enabled: false,
            commissioning_file: None,
            refresh_ms: 30_000,
        }
    }
}
impl MonitorConfig {
    pub fn validate(&self) -> Result<()> {
        if self.writes_enabled && !self.enabled {
            bail!("monitor writes require monitor.enabled");
        }
        if self.refresh_ms < 15_000 || self.refresh_ms > 300_000 {
            bail!("monitor.refresh_ms must be 15000..300000");
        }
        if self
            .commissioning_file
            .as_ref()
            .is_some_and(|p| !p.is_absolute())
        {
            bail!("monitor.commissioning_file must be absolute");
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MonitorControlId {
    Brightness,
    Backlight,
    Contrast,
    RedGain,
    GreenGain,
    BlueGain,
    Sharpness,
    ColorPreset,
}
impl MonitorControlId {
    fn code(self) -> u8 {
        match self {
            Self::Brightness => 0x10,
            Self::Backlight => 0x6b,
            Self::Contrast => 0x12,
            Self::RedGain => 0x16,
            Self::GreenGain => 0x18,
            Self::BlueGain => 0x1a,
            Self::Sharpness => 0x87,
            Self::ColorPreset => 0x14,
        }
    }
    fn label(self) -> &'static str {
        match self {
            Self::Brightness => "Monitor brightness",
            Self::Backlight => "Backlight level (white)",
            Self::Contrast => "Contrast",
            Self::RedGain => "Red gain",
            Self::GreenGain => "Green gain",
            Self::BlueGain => "Blue gain",
            Self::Sharpness => "Sharpness",
            Self::ColorPreset => "Color preset",
        }
    }
    fn rgb(self) -> bool {
        matches!(self, Self::RedGain | Self::GreenGain | Self::BlueGain)
    }
}
const CONTROLS: &[MonitorControlId] = &[
    MonitorControlId::Brightness,
    MonitorControlId::Backlight,
    MonitorControlId::Contrast,
    MonitorControlId::RedGain,
    MonitorControlId::GreenGain,
    MonitorControlId::BlueGain,
    MonitorControlId::Sharpness,
    MonitorControlId::ColorPreset,
];
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MonitorChoice {
    pub value: u16,
    pub label: String,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MonitorControl {
    pub id: MonitorControlId,
    pub label: String,
    pub kind: String,
    pub supported: bool,
    pub writable: bool,
    pub current: Option<u16>,
    pub maximum: Option<u16>,
    pub choices: Vec<MonitorChoice>,
    pub reason: Option<String>,
}
impl MonitorControl {
    fn unavailable(id: MonitorControlId, reason: &str) -> Self {
        Self {
            id,
            label: id.label().into(),
            kind: if id == MonitorControlId::ColorPreset {
                "enum"
            } else {
                "continuous"
            }
            .into(),
            supported: false,
            writable: false,
            current: None,
            maximum: None,
            choices: Vec::new(),
            reason: Some(reason.into()),
        }
    }
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MonitorDisplay {
    pub width: u32,
    pub height: u32,
    pub refresh_hz: f64,
    pub scale: f64,
    pub transform: u8,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MonitorTouch {
    pub connected: bool,
    pub device: String,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MonitorSnapshot {
    pub available: bool,
    pub identity_verified: bool,
    pub connector: Option<String>,
    pub serial: Option<String>,
    pub model: Option<String>,
    pub edid_sha256: Option<String>,
    pub i2c_bus: Option<u32>,
    pub refreshed_at_ms: u64,
    pub reason: Option<String>,
    pub controls: Vec<MonitorControl>,
    pub display: Option<MonitorDisplay>,
    pub touch: Option<MonitorTouch>,
}
impl Default for MonitorSnapshot {
    fn default() -> Self {
        Self {
            available: false,
            identity_verified: false,
            connector: None,
            serial: None,
            model: None,
            edid_sha256: None,
            i2c_bus: None,
            refreshed_at_ms: 0,
            reason: Some("Monitor capabilities have not been read".into()),
            controls: CONTROLS
                .iter()
                .map(|id| {
                    MonitorControl::unavailable(*id, "Monitor capabilities have not been read")
                })
                .collect(),
            display: None,
            touch: None,
        }
    }
}
#[derive(Debug, Deserialize)]
struct Commissioning {
    mode: String,
    output: CommissionedOutput,
    touch: Option<CommissionedTouch>,
}
#[derive(Debug, Deserialize)]
struct CommissionedOutput {
    connector: String,
    serial: String,
    model: String,
    edid_sha256: String,
    require_exact_match: bool,
    allow_primary_fallback: bool,
}
#[derive(Debug, Deserialize)]
struct CommissionedTouch {
    device: String,
}
#[derive(Debug, Clone, PartialEq, Eq)]
struct Target {
    connector: String,
    serial: String,
    model: String,
    hash: String,
    bus: u32,
    path: PathBuf,
}
#[derive(Debug)]
struct Paths {
    drm: PathBuf,
    i2c: PathBuf,
    dev: PathBuf,
    ddcutil: PathBuf,
    layout: bool,
}
impl Default for Paths {
    fn default() -> Self {
        Self {
            drm: "/sys/class/drm".into(),
            i2c: "/sys/class/i2c-dev".into(),
            dev: "/dev".into(),
            ddcutil: "/usr/bin/ddcutil".into(),
            layout: true,
        }
    }
}
#[derive(Debug)]
pub struct MonitorController {
    config: MonitorConfig,
    commissioning: PathBuf,
    paths: Paths,
    operation: Mutex<()>,
    snapshot: RwLock<MonitorSnapshot>,
    refresh_requested: Notify,
}
impl MonitorController {
    pub fn new(config: MonitorConfig) -> Self {
        let commissioning = config.commissioning_file.clone().unwrap_or_else(|| {
            let base = std::env::var_os("XDG_CONFIG_HOME")
                .map(PathBuf::from)
                .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
                .unwrap_or_default();
            base.join("xeneon-edge-agents/commissioning.toml")
        });
        Self {
            config,
            commissioning,
            paths: Paths::default(),
            operation: Mutex::new(()),
            snapshot: RwLock::new(MonitorSnapshot::default()),
            refresh_requested: Notify::new(),
        }
    }
    pub fn refresh_interval(&self) -> Duration {
        Duration::from_millis(self.config.refresh_ms)
    }
    /// Cached-only: no DDC or subprocess work on the dashboard/health collector.
    pub async fn snapshot(&self) -> MonitorSnapshot {
        self.snapshot.read().await.clone()
    }
    pub async fn wait_for_refresh(&self) {
        self.refresh_requested.notified().await;
    }
    #[cfg(test)]
    pub(crate) async fn hold_operation_for_test(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.operation.lock().await
    }
    pub async fn refresh(&self) -> Result<String> {
        let _guard = timeout(Duration::from_secs(20), self.operation.lock())
            .await
            .context("Monitor controller is busy; refresh was not queued")?;
        let result = timeout(Duration::from_secs(22), self.refresh_locked()).await;
        let next = match result {
            Ok(Ok(next)) => next,
            Ok(Err(error)) => self.failed_snapshot(&error.to_string()).await,
            Err(_) => {
                self.failed_snapshot("DDC refresh timed out; capabilities remain unavailable")
                    .await
            }
        };
        let available = next.available;
        let reason = next
            .reason
            .clone()
            .unwrap_or_else(|| "Monitor capabilities unavailable".into());
        *self.snapshot.write().await = next;
        if !available {
            bail!("{reason}");
        }
        Ok("Monitor capabilities refreshed from exact XENEON EDGE".into())
    }
    async fn failed_snapshot(&self, reason: &str) -> MonitorSnapshot {
        let mut snapshot = MonitorSnapshot {
            refreshed_at_ms: now(),
            reason: Some(bounded(reason)),
            controls: CONTROLS
                .iter()
                .map(|id| MonitorControl::unavailable(*id, &bounded(reason)))
                .collect(),
            ..MonitorSnapshot::default()
        };
        if let Ok((target, commissioning)) = self.discover() {
            snapshot.identity_verified = true;
            snapshot.connector = Some(target.connector.clone());
            snapshot.serial = Some(target.serial.clone());
            snapshot.model = Some(target.model.clone());
            snapshot.edid_sha256 = Some(target.hash.clone());
            snapshot.i2c_bus = Some(target.bus);
            if self.paths.layout {
                self.layout(&target, &commissioning, &mut snapshot).await;
            }
            if self.same_identity(&target).is_err() {
                snapshot.identity_verified = false;
                snapshot.connector = None;
                snapshot.serial = None;
                snapshot.model = None;
                snapshot.edid_sha256 = None;
                snapshot.i2c_bus = None;
                snapshot.display = None;
                snapshot.touch = None;
            }
        }
        snapshot
    }
    fn commissioned(&self) -> Result<Commissioning> {
        if !self.config.enabled {
            bail!("Monitor controls are disabled in configuration");
        }
        let text = read_bounded(&self.commissioning, 16 * 1024)
            .context("Monitor commissioning record is unavailable")?;
        let c: Commissioning = toml::from_str(std::str::from_utf8(&text)?)
            .context("Monitor commissioning record is invalid")?;
        if c.mode != "production"
            || !c.output.require_exact_match
            || c.output.allow_primary_fallback
            || c.output.serial.is_empty()
            || c.output.model != "XENEON EDGE"
            || c.output.edid_sha256.len() != 64
            || !c.output.edid_sha256.bytes().all(|b| b.is_ascii_hexdigit())
            || !c
                .output
                .connector
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
            || c.output.connector.is_empty()
        {
            bail!("Exact XENEON commissioning is incomplete; no monitor fallback is allowed");
        }
        Ok(c)
    }
    fn discover(&self) -> Result<(Target, Commissioning)> {
        let c = self.commissioned()?;
        let mut matches = Vec::new();
        for entry in fs::read_dir(&self.paths.drm).context("DRM monitor identity is unavailable")? {
            let path = entry?.path();
            if fs::read_to_string(path.join("status"))
                .ok()
                .as_deref()
                .map(str::trim)
                != Some("connected")
            {
                continue;
            }
            let Ok(bytes) = read_bounded(&path.join("edid"), 4096) else {
                continue;
            };
            let hash = format!("{:x}", Sha256::digest(&bytes));
            if !hash.eq_ignore_ascii_case(&c.output.edid_sha256) {
                continue;
            }
            let serial = edid_descriptor(&bytes, 0xff)
                .context("Exact monitor EDID serial is unavailable")?;
            let model =
                edid_descriptor(&bytes, 0xfc).context("Exact monitor EDID model is unavailable")?;
            let name = path
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or_default();
            let connector = name.split_once('-').map(|(_, s)| s).unwrap_or_default();
            // Commissioning connector names can change after hotplug. The
            // exact EDID, serial and model remain authoritative; this fresh
            // connector becomes part of the target fenced around every write.
            if serial != c.output.serial || model != c.output.model {
                continue;
            }
            matches.push((
                path.canonicalize()?,
                connector.to_owned(),
                serial,
                model,
                hash,
            ));
        }
        if matches.len() != 1 {
            bail!("Exact commissioned EDGE is absent or ambiguous; no other display is selected");
        }
        let (path, connector, serial, model, hash) = matches.remove(0);
        let mut buses = Vec::new();
        // The DRM 'ddc' symlink can name a GPU-level adapter. Use only actual
        // i2c-dev device ancestry beneath the EDID-matched connector.
        for entry in fs::read_dir(&self.paths.i2c).context("I2C device discovery is unavailable")? {
            let p = entry?.path();
            let Some(bus) = p
                .file_name()
                .and_then(|s| s.to_str())
                .and_then(|s| s.strip_prefix("i2c-"))
                .and_then(|s| s.parse::<u32>().ok())
            else {
                continue;
            };
            let Ok(device) = p.join("device").canonicalize() else {
                continue;
            };
            if device.starts_with(&path) && device != path {
                buses.push(bus);
            }
        }
        buses.sort_unstable();
        buses.dedup();
        if buses.len() != 1 {
            bail!("Exact EDGE I2C bus is absent or ambiguous; GPU DDC adapters are not a fallback");
        }
        Ok((
            Target {
                connector,
                serial,
                model,
                hash,
                bus: buses[0],
                path,
            },
            c,
        ))
    }
    fn device_access(&self, target: &Target) -> Result<()> {
        fs::OpenOptions::new().read(true).write(true).open(self.paths.dev.join(format!("i2c-{}",target.bus))).context("Exact EDGE I2C device is inaccessible to this process; hardware support is not determined")?;
        Ok(())
    }
    fn same_identity(&self, target: &Target) -> Result<()> {
        let (fresh, _) = self.discover()?;
        if &fresh != target {
            bail!("Monitor identity or I2C route changed; operation was not retried");
        }
        Ok(())
    }
    fn same_target(&self, target: &Target) -> Result<()> {
        self.same_identity(target)?;
        self.device_access(target)
    }
    async fn ddc(&self, target: &Target, args: &[String], deadline: Duration) -> Result<String> {
        self.ddc_with_mode(target, args, deadline, OutputMode::Strict)
            .await
    }
    async fn ddc_with_mode(
        &self,
        target: &Target,
        args: &[String],
        deadline: Duration,
        mode: OutputMode,
    ) -> Result<String> {
        let mut fixed = vec![
            "--noconfig".into(),
            "--disable-udf".into(),
            "--maxtries".into(),
            "1,2,2".into(),
            "--bus".into(),
            target.bus.to_string(),
            "--terse".into(),
        ];
        fixed.extend_from_slice(args);
        run_with_mode(&self.paths.ddcutil, &fixed, deadline, mode).await
    }
    async fn refresh_locked(&self) -> Result<MonitorSnapshot> {
        let (target, c) = self.discover()?;
        let mut next = MonitorSnapshot {
            identity_verified: true,
            connector: Some(target.connector.clone()),
            serial: Some(target.serial.clone()),
            model: Some(target.model.clone()),
            edid_sha256: Some(target.hash.clone()),
            i2c_bus: Some(target.bus),
            refreshed_at_ms: now(),
            ..MonitorSnapshot::default()
        };
        let readings: Result<(String, Vec<MonitorChoice>)> = async {
            self.device_access(&target)?;
            let cap = self
                .ddc(&target, &["capabilities".into()], Duration::from_secs(7))
                .await
                .ok();
            self.same_target(&target)?;
            let mut args = vec!["getvcp".into()];
            args.extend(CONTROLS.iter().map(|id| format!("{:02X}", id.code())));
            // Installed ddcutil 2.2.7 exits one for a mixed getvcp batch
            // containing ERR. Only this exact bounded read-only projection
            // accepts that status after validating every expected record.
            let text = self
                .ddc_with_mode(
                    &target,
                    &args,
                    Duration::from_secs(11),
                    OutputMode::VcpBatch,
                )
                .await?;
            self.same_target(&target)?;
            Ok((text, cap.as_deref().map(preset_choices).unwrap_or_default()))
        }
        .await;
        match readings {
            Ok((text, choices)) => {
                next.controls = CONTROLS
                    .iter()
                    .map(|id| control_from_reply(*id, &text, &choices, self.config.writes_enabled))
                    .collect();
                apply_rgb_gate(&mut next.controls, self.config.writes_enabled);
                next.available = next.controls.iter().any(|v| v.supported);
                next.reason = if next.available {
                    if self.config.writes_enabled {
                        None
                    } else {
                        Some(
                            "Monitor controls are read-only; monitor.writes_enabled is false"
                                .into(),
                        )
                    }
                } else {
                    Some("No supported monitor feature produced a valid DDC read".into())
                };
            }
            Err(error) => {
                // Failure to query picture settings does not erase an
                // independently reverified connected device identity.
                self.same_identity(&target)?;
                next.reason = Some(bounded(&error.to_string()));
                for control in &mut next.controls {
                    control.reason = next.reason.clone();
                }
            }
        }
        if self.paths.layout {
            self.layout(&target, &c, &mut next).await;
        }
        self.same_identity(&target)?;
        next.refreshed_at_ms = now();
        Ok(next)
    }
    async fn layout(&self, target: &Target, c: &Commissioning, next: &mut MonitorSnapshot) {
        let monitor_args = ["-j".into(), "monitors".into(), "all".into()];
        let device_args = ["-j".into(), "devices".into()];
        let (monitors, devices) = tokio::join!(
            run(
                Path::new("/usr/bin/hyprctl"),
                &monitor_args,
                Duration::from_secs(2)
            ),
            run(
                Path::new("/usr/bin/hyprctl"),
                &device_args,
                Duration::from_secs(2)
            )
        );
        if let Ok(value) =
            monitors.and_then(|s| serde_json::from_str::<serde_json::Value>(&s).map_err(Into::into))
            && let Some(items) = value.as_array()
        {
            let found: Vec<_> = items
                .iter()
                .filter(|v| {
                    v["name"].as_str() == Some(&target.connector)
                        && v["serial"].as_str() == Some(&target.serial)
                })
                .collect();
            if found.len() == 1 {
                let v = found[0];
                if let (Some(width), Some(height), Some(refresh_hz), Some(scale), Some(transform)) = (
                    v["width"].as_u64(),
                    v["height"].as_u64(),
                    v["refreshRate"].as_f64(),
                    v["scale"].as_f64(),
                    v["transform"].as_u64(),
                ) && width > 0
                    && width <= 16384
                    && height > 0
                    && height <= 16384
                    && refresh_hz.is_finite()
                    && refresh_hz > 0.0
                    && scale.is_finite()
                    && scale > 0.0
                    && transform <= 7
                {
                    next.display = Some(MonitorDisplay {
                        width: width as u32,
                        height: height as u32,
                        refresh_hz,
                        scale,
                        transform: transform as u8,
                    });
                }
            }
        }
        if let (Some(touch), Ok(value)) = (
            &c.touch,
            devices.and_then(|s| serde_json::from_str::<serde_json::Value>(&s).map_err(Into::into)),
        ) && let Some(list) = value["touch"].as_array()
        {
            next.touch = Some(MonitorTouch {
                connected: list
                    .iter()
                    .any(|v| v["name"].as_str() == Some(&touch.device)),
                device: touch.device.clone(),
            });
        }
    }
    pub async fn set(&self, id: MonitorControlId, value: u16) -> Result<String> {
        self.write(id, WriteValue::Raw(value)).await
    }
    pub async fn brightness_percent(&self, percent: u8) -> Result<String> {
        if percent > 100 {
            bail!("Brightness percent must be 0..100");
        }
        self.write(MonitorControlId::Brightness, WriteValue::Percent(percent))
            .await
    }
    async fn write(&self, id: MonitorControlId, value: WriteValue) -> Result<String> {
        if !self.config.writes_enabled {
            bail!("Monitor writes are disabled in configuration");
        }
        let _guard = timeout(Duration::from_secs(20), self.operation.lock())
            .await
            .context("Monitor controller is busy; write was not queued")?;
        let result = self.write_locked(id, value).await;
        if let Err(error) = &result {
            let mut s = self.snapshot.write().await;
            s.available = false;
            s.identity_verified = false;
            s.reason = Some(bounded(&error.to_string()));
            for control in &mut s.controls {
                control.writable = false;
            }
            s.refreshed_at_ms = now();
        }
        result
    }
    async fn read_one(&self, target: &Target, id: MonitorControlId) -> Result<Reading> {
        let text = self
            .ddc(
                target,
                &["getvcp".into(), format!("{:02X}", id.code())],
                Duration::from_secs(4),
            )
            .await?;
        parse_reply(&text, id, true)
    }
    async fn write_locked(&self, id: MonitorControlId, value: WriteValue) -> Result<String> {
        let (target, _) = self.discover()?;
        self.device_access(&target)?;
        let pre = self.read_one(&target, id).await?;
        let choices = if id == MonitorControlId::ColorPreset {
            let text = self
                .ddc(&target, &["capabilities".into()], Duration::from_secs(7))
                .await?;
            preset_choices(&text)
        } else {
            Vec::new()
        };
        if id.rgb() {
            let preset = self
                .read_one(&target, MonitorControlId::ColorPreset)
                .await?;
            if preset.current != 11 {
                bail!(
                    "RGB gains require the monitor's verified User 1 preset; select User 1 explicitly first"
                );
            }
        }
        let requested = match value {
            WriteValue::Raw(value) => value,
            WriteValue::Percent(p) => {
                let max = pre.maximum.context("Brightness maximum is unavailable")?;
                (u32::from(max) * u32::from(p) / 100) as u16
            }
        };
        if id == MonitorControlId::ColorPreset {
            if !choices.iter().any(|c| c.value == requested) {
                bail!("Color preset is not an advertised supported choice");
            }
        } else if pre.maximum.is_none_or(|m| m == 0 || requested > m) {
            bail!("Requested value exceeds the current monitor-reported maximum");
        }
        self.same_target(&target)?;
        // Exactly one set invocation and one write-only try. Normal ddcutil
        // verification stays enabled, followed by an independent get/readback.
        self.ddc(
            &target,
            &[
                "setvcp".into(),
                format!("{:02X}", id.code()),
                requested.to_string(),
            ],
            Duration::from_secs(4),
        )
        .await
        .context("Monitor write failed or may be unconfirmed; it was not retried")?;
        self.same_target(&target)
            .context("Monitor identity changed after write; outcome is unconfirmed")?;
        let post = self
            .read_one(&target, id)
            .await
            .context("Monitor write readback unavailable; outcome is unconfirmed")?;
        self.same_target(&target)
            .context("Monitor identity changed after readback; outcome is unconfirmed")?;
        if post.current != requested
            || (id != MonitorControlId::ColorPreset && post.maximum != pre.maximum)
        {
            bail!(
                "Monitor ignored or changed the requested value: readback {}, requested {}; operation was not retried",
                post.current,
                requested
            );
        }
        if id.rgb() {
            let preset = self
                .read_one(&target, MonitorControlId::ColorPreset)
                .await
                .context("RGB preset readback unavailable after write; outcome is unconfirmed")?;
            self.same_target(&target)
                .context("Monitor identity changed after RGB write; outcome is unconfirmed")?;
            if preset.current != 11 {
                bail!("Color preset changed during RGB write; outcome is unconfirmed");
            }
        }
        let mut snapshot = self.snapshot.write().await;
        snapshot.available = true;
        snapshot.identity_verified = true;
        snapshot.connector = Some(target.connector);
        snapshot.serial = Some(target.serial);
        snapshot.model = Some(target.model);
        snapshot.edid_sha256 = Some(target.hash);
        snapshot.i2c_bus = Some(target.bus);
        snapshot.refreshed_at_ms = now();
        snapshot.reason = None;
        if let Some(c) = snapshot.controls.iter_mut().find(|c| c.id == id) {
            c.current = Some(post.current);
            c.maximum = post.maximum;
            c.supported = true;
            c.writable = true;
            c.reason = None;
            if id == MonitorControlId::ColorPreset {
                c.choices = choices;
            }
        }
        if id == MonitorControlId::ColorPreset {
            // A preset can restore multiple picture values. Old readings are
            // not editable or presented as current while the worker refreshes.
            for control in snapshot.controls.iter_mut().filter(|c| c.id != id) {
                control.current = None;
                control.maximum = None;
                control.writable = false;
                control.reason =
                    Some("Color preset changed; refresh current picture values".into());
            }
            self.refresh_requested.notify_one();
        } else {
            apply_rgb_gate(&mut snapshot.controls, self.config.writes_enabled);
        }
        Ok(format!(
            "{} verified by readback: {}{}",
            id.label(),
            post.current,
            post.maximum.map(|m| format!(" / {m}")).unwrap_or_default()
        ))
    }
}
#[derive(Debug, Clone, Copy)]
enum WriteValue {
    Raw(u16),
    Percent(u8),
}
#[derive(Debug, Clone, Copy, PartialEq)]
struct Reading {
    current: u16,
    maximum: Option<u16>,
}
fn parse_reply(text: &str, id: MonitorControlId, only: bool) -> Result<Reading> {
    if text.len() > MAX_OUTPUT as usize {
        bail!("DDC reply exceeds its bound");
    }
    let mut rows = Vec::new();
    for line in text.lines().filter(|line| !line.trim().is_empty()) {
        let fields: Vec<_> = line.split_whitespace().collect();
        if fields.first() != Some(&"VCP") {
            bail!("DDC response is not a machine-readable VCP record");
        }
        let code = fields
            .get(1)
            .and_then(|s| u8::from_str_radix(s, 16).ok())
            .context("Invalid DDC feature code")?;
        if only && code != id.code() {
            bail!("DDC response named a different feature");
        }
        if code == id.code() {
            rows.push(fields);
        }
    }
    if rows.len() != 1 {
        bail!("DDC feature reply is missing or duplicated");
    }
    let f = &rows[0];
    if id == MonitorControlId::ColorPreset {
        let hex = |s: &str| -> Result<u8> {
            if s.len() != 3 || !s.starts_with('x') {
                bail!("Preset bytes must use xHH format");
            }
            Ok(u8::from_str_radix(&s[1..], 16)?)
        };
        let value = if f.len() == 4 && f[2] == "SNC" {
            hex(f[3])?
        } else if f.len() == 7 && f[2] == "CNC" {
            let bytes = [hex(f[3])?, hex(f[4])?, hex(f[5])?, hex(f[6])?];
            if bytes[0] != 0 || bytes[2] != 0 {
                bail!("Unexpected complex color preset representation");
            }
            bytes[3]
        } else {
            bail!("Color preset is not a supported SNC/CNC reply");
        };
        if !PRESETS.contains(&u16::from(value)) {
            bail!("Color preset value is not verified for the commissioned monitor");
        }
        return Ok(Reading {
            current: u16::from(value),
            maximum: None,
        });
    }
    if f.len() != 5 || f[2] != "C" {
        bail!("Monitor feature did not return a supported continuous value");
    }
    let decimal = |s: &str| -> Result<u16> {
        if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
            bail!("DDC continuous values must be decimal integers");
        }
        Ok(s.parse()?)
    };
    let current = decimal(f[3])?;
    let maximum = decimal(f[4])?;
    if maximum == 0 || current > maximum {
        bail!("Monitor current/maximum values are invalid");
    }
    Ok(Reading {
        current,
        maximum: Some(maximum),
    })
}
fn control_from_reply(
    id: MonitorControlId,
    text: &str,
    choices: &[MonitorChoice],
    writes: bool,
) -> MonitorControl {
    match parse_reply(text, id, false) {
        Ok(v) => {
            let mut control = MonitorControl {
                id,
                label: id.label().into(),
                kind: if id == MonitorControlId::ColorPreset {
                    "enum"
                } else {
                    "continuous"
                }
                .into(),
                supported: true,
                writable: writes,
                current: Some(v.current),
                maximum: v.maximum,
                choices: if id == MonitorControlId::ColorPreset {
                    choices.to_vec()
                } else {
                    Vec::new()
                },
                reason: if writes {
                    None
                } else {
                    Some("Monitor writes are disabled in configuration".into())
                },
            };
            if id == MonitorControlId::ColorPreset && choices.is_empty() {
                control.writable = false;
                control.reason = Some("Preset choices were not verified by capabilities".into());
            }
            control
        }
        Err(error) => MonitorControl::unavailable(id, &bounded(&error.to_string())),
    }
}
fn apply_rgb_gate(controls: &mut [MonitorControl], writes: bool) {
    let user = controls
        .iter()
        .any(|c| c.id == MonitorControlId::ColorPreset && c.supported && c.current == Some(11));
    for c in controls.iter_mut().filter(|c| c.id.rgb()) {
        if c.supported && !user {
            c.writable = false;
            c.reason = Some("RGB gain requires the verified User 1 color preset".into());
        } else if user
            && writes
            && c.supported
            && c.reason.as_deref() == Some("RGB gain requires the verified User 1 color preset")
        {
            c.writable = true;
            c.reason = None;
        }
    }
}
fn preset_choices(text: &str) -> Vec<MonitorChoice> {
    if text.len() > MAX_OUTPUT as usize {
        return Vec::new();
    }
    // Parse the raw vcp(...) feature list, retaining only verified preset IDs.
    let Some(start) = text.find("vcp(") else {
        return Vec::new();
    };
    let rest = &text[start + 4..];
    let mut depth = 0usize;
    let mut feature = String::new();
    let mut values = String::new();
    let mut found = Vec::new();
    let mut closed = false;
    for ch in rest.chars() {
        match ch {
            '(' if depth == 0 => {
                depth = 1;
                values.clear();
            }
            '(' => {
                return Vec::new();
            }
            ')' if depth == 1 => {
                if feature.eq_ignore_ascii_case("14") {
                    found.push(values.clone());
                }
                feature.clear();
                depth = 0;
            }
            ')' if depth == 0 => {
                closed = true;
                break;
            }
            c if depth == 1 => values.push(c),
            c if c.is_ascii_hexdigit() => feature.push(c),
            c if c.is_ascii_whitespace() => {
                if !feature.is_empty() {
                    feature.clear();
                }
            }
            _ => return Vec::new(),
        }
    }
    if found.len() != 1 || depth != 0 || !closed {
        return Vec::new();
    }
    let mut choices = Vec::new();
    for token in found[0].split_whitespace() {
        let Ok(value) = u16::from_str_radix(token, 16) else {
            return Vec::new();
        };
        if PRESETS.contains(&value) && !choices.iter().any(|c: &MonitorChoice| c.value == value) {
            choices.push(MonitorChoice {
                value,
                label: match value {
                    1 => "sRGB",
                    2 => "Display native",
                    4 => "5000 K",
                    5 => "6500 K",
                    6 => "7500 K",
                    8 => "9300 K",
                    11 => "User 1",
                    _ => unreachable!(),
                }
                .into(),
            });
        }
    }
    choices
}
fn edid_descriptor(bytes: &[u8], tag: u8) -> Result<String> {
    if bytes.len() < 128
        || !bytes.len().is_multiple_of(128)
        || bytes[..8] != [0, 255, 255, 255, 255, 255, 255, 0]
        || bytes
            .chunks(128)
            .any(|b| b.iter().fold(0u8, |s, b| s.wrapping_add(*b)) != 0)
    {
        bail!("EDID structure or checksum is invalid");
    }
    let descriptors: Vec<_> = bytes[54..126]
        .as_chunks::<18>()
        .0
        .iter()
        .filter(|d| d[..3] == [0, 0, 0] && d[3] == tag)
        .collect();
    if descriptors.len() != 1 {
        bail!("EDID identity descriptor is absent or ambiguous");
    }
    let text = std::str::from_utf8(&descriptors[0][5..18])?
        .trim_matches(|c: char| c.is_ascii_whitespace() || c == '\0');
    if text.is_empty() || !text.is_ascii() || text.chars().any(|c| c.is_control()) {
        bail!("EDID identity text is invalid");
    }
    Ok(text.into())
}
fn read_bounded(path: &Path, max: u64) -> Result<Vec<u8>> {
    let mut data = Vec::new();
    fs::File::open(path)?.take(max + 1).read_to_end(&mut data)?;
    if data.len() as u64 > max {
        bail!("File exceeds its bound");
    }
    Ok(data)
}
fn bounded(s: &str) -> String {
    s.chars().filter(|c| !c.is_control()).take(240).collect()
}
fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}
#[derive(Clone, Copy)]
enum OutputMode {
    Strict,
    VcpBatch,
}
fn valid_mixed_vcp_batch(text: &str) -> bool {
    if text.len() > MAX_OUTPUT as usize {
        return false;
    }
    let mut seen = std::collections::HashSet::new();
    let mut values = 0;
    let mut errors = 0;
    for line in text.lines().filter(|line| !line.trim().is_empty()) {
        let fields: Vec<_> = line.split_whitespace().collect();
        if fields.first() != Some(&"VCP") {
            return false;
        }
        let Some(id) = fields
            .get(1)
            .and_then(|code| u8::from_str_radix(code, 16).ok())
            .and_then(|code| CONTROLS.iter().find(|id| id.code() == code))
        else {
            return false;
        };
        if !seen.insert(id.code()) {
            return false;
        }
        if fields.len() == 3 && fields[2] == "ERR" {
            errors += 1;
        } else if parse_reply(line, *id, true).is_ok() {
            values += 1;
        } else {
            return false;
        }
    }
    seen.len() == CONTROLS.len() && values > 0 && errors > 0
}
async fn run(program: &Path, args: &[String], deadline: Duration) -> Result<String> {
    run_with_mode(program, args, deadline, OutputMode::Strict).await
}
async fn run_with_mode(
    program: &Path,
    args: &[String],
    deadline: Duration,
    mode: OutputMode,
) -> Result<String> {
    let mut child = Command::new(program)
        .args(args)
        .env("LC_ALL", "C")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .context("Monitor command could not start")?;
    let out = child.stdout.take().unwrap();
    let err = child.stderr.take().unwrap();
    let operation = async {
        let (out, err, status) = tokio::join!(read_output(out), read_output(err), child.wait());
        let out = out?;
        let err = err?;
        let status = status?;
        let text = String::from_utf8(out)?;
        let mixed_read = matches!(mode, OutputMode::VcpBatch)
            && status.code() == Some(1)
            && err.iter().all(u8::is_ascii_whitespace)
            && valid_mixed_vcp_batch(&text);
        if !status.success() && !mixed_read {
            bail!(
                "Monitor command failed ({status}): stderr={}; stdout={}",
                bounded(
                    if err.is_empty() {
                        "<empty>".into()
                    } else {
                        String::from_utf8_lossy(&err)
                    }
                    .as_ref()
                ),
                bounded(if text.trim().is_empty() {
                    "<empty>"
                } else {
                    &text
                }),
            );
        }
        Ok(text)
    };
    match timeout(deadline, operation).await {
        Ok(result) => result,
        Err(_) => {
            let _ = child.kill().await;
            let _ = child.wait().await;
            bail!("Monitor command timed out; no write was retried");
        }
    }
}
async fn read_output(mut reader: impl tokio::io::AsyncRead + Unpin) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    (&mut reader)
        .take(MAX_OUTPUT + 1)
        .read_to_end(&mut bytes)
        .await?;
    if bytes.len() as u64 > MAX_OUTPUT {
        bail!("Monitor command output exceeds its bound");
    }
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::os::unix::fs::{PermissionsExt, symlink};
    struct Fixture {
        root: tempfile::TempDir,
        controller: MonitorController,
    }
    fn edid() -> Vec<u8> {
        let mut b = vec![0u8; 128];
        b[..8].copy_from_slice(&[0, 255, 255, 255, 255, 255, 255, 0]);
        for (offset, tag, text) in [(54, 0xff, "035926215698"), (72, 0xfc, "XENEON EDGE")] {
            b[offset + 3] = tag;
            b[offset + 5..offset + 18].fill(b' ');
            b[offset + 5..offset + 5 + text.len()].copy_from_slice(text.as_bytes());
        }
        b[127] = 0u8.wrapping_sub(b[..127].iter().fold(0u8, |s, b| s.wrapping_add(*b)));
        b
    }
    impl Fixture {
        fn new(writes: bool) -> Self {
            let root = tempfile::tempdir().unwrap();
            let p = root.path();
            let connector = p.join("drm/card1-DP-2");
            fs::create_dir_all(connector.join("i2c-12")).unwrap();
            fs::create_dir_all(p.join("i2c/i2c-12")).unwrap();
            fs::create_dir_all(p.join("dev")).unwrap();
            fs::write(connector.join("status"), "connected\n").unwrap();
            fs::write(connector.join("edid"), edid()).unwrap();
            symlink(connector.join("i2c-12"), p.join("i2c/i2c-12/device")).unwrap();
            fs::write(p.join("dev/i2c-12"), "").unwrap();
            // A deliberately wrong GPU DDC symlink must never be selected.
            fs::create_dir_all(p.join("gpu/i2c-4")).unwrap();
            symlink(p.join("gpu/i2c-4"), connector.join("ddc")).unwrap();
            let commissioning = p.join("commissioning.toml");
            fs::write(&commissioning,format!("mode=\"production\"\n[output]\nconnector=\"DP-2\"\nserial=\"035926215698\"\nmodel=\"XENEON EDGE\"\nedid_sha256=\"{:x}\"\nrequire_exact_match=true\nallow_primary_fallback=false\n",Sha256::digest(edid()))).unwrap();
            let state = p.join("state.json");
            fs::write(&state,json!({"brightness":95,"maximum":100,"preset":11,"ignore":false,"delay":0,"swap":false}).to_string()).unwrap();
            let script = p.join("ddcutil");
            fs::write(
                &script,
                format!(
                    r#"#!/usr/bin/python3
import json,sys,time,pathlib,signal,os
base=pathlib.Path({base})
a=sys.argv[1:]
with (base/'log').open('a') as f: f.write(json.dumps(a)+'\n')
s=json.loads((base/'state.json').read_text())
if 'capabilities' in a:
 print('(prot(monitor)model(RTK)cmds(01 02 03)vcp(10 12 14(01 02 04 05 06 08 0B) 16 18 1A 87))')
elif 'getvcp' in a:
 codes=a[a.index('getvcp')+1:]
 if len(codes)>1 and s.get('batch_empty',False):sys.exit(s.get('batch_exit',1))
 for c in codes:
  if c=='14': print('VCP 14 CNC x00 x0b x00 x%02x'%s['preset'])
  elif c=='10': print('VCP 10 C %d %d'%(s['brightness'],s['maximum']))
  elif c=='6B': print('VCP 6B ERR')
  elif c=='87': print('VCP 87 C 2 4')
  else: print('VCP %s C %d 255'%(c,s.get('gain',127)))
 if len(codes)>1:
  if s.get('batch_signal',False):sys.stdout.flush();os.kill(os.getpid(),signal.SIGTERM)
  if s.get('batch_stderr',False):print('fatal transport failure',file=sys.stderr)
  if s.get('batch_malformed',False):print('malformed response')
  sys.exit(s.get('batch_exit',0))
elif 'setvcp' in a:
 c,v=a[a.index('setvcp')+1:];time.sleep(s['delay'])
 if s['swap']:
  p=base/'drm/card1-DP-2/edid';b=bytearray(p.read_bytes());b[59]^=1;p.write_bytes(b)
 if not s['ignore']:
  if c=='10':s['brightness']=int(v)
  if c=='14':s['preset']=int(v);s['gain']=100
  (base/'state.json').write_text(json.dumps(s))
 if s.get('set_exit',0):print('setvcp did not complete');sys.exit(s['set_exit'])
else: sys.exit(1)
"#,
                    base = serde_json::to_string(p.to_str().unwrap()).unwrap()
                ),
            )
            .unwrap();
            fs::set_permissions(&script, fs::Permissions::from_mode(0o700)).unwrap();
            let mut controller = MonitorController::new(MonitorConfig {
                writes_enabled: writes,
                commissioning_file: Some(commissioning),
                ..MonitorConfig::default()
            });
            controller.paths = Paths {
                drm: p.join("drm"),
                i2c: p.join("i2c"),
                dev: p.join("dev"),
                ddcutil: script,
                layout: false,
            };
            Self { root, controller }
        }
        fn change(&self, key: &str, value: serde_json::Value) {
            let p = self.root.path().join("state.json");
            let mut state: serde_json::Value =
                serde_json::from_slice(&fs::read(&p).unwrap()).unwrap();
            state[key] = value;
            fs::write(p, state.to_string()).unwrap();
        }
        fn log(&self) -> Vec<Vec<String>> {
            fs::read_to_string(self.root.path().join("log"))
                .unwrap_or_default()
                .lines()
                .map(|s| serde_json::from_str(s).unwrap())
                .collect()
        }
        fn writes(&self) -> usize {
            self.log()
                .iter()
                .filter(|a| a.contains(&"setvcp".into()))
                .count()
        }
    }
    #[test]
    fn vcp_reply_requires_exact_feature_unique_row_and_valid_bounds() {
        assert_eq!(
            parse_reply("VCP 10 C 95 100\n", MonitorControlId::Brightness, true).unwrap(),
            Reading {
                current: 95,
                maximum: Some(100)
            }
        );
        for text in [
            "VCP 10 ERR",
            "VCP 12 C 50 100",
            "VCP 10 C 101 100",
            "VCP 10 C 0 0",
            "VCP 10 C -1 100",
            "VCP 10 C 1.5 100",
            "VCP 10 C 1 65536",
            "VCP 10 C 95 100 extra",
            "VCP 10 C 95 100\nVCP 10 C 95 100",
            "noise\nVCP 10 C 95 100",
        ] {
            assert!(
                parse_reply(text, MonitorControlId::Brightness, true).is_err(),
                "{text}"
            );
        }
        let batch = "VCP 10 C 95 100\nVCP 6B ERR\n";
        assert!(parse_reply(batch, MonitorControlId::Brightness, false).is_ok());
        assert!(parse_reply(batch, MonitorControlId::Backlight, false).is_err());
    }
    #[test]
    fn preset_complex_bytes_have_feature_specific_semantics_and_choices() {
        assert_eq!(
            parse_reply(
                "VCP 14 CNC x00 x0b x00 x0b",
                MonitorControlId::ColorPreset,
                true
            )
            .unwrap(),
            Reading {
                current: 11,
                maximum: None
            }
        );
        assert_eq!(
            parse_reply("VCP 14 SNC x05", MonitorControlId::ColorPreset, true)
                .unwrap()
                .current,
            5
        );
        for text in [
            "VCP 14 CNC x01 x0b x00 x0b",
            "VCP 14 CNC x00 x0b x01 x0b",
            "VCP 14 CNC x00 x0b x00 xff",
            "VCP 14 CNC x00 x0b x00 11",
            "VCP 14 C 11 11",
            "VCP 14 SNC x03",
        ] {
            assert!(parse_reply(text, MonitorControlId::ColorPreset, true).is_err());
        }
        let choices = preset_choices("(vcp(10 12 14(01 02 04 05 06 08 0B 03 FF) 16))");
        assert_eq!(
            choices.iter().map(|c| c.value).collect::<Vec<_>>(),
            vec![1, 2, 4, 5, 6, 8, 11]
        );
        assert!(preset_choices("(vcp(14(01) 14(05)))").is_empty());
        assert!(preset_choices("(vcp(14(no)))").is_empty());
        assert!(preset_choices("(vcp(14(01 0B)").is_empty());
        assert!(preset_choices("(vcp(14(01 0B").is_empty());
    }
    #[test]
    fn identity_binds_nested_i2c_bus_not_gpu_ddc_and_rejects_ambiguity() {
        let f = Fixture::new(true);
        let (target, _) = f.controller.discover().unwrap();
        assert_eq!(target.bus, 12);
        let p = f.root.path();
        fs::create_dir_all(p.join("i2c/i2c-13")).unwrap();
        fs::create_dir_all(p.join("drm/card1-DP-2/i2c-13")).unwrap();
        symlink(p.join("drm/card1-DP-2/i2c-13"), p.join("i2c/i2c-13/device")).unwrap();
        assert!(f.controller.discover().is_err());
        fs::remove_dir_all(p.join("i2c/i2c-13")).unwrap();
        fs::write(p.join("drm/card1-DP-2/status"), "disconnected").unwrap();
        assert!(f.controller.discover().is_err());
        assert_eq!(f.writes(), 0);
    }
    #[test]
    fn exact_identity_follows_connector_move_but_an_inflight_target_is_invalidated() {
        let f = Fixture::new(true);
        let (before, _) = f.controller.discover().unwrap();
        let p = f.root.path();
        fs::rename(p.join("drm/card1-DP-2"), p.join("drm/card1-DP-3")).unwrap();
        fs::remove_file(p.join("i2c/i2c-12/device")).unwrap();
        symlink(p.join("drm/card1-DP-3/i2c-12"), p.join("i2c/i2c-12/device")).unwrap();
        let (after, _) = f.controller.discover().unwrap();
        assert_eq!(after.connector, "DP-3");
        assert_eq!(after.serial, before.serial);
        assert_eq!(after.hash, before.hash);
        assert_eq!(after.bus, 12);
        assert!(f.controller.same_target(&before).is_err());
        assert!(f.controller.same_target(&after).is_ok());
        let duplicate = p.join("drm/card1-DP-4");
        fs::create_dir_all(&duplicate).unwrap();
        fs::write(duplicate.join("status"), "connected").unwrap();
        fs::write(duplicate.join("edid"), edid()).unwrap();
        assert!(f.controller.discover().is_err());
        assert_eq!(f.writes(), 0);
    }
    #[tokio::test]
    async fn refresh_is_per_feature_and_device_inaccessibility_is_not_unsupported() {
        let f = Fixture::new(false);
        f.controller.refresh().await.unwrap();
        let s = f.controller.snapshot().await;
        assert!(s.identity_verified && s.available);
        assert_eq!(s.i2c_bus, Some(12));
        let b = s
            .controls
            .iter()
            .find(|c| c.id == MonitorControlId::Backlight)
            .unwrap();
        assert!(!b.supported && !b.writable);
        assert!(
            s.controls
                .iter()
                .filter(|c| c.supported)
                .all(|c| !c.writable)
        );
        assert!(
            f.controller
                .set(MonitorControlId::Brightness, 94)
                .await
                .is_err()
        );
        assert_eq!(f.writes(), 0);
        fs::remove_file(f.root.path().join("dev/i2c-12")).unwrap();
        assert!(f.controller.refresh().await.is_err());
        let s = f.controller.snapshot().await;
        assert!(s.identity_verified && !s.available);
        assert!(s.reason.unwrap().contains("inaccessible"));
    }
    #[tokio::test]
    async fn mixed_get_exit_one_preserves_valid_controls_and_does_not_relax_writes() {
        let f = Fixture::new(true);
        f.change("batch_exit", json!(1));
        f.controller.refresh().await.unwrap();
        let s = f.controller.snapshot().await;
        assert!(s.available && s.identity_verified);
        assert_eq!(s.controls.iter().filter(|c| c.supported).count(), 7);
        let brightness = s
            .controls
            .iter()
            .find(|c| c.id == MonitorControlId::Brightness)
            .unwrap();
        assert_eq!(brightness.current, Some(95));
        assert_eq!(brightness.maximum, Some(100));
        assert!(brightness.writable);
        assert!(
            !s.controls
                .iter()
                .find(|c| c.id == MonitorControlId::Backlight)
                .unwrap()
                .supported
        );
        assert_eq!(f.writes(), 0);
        f.change("set_exit", json!(1));
        let error = f
            .controller
            .set(MonitorControlId::Brightness, 94)
            .await
            .unwrap_err();
        assert!(format!("{error:#}").contains("exit status: 1"));
        assert!(error.to_string().contains("unconfirmed"));
        assert_eq!(f.writes(), 1);
        assert!(!f.controller.snapshot().await.available);
    }

    #[tokio::test]
    async fn failed_batch_keeps_fresh_identity_but_never_supports_fatal_or_malformed_rows() {
        for (key, value, diagnostic) in [
            ("batch_exit", json!(2), "exit status: 2"),
            ("batch_signal", json!(true), "signal:"),
            ("batch_stderr", json!(true), "fatal transport failure"),
            ("batch_empty", json!(true), "stdout=<empty>"),
            ("batch_malformed", json!(true), "exit status: 1"),
        ] {
            let f = Fixture::new(true);
            f.change("batch_exit", json!(1));
            f.change(key, value);
            let error = f.controller.refresh().await.unwrap_err();
            assert!(error.to_string().contains(diagnostic), "{key}: {error}");
            let s = f.controller.snapshot().await;
            assert!(s.identity_verified, "{key}");
            assert_eq!(s.connector.as_deref(), Some("DP-2"));
            assert_eq!(s.serial.as_deref(), Some("035926215698"));
            assert_eq!(s.i2c_bus, Some(12));
            assert!(!s.available);
            assert!(s.controls.iter().all(|c| !c.supported && !c.writable));
            assert_eq!(f.writes(), 0);
        }
    }

    #[test]
    fn partial_batch_requires_complete_unique_expected_valid_rows_and_an_err() {
        let valid = "VCP 10 C 95 100\nVCP 6B ERR\nVCP 12 C 50 100\nVCP 16 C 151 255\nVCP 18 C 127 255\nVCP 1A C 139 255\nVCP 87 C 2 4\nVCP 14 CNC x00 x0b x00 x0b\n";
        assert!(valid_mixed_vcp_batch(valid));
        for invalid in [
            "".to_string(),
            valid.replace("VCP 6B ERR\n", ""),
            valid.replace("VCP 6B ERR", "VCP 6B ERR fatal"),
            valid.replace("VCP 6B ERR", "VCP 6B C 1 100"),
            valid.replace("VCP 12 C 50 100", "VCP 10 C 50 100"),
            valid.replace("VCP 12 C 50 100", "VCP 60 C 50 100"),
            valid.replace("VCP 12 C 50 100", "VCP 12 C 101 100"),
            format!("{valid}fatal transport failure\n"),
            format!("{valid}{}", " ".repeat(MAX_OUTPUT as usize)),
            CONTROLS
                .iter()
                .map(|id| format!("VCP {:02X} ERR\n", id.code()))
                .collect(),
        ] {
            assert!(!valid_mixed_vcp_batch(&invalid), "{invalid}");
        }
    }

    #[tokio::test]
    async fn raw_and_legacy_percent_writes_require_matching_readback_and_fixed_args() {
        let f = Fixture::new(true);
        f.controller.refresh().await.unwrap();
        f.change("maximum", json!(200));
        assert!(
            f.controller
                .brightness_percent(50)
                .await
                .unwrap()
                .contains("100 / 200")
        );
        assert_eq!(f.writes(), 1);
        let log = f.log();
        let set = log.iter().find(|a| a.contains(&"setvcp".into())).unwrap();
        assert_eq!(
            set,
            &vec![
                "--noconfig",
                "--disable-udf",
                "--maxtries",
                "1,2,2",
                "--bus",
                "12",
                "--terse",
                "setvcp",
                "10",
                "100"
            ]
            .into_iter()
            .map(str::to_owned)
            .collect::<Vec<_>>()
        );
        assert!(
            f.controller
                .set(MonitorControlId::Brightness, 201)
                .await
                .is_err()
        );
        assert_eq!(f.writes(), 1);
        f.change("ignore", json!(true));
        assert!(
            f.controller
                .set(MonitorControlId::Brightness, 94)
                .await
                .is_err()
        );
        assert_eq!(f.writes(), 2);
        assert!(!f.controller.snapshot().await.available);
    }
    #[tokio::test]
    async fn preset_rgb_dependency_is_explicit_and_monitor_swap_never_confirms() {
        let f = Fixture::new(true);
        f.change("preset", json!(5));
        f.controller.refresh().await.unwrap();
        let s = f.controller.snapshot().await;
        assert!(
            s.controls
                .iter()
                .filter(|c| c.id.rgb())
                .all(|c| !c.writable)
        );
        assert!(
            f.controller
                .set(MonitorControlId::RedGain, 100)
                .await
                .is_err()
        );
        assert_eq!(f.writes(), 0);
        assert!(
            f.controller
                .set(MonitorControlId::ColorPreset, 3)
                .await
                .is_err()
        );
        assert_eq!(f.writes(), 0);
        f.controller
            .set(MonitorControlId::ColorPreset, 11)
            .await
            .unwrap();
        assert!(
            f.controller
                .snapshot()
                .await
                .controls
                .iter()
                .filter(|c| c.id.rgb())
                .all(|c| !c.writable && c.current.is_none())
        );
        f.controller.refresh().await.unwrap();
        assert!(
            f.controller
                .snapshot()
                .await
                .controls
                .iter()
                .filter(|c| c.id.rgb())
                .all(|c| c.writable && c.current == Some(100))
        );
        f.change("swap", json!(true));
        assert!(
            f.controller
                .set(MonitorControlId::Brightness, 94)
                .await
                .is_err()
        );
        assert_eq!(f.writes(), 2);
    }
    #[tokio::test]
    async fn uncertain_timeout_is_one_write_and_cached_reads_do_not_wait_for_ddc() {
        let f = Fixture::new(true);
        f.controller.refresh().await.unwrap();
        f.change("delay", json!(10));
        let (write, read) =
            tokio::join!(f.controller.set(MonitorControlId::Brightness, 94), async {
                tokio::time::sleep(Duration::from_millis(100)).await;
                timeout(Duration::from_millis(100), f.controller.snapshot())
                    .await
                    .unwrap()
            });
        assert!(write.is_err());
        assert!(read.available);
        assert_eq!(f.writes(), 1);
        assert!(!f.controller.snapshot().await.available);
    }
    #[test]
    fn configuration_and_typed_controls_are_bounded() {
        assert!(
            MonitorConfig {
                writes_enabled: true,
                enabled: false,
                ..MonitorConfig::default()
            }
            .validate()
            .is_err()
        );
        for value in [
            json!({"operation":"monitor_set","control":"factory_reset","value":1}),
            json!({"operation":"monitor_set","control":"brightness","value":65536}),
            json!({"operation":"monitor_set","control":"brightness","value":50,"command":"sh"}),
        ] {
            assert!(serde_json::from_value::<crate::omarchy::OmarchyRequest>(value).is_err());
        }
    }
    #[test]
    fn different_display_and_wrong_commissioned_serial_are_never_fallbacks() {
        let f = Fixture::new(true);
        let p = f.root.path();
        let lg = p.join("drm/card1-DP-4");
        fs::create_dir_all(&lg).unwrap();
        fs::write(lg.join("status"), "connected").unwrap();
        let mut b = edid();
        b[59] = b'9';
        b[127] = 0;
        b[127] = 0u8.wrapping_sub(b[..127].iter().fold(0u8, |s, b| s.wrapping_add(*b)));
        fs::write(lg.join("edid"), b).unwrap();
        fs::write(p.join("drm/card1-DP-2/status"), "disconnected").unwrap();
        assert!(f.controller.discover().is_err());
        fs::write(p.join("drm/card1-DP-2/status"), "connected").unwrap();
        let c = &f.controller.commissioning;
        let text = fs::read_to_string(c)
            .unwrap()
            .replace("035926215698", "035926215699");
        fs::write(c, text).unwrap();
        assert!(f.controller.discover().is_err());
        assert_eq!(f.writes(), 0);
    }
}
