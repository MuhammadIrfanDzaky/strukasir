import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Notifikasi singkat (berhasil / gagal) di kanan atas, di atas semua halaman & dialog.
/// API-nya meniru ScaffoldMessenger (`AppToast.of(context).showSnackBar(SnackBar(...))`) supaya
/// pemanggil cukup ganti `ScaffoldMessenger` → `AppToast`; isi, aksi & durasi SnackBar dipakai apa adanya.
/// Satu toast sekaligus: toast baru menggantikan yang lama.
class AppToast {
  AppToast._(this._overlay);

  final OverlayState _overlay;

  static OverlayEntry? _entry;

  static AppToast of(BuildContext context) => AppToast._(Overlay.of(context, rootOverlay: true));

  void showSnackBar(SnackBar bar) {
    hideCurrentSnackBar();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Toast(
        content: bar.content,
        action: bar.action,
        duration: bar.duration,
        onClose: () {
          if (_entry == entry) hideCurrentSnackBar();
        },
      ),
    );
    _entry = entry;
    _overlay.insert(entry);
  }

  void hideCurrentSnackBar() {
    final e = _entry;
    _entry = null;
    if (e != null && e.mounted) e.remove();
  }
}

/// Pesan yang terbaca sebagai kegagalan → garis merah di kiri (warna status saja, tanpa ikon).
final _failure = RegExp(r'gagal|tidak bisa|tidak dapat|salah|ditolak|error|kesalahan|belum', caseSensitive: false);

class _Toast extends StatefulWidget {
  const _Toast({required this.content, required this.onClose, required this.duration, this.action});

  final Widget content;
  final Duration duration;
  final SnackBarAction? action;
  final VoidCallback onClose;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))..forward();

  /// Timer milik toast ini: ikut batal saat toast dilepas (tidak menggantung setelah layar ditutup).
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onClose);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = (mq.size.width - AppSpace.s4 * 2).clamp(0.0, 400.0);
    final c = widget.content;
    final failed = c is Text && _failure.hasMatch(c.data ?? '');
    final action = widget.action;
    return Positioned(
      top: mq.padding.top + AppSpace.s4,
      right: AppSpace.s4,
      width: width,
      child: FadeTransition(
        opacity: _anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut)),
          child: Semantics(
            liveRegion: true,
            child: Material(
              color: AppColors.ink,
              elevation: 6,
              borderRadius: AppRadius.mdAll,
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: failed ? AppColors.danger : AppColors.ink, width: 4)),
                ),
                padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s2, AppSpace.s1, AppSpace.s2),
                child: Row(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.s1),
                      child: DefaultTextStyle.merge(style: AppType.body.copyWith(color: AppColors.onInk), child: c),
                    ),
                  ),
                  if (action != null)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: AppColors.primaryOnDark, backgroundColor: AppColors.onInk.withValues(alpha: 0.1)),
                      onPressed: () {
                        widget.onClose();
                        action.onPressed();
                      },
                      child: Text(action.label),
                    ),
                  IconButton(
                    tooltip: 'Tutup',
                    visualDensity: VisualDensity.compact,
                    color: AppColors.onInkMuted,
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
