use std::fs;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::thread;
use std::time::{Duration, Instant};

pub struct LabRuntime {
    pub lab_url: String,
    work_dir: PathBuf,
    php: Mutex<Option<Child>>,
    probe: Mutex<Option<Child>>,
}

impl LabRuntime {
    pub fn start(resource_lab: &Path) -> Result<Self, String> {
        let work_dir = prepare_work_dir(resource_lab)?;
        let php_bin = resolve_php_bin(&work_dir)?;
        ensure_lab_ready(&work_dir, &php_bin)?;

        let port = pick_free_port()?;
        let mut php = spawn_php(&php_bin, &work_dir, port)?;
        let lab_url = format!("http://127.0.0.1:{port}/diagnostic");

        if let Err(err) = wait_for_http(&lab_url, Duration::from_secs(45)) {
            let _ = php.kill();
            let _ = php.wait();
            return Err(err);
        }

        let probe = spawn_probe(&work_dir).ok().flatten();

        Ok(Self {
            lab_url,
            work_dir,
            php: Mutex::new(Some(php)),
            probe: Mutex::new(probe),
        })
    }

    pub fn probe_status(&self) -> String {
        if let Ok(mut guard) = self.probe.lock() {
            if let Some(child) = guard.as_mut() {
                match child.try_wait() {
                    Ok(None) => return "running".into(),
                    Ok(Some(status)) => {
                        *guard = None;
                        return format!("exited:{status}");
                    }
                    Err(e) => return format!("error:{e}"),
                }
            }
        }
        "stopped".into()
    }

    pub fn ensure_probe(&self) -> Result<String, String> {
        let status = self.probe_status();
        if status == "running" {
            return Ok(status);
        }
        let child = spawn_probe(&self.work_dir)?.ok_or_else(|| "Probe not available on this platform".to_string())?;
        if let Ok(mut guard) = self.probe.lock() {
            *guard = Some(child);
        }
        Ok("restarted".into())
    }

    pub fn shutdown(&self) {
        if let Ok(mut guard) = self.php.lock() {
            if let Some(mut child) = guard.take() {
                let _ = child.kill();
                let _ = child.wait();
            }
        }
        if let Ok(mut guard) = self.probe.lock() {
            if let Some(mut child) = guard.take() {
                let _ = child.kill();
                let _ = child.wait();
            }
        }
    }
}

impl Drop for LabRuntime {
    fn drop(&mut self) {
        self.shutdown();
    }
}

fn prepare_work_dir(resource_lab: &Path) -> Result<PathBuf, String> {
    if let Ok(override_root) = std::env::var("PCLAB_LAB_ROOT") {
        let path = PathBuf::from(override_root);
        if path.join("public").is_dir() {
            return Ok(path);
        }
        return Err(format!(
            "PCLAB_LAB_ROOT does not look like a lab root: {}",
            path.display()
        ));
    }

    if !resource_lab.join("public").is_dir() {
        return Err(format!(
            "Lab payload missing at {}. Run scripts/stage-desktop-payload before building.",
            resource_lab.display()
        ));
    }

    let data_dir = dirs::data_local_dir()
        .ok_or_else(|| "Could not resolve local app data directory".to_string())?
        .join("PC Lab Kit");

    fs::create_dir_all(&data_dir).map_err(|e| format!("Create app data dir: {e}"))?;

    let marker = data_dir.join(".pclab-payload-version");
    let want_version = env!("CARGO_PKG_VERSION");
    let needs_copy = match fs::read_to_string(&marker) {
        Ok(v) => v.trim() != want_version || !data_dir.join("public").is_dir(),
        Err(_) => true,
    };

    if needs_copy {
        // Refresh payload but keep user storage/settings when possible.
        for name in ["app", "bin", "config", "public", "resources", "routes", "vendor", "runtime", "agent", "cron", "database"] {
            let from = resource_lab.join(name);
            let to = data_dir.join(name);
            if from.exists() {
                if to.exists() {
                    let _ = fs::remove_dir_all(&to);
                }
                copy_dir_recursive(&from, &to)
                    .map_err(|e| format!("Copy {name}: {e}"))?;
            }
        }
        for file in [".env.example", "composer.json", "composer.lock", "PcLabKit", "PcLabKit.bat"] {
            let from = resource_lab.join(file);
            if from.is_file() {
                fs::copy(&from, data_dir.join(file)).map_err(|e| format!("Copy {file}: {e}"))?;
            }
        }
        fs::write(&marker, want_version).map_err(|e| format!("Write payload marker: {e}"))?;
    }

    Ok(data_dir)
}

pub fn resolve_resource_lab(resolver: &tauri::path::PathResolver) -> Result<PathBuf, String> {
    for rel in ["lab", "resources/lab"] {
        if let Ok(path) = resolver.resolve(rel, tauri::path::BaseDirectory::Resource) {
            if path.join("public").is_dir() {
                return Ok(path);
            }
        }
    }

    if let Ok(dir) = resolver.resource_dir() {
        for candidate in [dir.join("lab"), dir.join("resources").join("lab")] {
            if candidate.join("public").is_dir() {
                return Ok(candidate);
            }
        }
    }

    // Dev fallback: staged resources or repository root.
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let staged = manifest_dir.join("resources").join("lab");
    if staged.join("public").is_dir() {
        return Ok(staged);
    }

    let repo_root = manifest_dir
        .parent()
        .and_then(|p| p.parent())
        .ok_or_else(|| "Cannot resolve repository root".to_string())?
        .to_path_buf();
    if repo_root.join("public").is_dir() {
        return Ok(repo_root);
    }

    Err("Lab payload missing. Run scripts/stage-desktop-payload.ps1 (or .sh) before building.".into())
}

fn resolve_php_bin(work_dir: &Path) -> Result<PathBuf, String> {
    #[cfg(windows)]
    {
        let bundled = work_dir.join("runtime").join("php").join("php.exe");
        if bundled.is_file() {
            return Ok(bundled);
        }
    }
    #[cfg(not(windows))]
    {
        let candidates = [
            work_dir.join("runtime").join("php").join("bin").join("php"),
            work_dir.join("runtime").join("php").join("php"),
        ];
        for c in candidates {
            if c.is_file() {
                return Ok(c);
            }
        }
    }

    which::which("php").map_err(|_| {
        "PHP not found. Bundle runtime/php into the desktop payload or install PHP 8.2+.".to_string()
    })
}

fn ensure_lab_ready(work_dir: &Path, php_bin: &Path) -> Result<(), String> {
    let env_path = work_dir.join(".env");
    let example = work_dir.join(".env.example");
    if !env_path.exists() && example.exists() {
        fs::copy(&example, &env_path).map_err(|e| format!("Copy .env: {e}"))?;
    }

    for sub in [
        "storage/database",
        "storage/cache",
        "storage/cache/benchmark",
        "storage/settings",
        "public/downloads",
    ] {
        fs::create_dir_all(work_dir.join(sub)).map_err(|e| format!("Create {sub}: {e}"))?;
    }

    if !work_dir.join("vendor").join("autoload.php").is_file() {
        return Err("vendor/autoload.php missing in lab payload".into());
    }

    let migrate = work_dir.join("bin").join("migrate.php");
    if migrate.is_file() {
        let status = Command::new(php_bin)
            .arg(&migrate)
            .current_dir(work_dir)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map_err(|e| format!("Run migrate: {e}"))?;
        if !status.success() {
            eprintln!("migrate.php exited with {status}");
        }
    }

    Ok(())
}

fn pick_free_port() -> Result<u16, String> {
    let listener = TcpListener::bind("127.0.0.1:0").map_err(|e| format!("bind: {e}"))?;
    let port = listener
        .local_addr()
        .map_err(|e| format!("local_addr: {e}"))?
        .port();
    drop(listener);
    Ok(port)
}

fn spawn_php(php_bin: &Path, work_dir: &Path, port: u16) -> Result<Child, String> {
    let mut cmd = Command::new(php_bin);
    cmd.args(["-S", &format!("127.0.0.1:{port}"), "-t", "public"])
        .current_dir(work_dir)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }

    cmd.spawn()
        .map_err(|e| format!("Failed to start PHP server ({}): {e}", php_bin.display()))
}

fn wait_for_http(url: &str, timeout: Duration) -> Result<(), String> {
    let start = Instant::now();
    let mut last_err = String::from("not ready");
    while start.elapsed() < timeout {
        match http_get_ok(url) {
            Ok(()) => return Ok(()),
            Err(e) => last_err = e,
        }
        thread::sleep(Duration::from_millis(250));
    }
    Err(format!("Lab did not become ready at {url}: {last_err}"))
}

fn http_get_ok(url: &str) -> Result<(), String> {
    let without_scheme = url
        .strip_prefix("http://")
        .ok_or_else(|| "only http:// URLs supported".to_string())?;
    let (host_port, path) = without_scheme
        .split_once('/')
        .map(|(h, p)| (h, format!("/{p}")))
        .unwrap_or((without_scheme, "/".into()));

    let mut stream =
        TcpStream::connect(host_port).map_err(|e| format!("connect {host_port}: {e}"))?;
    stream.set_read_timeout(Some(Duration::from_secs(2))).ok();
    stream.set_write_timeout(Some(Duration::from_secs(2))).ok();

    let req = format!("GET {path} HTTP/1.1\r\nHost: {host_port}\r\nConnection: close\r\n\r\n");
    stream
        .write_all(req.as_bytes())
        .map_err(|e| format!("write: {e}"))?;

    let mut buf = [0u8; 128];
    let n = stream.read(&mut buf).map_err(|e| format!("read: {e}"))?;
    if n == 0 {
        return Err("empty response".into());
    }
    let head = String::from_utf8_lossy(&buf[..n]);
    if head.contains(" 200 ") || head.contains(" 302 ") || head.contains(" 301 ") {
        Ok(())
    } else {
        Err(format!(
            "unexpected response: {}",
            head.lines().next().unwrap_or("")
        ))
    }
}

fn spawn_probe(work_dir: &Path) -> Result<Option<Child>, String> {
    #[cfg(not(windows))]
    {
        let _ = work_dir;
        return Ok(None);
    }

    #[cfg(windows)]
    {
        let probe_dir = work_dir.join("agent").join("pclab_probe");
        let serve = probe_dir.join("PcLabProbeServe.ps1");
        if !serve.is_file() {
            return Ok(None);
        }

        let mut cmd = Command::new("powershell.exe");
        cmd.args([
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            serve.to_str().ok_or("probe path utf-8")?,
        ])
        .current_dir(&probe_dir)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        cmd.creation_flags(CREATE_NO_WINDOW);

        match cmd.spawn() {
            Ok(child) => Ok(Some(child)),
            Err(e) => {
                eprintln!("probe spawn failed (lab will still open): {e}");
                Ok(None)
            }
        }
    }
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> std::io::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let ty = entry.file_type()?;
        let from = entry.path();
        let to = dst.join(entry.file_name());
        if ty.is_dir() {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if matches!(
                name.as_ref(),
                ".git" | ".cursor" | "build-cache" | "graphify-out" | "node_modules" | "desktop"
            ) {
                continue;
            }
            copy_dir_recursive(&from, &to)?;
        } else {
            if let Some(parent) = to.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(&from, &to)?;
        }
    }
    Ok(())
}
