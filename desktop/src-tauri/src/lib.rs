mod lab;

use lab::{resolve_resource_lab, LabRuntime};
use std::sync::Arc;
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_opener::init())
        .manage(AppState {
            runtime: std::sync::Mutex::new(None),
            error: std::sync::Mutex::new(None),
        })
        .invoke_handler(tauri::generate_handler![get_lab_url])
        .setup(|app| {
            let resource_dir = app
                .path()
                .resolve("", BaseDirectory::Resource)
                .ok()
                .map(|p| {
                    // resolve("") may point at resources root
                    p
                });

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
            Ok(())
        })
        .on_window_event(|window, event| {
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
