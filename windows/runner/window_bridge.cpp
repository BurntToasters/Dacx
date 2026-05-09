#include "window_bridge.h"

#include <windows.h>

#include <mutex>

#include "flutter_window.h"

namespace dacx {

using ::FlutterWindow;

namespace {

std::mutex g_mutex;
FlutterWindow* g_primary_window = nullptr;
bool g_primary_alive = false;

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

}  // namespace dacx
