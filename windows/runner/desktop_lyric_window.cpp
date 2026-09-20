#include "desktop_lyric_window.h"

#include <algorithm>

namespace {

constexpr wchar_t kWindowClass[] = L"CAMELLIA_DESKTOP_LYRIC_WINDOW";

bool RegisterLyricWindowClass() {
  static bool registered = false;
  if (registered) return true;
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = DesktopLyricWindow::WindowProc;
  window_class.hInstance = GetModuleHandleW(nullptr);
  window_class.lpszClassName = kWindowClass;
  registered = RegisterClassW(&window_class) != 0;
  return registered;
}

}  // namespace

DesktopLyricWindow::DesktopLyricWindow(HWND player_window)
    : player_window_(player_window) {}

DesktopLyricWindow::~DesktopLyricWindow() {
  if (window_) DestroyWindow(window_);
}

bool DesktopLyricWindow::Show(const std::wstring& text) {
  if (text.empty()) {
    Hide();
    return true;
  }
  if (!window_) {
    if (!RegisterLyricWindowClass()) return false;
    window_ = CreateWindowExW(
        WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        kWindowClass, L"", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr,
        GetModuleHandleW(nullptr), this);
    if (!window_) return false;
    if (!SetLayeredWindowAttributes(window_, 0, 225, LWA_ALPHA)) {
      DestroyWindow(window_);
      window_ = nullptr;
      return false;
    }
  }

  text_ = text;
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfoW(MonitorFromWindow(player_window_, MONITOR_DEFAULTTOPRIMARY),
                       &monitor_info)) {
    return false;
  }
  const RECT work = monitor_info.rcWork;
  const UINT dpi = GetDpiForWindow(player_window_);
  const int scale = static_cast<int>(dpi ? dpi : 96);
  const int width = std::min<int>(MulDiv(1100, scale, 96),
                             work.right - work.left - MulDiv(32, scale, 96));
  const int height = std::min<int>(MulDiv(150, scale, 96),
                              (work.bottom - work.top) / 4);
  const int x = work.left + (work.right - work.left - width) / 2;
  const int y = work.bottom - height - MulDiv(70, scale, 96);
  if (!SetWindowPos(window_, HWND_TOPMOST, x, y, width, height,
                    SWP_NOACTIVATE | SWP_SHOWWINDOW)) {
    return false;
  }
  InvalidateRect(window_, nullptr, TRUE);
  return true;
}

void DesktopLyricWindow::Hide() {
  if (window_) ShowWindow(window_, SW_HIDE);
}

LRESULT CALLBACK DesktopLyricWindow::WindowProc(HWND window, UINT message,
                                                 WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  auto* self = reinterpret_cast<DesktopLyricWindow*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  switch (message) {
    case WM_NCHITTEST:
      return HTTRANSPARENT;
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_PAINT:
      if (self) self->Paint(window);
      return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

void DesktopLyricWindow::Paint(HWND window) {
  PAINTSTRUCT paint{};
  HDC dc = BeginPaint(window, &paint);
  RECT bounds{};
  GetClientRect(window, &bounds);
  HBRUSH background = CreateSolidBrush(RGB(34, 22, 29));
  FillRect(dc, &bounds, background);
  DeleteObject(background);

  const UINT dpi = GetDpiForWindow(window);
  HFONT font = CreateFontW(-MulDiv(27, dpi ? dpi : 96, 96), 0, 0, 0,
                           FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                           OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                           CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
  HGDIOBJ old_font = SelectObject(dc, font);
  SetTextColor(dc, RGB(255, 245, 248));
  SetBkMode(dc, TRANSPARENT);
  const int padding = MulDiv(24, dpi ? dpi : 96, 96);
  RECT text_bounds{padding, padding, bounds.right - padding,
                   bounds.bottom - padding};
  DrawTextW(dc, text_.c_str(), -1, &text_bounds,
            DT_CENTER | DT_VCENTER | DT_WORDBREAK | DT_NOPREFIX);
  SelectObject(dc, old_font);
  DeleteObject(font);
  EndPaint(window, &paint);
}
