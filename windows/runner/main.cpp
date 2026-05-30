#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shobjidl.h>
#include <windows.h>

#include "flutter_window.h"
#include "instance_bridge.h"
#include "utils.h"
#include "window_bridge.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  HRESULT com_init = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(com_init)) {
    ::OutputDebugStringW(L"[Dacx] CoInitializeEx failed; aborting startup.\n");
    return EXIT_FAILURE;
  }

  // Match WiX Start Menu shortcut System.AppUserModel.ID for shell search/taskbar.
  ::SetCurrentProcessExplicitAppUserModelID(L"run.rosie.dacx");

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  bool force_new_instance =
      dacx::ConsumeNewInstanceFlag(command_line_arguments);
  bool allow_multi = dacx::AllowMultipleInstancesEnabled();

  if (!force_new_instance && !allow_multi) {
    if (!dacx::AcquireSingletonMutex()) {
      // Another Dacx is already running: forward any file paths and exit.
      std::vector<std::string> file_paths;
      for (const auto& arg : command_line_arguments) {
        if (!arg.empty() && arg[0] != '-') {
          file_paths.push_back(arg);
        }
      }
      if (!file_paths.empty()) {
        dacx::ForwardToRunningInstance(file_paths);
      }
      ::CoUninitialize();
      return EXIT_SUCCESS;
    }
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Dacx", origin, size)) {
    return EXIT_FAILURE;
  }
  // Quit-on-last-window-close handled by the registry instead of
  // SetQuitOnClose so closing the primary while aux windows live keeps
  // the app alive.
  dacx::RegisterPrimaryWindow(&window);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
