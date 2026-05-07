#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "instance_bridge.h"
#include "media_session.h"
#include "window_bridge.h"

namespace {

#ifndef IMAGE_FILE_MACHINE_ARM64
#define IMAGE_FILE_MACHINE_ARM64 0xAA64
#endif

using IsWow64Process2Fn = BOOL(WINAPI*)(HANDLE, USHORT*, USHORT*);

bool IsRunningUnderArm64Emulation() {
  HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
  if (kernel32 == nullptr) {
    return false;
  }
  auto is_wow64_process2 = reinterpret_cast<IsWow64Process2Fn>(
      GetProcAddress(kernel32, "IsWow64Process2"));
  if (is_wow64_process2 == nullptr) {
    return false;
  }

  USHORT process_machine = IMAGE_FILE_MACHINE_UNKNOWN;
  USHORT native_machine = IMAGE_FILE_MACHINE_UNKNOWN;
  if (!is_wow64_process2(GetCurrentProcess(), &process_machine,
                         &native_machine)) {
    return false;
  }

  return native_machine == IMAGE_FILE_MACHINE_ARM64 &&
         process_machine != IMAGE_FILE_MACHINE_UNKNOWN;
}

bool IsImeMessage(UINT message) {
  switch (message) {
    case WM_IME_SETCONTEXT:
    case WM_IME_NOTIFY:
    case WM_IME_STARTCOMPOSITION:
    case WM_IME_COMPOSITION:
    case WM_IME_ENDCOMPOSITION:
    case WM_IME_REQUEST:
    case WM_IME_CHAR:
    case WM_IME_KEYDOWN:
    case WM_IME_KEYUP:
      return true;
    default:
      return false;
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  running_under_arm64_emulation_ = IsRunningUnderArm64Emulation();
  flutter_controller_ready_ = !running_under_arm64_emulation_;
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

  // On some WoA systems, forwarding early startup messages into Flutter can
  // hit a null dereference before embedder internals are fully initialized.
  // Delay forwarding until the first rendered frame in that environment.
  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    flutter_controller_ready_ = true;
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

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

  if (running_under_arm64_emulation_) {
    // On some Windows-on-ARM systems the engine can crash handling
    // WM_PARENTNOTIFY/WM_DESTROY while processing child-window teardown.
    // Let the default Win32 path handle this notification instead.
    if (message == WM_PARENTNOTIFY && LOWORD(wparam) == WM_DESTROY) {
      return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
    }

    // IME messages can also trigger the same null-deref during startup on
    // WoA x64 emulation. Use the OS default IME handling path there.
    if (IsImeMessage(message)) {
      return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
    }
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
