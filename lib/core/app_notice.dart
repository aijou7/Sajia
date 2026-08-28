import 'dart:async';

import 'package:flutter/material.dart';

/// Menampilkan feedback singkat di atas seluruh tampilan aplikasi.
///
/// [SnackBar] tetap dipakai sebagai format input supaya warna, durasi, dan
/// aksi yang sudah ada di setiap fitur tidak perlu berubah. Berbeda dengan
/// ScaffoldMessenger, notifikasi ini dipasang ke root overlay sehingga tidak
/// tertutup oleh bottom sheet, dialog, atau navigasi bawah.
class AppNotice {
  AppNotice._();

  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;
  static int _noticeId = 0;

  static void show(BuildContext context, SnackBar snackBar) {
    final overlay = Overlay.of(context, rootOverlay: true);

    // Jika ada Snackbar lama dari transisi layar, jangan biarkan ia muncul
    // kembali di bawah setelah top notice terbaru sudah ditampilkan.
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    dismiss();

    final currentId = ++_noticeId;
    final entry = OverlayEntry(
      builder: (context) => _TopNotice(
        key: ValueKey('app-notice-$currentId'),
        snackBar: snackBar,
        onDismiss: () {
          if (currentId == _noticeId) dismiss();
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
    if (!snackBar.persist) {
      _dismissTimer = Timer(snackBar.duration, () {
        if (currentId == _noticeId) dismiss();
      });
    }
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _TopNotice extends StatelessWidget {
  const _TopNotice({
    super.key,
    required this.snackBar,
    required this.onDismiss,
  });

  final SnackBar snackBar;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snackBarTheme = theme.snackBarTheme;
    final colorScheme = theme.colorScheme;
    final backgroundColor = snackBar.backgroundColor ??
        snackBarTheme.backgroundColor ??
        colorScheme.inverseSurface;
    final contentStyle = snackBarTheme.contentTextStyle ??
        TextStyle(color: colorScheme.onInverseSurface);
    final action = snackBar.action;

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Semantics(
            container: true,
            liveRegion: true,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: 1),
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, -12 * (1 - value)),
                  child: child,
                ),
              ),
              child: Dismissible(
                key: key!,
                direction: DismissDirection.up,
                onDismissed: (_) => onDismiss(),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Material(
                    color: backgroundColor,
                    elevation: snackBar.elevation ?? snackBarTheme.elevation ?? 6,
                    clipBehavior: Clip.antiAlias,
                    shape: snackBar.shape ??
                        snackBarTheme.shape ??
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: DefaultTextStyle(
                              style: contentStyle,
                              child: snackBar.content,
                            ),
                          ),
                          if (action != null)
                            TextButton(
                              onPressed: () {
                                action.onPressed();
                                onDismiss();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    action.textColor ??
                                        snackBarTheme.actionTextColor ??
                                        contentStyle.color,
                              ),
                              child: Text(action.label),
                            ),
                          IconButton(
                            tooltip: 'Tutup notifikasi',
                            onPressed: onDismiss,
                            color: snackBar.closeIconColor ?? contentStyle.color,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
