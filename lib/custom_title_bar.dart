import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_colors.dart';

/// Custom window title bar that replaces the native Windows chrome.
class CustomTitleBar extends StatefulWidget {
  const CustomTitleBar({super.key, required this.onClose});

  final Future<void> Function() onClose;

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
    final cs = theme.colorScheme;

    // Pull all colors from the themed scheme so the title bar follows
    // the camellia palette instead of being a hardcoded gray strip.
    final bgColor = cs.surface;
    final textColor = cs.onSurface;
    final btnHover = cs.onSurface.withValues(alpha: 0.08);
    final closeHover = AppColors.camelliaDeep;

    return GestureDetector(
      onPanStart: (_) => _handleDrag(),
      onDoubleTap: _handleDoubleTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            // Real app icon — same image used on the home screen header.
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/branding/camellia_player_icon_1024.png',
                width: 22,
                height: 22,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            // Title
            Text(
              'Camellia Player',
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
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
              icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
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
              onTap: () async {
                await widget.onClose();
                await windowManager.close();
              },
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
