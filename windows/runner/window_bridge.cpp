#include "window_bridge.h"

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <shobjidl.h>

#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "flutter_window.h"

namespace dacx {

using ::FlutterWindow;
using MethodChannel = flutter::MethodChannel<flutter::EncodableValue>;
using MethodCall = flutter::MethodCall<flutter::EncodableValue>;
using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

namespace {

constexpr const char kWindowMethodChannel[] = "run.rosie.dacx/window/methods";
constexpr const wchar_t kAppUserModelId[] = L"run.rosie.dacx";

std::mutex g_mutex;
FlutterWindow* g_primary_window = nullptr;
bool g_primary_alive = false;

std::mutex g_channel_mutex;
std::unordered_map<flutter::BinaryMessenger*, std::unique_ptr<MethodChannel>>
    g_channels;

ITaskbarList3* g_taskbar = nullptr;
bool g_idle_inhibit_active = false;

void SetIdleInhibit(bool inhibit) {
  if (inhibit) {
    SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED |
                            ES_DISPLAY_REQUIRED);
    g_idle_inhibit_active = true;
  } else {
    SetThreadExecutionState(ES_CONTINUOUS);
    g_idle_inhibit_active = false;
  }
}

void ClearLayeredWindowStyle(HWND hwnd) {
  if (hwnd == nullptr) return;
  LONG ex_style = ::GetWindowLong(hwnd, GWL_EXSTYLE);
  if ((ex_style & WS_EX_LAYERED) == 0) return;
  ex_style &= ~(WS_EX_LAYERED | WS_EX_TRANSPARENT);
  ::SetWindowLong(hwnd, GWL_EXSTYLE, ex_style);
  ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
}

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int size = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                   static_cast<int>(utf8.size()), nullptr, 0);
  if (size <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        out.data(), size);
  return out;
}

std::wstring QuoteArgument(const std::wstring& value) {
  std::wstring escaped = L"\"";
  for (wchar_t ch : value) {
    if (ch == L'"') {
      escaped += L"\\\"";
    } else {
      escaped += ch;
    }
  }
  escaped += L'"';
  return escaped;
}

std::wstring Basename(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  if (slash == std::wstring::npos) return path;
  return path.substr(slash + 1);
}

bool EnsureTaskbar() {
  if (g_taskbar != nullptr) return true;
  HRESULT hr = ::CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(&g_taskbar));
  if (FAILED(hr) || g_taskbar == nullptr) {
    g_taskbar = nullptr;
    return false;
  }
  hr = g_taskbar->HrInit();
  if (FAILED(hr)) {
    g_taskbar->Release();
    g_taskbar = nullptr;
    return false;
  }
  return true;
}

void SetTaskbarProgress(HWND hwnd, double progress) {
  if (hwnd == nullptr || !EnsureTaskbar()) return;
  if (progress < 0.0) {
    g_taskbar->SetProgressState(hwnd, TBPF_NOPROGRESS);
    return;
  }
  const ULONGLONG total = 1000;
  double clamped = progress;
  if (clamped < 0.0) clamped = 0.0;
  if (clamped > 1.0) clamped = 1.0;
  const ULONGLONG completed = static_cast<ULONGLONG>(clamped * total);
  g_taskbar->SetProgressState(hwnd, TBPF_NORMAL);
  g_taskbar->SetProgressValue(hwnd, completed, total);
}

bool UpdateJumpList(const std::vector<std::string>& paths) {
  ICustomDestinationList* list = nullptr;
  HRESULT hr = ::CoCreateInstance(CLSID_DestinationList, nullptr,
                                  CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&list));
  if (FAILED(hr) || list == nullptr) return false;

  list->SetAppID(kAppUserModelId);

  UINT max_slots = 0;
  IObjectArray* removed = nullptr;
  hr = list->BeginList(&max_slots, IID_PPV_ARGS(&removed));
  if (removed != nullptr) removed->Release();
  if (FAILED(hr)) {
    list->Release();
    return false;
  }

  IObjectCollection* collection = nullptr;
  hr = ::CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr,
                          CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&collection));
  if (FAILED(hr) || collection == nullptr) {
    list->AbortList();
    list->Release();
    return false;
  }

  wchar_t exe_path[MAX_PATH] = {};
  ::GetModuleFileNameW(nullptr, exe_path, MAX_PATH);

  const size_t limit =
      paths.size() < 12 ? paths.size() : static_cast<size_t>(12);
  for (size_t i = 0; i < limit; ++i) {
    const std::wstring wide = Utf8ToWide(paths[i]);
    if (wide.empty()) continue;

    IShellLinkW* link = nullptr;
    hr = ::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                            IID_PPV_ARGS(&link));
    if (FAILED(hr) || link == nullptr) continue;

    link->SetPath(exe_path);
    link->SetArguments(QuoteArgument(wide).c_str());
    const std::wstring title = Basename(wide);
    if (!title.empty()) {
      link->SetDescription(title.c_str());
    }

    collection->AddObject(link);
    link->Release();
  }

  IObjectArray* items = nullptr;
  hr = collection->QueryInterface(IID_PPV_ARGS(&items));
  collection->Release();
  if (FAILED(hr) || items == nullptr) {
    list->AbortList();
    list->Release();
    return false;
  }

  list->AppendCategory(L"Recent", items);
  items->Release();
  hr = list->CommitList();
  list->Release();
  return SUCCEEDED(hr);
}

std::vector<std::string> ReadStringList(const flutter::EncodableValue* args) {
  std::vector<std::string> out;
  if (args == nullptr) return out;
  const auto* list = std::get_if<flutter::EncodableList>(args);
  if (list == nullptr) return out;
  for (const auto& entry : *list) {
    const auto* s = std::get_if<std::string>(&entry);
    if (s != nullptr && !s->empty()) out.push_back(*s);
  }
  return out;
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
      if (g_taskbar != nullptr && window != nullptr) {
        g_taskbar->SetProgressState(window->GetHandle(), TBPF_NOPROGRESS);
      }
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
        if (method == "updateJumpList") {
          const auto paths = ReadStringList(call.arguments());
          result->Success(flutter::EncodableValue(UpdateJumpList(paths)));
          return;
        }
        if (method == "setTaskbarProgress") {
          double progress = -1.0;
          if (const auto* value =
                  std::get_if<double>(call.arguments())) {
            progress = *value;
          } else if (const auto* intValue =
                         std::get_if<int32_t>(call.arguments())) {
            progress = static_cast<double>(*intValue);
          }
          SetTaskbarProgress(window->GetHandle(), progress);
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (method == "setIdleInhibit") {
          bool inhibit = false;
          if (const auto* value = std::get_if<bool>(call.arguments())) {
            inhibit = *value;
          }
          SetIdleInhibit(inhibit);
          result->Success(flutter::EncodableValue(true));
          return;
        }
        result->NotImplemented();
      });

  std::lock_guard<std::mutex> lock(g_channel_mutex);
  g_channels[messenger] = std::move(channel);
}

}  // namespace dacx
