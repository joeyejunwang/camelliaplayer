#ifndef RUNNER_DESKTOP_LYRIC_WINDOW_H_
#define RUNNER_DESKTOP_LYRIC_WINDOW_H_

#include <windows.h>

#include <string>

// A non-activating caption that can be dragged and resized above other windows.
class DesktopLyricWindow {
 public:
  explicit DesktopLyricWindow(HWND player_window);
  ~DesktopLyricWindow();

  bool Show(const std::wstring& text);
  void Hide();
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam);

 private:
  void Paint(HWND window);

  HWND player_window_;
  HWND window_ = nullptr;
  std::wstring text_;
};

#endif  // RUNNER_DESKTOP_LYRIC_WINDOW_H_
