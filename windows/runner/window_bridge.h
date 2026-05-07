#ifndef RUNNER_WINDOW_BRIDGE_H_
#define RUNNER_WINDOW_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/dart_project.h>

class FlutterWindow;

namespace dacx {

// Per-engine `run.rosie.dacx/window/methods` channel. Must be called for
// every Flutter engine so Cmd/Ctrl+N works in any window.
void RegisterWindowBridge(flutter::BinaryMessenger* messenger,
                          const flutter::DartProject& project);

// Track the primary FlutterWindow so the registry can post WM_QUIT once it
// and all aux windows are gone.
void RegisterPrimaryWindow(::FlutterWindow* window);

// Called from FlutterWindow::OnDestroy to schedule registry cleanup.
void NotifyWindowDestroyed(::FlutterWindow* window);

}  // namespace dacx

#endif  // RUNNER_WINDOW_BRIDGE_H_
