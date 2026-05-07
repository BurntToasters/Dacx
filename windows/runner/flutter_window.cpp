#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "instance_bridge.h"
#include "media_session.h"
#include "window_bridge.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  flutter_controller_ready_ = false;
  flutter_controller_tearing_down_ = false;

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
  dacx::RegisterMediaSession(
      flutter_controller_->engine()->messenger());
  dacx::StartOpenFileServer(flutter_controller_->engine()->messenger());
  dacx::RegisterWindowBridge(flutter_controller_->engine()->messenger(),
                             project_);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {});

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();
  flutter_controller_ready_ = true;

  return true;
}

void FlutterWindow::OnDestroy() {
  flutter_controller_ready_ = false;
  flutter_controller_tearing_down_ = true;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  // Aux windows: ask the registry to drop us. No-op for primary.
  dacx::NotifyWindowDestroyed(this);

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // During creation/teardown, skip forwarding messages to the Flutter view.
  // This avoids dereferencing stale/null controller internals in the engine.
  if (flutter_controller_tearing_down_ || !flutter_controller_ready_) {
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }

  // On some Windows-on-ARM systems the engine can crash handling
  // WM_PARENTNOTIFY/WM_DESTROY while processing child-window teardown.
  // Let the default Win32 path handle this notification instead.
  if (message == WM_PARENTNOTIFY && LOWORD(wparam) == WM_DESTROY) {
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
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
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
