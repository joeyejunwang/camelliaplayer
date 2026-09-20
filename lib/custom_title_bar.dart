import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

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

    final textColor = cs.onSurface;
    final btnHover = cs.onSurface.withValues(alpha: 0.08);
    final closeHover = cs.primary;

    return GestureDetector(
      onPanStart: (_) => _handleDrag(),
      onDoubleTap: _handleDoubleTap,
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            const SizedBox(width: 32),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primary.withValues(alpha: 0.6), cs.primary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.23),
                    blurRadius: 9,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.play_arrow_rounded, size: 17, color: Colors.white),
            ),
            const SizedBox(width: 14),
            // Title
            Text(
              'Camellia Player',
              style: TextStyle(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.5,
              ),
            ),
            const Spacer(),
            _WindowButton(
              icon: Icons.remove,
              tooltip: 'Minimize',
              hoverColor: btnHover,
              iconColor: textColor,
              onTap: () => windowManager.minimize(),
            ),
            const SizedBox(width: 12),
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
            width: 52,
            height: 48,
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
