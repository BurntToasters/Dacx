#ifndef RUNNER_WINDOW_BRIDGE_H_
#define RUNNER_WINDOW_BRIDGE_H_

class FlutterWindow;

namespace dacx {

void RegisterPrimaryWindow(::FlutterWindow* window);

void NotifyWindowDestroyed(::FlutterWindow* window);

}  // namespace dacx

#endif  // RUNNER_WINDOW_BRIDGE_H_
