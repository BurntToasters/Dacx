#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "instance_bridge.h"
#include "utils.h"
#include "window_bridge.h"

namespace {

constexpr const char kSafeStartupArg[] = "--safe-startup";
constexpr const wchar_t kSafeStartupEnv[] = L"DACX_SAFE_STARTUP";

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                 static_cast<int>(wide.size()), nullptr, 0,
                                 nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string out(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()),
                      &out[0], size, nullptr, nullptr);
  return out;
}

std::wstring ReadEnv(const wchar_t* name) {
  std::wstring buffer(128, L'\0');
  DWORD len = GetEnvironmentVariableW(name, &buffer[0],
                                      static_cast<DWORD>(buffer.size()));
  if (len == 0) return std::wstring();
  if (len >= buffer.size()) {
    buffer.resize(len + 1);
    len = GetEnvironmentVariableW(name, &buffer[0],
                                  static_cast<DWORD>(buffer.size()));
    if (len == 0 || len >= buffer.size()) return std::wstring();
  }
  buffer.resize(len);
  return buffer;
}

bool IsTruthy(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
  return value == L"1" || value == L"true" || value == L"yes" ||
         value == L"on";
}

std::wstring ResolveDacxDataDir() {
  std::wstring local_app_data = ReadEnv(L"LOCALAPPDATA");
  if (local_app_data.empty()) return std::wstring();
  return local_app_data + L"\\Dacx";
}

void EnsureDirExists(const std::wstring& path) {
  if (path.empty()) return;
  CreateDirectoryW(path.c_str(), nullptr);
}

bool FileExists(const std::wstring& path) {
  if (path.empty()) return false;
  DWORD attrs = GetFileAttributesW(path.c_str());
  if (attrs == INVALID_FILE_ATTRIBUTES) return false;
  return (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

void TouchFile(const std::wstring& path) {
  if (path.empty()) return;
  HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA,
                            FILE_SHARE_READ | FILE_SHARE_WRITE |
                                FILE_SHARE_DELETE,
                            nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                            nullptr);
  if (file != INVALID_HANDLE_VALUE) {
    CloseHandle(file);
  }
}

void DeleteFileQuietly(const std::wstring& path) {
  if (path.empty()) return;
  if (DeleteFileW(path.c_str())) return;
  DWORD err = GetLastError();
  if (err == ERROR_FILE_NOT_FOUND || err == ERROR_PATH_NOT_FOUND) return;
}

void LogStartup(const std::wstring& message) {
  std::wstring tagged = L"[Dacx] " + message + L"\n";
  OutputDebugStringW(tagged.c_str());

  const std::wstring dir = ResolveDacxDataDir();
  if (dir.empty()) return;
  EnsureDirExists(dir);
  const std::wstring log_path = dir + L"\\native-startup.log";
  HANDLE file = CreateFileW(log_path.c_str(), FILE_APPEND_DATA,
                            FILE_SHARE_READ | FILE_SHARE_WRITE |
                                FILE_SHARE_DELETE,
                            nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                            nullptr);
  if (file == INVALID_HANDLE_VALUE) return;

  SYSTEMTIME st{};
  GetLocalTime(&st);
  wchar_t timestamp[64];
  swprintf_s(timestamp, L"%04u-%02u-%02u %02u:%02u:%02u.%03u ",
             st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute,
             st.wSecond, st.wMilliseconds);
  std::string line_utf8 = WideToUtf8(std::wstring(timestamp) + message + L"\r\n");
  DWORD written = 0;
  WriteFile(file, line_utf8.data(), static_cast<DWORD>(line_utf8.size()),
            &written, nullptr);
  CloseHandle(file);
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

  const std::wstring local_dacx_dir = ResolveDacxDataDir();
  EnsureDirExists(local_dacx_dir);
  const std::wstring startup_guard_path =
      local_dacx_dir.empty() ? std::wstring()
                             : (local_dacx_dir + L"\\startup.guard");
  const bool previous_unclean_start = FileExists(startup_guard_path);
  TouchFile(startup_guard_path);

  const bool explicit_safe_arg = std::any_of(
      command_line_arguments.begin(), command_line_arguments.end(),
      [](const std::string& arg) { return arg == kSafeStartupArg; });
  const bool explicit_safe_env = IsTruthy(ReadEnv(kSafeStartupEnv));
  const bool safe_startup_enabled =
      explicit_safe_arg || explicit_safe_env || previous_unclean_start;

  if (safe_startup_enabled && !explicit_safe_arg) {
    command_line_arguments.push_back(kSafeStartupArg);
  }

  LogStartup(L"startup guard: previous_unclean=" +
             std::to_wstring(previous_unclean_start ? 1 : 0) +
             L", explicit_env=" + std::to_wstring(explicit_safe_env ? 1 : 0) +
             L", safe_mode=" + std::to_wstring(safe_startup_enabled ? 1 : 0));

  flutter::DartProject project(L"data");
  if (safe_startup_enabled) {
    // Temporary compatibility fallback for driver/thread-policy regressions.
    project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnSeparateThread);
    project.set_gpu_preference(flutter::GpuPreference::LowPowerPreference);
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Dacx", origin, size)) {
    LogStartup(L"window.Create failed");
    ::CoUninitialize();
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

  DeleteFileQuietly(startup_guard_path);
  LogStartup(L"shutdown clean");
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
