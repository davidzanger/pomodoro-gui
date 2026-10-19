#include "flutter_window.h"

#include <optional>
#include <wtsapi32.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT_PTR kUnlockRetryTimer = 1;
constexpr int kMaxUnlockRetries = 12;
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  attention_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "pomodoro_gui/window_attention", &flutter::StandardMethodCodec::GetInstance());
  attention_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setBreakDecisionVisible") {
          result->NotImplemented();
          return;
        }
        const auto* argument = call.arguments();
        if (!argument || !std::holds_alternative<bool>(*argument)) {
          result->Error("invalid_argument", "Expected a boolean visibility value.");
          return;
        }
        SetBreakAttention(std::get<bool>(*argument));
        result->Success();
      });
  session_notifications_registered_ =
      WTSRegisterSessionNotification(GetHandle(), NOTIFY_FOR_THIS_SESSION) != 0;

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  KillTimer(GetHandle(), kUnlockRetryTimer);
  if (session_notifications_registered_) {
    WTSUnRegisterSessionNotification(GetHandle());
    session_notifications_registered_ = false;
  }
  attention_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetBreakAttention(bool visible) {
  break_attention_active_ = visible;
  HWND hwnd = GetHandle();
  if (!visible) {
    KillTimer(hwnd, kUnlockRetryTimer);
    unlock_retry_count_ = 0;
    SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    FLASHWINFO flash = {sizeof(FLASHWINFO), hwnd, FLASHW_STOP, 0, 0};
    FlashWindowEx(&flash);
    return;
  }
  RaiseBreakDecision();
}

void FlutterWindow::RaiseBreakDecision() {
  if (!break_attention_active_) return;
  HWND hwnd = GetHandle();
  if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
  SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  BringWindowToTop(hwnd);
  SetForegroundWindow(hwnd);
  if (GetForegroundWindow() != hwnd) {
    FLASHWINFO flash = {sizeof(FLASHWINFO), hwnd,
                        FLASHW_TRAY | FLASHW_TIMERNOFG, 0, 0};
    FlashWindowEx(&flash);
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_WTSSESSION_CHANGE && wparam == WTS_SESSION_UNLOCK &&
      break_attention_active_) {
    RaiseBreakDecision();
    unlock_retry_count_ = 0;
    SetTimer(hwnd, kUnlockRetryTimer, 250, nullptr);
  } else if (message == WM_TIMER && wparam == kUnlockRetryTimer) {
    if (!break_attention_active_ || ++unlock_retry_count_ >= kMaxUnlockRetries ||
        GetForegroundWindow() == hwnd) {
      KillTimer(hwnd, kUnlockRetryTimer);
    } else {
      RaiseBreakDecision();
    }
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
