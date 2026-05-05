#include "instance_bridge.h"

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace dacx {

namespace {

constexpr const wchar_t* kSingletonMutexName =
    L"Local\\run.rosie.dacx.singleton";
constexpr const wchar_t* kOpenFilePipeBaseName =
    L"\\\\.\\pipe\\run.rosie.dacx.openfile";
constexpr const char kOpenFileMethodChannel[] =
    "run.rosie.dacx/open_file/methods";
constexpr const char kOpenFileEventChannel[] =
    "run.rosie.dacx/open_file/events";
constexpr const char kNewInstanceFlag[] = "--new-instance";
constexpr DWORD kPipeBufferSize = 64 * 1024;
constexpr DWORD kPipeWaitMs = 1000;
constexpr uint32_t kMaxMessageBytes = 32 * 1024;

HANDLE g_singleton_mutex = nullptr;

std::mutex g_pending_mutex;
std::vector<std::string> g_pending_paths;
std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> g_event_sink;
HWND g_dispatch_window = nullptr;

constexpr UINT WM_DACX_DELIVER_PATH = WM_USER + 0x42;

std::wstring CurrentUserSuffix() {
  wchar_t buf[256];
  DWORD len = static_cast<DWORD>(sizeof(buf) / sizeof(buf[0]));
  if (!GetUserNameW(buf, &len) || len == 0) return std::wstring();
  // GetUserNameW returns length including the trailing NUL.
  std::wstring out(buf, len > 0 ? len - 1 : 0);
  for (auto& c : out) {
    if (c == L'\\' || c == L'/' || c == L':' || c == L' ') c = L'_';
  }
  return out;
}

const std::wstring& PipeName() {
  static const std::wstring name = []() {
    std::wstring n = kOpenFilePipeBaseName;
    auto user = CurrentUserSuffix();
    if (!user.empty()) {
      n.push_back(L'.');
      n.append(user);
    }
    return n;
  }();
  return name;
}

std::wstring ResolveFlagFilePath() {
  wchar_t buf[MAX_PATH];
  DWORD len = GetEnvironmentVariableW(L"LOCALAPPDATA", buf, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) return std::wstring();
  std::wstring path(buf, len);
  path += L"\\Dacx\\allow_multi_instance";
  return path;
}

void EnqueuePath(const std::string& path) {
  std::lock_guard<std::mutex> lock(g_pending_mutex);
  g_pending_paths.push_back(path);
}

// Must run on the platform thread (the same thread that hosts the engine).
void DispatchQueuedToSink() {
  std::vector<std::string> drained;
  {
    std::lock_guard<std::mutex> lock(g_pending_mutex);
    if (!g_event_sink) return;
    drained.swap(g_pending_paths);
  }
  for (const auto& path : drained) {
    g_event_sink->Success(flutter::EncodableValue(path));
  }
}

LRESULT CALLBACK DispatchWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  if (msg == WM_DACX_DELIVER_PATH) {
    DispatchQueuedToSink();
    return 0;
  }
  return DefWindowProcW(hwnd, msg, wp, lp);
}

void EnsureDispatchWindow() {
  if (g_dispatch_window != nullptr) return;
  static const wchar_t* kClassName = L"DacxInstanceBridgeWindow";
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = DispatchWndProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = kClassName;
  RegisterClassExW(&wc);
  g_dispatch_window = CreateWindowExW(0, kClassName, L"", 0, 0, 0, 0, 0,
                                      HWND_MESSAGE, nullptr, wc.hInstance,
                                      nullptr);
}

void HandlePipeClient(HANDLE pipe) {
  uint32_t length = 0;
  DWORD read = 0;
  if (!ReadFile(pipe, &length, sizeof(length), &read, nullptr) ||
      read != sizeof(length) || length == 0 || length > kMaxMessageBytes) {
    DisconnectNamedPipe(pipe);
    CloseHandle(pipe);
    return;
  }
  std::string buffer(length, '\0');
  DWORD total = 0;
  while (total < length) {
    DWORD chunk = 0;
    if (!ReadFile(pipe, buffer.data() + total, length - total, &chunk,
                  nullptr) ||
        chunk == 0) {
      break;
    }
    total += chunk;
  }
  DisconnectNamedPipe(pipe);
  CloseHandle(pipe);
  if (total != length) return;

  size_t start = 0;
  for (size_t i = 0; i <= buffer.size(); i++) {
    if (i == buffer.size() || buffer[i] == '\0') {
      if (i > start) {
        EnqueuePath(buffer.substr(start, i - start));
      }
      start = i + 1;
    }
  }
  if (g_dispatch_window != nullptr) {
    PostMessageW(g_dispatch_window, WM_DACX_DELIVER_PATH, 0, 0);
  }
}

void PipeServerLoop() {
  const std::wstring& name = PipeName();
  for (;;) {
    HANDLE pipe = CreateNamedPipeW(
        name.c_str(),
        PIPE_ACCESS_INBOUND,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
        PIPE_UNLIMITED_INSTANCES, kPipeBufferSize, kPipeBufferSize, 0, nullptr);
    if (pipe == INVALID_HANDLE_VALUE) {
      Sleep(250);
      continue;
    }
    BOOL connected = ConnectNamedPipe(pipe, nullptr)
                         ? TRUE
                         : (GetLastError() == ERROR_PIPE_CONNECTED);
    if (!connected) {
      CloseHandle(pipe);
      continue;
    }
    HandlePipeClient(pipe);
  }
}

}  // namespace

bool AllowMultipleInstancesEnabled() {
  std::wstring path = ResolveFlagFilePath();
  if (path.empty()) return false;
  DWORD attrs = GetFileAttributesW(path.c_str());
  if (attrs == INVALID_FILE_ATTRIBUTES) return false;
  return (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool ConsumeNewInstanceFlag(std::vector<std::string>& args) {
  bool found = false;
  for (auto it = args.begin(); it != args.end();) {
    if (*it == kNewInstanceFlag) {
      it = args.erase(it);
      found = true;
    } else {
      ++it;
    }
  }
  return found;
}

bool ForwardToRunningInstance(const std::vector<std::string>& file_paths) {
  if (file_paths.empty()) return false;

  std::string payload;
  for (const auto& path : file_paths) {
    if (path.empty()) continue;
    if (!payload.empty()) payload.push_back('\0');
    payload.append(path);
  }
  if (payload.empty() || payload.size() > kMaxMessageBytes) return false;

  const std::wstring& name = PipeName();
  if (!WaitNamedPipeW(name.c_str(), kPipeWaitMs)) {
    return false;
  }
  HANDLE pipe = CreateFileW(name.c_str(), GENERIC_WRITE, 0, nullptr,
                            OPEN_EXISTING, 0, nullptr);
  if (pipe == INVALID_HANDLE_VALUE) return false;

  uint32_t length = static_cast<uint32_t>(payload.size());
  DWORD written = 0;
  bool ok = WriteFile(pipe, &length, sizeof(length), &written, nullptr) &&
            written == sizeof(length) &&
            WriteFile(pipe, payload.data(),
                      static_cast<DWORD>(payload.size()), &written, nullptr) &&
            written == payload.size();
  FlushFileBuffers(pipe);
  CloseHandle(pipe);
  return ok;
}

bool AcquireSingletonMutex() {
  HANDLE handle = CreateMutexW(nullptr, FALSE, kSingletonMutexName);
  if (handle == nullptr) {
    // Treat creation failure as "no contention" so the app still launches.
    return true;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(handle);
    return false;
  }
  g_singleton_mutex = handle;  // Hold for process lifetime.
  return true;
}

void StartOpenFileServer(flutter::BinaryMessenger* messenger) {
  static std::atomic_bool initialized{false};
  bool expected = false;
  if (!initialized.compare_exchange_strong(expected, true)) {
    return;
  }

  EnsureDispatchWindow();

  static std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel;
  method_channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kOpenFileMethodChannel,
          &flutter::StandardMethodCodec::GetInstance());
  method_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "getPendingFiles") {
          flutter::EncodableList list;
          {
            std::lock_guard<std::mutex> lock(g_pending_mutex);
            for (const auto& path : g_pending_paths) {
              list.push_back(flutter::EncodableValue(path));
            }
            g_pending_paths.clear();
          }
          result->Success(flutter::EncodableValue(list));
        } else {
          result->NotImplemented();
        }
      });

  static std::shared_ptr<flutter::EventChannel<flutter::EncodableValue>>
      event_channel;
  event_channel =
      std::make_shared<flutter::EventChannel<flutter::EncodableValue>>(
          messenger, kOpenFileEventChannel,
          &flutter::StandardMethodCodec::GetInstance());
  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [](const flutter::EncodableValue* /*arguments*/,
         std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        {
          std::lock_guard<std::mutex> lock(g_pending_mutex);
          g_event_sink = std::move(events);
        }
        DispatchQueuedToSink();
        return nullptr;
      },
      [](const flutter::EncodableValue* /*arguments*/)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        std::lock_guard<std::mutex> lock(g_pending_mutex);
        g_event_sink.reset();
        return nullptr;
      });
  event_channel->SetStreamHandler(std::move(handler));

  std::thread(PipeServerLoop).detach();
}

}  // namespace dacx
