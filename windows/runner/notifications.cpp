#include "notifications.h"

#include <propkey.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.UI.Notifications.h>

#include <map>
#include <mutex>

#pragma comment(lib, "windowsapp")
#pragma comment(lib, "propsys")

namespace {

constexpr wchar_t kAppId[] = L"Feather.Desktop";

std::mutex g_mutex;
std::wstring g_activated_tag;
std::map<std::wstring, winrt::Windows::UI::Notifications::ToastNotification> g_toasts;

std::wstring XmlEscape(const std::wstring& s) {
  std::wstring out;
  out.reserve(s.size());
  for (wchar_t c : s) {
    switch (c) {
      case L'&': out += L"&amp;"; break;
      case L'<': out += L"&lt;"; break;
      case L'>': out += L"&gt;"; break;
      case L'"': out += L"&quot;"; break;
      case L'\'': out += L"&apos;"; break;
      default: out += c;
    }
  }
  return out;
}

// Windows only shows toasts of unpackaged apps that have a Start menu shortcut carrying
// the same AppUserModelID. Create or refresh %APPDATA%\...\Start Menu\Programs\Feather.lnk.
void EnsureShortcut() {
  wchar_t exe[MAX_PATH];
  if (!::GetModuleFileNameW(nullptr, exe, MAX_PATH)) return;
  PWSTR programs = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr, &programs))) return;
  std::wstring lnk = std::wstring(programs) + L"\\Feather.lnk";
  ::CoTaskMemFree(programs);

  Microsoft::WRL::ComPtr<IShellLinkW> link;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&link)))) {
    return;
  }
  // Keep an existing shortcut if it already points at this exe.
  Microsoft::WRL::ComPtr<IPersistFile> file;
  if (FAILED(link.As(&file))) return;
  if (SUCCEEDED(file->Load(lnk.c_str(), STGM_READ))) {
    wchar_t target[MAX_PATH] = {};
    if (SUCCEEDED(link->GetPath(target, MAX_PATH, nullptr, 0)) &&
        _wcsicmp(target, exe) == 0) {
      return;
    }
  }
  link->SetPath(exe);
  std::wstring dir(exe);
  dir = dir.substr(0, dir.find_last_of(L'\\'));
  link->SetWorkingDirectory(dir.c_str());
  link->SetDescription(L"Feather - lightweight desktop app for Claude Code");

  Microsoft::WRL::ComPtr<IPropertyStore> store;
  if (FAILED(link.As(&store))) return;
  PROPVARIANT pv;
  if (FAILED(::InitPropVariantFromString(kAppId, &pv))) return;
  store->SetValue(PKEY_AppUserModel_ID, pv);
  store->Commit();
  ::PropVariantClear(&pv);
  file->Save(lnk.c_str(), TRUE);
}

// ---------------------------------------------------------------------------------
// Fallback: Feather's own small reminder window, for PCs where Windows notifications are
// switched off. Dark, always on top, never steals focus, stays until closed or clicked.

constexpr wchar_t kPopupClass[] = L"FeatherReminderPopup";

struct Popup {
  std::wstring tag, title, body;
  HWND main = nullptr;
};

std::map<HWND, Popup> g_popups;

bool ToastsEnabled() {
  DWORD value = 1, size = sizeof(value);
  if (::RegGetValueW(HKEY_CURRENT_USER,
                     L"Software\\Microsoft\\Windows\\CurrentVersion\\PushNotifications",
                     L"ToastEnabled", RRF_RT_REG_DWORD, nullptr, &value, &size) == ERROR_SUCCESS) {
    return value != 0;
  }
  return true;
}

int Scale(HWND hwnd, int v) {
  UINT dpi = ::GetDpiForWindow(hwnd);
  return ::MulDiv(v, dpi ? dpi : 96, 96);
}

RECT CloseRect(HWND hwnd) {
  RECT rc;
  ::GetClientRect(hwnd, &rc);
  int s = Scale(hwnd, 26);
  return RECT{rc.right - s - Scale(hwnd, 4), Scale(hwnd, 4), rc.right - Scale(hwnd, 4), Scale(hwnd, 4) + s};
}

void LayoutPopups() {
  RECT work;
  ::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  int i = 0;
  for (auto& [hwnd, p] : g_popups) {
    int w = Scale(hwnd, 360), h = Scale(hwnd, 92), m = Scale(hwnd, 12);
    int x = work.right - w - m;
    int y = work.bottom - (h + m) * (i + 1);
    ::SetWindowPos(hwnd, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    ++i;
  }
}

LRESULT CALLBACK PopupProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  switch (msg) {
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC dc = ::BeginPaint(hwnd, &ps);
      RECT rc;
      ::GetClientRect(hwnd, &rc);
      HBRUSH bg = ::CreateSolidBrush(RGB(0x25, 0x25, 0x26));
      ::FillRect(dc, &rc, bg);
      ::DeleteObject(bg);
      HBRUSH border = ::CreateSolidBrush(RGB(0x45, 0x45, 0x45));
      ::FrameRect(dc, &rc, border);
      ::DeleteObject(border);
      RECT bar{0, 0, Scale(hwnd, 4), rc.bottom};
      HBRUSH accent = ::CreateSolidBrush(RGB(0xD9, 0x77, 0x57));
      ::FillRect(dc, &bar, accent);
      ::DeleteObject(accent);
      ::SetBkMode(dc, TRANSPARENT);
      auto it = g_popups.find(hwnd);
      if (it != g_popups.end()) {
        HFONT bold = ::CreateFontW(-Scale(hwnd, 14), 0, 0, 0, FW_SEMIBOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0,
                                   CLEARTYPE_QUALITY, 0, L"Segoe UI");
        HFONT normal = ::CreateFontW(-Scale(hwnd, 13), 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0,
                                     CLEARTYPE_QUALITY, 0, L"Segoe UI");
        int pad = Scale(hwnd, 16);
        RECT t{pad, Scale(hwnd, 12), rc.right - Scale(hwnd, 36), Scale(hwnd, 34)};
        ::SelectObject(dc, bold);
        ::SetTextColor(dc, RGB(0xFF, 0xFF, 0xFF));
        ::DrawTextW(dc, it->second.title.c_str(), -1, &t, DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
        // Body: one line per "\n", each cut with an ellipsis.
        ::SelectObject(dc, normal);
        ::SetTextColor(dc, RGB(0xC8, 0xC8, 0xC8));
        const std::wstring& body = it->second.body;
        int y = Scale(hwnd, 38);
        size_t start = 0;
        for (int line = 0; line < 2 && start <= body.size(); ++line) {
          size_t end = body.find(L'\n', start);
          std::wstring part = body.substr(start, end == std::wstring::npos ? std::wstring::npos : end - start);
          if (!part.empty() && part.back() == L'\r') part.pop_back();
          RECT b{pad, y, rc.right - Scale(hwnd, 14), y + Scale(hwnd, 20)};
          ::DrawTextW(dc, part.c_str(), -1, &b, DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
          y += Scale(hwnd, 20);
          if (end == std::wstring::npos) break;
          start = end + 1;
        }
        RECT x = CloseRect(hwnd);
        ::SetTextColor(dc, RGB(0x9D, 0x9D, 0x9D));
        ::DrawTextW(dc, L"\x2715", -1, &x, DT_SINGLELINE | DT_CENTER | DT_VCENTER);
        ::DeleteObject(bold);
        ::DeleteObject(normal);
      }
      ::EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_SETCURSOR:
      ::SetCursor(::LoadCursor(nullptr, IDC_HAND));
      return TRUE;
    case WM_LBUTTONUP: {
      POINT pt{static_cast<short>(LOWORD(lp)), static_cast<short>(HIWORD(lp))};
      RECT x = CloseRect(hwnd);
      auto it = g_popups.find(hwnd);
      if (it != g_popups.end() && !::PtInRect(&x, pt)) {
        {
          std::lock_guard<std::mutex> lock(g_mutex);
          g_activated_tag = it->second.tag;
        }
        ::PostMessageW(it->second.main, kToastActivatedMessage, 0, 0);
      }
      ::DestroyWindow(hwnd);
      return 0;
    }
    case WM_DESTROY:
      g_popups.erase(hwnd);
      LayoutPopups();
      return 0;
  }
  return ::DefWindowProcW(hwnd, msg, wp, lp);
}

void ShowPopup(HWND main, const std::wstring& title, const std::wstring& body,
               const std::wstring& tag) {
  static bool registered = false;
  if (!registered) {
    WNDCLASSW wc = {};
    wc.lpfnWndProc = PopupProc;
    wc.hInstance = ::GetModuleHandleW(nullptr);
    wc.lpszClassName = kPopupClass;
    wc.hCursor = ::LoadCursor(nullptr, IDC_HAND);
    ::RegisterClassW(&wc);
    registered = true;
  }
  // One reminder per tag: replace an older one.
  for (auto& [hwnd, p] : g_popups) {
    if (p.tag == tag) {
      p.title = title;
      p.body = body;
      ::InvalidateRect(hwnd, nullptr, TRUE);
      return;
    }
  }
  HWND hwnd = ::CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kPopupClass, L"Feather",
                                WS_POPUP, 0, 0, 10, 10, nullptr, nullptr, ::GetModuleHandleW(nullptr), nullptr);
  if (!hwnd) return;
  // DrawText only breaks lines on CR LF.
  std::wstring text;
  for (wchar_t ch : body) {
    if (ch == L'\n') text += L"\r\n"; else if (ch != L'\r') text += ch;
  }
  g_popups[hwnd] = Popup{tag, title, text, main};
  LayoutPopups();
  ::ShowWindow(hwnd, SW_SHOWNOACTIVATE);
}

void HidePopup(const std::wstring& tag) {
  for (auto& [hwnd, p] : g_popups) {
    if (p.tag == tag) {
      ::DestroyWindow(hwnd);
      return;
    }
  }
}

}  // namespace

void InitNotifications() {
  ::SetCurrentProcessExplicitAppUserModelID(kAppId);
  EnsureShortcut();
}

bool ShowReminderToast(HWND window, const std::wstring& title,
                       const std::wstring& body, const std::wstring& tag,
                       const std::wstring& open_label,
                       const std::wstring& dismiss_label) {
  using namespace winrt::Windows::UI::Notifications;
  using winrt::Windows::Data::Xml::Dom::XmlDocument;
  if (!ToastsEnabled()) {
    ShowPopup(window, title, body, tag);
    return true;
  }
  try {
    std::wstring xml =
        L"<toast scenario=\"reminder\" launch=\"" + XmlEscape(tag) + L"\">"
        L"<visual><binding template=\"ToastGeneric\">"
        L"<text>" + XmlEscape(title) + L"</text>"
        L"<text>" + XmlEscape(body) + L"</text>"
        L"</binding></visual>"
        L"<actions>"
        L"<action content=\"" + XmlEscape(open_label) + L"\" arguments=\"" + XmlEscape(tag) +
        L"\" activationType=\"foreground\"/>"
        L"<action content=\"" + XmlEscape(dismiss_label) +
        L"\" arguments=\"dismiss\" activationType=\"system\"/>"
        L"</actions>"
        L"<audio src=\"ms-winsoundevent:Notification.Reminder\"/>"
        L"</toast>";
    XmlDocument doc;
    doc.LoadXml(xml);
    ToastNotification toast(doc);
    toast.Tag(tag.substr(0, 64));
    toast.Group(L"feather");
    HWND hwnd = window;
    toast.Activated([hwnd, tag](auto const&, auto const&) {
      {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_activated_tag = tag;
      }
      ::PostMessageW(hwnd, kToastActivatedMessage, 0, 0);
    });
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      g_toasts.insert_or_assign(tag, toast);
    }
    ToastNotificationManager::CreateToastNotifier(kAppId).Show(toast);
    return true;
  } catch (...) {
    ShowPopup(window, title, body, tag);
    return true;
  }
}

void HideToast(const std::wstring& tag) {
  using namespace winrt::Windows::UI::Notifications;
  HidePopup(tag);
  try {
    ToastNotificationManager::History().Remove(tag.substr(0, 64), L"feather", kAppId);
  } catch (...) {
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  g_toasts.erase(tag);
}

std::wstring TakeActivatedToastTag() {
  std::lock_guard<std::mutex> lock(g_mutex);
  std::wstring t = g_activated_tag;
  g_activated_tag.clear();
  return t;
}

void FlashUntilFocused(HWND window) {
  FLASHWINFO info = {sizeof(info)};
  info.hwnd = window;
  info.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
  info.uCount = 0;
  info.dwTimeout = 0;
  ::FlashWindowEx(&info);
}
