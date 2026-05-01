#include "media_session.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

#include <Windows.Media.h>
#include <SystemMediaTransportControlsInterop.h>
#include <wrl/client.h>
#include <atomic>
#include <memory>
#include <mutex>
#include <string>

#include "win32_window.h"

namespace dacx {

namespace {

using MethodChannel = flutter::MethodChannel<flutter::EncodableValue>;
using MethodCall = flutter::MethodCall<flutter::EncodableValue>;
using MethodResult = flutter::MethodResult<flutter::EncodableValue>;
using flutter::EncodableMap;
using flutter::EncodableValue;

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                 static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                      &out[0], size);
  return out;
}

template <typename T>
T GetOr(const EncodableMap& m, const char* key, T fallback) {
  auto it = m.find(EncodableValue(key));
  if (it == m.end()) return fallback;
  if (auto p = std::get_if<T>(&it->second)) return *p;
  return fallback;
}

std::string GetString(const EncodableMap& m, const char* key) {
  auto it = m.find(EncodableValue(key));
  if (it == m.end()) return std::string();
  if (auto p = std::get_if<std::string>(&it->second)) return *p;
  return std::string();
}

class MediaSession {
 public:
  static MediaSession& Get() {
    static MediaSession instance;
    return instance;
  }

  void Attach(std::unique_ptr<MethodChannel> channel) {
    std::lock_guard<std::mutex> lock(mutex_);
    channel_ = std::move(channel);
  }

  void HandleCall(const MethodCall& call,
                  std::unique_ptr<MethodResult> result) {
    const auto& method = call.method_name();
    const auto* args =
        std::get_if<EncodableMap>(call.arguments());

    try {
      if (method == "setEnabled") {
        bool enabled = args ? GetOr<bool>(*args, "enabled", false) : false;
        SetEnabled(enabled);
        result->Success();
        return;
      }
      if (method == "update") {
        if (args) Update(*args);
        result->Success();
        return;
      }
      if (method == "clear") {
        Clear();
        result->Success();
        return;
      }
      result->NotImplemented();
    } catch (const winrt::hresult_error& e) {
      result->Error("smtc_error", winrt::to_string(e.message()));
    } catch (const std::exception& e) {
      result->Error("smtc_error", e.what());
    } catch (...) {
      result->Error("smtc_error", "unknown");
    }
  }

 private:
  void EnsureInit() {
    if (smtc_) return;
    HWND hwnd = ::GetActiveWindow();
    if (!hwnd) return;
    auto interop = winrt::get_activation_factory<
        winrt::Windows::Media::SystemMediaTransportControls,
        ISystemMediaTransportControlsInterop>();
    winrt::Windows::Media::SystemMediaTransportControls controls{nullptr};
    HRESULT hr = interop->GetForWindow(
        hwnd, winrt::guid_of<winrt::Windows::Media::SystemMediaTransportControls>(),
        winrt::put_abi(controls));
    if (FAILED(hr)) return;
    smtc_ = controls;
    using namespace winrt::Windows::Media;
    smtc_.IsEnabled(true);
    smtc_.IsPlayEnabled(true);
    smtc_.IsPauseEnabled(true);
    smtc_.IsNextEnabled(true);
    smtc_.IsPreviousEnabled(true);
    smtc_.IsStopEnabled(true);
    updater_ = smtc_.DisplayUpdater();
    updater_.Type(MediaPlaybackType::Music);
    button_token_ = smtc_.ButtonPressed(
        [this](auto&&, SystemMediaTransportControlsButtonPressedEventArgs args) {
          DispatchButton(args.Button());
        });
  }

  void SetEnabled(bool enabled) {
    EnsureInit();
    if (!smtc_) return;
    smtc_.IsEnabled(enabled);
    enabled_ = enabled;
  }

  void Update(const EncodableMap& m) {
    EnsureInit();
    if (!smtc_ || !enabled_) return;
    using namespace winrt::Windows::Media;

    std::string title = GetString(m, "title");
    std::string artist = GetString(m, "artist");
    std::string album = GetString(m, "album");
    if (!title.empty()) {
      updater_.MusicProperties().Title(Utf8ToWide(title));
    }
    if (!artist.empty()) {
      updater_.MusicProperties().Artist(Utf8ToWide(artist));
    }
    if (!album.empty()) {
      updater_.MusicProperties().AlbumTitle(Utf8ToWide(album));
    }
    updater_.Update();

    auto pi = m.find(EncodableValue("playing"));
    if (pi != m.end()) {
      bool playing = false;
      if (auto p = std::get_if<bool>(&pi->second)) playing = *p;
      smtc_.PlaybackStatus(playing ? MediaPlaybackStatus::Playing
                                   : MediaPlaybackStatus::Paused);
    }
  }

  void Clear() {
    if (!smtc_) return;
    using namespace winrt::Windows::Media;
    updater_.ClearAll();
    updater_.Update();
    smtc_.PlaybackStatus(MediaPlaybackStatus::Stopped);
  }

  void DispatchButton(
      winrt::Windows::Media::SystemMediaTransportControlsButton button) {
    using B = winrt::Windows::Media::SystemMediaTransportControlsButton;
    const char* action = nullptr;
    switch (button) {
      case B::Play: action = "play"; break;
      case B::Pause: action = "pause"; break;
      case B::Stop: action = "stop"; break;
      case B::Next: action = "next"; break;
      case B::Previous: action = "previous"; break;
      default: return;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    if (!channel_) return;
    EncodableMap args{{EncodableValue("action"), EncodableValue(action)}};
    channel_->InvokeMethod(
        "command",
        std::make_unique<EncodableValue>(EncodableValue(args)));
  }

  std::mutex mutex_;
  std::unique_ptr<MethodChannel> channel_;
  winrt::Windows::Media::SystemMediaTransportControls smtc_{nullptr};
  winrt::Windows::Media::SystemMediaTransportControlsDisplayUpdater updater_{
      nullptr};
  winrt::event_token button_token_{};
  std::atomic<bool> enabled_{false};
};

}  // namespace

void RegisterMediaSession(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<MethodChannel>(
      messenger, "run.rosie.dacx/media_session",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const MethodCall& call, std::unique_ptr<MethodResult> result) {
        MediaSession::Get().HandleCall(call, std::move(result));
      });
  MediaSession::Get().Attach(std::move(channel));
}

}  // namespace dacx
