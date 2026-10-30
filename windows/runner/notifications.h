#ifndef RUNNER_NOTIFICATIONS_H_
#define RUNNER_NOTIFICATIONS_H_

#include <windows.h>

#include <string>

// Window message posted to the main window when the user clicks a toast. The tag of the
// clicked toast is fetched with TakeActivatedToastTag().
constexpr UINT kToastActivatedMessage = WM_APP + 0x46;

// Registers the app identity Windows needs for toasts (AppUserModelID + Start menu
// shortcut that carries it). Safe to call on every start.
void InitNotifications();

// Shows a toast that stays on screen until dismissed (scenario "reminder").
// |tag| identifies it (e.g. the tab id); a newer toast with the same tag replaces it.
bool ShowReminderToast(HWND window, const std::wstring& title,
                       const std::wstring& body, const std::wstring& tag,
                       const std::wstring& open_label,
                       const std::wstring& dismiss_label);

// Removes the toast with |tag| (e.g. the request was answered in the app).
void HideToast(const std::wstring& tag);

std::wstring TakeActivatedToastTag();

// Flashes the taskbar button until the window comes to the foreground.
void FlashUntilFocused(HWND window);

#endif  // RUNNER_NOTIFICATIONS_H_
