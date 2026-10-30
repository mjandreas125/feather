#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <dwmapi.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "clipboard_image.h"
#include "notifications.h"
#include <shellapi.h>

namespace {

std::wstring Wide(const std::string& s) {
  int n = ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  std::wstring w(n > 0 ? n - 1 : 0, L'\0');
  if (n > 1) ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, &w[0], n);
  return w;
}

std::string Utf8(const std::wstring& w) {
  int n = ::WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string s(n > 0 ? n - 1 : 0, '\0');
  if (n > 1) ::WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, &s[0], n, nullptr, nullptr);
  return s;
}

std::string Arg(const flutter::EncodableMap& m, const char* key) {
  auto it = m.find(flutter::EncodableValue(key));
  if (it == m.end()) return "";
  const auto* s = std::get_if<std::string>(&it->second);
  return s ? *s : "";
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "feather/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (call.method_name() == "setTitle") {
          if (const auto* s = std::get_if<std::string>(call.arguments())) {
            ::SetWindowTextW(GetHandle(), Wide(*s).c_str());
          }
          result->Success();
        } else if (call.method_name() == "isForeground") {
          result->Success(flutter::EncodableValue(::GetForegroundWindow() == GetHandle()));
        } else if (call.method_name() == "clipboardImage") {
          std::vector<uint8_t> png = ClipboardImagePng();
          if (png.empty()) result->Success();
          else result->Success(flutter::EncodableValue(png));
        } else if (call.method_name() == "clipboardFiles") {
          flutter::EncodableList list;
          for (const auto& f : ClipboardFiles()) list.push_back(flutter::EncodableValue(f));
          result->Success(flutter::EncodableValue(list));
        } else if (call.method_name() == "flash") {
          FlashUntilFocused(GetHandle());
          result->Success();
        } else if (call.method_name() == "toast" && args) {
          bool ok = ShowReminderToast(GetHandle(), Wide(Arg(*args, "title")),
                                      Wide(Arg(*args, "body")), Wide(Arg(*args, "tag")),
                                      Wide(Arg(*args, "open")), Wide(Arg(*args, "dismiss")));
          result->Success(flutter::EncodableValue(ok));
        } else if (call.method_name() == "hideToast") {
          if (const auto* s = std::get_if<std::string>(call.arguments())) HideToast(Wide(*s));
          result->Success();
        } else if (call.method_name() == "setDark") {
          if (const auto* b = std::get_if<bool>(call.arguments())) {
            SetDarkFrame(*b);
          }
          result->Success();
        } else if (call.method_name() == "startDrag") {
          // Let Windows move the window as if the title bar was grabbed (keeps snapping).
          ::ReleaseCapture();
          ::SendMessageW(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
        } else if (call.method_name() == "startResize") {
          const auto* edge = std::get_if<std::string>(call.arguments());
          WPARAM hit = HTTOP;
          if (edge && *edge == "topLeft") hit = HTTOPLEFT;
          if (edge && *edge == "topRight") hit = HTTOPRIGHT;
          ::ReleaseCapture();
          ::SendMessageW(GetHandle(), WM_NCLBUTTONDOWN, hit, 0);
          result->Success();
        } else if (call.method_name() == "minimize") {
          ::ShowWindow(GetHandle(), SW_MINIMIZE);
          result->Success();
        } else if (call.method_name() == "toggleMaximize") {
          ::ShowWindow(GetHandle(), ::IsZoomed(GetHandle()) ? SW_RESTORE : SW_MAXIMIZE);
          result->Success();
        } else if (call.method_name() == "isMaximized") {
          result->Success(flutter::EncodableValue(::IsZoomed(GetHandle()) != 0));
        } else if (call.method_name() == "close") {
          ::PostMessageW(GetHandle(), WM_CLOSE, 0, 0);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  ::DragAcceptFiles(GetHandle(), TRUE);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (message == WM_SIZE && window_channel_) {
    // Tell Dart so the maximise/restore button shows the right glyph.
    window_channel_->InvokeMethod(
        "maximizedChanged", std::make_unique<flutter::EncodableValue>(wparam == SIZE_MAXIMIZED));
  }

  if (message == WM_DROPFILES) {
    HDROP drop = reinterpret_cast<HDROP>(wparam);
    flutter::EncodableList list;
    UINT n = ::DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    for (UINT i = 0; i < n; ++i) {
      wchar_t path[MAX_PATH * 4];
      if (::DragQueryFileW(drop, i, path, MAX_PATH * 4)) list.push_back(flutter::EncodableValue(Utf8(path)));
    }
    ::DragFinish(drop);
    if (window_channel_) {
      window_channel_->InvokeMethod("filesDropped", std::make_unique<flutter::EncodableValue>(list));
    }
    return 0;
  }

  if (message == kToastActivatedMessage) {
    std::wstring tag = TakeActivatedToastTag();
    if (::IsIconic(hwnd)) ::ShowWindow(hwnd, SW_RESTORE);
    ::SetForegroundWindow(hwnd);
    if (window_channel_) {
      window_channel_->InvokeMethod(
          "toastActivated", std::make_unique<flutter::EncodableValue>(Utf8(tag)));
    }
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
