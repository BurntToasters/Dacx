#include "window_bridge.h"

#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

#include "flutter_window.h"

namespace dacx {

using ::FlutterWindow;
using MethodChannel = flutter::MethodChannel<flutter::EncodableValue>;
using MethodCall = flutter::MethodCall<flutter::EncodableValue>;
using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

namespace {

constexpr const char kWindowMethodChannel[] = "run.rosie.dacx/window/methods";

std::mutex g_mutex;
FlutterWindow* g_primary_window = nullptr;
bool g_primary_alive = false;

std::mutex g_channel_mutex;
std::unordered_map<flutter::BinaryMessenger*, std::unique_ptr<MethodChannel>>
    g_channels;

/// window_manager.setOpacity always ORs WS_EX_LAYERED. That style flattens
/// DWM acrylic/mica into a plain translucent pane (no desktop blur). Clear it
/// before applying flutter_acrylic effects.
void ClearLayeredWindowStyle(HWND hwnd) {
  if (hwnd == nullptr) return;
  LONG ex_style = ::GetWindowLong(hwnd, GWL_EXSTYLE);
  if ((ex_style & WS_EX_LAYERED) == 0) return;
  ex_style &= ~(WS_EX_LAYERED | WS_EX_TRANSPARENT);
  ::SetWindowLong(hwnd, GWL_EXSTYLE, ex_style);
  // Force a non-client / frame refresh so DWM picks up the style change.
  ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
}

}  // namespace

void RegisterPrimaryWindow(FlutterWindow* window) {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_primary_window = window;
  g_primary_alive = (window != nullptr);
}

void NotifyWindowDestroyed(FlutterWindow* window) {
  bool should_quit = false;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (window == g_primary_window) {
      g_primary_alive = false;
      should_quit = true;
    }
  }
  if (should_quit) {
    PostQuitMessage(0);
  }
}

void RegisterWindowMethodsChannel(flutter::BinaryMessenger* messenger,
                                  FlutterWindow* window) {
  if (messenger == nullptr || window == nullptr) return;

  auto channel = std::make_unique<MethodChannel>(
      messenger, kWindowMethodChannel,
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [window](const MethodCall& call,
               std::unique_ptr<MethodResult> result) {
        const std::string& method = call.method_name();
        if (method == "clearLayeredStyle") {
          ClearLayeredWindowStyle(window->GetHandle());
          result->Success(flutter::EncodableValue(true));
          return;
        }
        result->NotImplemented();
      });

  std::lock_guard<std::mutex> lock(g_channel_mutex);
  g_channels[messenger] = std::move(channel);
}

}  // namespace dacx
