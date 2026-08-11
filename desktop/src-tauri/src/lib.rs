mod lab;

use lab::{resolve_resource_lab, LabRuntime};
use std::sync::Arc;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::Manager;
use tauri::path::BaseDirectory;

struct AppState {
    runtime: std::sync::Mutex<Option<Arc<LabRuntime>>>,
    error: std::sync::Mutex<Option<String>>,
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
            let resource_dir = app
                .path()
                .resolve("", BaseDirectory::Resource)
                .ok()
                .map(|p| p);

            let lab_dir = match resolve_resource_lab(resource_dir) {
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

            match LabRuntime::start(&lab_dir) {
                Ok(rt) => {
                    let rt = Arc::new(rt);
                    if let Some(state) = app.try_state::<AppState>() {
                        if let Ok(mut g) = state.runtime.lock() {
                            *g = Some(Arc::clone(&rt));
                        }
                    }
                    app.manage(ShutdownHandle(rt));
                }
                Err(err) => {
                    eprintln!("PC Lab Kit failed to start: {err}");
                    if let Some(state) = app.try_state::<AppState>() {
                        if let Ok(mut g) = state.error.lock() {
                            *g = Some(err);
                        }
                    }
                }
            }

            let show_i = MenuItem::with_id(app, "show", "Open Lab", true, None::<&str>)?;
            let probe_i = MenuItem::with_id(app, "probe", "Restart Probe", true, None::<&str>)?;
            let status_i = MenuItem::with_id(app, "status", "Probe Status", true, None::<&str>)?;
            let quit_i = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show_i, &probe_i, &status_i, &quit_i])?;

            let mut tray = TrayIconBuilder::new()
                .menu(&menu)
                .tooltip("PC Lab Kit")
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    "probe" => {
                        if let Some(state) = app.try_state::<AppState>() {
                            if let Ok(guard) = state.runtime.lock() {
                                if let Some(rt) = guard.as_ref() {
                                    match rt.ensure_probe() {
                                        Ok(s) => eprintln!("probe: {s}"),
                                        Err(e) => eprintln!("probe restart failed: {e}"),
                                    }
                                }
                            }
                        }
                    }
                    "status" => {
                        if let Some(state) = app.try_state::<AppState>() {
                            if let Ok(guard) = state.runtime.lock() {
                                if let Some(rt) = guard.as_ref() {
                                    eprintln!("probe status: {}", rt.probe_status());
                                }
                            }
                        }
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

            // Soft watchdog: if probe exited, try once to bring it back.
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                loop {
                    std::thread::sleep(std::time::Duration::from_secs(20));
                    if let Some(state) = handle.try_state::<AppState>() {
                        if let Ok(guard) = state.runtime.lock() {
                            if let Some(rt) = guard.as_ref() {
                                let st = rt.probe_status();
                                if st != "running" && st != "unavailable" && !st.starts_with("error") {
                                    let _ = rt.ensure_probe();
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
