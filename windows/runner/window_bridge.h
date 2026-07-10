#ifndef RUNNER_WINDOW_BRIDGE_H_
#define RUNNER_WINDOW_BRIDGE_H_

#include <flutter/binary_messenger.h>

class FlutterWindow;

namespace dacx {

void RegisterPrimaryWindow(::FlutterWindow* window);

void NotifyWindowDestroyed(::FlutterWindow* window);

/// Registers run.rosie.dacx/window/methods for native window helpers
/// (e.g. clearing WS_EX_LAYERED so acrylic/mica blur can work).
void RegisterWindowMethodsChannel(flutter::BinaryMessenger* messenger,
                                  ::FlutterWindow* window);

}  // namespace dacx

#endif  // RUNNER_WINDOW_BRIDGE_H_
