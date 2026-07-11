#include "media_session.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>

#include <Windows.Media.h>
#include <SystemMediaTransportControlsInterop.h>
#include <wrl/client.h>
#include <algorithm>
#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

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

// RFC 3986 percent-encoding for the path portion of a file:// URI. Leaves
// unreserved characters and '/' untouched; encodes spaces, '#', '?', etc.
std::string PercentEncodePath(const std::string& path) {
  static const char* hex = "0123456789ABCDEF";
  std::string out;
  out.reserve(path.size());
  for (unsigned char c : path) {
    const bool unreserved =
        (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' ||
        c == '~' || c == '/' || c == ':' || c == '\\';
    if (unreserved) {
      out.push_back(static_cast<char>(c));
    } else {
      out.push_back('%');
      out.push_back(hex[c >> 4]);
      out.push_back(hex[c & 0x0F]);
    }
  }
  return out;
}

class MediaSession {
 public:
  static MediaSession& Get() {
    static MediaSession instance;
    return instance;
  }

  void Attach(std::unique_ptr<MethodChannel> channel) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* raw = channel.get();
    channels_.push_back(std::move(channel));
    active_channel_ = raw;
  }

  void Detach(MethodChannel* channel) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (active_channel_ == channel) {
      active_channel_ = nullptr;
    }
    channels_.erase(
        std::remove_if(channels_.begin(), channels_.end(),
                       [channel](const std::unique_ptr<MethodChannel>& c) {
                         return c.get() == channel;
                       }),
        channels_.end());
    if (active_channel_ == nullptr && !channels_.empty()) {
      active_channel_ = channels_.back().get();
    }
  }

  void HandleCall(MethodChannel* invoking_channel,
                  const MethodCall& call,
                  std::unique_ptr<MethodResult> result) {
    const auto& method = call.method_name();
    const auto* args =
        std::get_if<EncodableMap>(call.arguments());

    try {
      if (method == "setEnabled") {
        bool enabled = args ? GetOr<bool>(*args, "enabled", false) : false;
        if (enabled) {
          std::lock_guard<std::mutex> lock(mutex_);
          active_channel_ = invoking_channel;
        }
        SetEnabled(enabled);
        result->Success();
        return;
      }
      if (method == "update") {
        if (args) {
          // Latest writer wins.
          {
            std::lock_guard<std::mutex> lock(mutex_);
            active_channel_ = invoking_channel;
          }
          Update(*args);
        }
        result->Success();
        return;
      }
      if (method == "clear") {
        // Only the active source may clear.
        bool allow = false;
        {
          std::lock_guard<std::mutex> lock(mutex_);
          allow = (active_channel_ == nullptr ||
                   active_channel_ == invoking_channel);
        }
        if (allow) Clear();
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
    if (!hwnd) {
      ::OutputDebugStringW(L"[Dacx] SMTC init: no active window yet.\n");
      return;
    }
    auto interop = winrt::get_activation_factory<
        winrt::Windows::Media::SystemMediaTransportControls,
        ISystemMediaTransportControlsInterop>();
    winrt::Windows::Media::SystemMediaTransportControls controls{nullptr};
    HRESULT hr = interop->GetForWindow(
        hwnd, winrt::guid_of<winrt::Windows::Media::SystemMediaTransportControls>(),
        winrt::put_abi(controls));
    if (FAILED(hr)) {
      wchar_t buf[128];
      swprintf_s(buf, L"[Dacx] SMTC GetForWindow failed: hr=0x%08lX\n",
                 static_cast<unsigned long>(hr));
      ::OutputDebugStringW(buf);
      return;
    }
    smtc_ = controls;
    using namespace winrt::Windows::Media;
    smtc_.IsEnabled(true);
    smtc_.IsPlayEnabled(true);
    smtc_.IsPauseEnabled(true);
    smtc_.IsNextEnabled(true);
    smtc_.IsPreviousEnabled(true);
    smtc_.IsStopEnabled(true);
    smtc_.PlaybackPositionChangeRequested(
        [this](auto&&, PlaybackPositionChangeRequestedEventArgs args) {
          int64_t ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                          args.RequestedPlaybackPosition()).count();
          DispatchPosition(static_cast<int>(ms));
        });
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
    using namespace winrt::Windows::Storage::Streams;

    std::string title = GetString(m, "title");
    std::string artist = GetString(m, "artist");
    std::string album = GetString(m, "album");
    bool changedDisplay = false;
    if (!title.empty()) {
      updater_.MusicProperties().Title(Utf8ToWide(title));
      changedDisplay = true;
    }
    if (!artist.empty()) {
      updater_.MusicProperties().Artist(Utf8ToWide(artist));
      changedDisplay = true;
    }
    if (!album.empty()) {
      updater_.MusicProperties().AlbumTitle(Utf8ToWide(album));
      changedDisplay = true;
    }
    auto artIt = m.find(EncodableValue("artUri"));
    if (artIt != m.end()) {
      std::string artUri;
      if (auto p = std::get_if<std::string>(&artIt->second)) artUri = *p;
      if (!artUri.empty()) {
        try {
          winrt::Windows::Foundation::Uri uri{nullptr};
          if (artUri.rfind("http://", 0) == 0 ||
              artUri.rfind("https://", 0) == 0 ||
              artUri.rfind("file://", 0) == 0) {
            uri = winrt::Windows::Foundation::Uri(winrt::to_hstring(artUri));
          } else {
            // Bare local path -- normalize separators and percent-encode so
            // characters like spaces, '#', '?' don't break the URI parser.
            std::string normalized = artUri;
            for (auto& ch : normalized) {
              if (ch == '\\') ch = '/';
            }
            uri = winrt::Windows::Foundation::Uri(
                winrt::to_hstring(std::string("file:///") +
                                  PercentEncodePath(normalized)));
          }
          updater_.Thumbnail(
              RandomAccessStreamReference::CreateFromUri(uri));
          changedDisplay = true;
        } catch (...) {
        }
      } else {
        updater_.Thumbnail(nullptr);
        changedDisplay = true;
      }
    }
    if (changedDisplay) updater_.Update();

    auto pi = m.find(EncodableValue("playing"));
    if (pi != m.end()) {
      bool playing = false;
      if (auto p = std::get_if<bool>(&pi->second)) playing = *p;
      smtc_.PlaybackStatus(playing ? MediaPlaybackStatus::Playing
                                   : MediaPlaybackStatus::Paused);
    }

    // SMTC has no public PlaybackRate property; accept rate from Dart so
    // updates stay coherent with MPRIS/macOS and future WinRT surfaces.
    auto rateIt = m.find(EncodableValue("rate"));
    if (rateIt != m.end()) {
      if (auto pr = std::get_if<double>(&rateIt->second)) {
        if (*pr > 0) last_rate_ = *pr;
      } else if (auto pr = std::get_if<int32_t>(&rateIt->second)) {
        if (*pr > 0) last_rate_ = static_cast<double>(*pr);
      }
    }

    auto durIt = m.find(EncodableValue("durationMs"));
    auto posIt = m.find(EncodableValue("positionMs"));
    int64_t durMs = -1;
    int64_t posMs = -1;
    if (durIt != m.end()) {
      if (auto pi32 = std::get_if<int>(&durIt->second)) durMs = *pi32;
      else if (auto pi64 = std::get_if<int64_t>(&durIt->second)) durMs = *pi64;
    }
    if (posIt != m.end()) {
      if (auto pi32 = std::get_if<int>(&posIt->second)) posMs = *pi32;
      else if (auto pi64 = std::get_if<int64_t>(&posIt->second)) posMs = *pi64;
    }
    if (durMs >= 0 || posMs >= 0) {
      if (durMs >= 0) last_duration_ms_ = durMs;
      if (posMs >= 0) last_position_ms_ = posMs;
      // SMTC rejects timeline updates where Position > MaxSeekTime; clamp.
      int64_t clampedPos = last_position_ms_;
      if (last_duration_ms_ > 0 && clampedPos > last_duration_ms_) {
        clampedPos = last_duration_ms_;
      }
      if (clampedPos < 0) clampedPos = 0;
      SystemMediaTransportControlsTimelineProperties tl;
      tl.StartTime(std::chrono::milliseconds{0});
      tl.MinSeekTime(std::chrono::milliseconds{0});
      tl.EndTime(std::chrono::milliseconds{last_duration_ms_});
      tl.MaxSeekTime(std::chrono::milliseconds{last_duration_ms_});
      tl.Position(std::chrono::milliseconds{clampedPos});
      smtc_.UpdateTimelineProperties(tl);
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
    MethodChannel* target = active_channel_;
    if (target == nullptr && !channels_.empty()) {
      target = channels_.back().get();
    }
    if (target == nullptr) return;
    EncodableMap args{{EncodableValue("action"), EncodableValue(action)}};
    target->InvokeMethod(
        "command",
        std::make_unique<EncodableValue>(EncodableValue(args)));
  }

  void DispatchPosition(int positionMs) {
    std::lock_guard<std::mutex> lock(mutex_);
    MethodChannel* target = active_channel_;
    if (target == nullptr && !channels_.empty()) {
      target = channels_.back().get();
    }
    if (target == nullptr) return;
    EncodableMap args{
        {EncodableValue("action"), EncodableValue("seek")},
        {EncodableValue("positionMs"), EncodableValue(positionMs)},
    };
    target->InvokeMethod(
        "command",
        std::make_unique<EncodableValue>(EncodableValue(args)));
  }

  std::mutex mutex_;
  std::vector<std::unique_ptr<MethodChannel>> channels_;
  MethodChannel* active_channel_{nullptr};  // non-owning, into channels_
  winrt::Windows::Media::SystemMediaTransportControls smtc_{nullptr};
  winrt::Windows::Media::SystemMediaTransportControlsDisplayUpdater updater_{
      nullptr};
  winrt::event_token button_token_{};
  std::atomic<bool> enabled_{false};
  int64_t last_duration_ms_{0};
  int64_t last_position_ms_{0};
  double last_rate_{1.0};
};

}  // namespace

namespace {
  std::mutex g_reg_mutex;
  std::unordered_map<flutter::BinaryMessenger*, MethodChannel*> g_registered;
}

void RegisterMediaSession(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<MethodChannel>(
      messenger, "run.rosie.dacx/media_session",
      &flutter::StandardMethodCodec::GetInstance());
  auto* raw_channel = channel.get();
  channel->SetMethodCallHandler(
      [raw_channel](const MethodCall& call,
                    std::unique_ptr<MethodResult> result) {
        MediaSession::Get().HandleCall(raw_channel, call, std::move(result));
      });
  {
    std::lock_guard<std::mutex> lock(g_reg_mutex);
    g_registered[messenger] = raw_channel;
  }
  MediaSession::Get().Attach(std::move(channel));
}

void UnregisterMediaSession(flutter::BinaryMessenger* messenger) {
  MethodChannel* raw = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_reg_mutex);
    auto it = g_registered.find(messenger);
    if (it != g_registered.end()) {
      raw = it->second;
      g_registered.erase(it);
    }
  }
  if (raw) {
    MediaSession::Get().Detach(raw);
  }
}

}  // namespace dacx
