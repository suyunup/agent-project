#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod session;
use serde::{Deserialize, Serialize};
use session::{Phase, Sessions};
use std::{
    ffi::{c_char, c_void, CStr, CString},
    sync::Mutex,
    time::Duration,
};
use tauri::{Emitter, Manager};

// Native entrypoints must only be invoked inside on_main or setup/tick callbacks.
extern "C" {
    fn cw_permission() -> i32;
    fn cw_request_permission();
    fn cw_enabled() -> i32;
    fn cw_available() -> i32;
    fn cw_enable(value: i32) -> i32;
    fn cw_poll() -> *mut c_char;
    fn cw_free(value: *mut c_char);
    fn cw_cancel();
    fn cw_show(window: *mut c_void);
    fn cw_hide();
    fn cw_key() -> i32;
    fn cw_copy(text: *const c_char) -> i32;
    fn cw_paste(text: *const c_char) -> i32;
    fn cw_outcome() -> i32;
    fn cw_error() -> *const c_char;
}
#[derive(Default)]
struct AppState {
    sessions: Mutex<Sessions>,
}
#[derive(Serialize)]
struct Status {
    permission: bool,
    enabled: bool,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
enum Action {
    Transform,
    PasteOriginal,
    PasteResult,
    Copy,
    Cancel,
}

async fn on_main<T: Send + 'static>(
    app: tauri::AppHandle,
    task: impl FnOnce(tauri::AppHandle) -> Result<T, String> + Send + 'static,
) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let (send, receive) = std::sync::mpsc::sync_channel(1);
        let handle = app.clone();
        app.run_on_main_thread(move || {
            let _ = send.send(task(handle));
        })
        .map_err(|_| "메인 스레드 작업을 시작하지 못했습니다.".to_string())?;
        receive
            .recv()
            .map_err(|_| "앱이 종료되었습니다.".to_string())?
    })
    .await
    .map_err(|_| "앱 작업이 중단되었습니다.".to_string())?
}
fn paste_error() -> String {
    let message = unsafe { CStr::from_ptr(cw_error()) }
        .to_string_lossy()
        .into_owned();
    format!("{message} 결과를 복사해 직접 붙여넣을 수 있습니다.")
}
fn emit_session(app: &tauri::AppHandle, sessions: &Sessions) {
    let _ = app.emit_to("overlay", "session", &sessions.current);
}
fn hide(app: &tauri::AppHandle) {
    unsafe {
        cw_hide();
    }
    if let Some(window) = app.get_webview_window("overlay") {
        let _ = window.hide();
    }
}
fn show(app: &tauri::AppHandle) -> Result<(), String> {
    let window = app
        .get_webview_window("overlay")
        .ok_or("가공 메뉴 창을 찾을 수 없습니다.")?;
    let pointer = window
        .ns_window()
        .map_err(|_| "가공 메뉴 창을 열 수 없습니다.")?;
    unsafe {
        cw_show(pointer);
    }
    Ok(())
}
#[tauri::command]
async fn status(app: tauri::AppHandle) -> Result<Status, String> {
    on_main(app, |_| {
        Ok(unsafe {
            Status {
                permission: cw_permission() != 0,
                enabled: cw_enabled() != 0,
            }
        })
    })
    .await
}
#[tauri::command]
async fn request_permission(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
) -> Result<(), String> {
    if window.label() != "main" {
        return Err("메인 창에서 권한을 요청하세요.".into());
    }
    on_main(app, |_| {
        unsafe {
            cw_request_permission();
        }
        Ok(())
    })
    .await
}
#[tauri::command]
async fn set_enabled(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    enabled: bool,
) -> Result<(), String> {
    if window.label() != "main" {
        return Err("메인 창에서 호출 설정을 변경하세요.".into());
    }
    on_main(app, move |app| {
        if unsafe { cw_enable(i32::from(enabled)) } == 0 { return Err("접근성 권한 또는 이벤트 탭을 사용할 수 없습니다. 시스템 설정에서 권한을 확인한 뒤 다시 켜세요.".into()); }
        {
            let state = app.state::<AppState>();
            let mut sessions = state.sessions.lock().unwrap();
            sessions.current = None; emit_session(&app, &sessions); hide(&app);
        }
        Ok(())
    }).await
}
#[tauri::command]
async fn current_session(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
) -> Result<Option<session::Session>, String> {
    if window.label() != "overlay" {
        return Err("가공 메뉴에서만 조회할 수 있습니다.".into());
    }
    Ok(app
        .state::<AppState>()
        .sessions
        .lock()
        .unwrap()
        .current
        .clone())
}
#[tauri::command]
async fn session_action(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    id: u64,
    action: Action,
) -> Result<(), String> {
    if window.label() != "overlay" {
        return Err("가공 메뉴에서만 실행할 수 있습니다.".into());
    }
    on_main(app, move |app| {
        let state = app.state::<AppState>();
        let mut sessions = state.sessions.lock().unwrap();
        sessions.get(id)?;
        match action {
            Action::Transform => sessions.transform(id)?,
            Action::Cancel => {
                sessions.cancel(id)?;
                unsafe {
                    cw_cancel();
                }
                hide(&app);
            }
            Action::Copy => {
                let s = sessions.get(id)?;
                if s.phase == Phase::Sending {
                    return Err("붙여넣기가 진행 중입니다.".into());
                }
                let text = CString::new(s.output.as_deref().ok_or("먼저 변환을 실행하세요.")?)
                    .map_err(|_| "NUL 문자가 포함된 텍스트는 지원하지 않습니다.")?;
                if unsafe { cw_copy(text.as_ptr()) } == 0 {
                    return Err("클립보드에 복사하지 못했습니다.".into());
                }
                s.message = Some("결과를 복사했습니다.".into());
            }
            Action::PasteOriginal | Action::PasteResult => {
                let original = matches!(action, Action::PasteOriginal);
                let text = sessions.begin_send(id, original)?;
                let text = match CString::new(text) {
                    Ok(text) => text,
                    Err(_) => {
                        let s = sessions.get(id)?;
                        s.phase = if s.output.is_some() {
                            Phase::Result
                        } else {
                            Phase::Menu
                        };
                        return Err("NUL 문자가 포함된 텍스트는 지원하지 않습니다.".into());
                    }
                };
                hide(&app);
                if unsafe { cw_paste(text.as_ptr()) } == 0 {
                    let s = sessions.get(id)?;
                    s.phase = if s.output.is_some() {
                        Phase::Result
                    } else {
                        Phase::Menu
                    };
                    s.message = Some(paste_error());
                    show(&app)?;
                }
            }
        }
        emit_session(&app, &sessions);
        Ok(())
    })
    .await
}
fn tick(app: &tauri::AppHandle) {
    let state = app.state::<AppState>();
    let mut sessions = state.sessions.lock().unwrap();
    unsafe {
        if cw_available() == 0 && sessions.current.is_some() {
            cw_cancel();
            sessions.current = None;
            emit_session(app, &sessions);
            hide(app);
        }
        let pointer = cw_poll();
        if !pointer.is_null() {
            let text = CStr::from_ptr(pointer).to_string_lossy().into_owned();
            cw_free(pointer);
            if sessions.start(text) {
                emit_session(app, &sessions);
                if show(app).is_err() {
                    cw_cancel();
                    sessions.current = None;
                    emit_session(app, &sessions);
                }
            }
        }
        let key = cw_key();
        if key != 0 {
            let _ = app.emit_to("overlay", "overlay-key", key);
        }
        let outcome = cw_outcome();
        if outcome == 1 {
            cw_cancel();
            sessions.current = None;
            emit_session(app, &sessions);
            hide(app);
        } else if outcome < 0 {
            if let Some(s) = sessions.current.as_mut() {
                s.phase = if s.output.is_some() {
                    Phase::Result
                } else {
                    Phase::Menu
                };
                s.message = Some(paste_error());
            }
            emit_session(app, &sessions);
            let _ = show(app);
        }
    }
}
fn main() {
    tauri::Builder::default()
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            status,
            request_permission,
            set_enabled,
            current_session,
            session_action
        ])
        .setup(|app| {
            let handle = app.handle().clone();
            std::thread::spawn(move || loop {
                std::thread::sleep(Duration::from_millis(40));
                let (send, receive) = std::sync::mpsc::sync_channel(1);
                let tick_handle = handle.clone();
                if handle
                    .run_on_main_thread(move || {
                        tick(&tick_handle);
                        let _ = send.send(());
                    })
                    .is_err()
                {
                    break;
                }
                if receive.recv().is_err() {
                    break;
                }
            });
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                if window.label() == "main" {
                    unsafe {
                        cw_enable(0);
                    }
                    window.app_handle().exit(0);
                } else {
                    api.prevent_close();
                    unsafe {
                        cw_cancel();
                    }
                    let state = window.state::<AppState>();
                    let mut sessions = state.sessions.lock().unwrap();
                    sessions.current = None;
                    emit_session(window.app_handle(), &sessions);
                    let _ = window.hide();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("ClipWeave could not start");
}
