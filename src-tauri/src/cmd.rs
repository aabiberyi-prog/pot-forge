use crate::config::get;
use crate::config::set;
use crate::config::StoreWrapper;
use crate::error::Error;
use crate::StringWrapper;
use crate::APP;
use log::{error, info};
use serde_json::{json, Value};
use std::io::Read;
use std::path::PathBuf;
use std::process::Command;
use tauri::Manager;

#[tauri::command]
pub fn get_text(state: tauri::State<StringWrapper>) -> String {
    return state.0.lock().unwrap().to_string();
}

#[tauri::command]
pub fn reload_store() {
    let state = APP.get().unwrap().state::<StoreWrapper>();
    let mut store = state.0.lock().unwrap();
    store.load().unwrap();
}

#[tauri::command]
pub fn cut_image(left: u32, top: u32, width: u32, height: u32, app_handle: tauri::AppHandle) {
    use dirs::cache_dir;
    use image::GenericImage;
    info!("Cut image: {}x{}+{}+{}", width, height, left, top);
    let mut app_cache_dir_path = cache_dir().expect("Get Cache Dir Failed");
    app_cache_dir_path.push(&app_handle.config().tauri.bundle.identifier);
    app_cache_dir_path.push("pot_screenshot.png");
    if !app_cache_dir_path.exists() {
        return;
    }
    let mut img = match image::open(&app_cache_dir_path) {
        Ok(v) => v,
        Err(e) => {
            error!("{:?}", e.to_string());
            return;
        }
    };
    let img2 = img.sub_image(left, top, width, height);
    app_cache_dir_path.pop();
    app_cache_dir_path.push("pot_screenshot_cut.png");
    match img2.to_image().save(&app_cache_dir_path) {
        Ok(_) => {}
        Err(e) => {
            error!("{:?}", e.to_string());
        }
    }
}

#[tauri::command]
pub fn get_base64(app_handle: tauri::AppHandle) -> String {
    use base64::{engine::general_purpose, Engine as _};
    use dirs::cache_dir;
    use std::fs::File;
    use std::io::Read;
    let mut app_cache_dir_path = cache_dir().expect("Get Cache Dir Failed");
    app_cache_dir_path.push(&app_handle.config().tauri.bundle.identifier);
    app_cache_dir_path.push("pot_screenshot_cut.png");
    if !app_cache_dir_path.exists() {
        return "".to_string();
    }
    let mut file = File::open(app_cache_dir_path).unwrap();
    let mut vec = Vec::new();
    match file.read_to_end(&mut vec) {
        Ok(_) => {}
        Err(e) => {
            error!("{:?}", e.to_string());
            return "".to_string();
        }
    }
    let base64 = general_purpose::STANDARD.encode(&vec);
    base64.replace("\r\n", "")
}

#[tauri::command]
pub fn copy_img(app_handle: tauri::AppHandle, width: usize, height: usize) -> Result<(), Error> {
    use arboard::{Clipboard, ImageData};
    use dirs::cache_dir;
    use image::ImageReader;
    use std::borrow::Cow;

    let mut app_cache_dir_path = cache_dir().expect("Get Cache Dir Failed");
    app_cache_dir_path.push(&app_handle.config().tauri.bundle.identifier);
    app_cache_dir_path.push("pot_screenshot_cut.png");
    let data = ImageReader::open(app_cache_dir_path)?.decode()?;

    let img = ImageData {
        width,
        height,
        bytes: Cow::from(data.as_bytes()),
    };
    let result = Clipboard::new()?.set_image(img)?;
    Ok(result)
}

#[tauri::command]
pub fn set_proxy() -> Result<bool, ()> {
    let host = match get("proxy_host") {
        Some(v) => v.as_str().unwrap().to_string(),
        None => return Err(()),
    };
    let port = match get("proxy_port") {
        Some(v) => v.as_i64().unwrap(),
        None => return Err(()),
    };
    let no_proxy = match get("no_proxy") {
        Some(v) => v.as_str().unwrap().to_string(),
        None => return Err(()),
    };
    let proxy = format!("http://{}:{}", host, port);

    std::env::set_var("http_proxy", &proxy);
    std::env::set_var("https_proxy", &proxy);
    std::env::set_var("all_proxy", &proxy);
    std::env::set_var("no_proxy", &no_proxy);
    Ok(true)
}

#[tauri::command]
pub fn unset_proxy() -> Result<bool, ()> {
    std::env::remove_var("http_proxy");
    std::env::remove_var("https_proxy");
    std::env::remove_var("all_proxy");
    std::env::remove_var("no_proxy");
    Ok(true)
}

#[tauri::command]
pub fn install_plugin(path_list: Vec<String>) -> Result<i32, Error> {
    let mut success_count = 0;

    for path in path_list {
        if !path.ends_with("potext") {
            continue;
        }
        let path = std::path::Path::new(&path);
        let file_name = path.file_name().unwrap().to_str().unwrap();
        let file_name = file_name.replace(".potext", "");
        if !file_name.starts_with("plugin") {
            return Err(Error::Error(
                "Invalid Plugin: file name must start with plugin".into(),
            ));
        }

        let mut zip = zip::ZipArchive::new(std::fs::File::open(path)?)?;
        #[allow(unused_mut)]
        let mut plugin_type: String;
        if let Ok(mut info) = zip.by_name("info.json") {
            let mut content = String::new();
            info.read_to_string(&mut content)?;
            let json: serde_json::Value = serde_json::from_str(&content)?;
            plugin_type = json["plugin_type"]
                .as_str()
                .ok_or(Error::Error("can't find plugin type in info.json".into()))?
                .to_string();
        } else {
            return Err(Error::Error("Invalid Plugin: miss info.json".into()));
        }
        if zip.by_name("main.js").is_err() {
            return Err(Error::Error("Invalid Plugin: miss main.js".into()));
        }
        let config_path = dirs::config_dir().unwrap();
        let config_path =
            config_path.join(APP.get().unwrap().config().tauri.bundle.identifier.clone());
        let config_path = config_path.join("plugins");
        let config_path = config_path.join(plugin_type);
        let plugin_path = config_path.join(file_name);
        std::fs::create_dir_all(&config_path)?;
        zip.extract(&plugin_path)?;

        success_count += 1;
    }
    Ok(success_count)
}

#[tauri::command]
pub fn run_binary(
    plugin_type: String,
    plugin_name: String,
    cmd_name: String,
    args: Vec<String>,
) -> Result<Value, Error> {
    #[cfg(target_os = "windows")]
    use std::os::windows::process::CommandExt;
    use std::process::Command;

    let config_path = dirs::config_dir().unwrap();
    let config_path = config_path.join(APP.get().unwrap().config().tauri.bundle.identifier.clone());
    let config_path = config_path.join("plugins");
    let config_path = config_path.join(plugin_type);
    let plugin_path = config_path.join(plugin_name);

    #[cfg(target_os = "windows")]
    let mut cmd = Command::new(&cmd_name);
    #[cfg(target_os = "windows")]
    let cmd = cmd.creation_flags(0x08000000);
    #[cfg(not(target_os = "windows"))]
    let mut cmd = Command::new(&cmd_name);

    let output = cmd.args(args).current_dir(plugin_path).output()?;
    Ok(json!({
        "stdout": String::from_utf8_lossy(&output.stdout).to_string(),
        "stderr": String::from_utf8_lossy(&output.stderr).to_string(),
        "status": output.status.code().unwrap_or(-1),
    }))
}

#[tauri::command]
pub fn font_list() -> Result<Vec<String>, Error> {
    use font_kit::source::SystemSource;
    let source = SystemSource::new();

    Ok(source.all_families()?)
}

#[tauri::command]
pub fn open_devtools(window: tauri::Window) {
    if !window.is_devtools_open() {
        window.open_devtools();
    } else {
        window.close_devtools();
    }
}

/// Apply window opacity (0.15–1.0). Persists as `window_opacity` in config.
#[tauri::command]
pub fn set_window_opacity(app_handle: tauri::AppHandle, opacity: f64) -> Result<f64, String> {
    let opacity = opacity.clamp(0.15, 1.0);
    set("window_opacity", opacity);
    apply_opacity_to_app(&app_handle, opacity)?;
    Ok(opacity)
}

/// Read current opacity preference (default 0.92).
#[tauri::command]
pub fn get_window_opacity() -> f64 {
    match get("window_opacity") {
        Some(v) => v.as_f64().unwrap_or(0.92).clamp(0.15, 1.0),
        None => 0.92,
    }
}

pub fn apply_opacity_to_app(app_handle: &tauri::AppHandle, opacity: f64) -> Result<(), String> {
    let opacity = opacity.clamp(0.15, 1.0);
    let labels = ["translate", "config", "recognize", "updater"];
    for label in labels {
        if let Some(window) = app_handle.get_window(label) {
            apply_opacity_to_window(&window, opacity)?;
        }
    }
    Ok(())
}

pub fn apply_opacity_to_window(window: &tauri::Window, opacity: f64) -> Result<(), String> {
    let opacity = opacity.clamp(0.15, 1.0);
    #[cfg(windows)]
    {
        #[link(name = "user32")]
        extern "system" {
            fn GetWindowLongW(hwnd: *mut core::ffi::c_void, index: i32) -> i32;
            fn SetWindowLongW(hwnd: *mut core::ffi::c_void, index: i32, new_long: i32) -> i32;
            fn SetLayeredWindowAttributes(
                hwnd: *mut core::ffi::c_void,
                key: u32,
                alpha: u8,
                flags: u32,
            ) -> i32;
        }
        const GWL_EXSTYLE: i32 = -20;
        const WS_EX_LAYERED: i32 = 0x0008_0000;
        const LWA_ALPHA: u32 = 0x2;

        // tauri 1.8 returns windows::Win32::Foundation::HWND
        let hwnd_raw = window.hwnd().map_err(|e| e.to_string())?;
        let hwnd = hwnd_raw.0 as *mut core::ffi::c_void;
        unsafe {
            let ex = GetWindowLongW(hwnd, GWL_EXSTYLE);
            if ex & WS_EX_LAYERED == 0 {
                SetWindowLongW(hwnd, GWL_EXSTYLE, ex | WS_EX_LAYERED);
            }
            let alpha = (opacity * 255.0).round() as u8;
            let ok = SetLayeredWindowAttributes(hwnd, 0, alpha, LWA_ALPHA);
            if ok == 0 {
                return Err("SetLayeredWindowAttributes failed".into());
            }
        }
        return Ok(());
    }
    #[cfg(not(windows))]
    {
        // Best-effort: emit to frontend so CSS can dim content.
        let _ = window.emit("window_opacity", opacity);
        Ok(())
    }
}

fn find_edge_tts_exe() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("EDGE_TTS_PATH") {
        let pb = PathBuf::from(p);
        if pb.exists() {
            return Some(pb);
        }
    }
    let local = std::env::var("LOCALAPPDATA").ok().map(PathBuf::from);
    if let Some(base) = local {
        let candidates = [
            base.join("hermes\\hermes-agent\\venv\\Scripts\\edge-tts.exe"),
            base.join("Programs\\Python\\Python312\\Scripts\\edge-tts.exe"),
            base.join("Programs\\Python\\Python311\\Scripts\\edge-tts.exe"),
            base.join("Programs\\Python\\Python310\\Scripts\\edge-tts.exe"),
        ];
        for c in candidates {
            if c.exists() {
                return Some(c);
            }
        }
    }
    // PATH lookup
    #[cfg(windows)]
    {
        let output = Command::new("where.exe").arg("edge-tts").output().ok()?;
        if output.status.success() {
            let text = String::from_utf8_lossy(&output.stdout);
            if let Some(line) = text.lines().next() {
                let p = PathBuf::from(line.trim());
                if p.exists() {
                    return Some(p);
                }
            }
        }
    }
    #[cfg(not(windows))]
    {
        let output = Command::new("which").arg("edge-tts").output().ok()?;
        if output.status.success() {
            let text = String::from_utf8_lossy(&output.stdout);
            if let Some(line) = text.lines().next() {
                let p = PathBuf::from(line.trim());
                if p.exists() {
                    return Some(p);
                }
            }
        }
    }
    None
}

/// Synthesize speech with Microsoft Edge neural voices via local `edge-tts` CLI.
/// Returns raw MP3 bytes as a JSON array of numbers (Lingva-compatible).
#[tauri::command(async)]
pub fn edge_tts_synthesize(
    text: String,
    lang: String,
    voice_zh: Option<String>,
    voice_en: Option<String>,
    rate: Option<String>,
    pitch: Option<String>,
) -> Result<Vec<u8>, String> {
    if text.trim().is_empty() {
        return Err("text is empty".into());
    }
    if text.chars().count() > 2000 {
        return Err("text must be at most 2000 characters".into());
    }

    let edge = find_edge_tts_exe().ok_or_else(|| {
        "edge-tts not found. Install with: pip install edge-tts  (or set EDGE_TTS_PATH)".to_string()
    })?;

    let lang_l = lang.to_lowercase();
    let voice = if lang_l.starts_with("zh") || lang_l.starts_with("cmn") {
        voice_zh.unwrap_or_else(|| "zh-CN-XiaoxiaoNeural".into())
    } else {
        voice_en.unwrap_or_else(|| "en-US-AvaNeural".into())
    };
    let rate = rate.unwrap_or_else(|| "+0%".into());
    let pitch = pitch.unwrap_or_else(|| "+8Hz".into());

    let tmp = std::env::temp_dir().join(format!(
        "pot-forge-tts-{}.mp3",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0)
    ));

    #[cfg(windows)]
    use std::os::windows::process::CommandExt;

    let mut cmd = Command::new(&edge);
    #[cfg(windows)]
    cmd.creation_flags(0x08000000); // CREATE_NO_WINDOW
    let output = cmd
        .args([
            "--voice",
            &voice,
            "--rate",
            &rate,
            "--pitch",
            &pitch,
            "--text",
            &text,
            "--write-media",
            tmp.to_str().ok_or("temp path invalid")?,
        ])
        .output()
        .map_err(|e| format!("failed to run edge-tts: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let _ = std::fs::remove_file(&tmp);
        return Err(format!(
            "edge-tts exit {:?}: {}",
            output.status.code(),
            stderr
        ));
    }

    let bytes = std::fs::read(&tmp).map_err(|e| format!("read mp3 failed: {e}"))?;
    let _ = std::fs::remove_file(&tmp);
    if bytes.len() < 32 {
        return Err("edge-tts produced empty audio".into());
    }
    info!(
        "edge_tts voice={} lang={} chars={} bytes={}",
        voice,
        lang,
        text.chars().count(),
        bytes.len()
    );
    Ok(bytes)
}
