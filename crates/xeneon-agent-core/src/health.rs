use std::{
    fs,
    path::{Path, PathBuf},
    time::Instant,
};

use crate::model::{HealthSnapshot, Metric};

#[derive(Debug)]
pub struct HealthCollector {
    proc_root: PathBuf,
    sys_root: PathBuf,
    previous_cpu: Option<CpuTotals>,
    previous_network: Option<(NetworkTotals, Instant)>,
}

#[derive(Debug, Clone, Copy)]
struct CpuTotals {
    total: u64,
    idle: u64,
}

#[derive(Debug, Clone, Default)]
struct NetworkTotals {
    down: u64,
    up: u64,
    interfaces: Vec<String>,
}

impl Default for HealthCollector {
    fn default() -> Self {
        Self::new("/proc", "/sys")
    }
}

impl HealthCollector {
    pub fn new(proc_root: impl Into<PathBuf>, sys_root: impl Into<PathBuf>) -> Self {
        Self {
            proc_root: proc_root.into(),
            sys_root: sys_root.into(),
            previous_cpu: None,
            previous_network: None,
        }
    }

    pub fn sample(&mut self) -> HealthSnapshot {
        let now = Instant::now();
        let cpu = self.sample_cpu();
        let (network_down, network_up) = self.sample_network(now);
        let (gpu, gpu_temperature) = gpu_metrics(&self.sys_root);

        HealthSnapshot {
            cpu,
            cpu_temperature: cpu_temperature(&self.sys_root).map_or_else(
                || Metric::unavailable("°C"),
                |value| Metric::available(value, "°C"),
            ),
            gpu: gpu.map_or_else(
                || Metric::unavailable("%"),
                |value| Metric::available(value, "%"),
            ),
            gpu_temperature: gpu_temperature.map_or_else(
                || Metric::unavailable("°C"),
                |value| Metric::available(value, "°C"),
            ),
            memory: memory_percent(&self.proc_root.join("meminfo")).map_or_else(
                || Metric::unavailable("%"),
                |value| Metric::available(value, "%"),
            ),
            network_down,
            network_up,
            battery: battery_percent(&self.sys_root.join("class/power_supply")).map_or_else(
                || Metric::unavailable("%"),
                |value| Metric::available(value, "%"),
            ),
        }
    }

    fn sample_cpu(&mut self) -> Metric {
        let current = read_cpu_totals(&self.proc_root.join("stat"));
        let metric = current
            .zip(self.previous_cpu)
            .and_then(|(current, previous)| {
                let total = current.total.checked_sub(previous.total)?;
                let idle = current.idle.checked_sub(previous.idle)?;
                (total > 0).then(|| 100.0 * (total.saturating_sub(idle)) as f64 / total as f64)
            })
            .map_or_else(
                || Metric::unavailable("%"),
                |value| Metric::available(value, "%"),
            );
        self.previous_cpu = current;
        metric
    }

    fn sample_network(&mut self, now: Instant) -> (Metric, Metric) {
        let current = read_network_totals(&self.proc_root.join("net/dev"), &self.sys_root);
        let metrics = current
            .as_ref()
            .zip(self.previous_network.as_ref())
            .and_then(|(current, (previous, previous_at))| {
                if current.interfaces != previous.interfaces {
                    return None;
                }
                let down = current.down.checked_sub(previous.down)?;
                let up = current.up.checked_sub(previous.up)?;
                let elapsed = now.duration_since(*previous_at).as_secs_f64();
                (elapsed > 0.0).then(|| {
                    (
                        Metric::available(down as f64 / elapsed, "B/s"),
                        Metric::available(up as f64 / elapsed, "B/s"),
                    )
                })
            })
            .unwrap_or_else(|| (Metric::unavailable("B/s"), Metric::unavailable("B/s")));
        self.previous_network = current.map(|current| (current, now));
        metrics
    }
}

fn read_cpu_totals(path: &Path) -> Option<CpuTotals> {
    let contents = fs::read_to_string(path).ok()?;
    let values: Vec<u64> = contents
        .lines()
        .next()?
        .strip_prefix("cpu ")?
        .split_whitespace()
        .take(8)
        .map(str::parse)
        .collect::<Result<_, _>>()
        .ok()?;
    if values.len() < 4 {
        return None;
    }
    Some(CpuTotals {
        total: values.iter().copied().try_fold(0_u64, u64::checked_add)?,
        idle: values[3].checked_add(values.get(4).copied().unwrap_or_default())?,
    })
}

fn memory_percent(path: &Path) -> Option<f64> {
    let contents = fs::read_to_string(path).ok()?;
    let mut total = None;
    let mut available = None;
    for line in contents.lines() {
        let mut fields = line.split_whitespace();
        match fields.next()? {
            "MemTotal:" => total = fields.next()?.parse::<f64>().ok(),
            "MemAvailable:" => available = fields.next()?.parse::<f64>().ok(),
            _ => {}
        }
    }
    let total = total?;
    let available = available?;
    (total.is_finite() && total > 0.0 && (0.0..=total).contains(&available))
        .then(|| 100.0 * (total - available) / total)
}

fn read_network_totals(path: &Path, sys_root: &Path) -> Option<NetworkTotals> {
    let contents = fs::read_to_string(path).ok()?;
    let mut totals = NetworkTotals::default();
    for line in contents.lines().skip(2) {
        let Some((name, values)) = line.split_once(':') else {
            continue;
        };
        let name = name.trim();
        let interface = sys_root.join("class/net").join(name);
        // Count the physical uplink once: bridge/veth/tunnel interfaces lack
        // a device, and disconnected adapters must not dilute live traffic.
        if name == "lo"
            || name.contains('/')
            || !interface.join("device").is_dir()
            || !fs::read_to_string(interface.join("operstate"))
                .is_ok_and(|state| state.trim() == "up")
        {
            continue;
        }
        let fields: Vec<_> = values.split_whitespace().collect();
        if fields.len() < 9 {
            continue;
        }
        let (Ok(down), Ok(up)) = (fields[0].parse::<u64>(), fields[8].parse::<u64>()) else {
            continue;
        };
        totals.down = totals.down.saturating_add(down);
        totals.up = totals.up.saturating_add(up);
        totals.interfaces.push(name.to_owned());
    }
    totals.interfaces.sort();
    (!totals.interfaces.is_empty()).then_some(totals)
}

fn battery_percent(root: &Path) -> Option<f64> {
    sorted_dirs(root)
        .into_iter()
        .filter(|path| {
            fs::read_to_string(path.join("type")).is_ok_and(|value| value.trim() == "Battery")
        })
        .find_map(|path| {
            read_number(&path.join("capacity"), 1.0).filter(|value| (0.0..=100.0).contains(value))
        })
}

fn cpu_temperature(sys_root: &Path) -> Option<f64> {
    let hwmon = sorted_dirs(&sys_root.join("class/hwmon"))
        .into_iter()
        .filter(|path| {
            fs::read_to_string(path.join("name")).is_ok_and(|name| {
                matches!(
                    name.trim(),
                    "coretemp" | "k10temp" | "zenpower" | "cpu_thermal"
                )
            })
        })
        .flat_map(|path| sensor_temperatures(&path))
        .max_by(f64::total_cmp);
    hwmon.or_else(|| {
        sorted_dirs(&sys_root.join("class/thermal"))
            .into_iter()
            .filter(|path| {
                fs::read_to_string(path.join("type")).is_ok_and(|name| {
                    matches!(name.trim(), "x86_pkg_temp" | "cpu-thermal" | "cpu_thermal")
                })
            })
            .filter_map(|path| temperature_number(&path.join("temp")))
            .max_by(f64::total_cmp)
    })
}

fn temperature_number(path: &Path) -> Option<f64> {
    read_number(path, 1_000.0).filter(|value| (-20.0..=150.0).contains(value))
}

fn sensor_temperatures(root: &Path) -> Vec<f64> {
    let mut paths: Vec<_> = fs::read_dir(root)
        .into_iter()
        .flat_map(|entries| entries.flatten())
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| {
                    name.strip_prefix("temp")
                        .and_then(|name| name.strip_suffix("_input"))
                        .is_some_and(|index| {
                            !index.is_empty() && index.bytes().all(|byte| byte.is_ascii_digit())
                        })
                })
        })
        .collect();
    paths.sort();
    paths
        .into_iter()
        .take(32)
        .filter_map(|path| temperature_number(&path))
        .collect()
}

fn gpu_card_busy(card: &Path) -> Option<f64> {
    read_number(&card.join("device/gpu_busy_percent"), 1.0)
        .or_else(|| read_number(&card.join("gpu_busy_percent"), 1.0))
        .filter(|value| (0.0..=100.0).contains(value))
}

fn gpu_card_temperature(card: &Path) -> Option<f64> {
    sorted_dirs(&card.join("device/hwmon"))
        .into_iter()
        .flat_map(|hwmon| sensor_temperatures(&hwmon))
        .max_by(f64::total_cmp)
}

fn gpu_metrics(sys_root: &Path) -> (Option<f64>, Option<f64>) {
    let cards: Vec<_> = drm_cards(&sys_root.join("class/drm")).collect();
    let selected = cards
        .iter()
        .find(|card| gpu_card_busy(card).is_some())
        .or_else(|| {
            cards
                .iter()
                .find(|card| gpu_card_temperature(card).is_some())
        });
    selected.map_or((None, None), |card| {
        (gpu_card_busy(card), gpu_card_temperature(card))
    })
}

fn drm_cards(root: &Path) -> impl Iterator<Item = PathBuf> {
    let mut cards: Vec<_> = fs::read_dir(root)
        .into_iter()
        .flat_map(|entries| entries.flatten())
        .filter(|entry| {
            let name = entry.file_name();
            let Some(name) = name.to_str() else {
                return false;
            };
            let Some(index) = name.strip_prefix("card") else {
                return false;
            };
            !index.is_empty() && index.bytes().all(|byte| byte.is_ascii_digit())
        })
        .map(|entry| entry.path())
        .collect();
    cards.sort();
    cards.into_iter()
}

fn read_number(path: &Path, divisor: f64) -> Option<f64> {
    fs::read_to_string(path)
        .ok()?
        .trim()
        .parse::<f64>()
        .ok()
        .map(|value| value / divisor)
        .filter(|value| value.is_finite())
}

fn sorted_dirs(root: &Path) -> Vec<PathBuf> {
    // sysfs class entries are normally symlinks to /sys/devices.
    let mut paths: Vec<_> = fs::read_dir(root)
        .into_iter()
        .flat_map(|entries| entries.flatten())
        .map(|entry| entry.path())
        .filter(|path| fs::metadata(path).is_ok_and(|kind| kind.is_dir()))
        .collect();
    paths.sort();
    paths
}

#[cfg(test)]
mod tests {
    use std::{fs, os::unix::fs::symlink, thread, time::Duration};

    use super::*;

    fn write(path: &Path, contents: &str) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, contents).unwrap();
    }

    fn physical_interface(sys_root: &Path, name: &str, state: &str) {
        let device = sys_root.join("devices").join(name);
        fs::create_dir_all(&device).unwrap();
        write(
            &sys_root.join("class/net").join(name).join("operstate"),
            state,
        );
        symlink(device, sys_root.join("class/net").join(name).join("device")).unwrap();
    }

    #[test]
    fn unavailable_is_distinct_from_zero() {
        let root = tempfile::tempdir().unwrap();
        let mut collector = HealthCollector::new(root.path().join("proc"), root.path().join("sys"));
        let health = collector.sample();
        assert!(!health.cpu.available);
        assert_eq!(health.cpu.value, None);
        assert!(!health.battery.available);
    }

    #[test]
    fn samples_proc_and_sys_metrics() {
        let root = tempfile::tempdir().unwrap();
        let proc_root = root.path().join("proc");
        let sys_root = root.path().join("sys");
        write(&proc_root.join("stat"), "cpu  100 0 50 850 0 0 0 0\n");
        write(
            &proc_root.join("meminfo"),
            "MemTotal: 1000 kB\nMemAvailable: 600 kB\n",
        );
        write(
            &proc_root.join("net/dev"),
            "Inter-| Receive | Transmit\n face |\neth0: 1000 0 0 0 0 0 0 0 500 0 0 0 0 0 0 0\n",
        );
        physical_interface(&sys_root, "eth0", "up");
        write(&sys_root.join("class/power_supply/BAT0/type"), "Battery\n");
        write(&sys_root.join("class/power_supply/BAT0/capacity"), "82\n");
        write(
            &sys_root.join("class/thermal/thermal_zone0/type"),
            "x86_pkg_temp\n",
        );
        write(
            &sys_root.join("class/thermal/thermal_zone0/temp"),
            "45000\n",
        );

        let mut collector = HealthCollector::new(&proc_root, &sys_root);
        let first = collector.sample();
        assert_eq!(first.memory.value, Some(40.0));
        assert_eq!(first.battery.value, Some(82.0));
        assert_eq!(first.cpu_temperature.value, Some(45.0));
        assert!(!first.cpu.available);

        write(&proc_root.join("stat"), "cpu  150 0 50 900 0 0 0 0\n");
        write(
            &proc_root.join("net/dev"),
            "Inter-| Receive | Transmit\n face |\neth0: 2000 0 0 0 0 0 0 0 1500 0 0 0 0 0 0 0\n",
        );
        thread::sleep(Duration::from_millis(2));
        let second = collector.sample();
        assert!(second.cpu.available);
        assert!(second.network_down.available);
        assert!(second.network_up.available);
    }

    #[test]
    fn malformed_network_interfaces_do_not_hide_valid_totals() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("net/dev");
        write(
            &path,
            "Inter-| Receive | Transmit\n face |\nmissing separator\nbad0: nope 0 0 0 0 0 0 0 12 0 0 0 0 0 0 0\neth0: 1000 0 0 0 0 0 0 0 500 0 0 0 0 0 0 0\n",
        );

        let sys_root = root.path().join("sys");
        physical_interface(&sys_root, "eth0", "up");
        let totals = read_network_totals(&path, &sys_root).unwrap();
        assert_eq!(totals.down, 1000);
        assert_eq!(totals.up, 500);
    }

    #[test]
    fn reads_bounded_drm_card_metrics_without_recursive_device_walk() {
        let root = tempfile::tempdir().unwrap();
        let device = root.path().join("devices/gpu");
        write(&device.join("gpu_busy_percent"), "37\n");
        write(&device.join("hwmon/hwmon0/temp1_input"), "51000\n");
        write(&device.join("unrelated/nested/gpu_busy_percent"), "99\n");
        let drm = root.path().join("sys/class/drm");
        fs::create_dir_all(drm.join("card1")).unwrap();
        symlink(&device, drm.join("card1/device")).unwrap();

        assert_eq!(
            gpu_metrics(&root.path().join("sys")),
            (Some(37.0), Some(51.0))
        );
    }

    #[test]
    fn ignores_connector_and_unbounded_drm_subtrees() {
        let root = tempfile::tempdir().unwrap();
        let drm = root.path().join("sys/class/drm");
        write(&drm.join("card0-DP-1/device/gpu_busy_percent"), "88\n");
        write(&drm.join("renderD128/nested/gpu_busy_percent"), "77\n");

        assert_eq!(gpu_metrics(&root.path().join("sys")), (None, None));
    }

    #[test]
    fn follows_sysfs_class_symlinks_and_selects_only_cpu_sensors() {
        let root = tempfile::tempdir().unwrap();
        let sys_root = root.path().join("sys");
        let cpu = root.path().join("devices/cpu");
        write(&cpu.join("name"), "k10temp\n");
        write(&cpu.join("temp1_input"), "48500\n");
        let gpu = root.path().join("devices/gpu");
        write(&gpu.join("name"), "amdgpu\n");
        write(&gpu.join("temp1_input"), "93000\n");
        fs::create_dir_all(sys_root.join("class/hwmon")).unwrap();
        symlink(cpu, sys_root.join("class/hwmon/hwmon4")).unwrap();
        symlink(gpu, sys_root.join("class/hwmon/hwmon3")).unwrap();
        write(
            &sys_root.join("class/thermal/thermal_zone0/type"),
            "acpitz\n",
        );
        write(
            &sys_root.join("class/thermal/thermal_zone0/temp"),
            "99000\n",
        );
        assert_eq!(cpu_temperature(&sys_root), Some(48.5));
        let battery = root.path().join("devices/battery");
        write(&battery.join("type"), "Battery\n");
        write(&battery.join("capacity"), "73\n");
        fs::create_dir_all(sys_root.join("class/power_supply")).unwrap();
        symlink(battery, sys_root.join("class/power_supply/BAT0")).unwrap();
        assert_eq!(
            battery_percent(&sys_root.join("class/power_supply")),
            Some(73.0)
        );
    }

    #[test]
    fn gpu_utilization_and_temperature_never_mix_cards() {
        let root = tempfile::tempdir().unwrap();
        write(
            &root.path().join("class/drm/card0/device/gpu_busy_percent"),
            "31\n",
        );
        write(
            &root
                .path()
                .join("class/drm/card1/device/hwmon/hwmon0/temp1_input"),
            "87000\n",
        );
        assert_eq!(gpu_metrics(root.path()), (Some(31.0), None));
        write(
            &root
                .path()
                .join("class/drm/card0/device/hwmon/hwmon1/temp1_input"),
            "51000\n",
        );
        assert_eq!(gpu_metrics(root.path()), (Some(31.0), Some(51.0)));
        write(
            &root.path().join("class/drm/card0/device/gpu_busy_percent"),
            "NaN\n",
        );
        assert_eq!(gpu_metrics(root.path()), (None, Some(51.0)));
    }

    #[test]
    fn network_counts_only_active_physical_links_and_resets_changed_baselines() {
        let root = tempfile::tempdir().unwrap();
        let proc_root = root.path().join("proc");
        let sys_root = root.path().join("sys");
        physical_interface(&sys_root, "eth0", "up");
        physical_interface(&sys_root, "wlan0", "down");
        write(&sys_root.join("class/net/docker0/operstate"), "up\n");
        let network = "Inter-| Receive | Transmit\n face |\neth0: 1000 0 0 0 0 0 0 0 500 0 0 0 0 0 0 0\nwlan0: 9000 0 0 0 0 0 0 0 9000 0 0 0 0 0 0 0\ndocker0: 8000 0 0 0 0 0 0 0 8000 0 0 0 0 0 0 0\n";
        write(&proc_root.join("net/dev"), network);
        let totals = read_network_totals(&proc_root.join("net/dev"), &sys_root).unwrap();
        assert_eq!((totals.down, totals.up), (1000, 500));
        assert_eq!(totals.interfaces, ["eth0"]);
        let mut collector = HealthCollector::new(&proc_root, &sys_root);
        let now = Instant::now();
        assert!(!collector.sample_network(now).0.available);
        write(
            &proc_root.join("net/dev"),
            &network.replace("eth0: 1000", "eth0: 2000"),
        );
        assert_eq!(
            collector
                .sample_network(now + Duration::from_secs(1))
                .0
                .value,
            Some(1000.0)
        );
        write(&sys_root.join("class/net/wlan0/operstate"), "up\n");
        assert!(
            !collector
                .sample_network(now + Duration::from_secs(2))
                .0
                .available
        );
        write(
            &proc_root.join("net/dev"),
            &network.replace("eth0: 1000", "eth0: 1"),
        );
        assert!(
            !collector
                .sample_network(now + Duration::from_secs(3))
                .0
                .available
        );
    }

    #[test]
    fn malformed_cpu_and_out_of_range_metrics_fail_closed() {
        let root = tempfile::tempdir().unwrap();
        write(&root.path().join("stat"), "cpu  1 nope 2 3\n");
        assert!(read_cpu_totals(&root.path().join("stat")).is_none());
        write(&root.path().join("stat"), "cpu  1 2 3 4 5 6 7 8 100 100\n");
        assert_eq!(
            read_cpu_totals(&root.path().join("stat")).unwrap().total,
            36
        );
        write(
            &root.path().join("meminfo"),
            "MemTotal: 10 kB\nMemAvailable: 20 kB\n",
        );
        assert!(memory_percent(&root.path().join("meminfo")).is_none());
        write(&root.path().join("BAT0/type"), "Battery\n");
        write(&root.path().join("BAT0/capacity"), "101\n");
        assert!(battery_percent(root.path()).is_none());
    }
}
