#include "window_bridge.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <mutex>
#include <vector>

#include "flutter_window.h"

namespace dacx {

namespace {

constexpr const char kWindowMethodChannel[] = "run.rosie.dacx/window/methods";

constexpr UINT WM_DACX_PRUNE_WINDOWS = WM_USER + 0x43;

std::mutex g_mutex;
std::vector<std::unique_ptr<FlutterWindow>> g_windows;
// Per-engine method channels held here to avoid a shared_ptr cycle inside
// the channel's own handler.
std::vector<std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>>
    g_channels;
// Pointers whose OnDestroy fired; pruned from g_windows on the next
// WM_DACX_PRUNE_WINDOWS pump.
std::vector<FlutterWindow*> g_pending_prune;
// Primary window (lives on the stack in wWinMain). Tracked so we can post
// WM_QUIT once both primary and aux windows are gone.
FlutterWindow* g_primary_window = nullptr;
bool g_primary_alive = false;
HWND g_prune_window = nullptr;
// Cached DartProject so subsequent spawns get the same configuration as the
// primary, independent of any single FlutterWindow's lifetime.
std::unique_ptr<flutter::DartProject> g_template_project;
int g_cascade_offset = 0;

LRESULT CALLBACK PruneWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  if (msg == WM_DACX_PRUNE_WINDOWS) {
    std::vector<std::unique_ptr<FlutterWindow>> drop;
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      for (auto* dead : g_pending_prune) {
        for (auto it = g_windows.begin(); it != g_windows.end(); ++it) {
          if (it->get() == dead) {
            // Move out under the lock; destroy after release to avoid
            // re-entering the mutex from ~FlutterWindow.
            drop.push_back(std::move(*it));
            g_windows.erase(it);
            break;
          }
        }
      }
      g_pending_prune.clear();
    }
    drop.clear();
    return 0;
  }
  return DefWindowProcW(hwnd, msg, wp, lp);
}

void EnsurePruneWindow() {
  if (g_prune_window != nullptr) return;
  static const wchar_t* kClassName = L"DacxWindowBridgePrune";
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = PruneWndProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = kClassName;
  RegisterClassExW(&wc);
  g_prune_window =
      CreateWindowExW(0, kClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
                      wc.hInstance, nullptr);
}

bool SpawnWindow() {
  std::unique_ptr<flutter::DartProject> spawn_project;
  Win32Window::Point origin(40, 40);
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_template_project) return false;
    // Aux windows must NOT inherit dart_entrypoint_arguments (CLI args
    // meaningful only to the primary engine).
    spawn_project = std::make_unique<flutter::DartProject>(*g_template_project);
    spawn_project->set_dart_entrypoint_arguments({});
    g_cascade_offset = (g_cascade_offset + 28) % 280;
    origin = Win32Window::Point(40 + g_cascade_offset, 40 + g_cascade_offset);
  }

  auto window = std::make_unique<FlutterWindow>(*spawn_project);
  Win32Window::Size size(1280, 720);
  if (!window->Create(L"Dacx", origin, size)) {
    return false;
  }
  // Do NOT SetQuitOnClose(true) on aux windows: closing one must not kill
  // the message loop.
  window->Show();
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_windows.push_back(std::move(window));
  }
  return true;
}

}  // namespace

void RegisterWindowBridge(flutter::BinaryMessenger* messenger,
                          const flutter::DartProject& project) {
  EnsurePruneWindow();
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    // First registration caches the template; later registrations reuse it.
    if (!g_template_project) {
      g_template_project = std::make_unique<flutter::DartProject>(project);
    }
  }

  auto channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kWindowMethodChannel,
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "openNewWindow") {
          bool ok = SpawnWindow();
          result->Success(flutter::EncodableValue(ok));
          return;
        }
        result->NotImplemented();
      });
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_channels.push_back(std::move(channel));
  }
}

void RegisterPrimaryWindow(FlutterWindow* window) {
  EnsurePruneWindow();
  std::lock_guard<std::mutex> lock(g_mutex);
  g_primary_window = window;
  g_primary_alive = (window != nullptr);
}

void NotifyWindowDestroyed(FlutterWindow* window) {
  bool need_post = false;
  bool should_quit = false;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (window == g_primary_window) {
      g_primary_alive = false;
    } else {
      bool tracked = false;
      for (const auto& up : g_windows) {
        if (up.get() == window) { tracked = true; break; }
      }
      if (tracked) {
        g_pending_prune.push_back(window);
        need_post = (g_prune_window != nullptr);
      }
    }
    // Schedule WM_QUIT once nothing is alive.
    bool any_aux = false;
    for (const auto& up : g_windows) {
      bool pending = false;
      for (auto* p : g_pending_prune) {
        if (p == up.get()) { pending = true; break; }
      }
      if (!pending) { any_aux = true; break; }
    }
    if (!g_primary_alive && !any_aux) {
      should_quit = true;
    }
  }
  if (need_post) {
    PostMessageW(g_prune_window, WM_DACX_PRUNE_WINDOWS, 0, 0);
  }
  if (should_quit) {
    PostQuitMessage(0);
  }
}

}  // namespace dacx
