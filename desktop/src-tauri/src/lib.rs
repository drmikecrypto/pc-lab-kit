mod lab;

use lab::{resolve_resource_lab, LabRuntime};
use std::io::{Read, Write};
use std::sync::Arc;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{TrayIconBuilder, TrayIconId};
use tauri::Manager;

struct AppState {
    runtime: std::sync::Mutex<Option<Arc<LabRuntime>>>,
    error: std::sync::Mutex<Option<String>>,
}

fn fetch_probe_health() -> Option<(bool, i64)> {
    let addr = "127.0.0.1:18765".parse().ok()?;
    let mut stream = std::net::TcpStream::connect_timeout(
        &addr,
        std::time::Duration::from_millis(400),
    )
    .ok()?;
    stream
        .set_read_timeout(Some(std::time::Duration::from_millis(400)))
        .ok()?;
    stream
        .set_write_timeout(Some(std::time::Duration::from_millis(400)))
        .ok()?;
    stream
        .write_all(b"GET /health HTTP/1.0\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
        .ok()?;
    let mut buf = String::new();
    stream.read_to_string(&mut buf).ok()?;
    let body = buf.split("\r\n\r\n").nth(1)?;
    let v: serde_json::Value = serde_json::from_str(body.trim()).ok()?;
    let elevated = v.get("elevated").and_then(|x| x.as_bool()).unwrap_or(false);
    let count = v
        .get("open_book_count")
        .and_then(|x| x.as_i64())
        .unwrap_or(0);
    Some((elevated, count))
}

fn format_probe_tooltip(status: &str) -> String {
    if status == "running" || status.starts_with("service:") || status.starts_with("external:") {
        if let Some((elevated, count)) = fetch_probe_health() {
            let elev = if elevated { "elevated" } else { "not elevated" };
            let mode = if status.starts_with("service:") {
                "service"
            } else if status.starts_with("external:") {
                "external"
            } else {
                "sidecar"
            };
            return format!("PC Lab Kit · Probe: {mode} · {elev} · {count} open-book");
        }
        return format!("PC Lab Kit · Probe: {status}");
    }
    format!("PC Lab Kit · Probe: {status}")
}

fn probe_status_message(status: &str) -> String {
    match status {
        "running" => "Probe is running on 127.0.0.1:18765.\nSensors, RGB, and benches are available.".into(),
        s if s.starts_with("service:") => {
            "Probe Windows Service is healthy on 127.0.0.1:18765.\nDesktop will not spawn a second probe.".into()
        }
        s if s.starts_with("external:") => {
            "An external probe is already healthy on 127.0.0.1:18765.\nDesktop skipped sidecar spawn.".into()
        }
        "unavailable" => "Probe is unavailable on this platform (or not bundled).\nLab UI still works for history and imports.".into(),
        s if s.starts_with("error") => format!("Probe error:\n{s}\n\nTry Restart Probe from this menu."),
        s if s.contains("exited") || s.contains("stopped") => {
            format!("Probe status: {s}\n\nUse Restart Probe to bring it back.")
        }
        other => format!("Probe status: {other}"),
    }
}

fn show_probe_status_dialog(app: &tauri::AppHandle, status: &str) {
    let msg = probe_status_message(status);
    let escaped = msg
        .replace('\\', "\\\\")
        .replace('`', "\\`")
        .replace("${", "\\${");
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
        let js = format!("window.alert(`PC Lab Kit — Probe Status\\n\\n{escaped}`)");
        let _ = window.eval(&js);
    }
}

#[tauri::command]
fn get_lab_url(state: tauri::State<'_, AppState>) -> Result<String, String> {
    if let Ok(guard) = state.runtime.lock() {
        if let Some(rt) = guard.as_ref() {
            return Ok(rt.lab_url.clone());
        }
    }
    if let Ok(guard) = state.error.lock() {
        if let Some(err) = guard.as_ref() {
            return Err(err.clone());
        }
    }
    Err("Laboratory is still starting…".into())
}

#[tauri::command]
fn get_probe_status(state: tauri::State<'_, AppState>) -> Result<String, String> {
    if let Ok(guard) = state.runtime.lock() {
        if let Some(rt) = guard.as_ref() {
            return Ok(rt.probe_status());
        }
    }
    Ok("unavailable".into())
}

#[tauri::command]
fn restart_probe(state: tauri::State<'_, AppState>) -> Result<String, String> {
    if let Ok(guard) = state.runtime.lock() {
        if let Some(rt) = guard.as_ref() {
            return rt.ensure_probe();
        }
    }
    Err("Lab runtime not ready".into())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_opener::init())
        .manage(AppState {
            runtime: std::sync::Mutex::new(None),
            error: std::sync::Mutex::new(None),
        })
        .invoke_handler(tauri::generate_handler![
            get_lab_url,
            get_probe_status,
            restart_probe
        ])
        .setup(|app| {
            let lab_dir = match resolve_resource_lab(app.path()) {
                Ok(p) => p,
                Err(err) => {
                    if let Some(state) = app.try_state::<AppState>() {
                        if let Ok(mut g) = state.error.lock() {
                            *g = Some(err.clone());
                        }
                    }
                    eprintln!("PC Lab Kit resource resolve failed: {err}");
                    return Ok(());
                }
            };

            let initial_probe = match LabRuntime::start(&lab_dir) {
                Ok(rt) => {
                    let status = rt.probe_status();
                    let rt = Arc::new(rt);
                    if let Some(state) = app.try_state::<AppState>() {
                        if let Ok(mut g) = state.runtime.lock() {
                            *g = Some(Arc::clone(&rt));
                        }
                    }
                    app.manage(ShutdownHandle(rt));
                    status
                }
                Err(err) => {
                    eprintln!("PC Lab Kit failed to start: {err}");
                    if let Some(state) = app.try_state::<AppState>() {
                        if let Ok(mut g) = state.error.lock() {
                            *g = Some(err);
                        }
                    }
                    "error".into()
                }
            };

            let show_i = MenuItem::with_id(app, "show", "Open Lab", true, None::<&str>)?;
            let probe_i = MenuItem::with_id(app, "probe", "Restart Probe", true, None::<&str>)?;
            let status_i = MenuItem::with_id(app, "status", "Probe Status", true, None::<&str>)?;
            let quit_i = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show_i, &probe_i, &status_i, &quit_i])?;

            let tray_id = TrayIconId::new("main");
            let mut tray = TrayIconBuilder::with_id(tray_id.clone())
                .menu(&menu)
                .tooltip(format_probe_tooltip(&initial_probe))
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    "probe" => {
                        let mut msg = "Probe restart unavailable".to_string();
                        if let Some(state) = app.try_state::<AppState>() {
                            if let Ok(guard) = state.runtime.lock() {
                                if let Some(rt) = guard.as_ref() {
                                    msg = match rt.ensure_probe() {
                                        Ok(s) => format!("Probe: {s}"),
                                        Err(e) => format!("Probe restart failed: {e}"),
                                    };
                                    if let Some(tray) = app.tray_by_id("main") {
                                        let st = rt.probe_status();
                                        let _ = tray.set_tooltip(Some(format_probe_tooltip(&st)));
                                    }
                                }
                            }
                        }
                        show_probe_status_dialog(app, &msg);
                    }
                    "status" => {
                        let status = if let Some(state) = app.try_state::<AppState>() {
                            if let Ok(guard) = state.runtime.lock() {
                                guard
                                    .as_ref()
                                    .map(|rt| rt.probe_status())
                                    .unwrap_or_else(|| "unavailable".into())
                            } else {
                                "unavailable".into()
                            }
                        } else {
                            "unavailable".into()
                        };
                        if let Some(tray) = app.tray_by_id("main") {
                            let _ = tray.set_tooltip(Some(format_probe_tooltip(&status)));
                        }
                        show_probe_status_dialog(app, &status);
                    }
                    "quit" => {
                        if let Some(handle) = app.try_state::<ShutdownHandle>() {
                            handle.0.shutdown();
                        }
                        app.exit(0);
                    }
                    _ => {}
                });
            if let Some(icon) = app.default_window_icon().cloned() {
                tray = tray.icon(icon);
            }
            let _tray = tray.build(app)?;

            // Soft watchdog: if probe exited, try once to bring it back; keep tooltip fresh.
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                loop {
                    std::thread::sleep(std::time::Duration::from_secs(20));
                    if let Some(state) = handle.try_state::<AppState>() {
                        if let Ok(guard) = state.runtime.lock() {
                            if let Some(rt) = guard.as_ref() {
                                let mut st = rt.probe_status();
                                if st != "running"
                                    && st != "unavailable"
                                    && !st.starts_with("error")
                                {
                                    let _ = rt.ensure_probe();
                                    st = rt.probe_status();
                                }
                                if let Some(tray) = handle.tray_by_id("main") {
                                    let _ = tray.set_tooltip(Some(format_probe_tooltip(&st)));
                                }
                            }
                        }
                    }
                }
            });

            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                // Keep lab alive in tray — hide instead of destroy.
                api.prevent_close();
                let _ = window.hide();
            }
            if let tauri::WindowEvent::Destroyed = event {
                if let Some(handle) = window.app_handle().try_state::<ShutdownHandle>() {
                    handle.0.shutdown();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

struct ShutdownHandle(Arc<LabRuntime>);
