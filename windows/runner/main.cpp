#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shobjidl.h>
#include <windows.h>

#include "flutter_window.h"
#include "instance_bridge.h"
#include "utils.h"
#include "window_bridge.h"

namespace {

constexpr char kActivateSentinel[] = "__DACX_ACTIVATE__";

bool IsAsciiLetter(char ch) {
  return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
}

// True for "scheme://..." or a 2+ letter scheme such as "file:". A single
// drive letter ("C:") is a path, not a scheme.
bool LooksLikeUri(const std::string& arg) {
  if (arg.find("://") != std::string::npos) {
    return true;
  }
  size_t letters = 0;
  while (letters < arg.size() && IsAsciiLetter(arg[letters])) {
    ++letters;
  }
  return letters >= 2 && letters < arg.size() && arg[letters] == ':';
}

// True for UNC/extended paths ("\\server\share", "\\?\..."), rooted paths,
// and drive-absolute paths ("C:\..." or "C:/..."). These are left untouched.
bool IsAbsoluteOrRooted(const std::string& arg) {
  if (!arg.empty() && (arg[0] == '\\' || arg[0] == '/')) {
    return true;
  }
  return arg.size() >= 3 && IsAsciiLetter(arg[0]) && arg[1] == ':' &&
         (arg[2] == '\\' || arg[2] == '/');
}

// Resolves a local relative path against this process's working directory.
// Returns the input unchanged when it is not a relative path or on failure.
std::string ResolveRelativePath(const std::string& arg) {
  // Caps the size so the int conversion for MultiByteToWideChar is safe.
  constexpr size_t kMaxArgBytes = 32767;
  if (arg.empty() || arg[0] == '-' || arg == kActivateSentinel ||
      arg.size() > kMaxArgBytes || LooksLikeUri(arg) ||
      IsAbsoluteOrRooted(arg)) {
    return arg;
  }
  const int arg_bytes = static_cast<int>(arg.size());
  const int wide_len = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                             arg.data(), arg_bytes, nullptr, 0);
  if (wide_len <= 0) {
    return arg;
  }
  std::wstring wide(static_cast<size_t>(wide_len), L'\0');
  if (::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, arg.data(),
                            arg_bytes, wide.data(), wide_len) != wide_len) {
    return arg;
  }
  // Resolve now: the receiving instance would otherwise use its own cwd.
  const DWORD needed = ::GetFullPathNameW(wide.c_str(), 0, nullptr, nullptr);
  if (needed == 0) {
    return arg;
  }
  std::wstring full(static_cast<size_t>(needed), L'\0');
  const DWORD written =
      ::GetFullPathNameW(wide.c_str(), needed, full.data(), nullptr);
  if (written == 0 || written >= needed) {
    return arg;
  }
  full.resize(static_cast<size_t>(written));
  std::string utf8 = Utf8FromUtf16(full.c_str());
  return utf8.empty() ? arg : utf8;
}

}  // namespace

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
  for (std::string& arg : command_line_arguments) {
    arg = ResolveRelativePath(arg);
  }
  bool allow_multi = dacx::AllowMultipleInstancesEnabled();

  if (!force_new_instance && !allow_multi) {
    if (!dacx::AcquireSingletonMutex()) {
      // Another Dacx is already running: forward paths (or an activate
      // sentinel) and exit. Never create a second window.
      std::vector<std::string> file_paths;
      for (const auto& arg : command_line_arguments) {
        if (!arg.empty() && arg[0] != '-') {
          file_paths.push_back(arg);
        }
      }
      if (file_paths.empty()) {
        file_paths.emplace_back("__DACX_ACTIVATE__");
      }
      bool forwarded = false;
      for (int attempt = 0; attempt < 30 && !forwarded; ++attempt) {
        forwarded = dacx::ForwardToRunningInstance(file_paths);
        if (!forwarded) {
          ::Sleep(150);
        }
      }
      ::CoUninitialize();
      return forwarded ? EXIT_SUCCESS : EXIT_FAILURE;
    }
    dacx::StartOpenFilePipe();
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
