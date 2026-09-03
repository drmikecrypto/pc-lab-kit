use serde::Deserialize;
use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindowBuilder};

#[derive(Debug, Deserialize)]
pub struct LcdPlayerArgs {
    pub url: String,
    pub label: Option<String>,
    pub x: Option<f64>,
    pub y: Option<f64>,
    pub width: Option<f64>,
    pub height: Option<f64>,
    pub title: Option<String>,
}

fn parse_player_url(raw: &str) -> Result<WebviewUrl, String> {
    if raw.starts_with("http://") || raw.starts_with("https://") || raw.starts_with("file:") {
        let u: url::Url = raw.parse().map_err(|e| format!("bad url: {e}"))?;
        return Ok(WebviewUrl::External(u));
    }
    let path = std::path::PathBuf::from(raw);
    let abs = if path.is_absolute() {
        path
    } else {
        std::env::current_dir()
            .map_err(|e| e.to_string())?
            .join(path)
    };
    let u = url::Url::from_file_path(&abs).map_err(|_| "invalid file path for LCD player")?;
    Ok(WebviewUrl::External(u))
}

#[tauri::command]
pub async fn lcd_open_player(app: AppHandle, args: LcdPlayerArgs) -> Result<String, String> {
    let label = args.label.unwrap_or_else(|| "lcd-player".to_string());
    if let Some(existing) = app.get_webview_window(&label) {
        let _ = existing.close();
    }
    let url = parse_player_url(&args.url)?;
    let w = args.width.unwrap_or(800.0);
    let h = args.height.unwrap_or(600.0);
    let x = args.x.unwrap_or(0.0);
    let y = args.y.unwrap_or(0.0);
    let title = args.title.unwrap_or_else(|| "PC Lab Kit LCD".into());

    WebviewWindowBuilder::new(&app, &label, url)
        .title(title)
        .inner_size(w, h)
        .decorations(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .resizable(false)
        .position(x, y)
        .visible(true)
        .focused(true)
        .build()
        .map_err(|e| e.to_string())?;
    Ok(label)
}

#[tauri::command]
pub async fn lcd_close_player(app: AppHandle, label: Option<String>) -> Result<bool, String> {
    let label = label.unwrap_or_else(|| "lcd-player".to_string());
    if let Some(w) = app.get_webview_window(&label) {
        w.close().map_err(|e| e.to_string())?;
        return Ok(true);
    }
    Ok(false)
}
