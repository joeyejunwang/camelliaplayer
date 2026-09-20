#include "desktop_lyric_window.h"

#include <algorithm>
#include <windowsx.h>

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
  const bool first_show = window_ == nullptr;
  if (first_show) {
    if (!RegisterLyricWindowClass()) return false;
    window_ = CreateWindowExW(
        WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        kWindowClass, L"", WS_POPUP | WS_THICKFRAME, 0, 0, 0, 0, nullptr, nullptr,
        GetModuleHandleW(nullptr), this);
    if (!window_) return false;
    if (!SetLayeredWindowAttributes(window_, 0, 225, LWA_ALPHA)) {
      DestroyWindow(window_);
      window_ = nullptr;
      return false;
    }
  }

  text_ = text;
  if (first_show) {
    MONITORINFO monitor_info{};
    monitor_info.cbSize = sizeof(monitor_info);
    if (!GetMonitorInfoW(
            MonitorFromWindow(player_window_, MONITOR_DEFAULTTOPRIMARY),
            &monitor_info)) {
      return false;
    }
    const RECT work = monitor_info.rcWork;
    const UINT dpi = GetDpiForWindow(player_window_);
    const int scale = static_cast<int>(dpi ? dpi : 96);
    const int width = std::min<int>(
        MulDiv(1100, scale, 96),
        work.right - work.left - MulDiv(32, scale, 96));
    const int height = std::min<int>(MulDiv(150, scale, 96),
                                     (work.bottom - work.top) / 4);
    const int x = work.left + (work.right - work.left - width) / 2;
    const int y = work.bottom - height - MulDiv(70, scale, 96);
    if (!SetWindowPos(window_, HWND_TOPMOST, x, y, width, height,
                      SWP_NOACTIVATE | SWP_SHOWWINDOW)) {
      return false;
    }
  } else if (!SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0,
                           SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                               SWP_SHOWWINDOW)) {
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
    case WM_NCCALCSIZE:
      if (wparam) return 0;
      break;
    case WM_NCHITTEST: {
      RECT bounds{};
      GetWindowRect(window, &bounds);
      const UINT dpi = GetDpiForWindow(window);
      const int border = MulDiv(10, dpi ? dpi : 96, 96);
      const int x = GET_X_LPARAM(lparam);
      const int y = GET_Y_LPARAM(lparam);
      const bool left = x < bounds.left + border;
      const bool right = x >= bounds.right - border;
      const bool top = y < bounds.top + border;
      const bool bottom = y >= bounds.bottom - border;
      if (top && left) return HTTOPLEFT;
      if (top && right) return HTTOPRIGHT;
      if (bottom && left) return HTBOTTOMLEFT;
      if (bottom && right) return HTBOTTOMRIGHT;
      if (left) return HTLEFT;
      if (right) return HTRIGHT;
      if (top) return HTTOP;
      if (bottom) return HTBOTTOM;
      return HTCAPTION;
    }
    case WM_GETMINMAXINFO: {
      auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
      const UINT dpi = GetDpiForWindow(window);
      limits->ptMinTrackSize.x = MulDiv(240, dpi ? dpi : 96, 96);
      limits->ptMinTrackSize.y = MulDiv(60, dpi ? dpi : 96, 96);
      return 0;
    }
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
  HBRUSH outline = CreateSolidBrush(RGB(86, 57, 69));
  FrameRect(dc, &bounds, outline);
  DeleteObject(outline);

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
  HPEN grip = CreatePen(PS_SOLID, 1, RGB(188, 123, 143));
  HGDIOBJ old_pen = SelectObject(dc, grip);
  for (int offset = 0; offset < 3; ++offset) {
    const int inset = padding / 3 + offset * 5;
    MoveToEx(dc, bounds.right - inset - 8, bounds.bottom - 5, nullptr);
    LineTo(dc, bounds.right - 5, bounds.bottom - inset - 8);
  }
  SelectObject(dc, old_pen);
  DeleteObject(grip);
  SelectObject(dc, old_font);
  DeleteObject(font);
  EndPaint(window, &paint);
}
