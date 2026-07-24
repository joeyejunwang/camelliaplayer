import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Custom window title bar that replaces the native Windows chrome.
class CustomTitleBar extends StatefulWidget {
  const CustomTitleBar({super.key});

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _init();
  }

  Future<void> _init() async {
    _isMaximized = await windowManager.isMaximized();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  void _handleDrag() {
    if (_isMaximized) {
      windowManager.unmaximize();
    }
    windowManager.startDragging();
  }

  void _handleDoubleTap() {
    if (_isMaximized) {
      windowManager.unmaximize();
    } else {
      windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Colours per theme brightness
    final bgColor = isDark
        ? const Color(0xFF1C1B1F)
        : const Color(0xFFF6F2F4);
    final textColor = isDark ? Colors.white : const Color(0xFF1C1B1F);
    final btnHover = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final closeHover = isDark
        ? const Color(0xFFE81123)
        : const Color(0xFFE81123);

    return GestureDetector(
      onPanStart: (_) => _handleDrag(),
      onDoubleTap: _handleDoubleTap,
      child: Container(
        height: 40,
        color: bgColor,
        child: Row(
          children: [
            const SizedBox(width: 12),
            // App icon
            Icon(
              Icons.play_circle_fill_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            // Title
            Text(
              'Camellia Player',
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            // ── Window control buttons ────────────────────────────────────
            _WindowButton(
              icon: Icons.remove,
              tooltip: 'Minimize',
              hoverColor: btnHover,
              iconColor: textColor,
              onTap: () => windowManager.minimize(),
            ),
            _WindowButton(
              icon: _isMaximized
                  ? Icons.filter_none
                  : Icons.crop_square,
              tooltip: _isMaximized ? 'Restore' : 'Maximize',
              hoverColor: btnHover,
              iconColor: textColor,
              onTap: () async {
                if (_isMaximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            _WindowButton(
              icon: Icons.close,
              tooltip: 'Close',
              hoverColor: closeHover,
              hoverIconColor: Colors.white,
              onTap: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.hoverColor,
    required this.onTap,
    this.iconColor,
    this.hoverIconColor,
  });

  final IconData icon;
  final String tooltip;
  final Color hoverColor;
  final Color? iconColor;
  final Color? hoverIconColor;
  final VoidCallback onTap;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isClose = widget.tooltip == 'Close';
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: 40,
            color: _isHovered ? widget.hoverColor : Colors.transparent,
            child: Icon(
              widget.icon,
              size: 16,
              color: _isHovered && (widget.hoverIconColor != null || isClose)
                  ? (widget.hoverIconColor ?? widget.hoverColor)
                  : widget.iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
