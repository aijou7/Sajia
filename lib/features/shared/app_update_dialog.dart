import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_update_service.dart';

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.info,
    required this.service,
  });

  final AppUpdateInfo info;
  final AppUpdateService service;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  File? _downloadedFile;
  double _progress = 0;
  bool _busy = false;
  bool _needsPermission = false;
  String? _error;

  Future<void> _downloadOrInstall() async {
    if (_busy) return;
    if (_downloadedFile != null) {
      await _install();
      return;
    }
    if (!await widget.service.canRequestPackageInstalls()) {
      setState(() {
        _needsPermission = true;
        _error = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final file = await widget.service.downloadAndVerify(
        widget.info,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadedFile = file;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _install() async {
    final file = _downloadedFile;
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.installApk(file);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openPermissionSettings() async {
    await widget.service.openInstallPermissionSettings();
    if (!mounted) return;
    final allowed = await widget.service.canRequestPackageInstalls();
    setState(() {
      _needsPermission = !allowed;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final canDismiss = !info.isMandatory && !_busy;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.system_update_alt_rounded),
          const SizedBox(width: 10),
          Expanded(child: Text('Kasata ${info.latestVersion} tersedia')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info.isMandatory
                  ? 'Pembaruan ini diperlukan agar Kasata tetap dapat digunakan.'
                  : 'Versi baru sudah siap dengan perbaikan dan fitur terbaru.',
            ),
            if (info.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(info.releaseNotes),
            ],
            if (_needsPermission) ...[
              const SizedBox(height: 16),
              const Text(
                'Izinkan Kasata memasang update dari sumber ini satu kali di Pengaturan Android.',
              ),
            ],
            if (_busy && _downloadedFile == null) ...[
              const SizedBox(height: 18),
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              const SizedBox(height: 8),
              Text('${(_progress * 100).round()}% mengunduh update'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (canDismiss)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Nanti'),
          ),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : _needsPermission
                  ? _openPermissionSettings
                  : _downloadOrInstall,
          icon: Icon(
            _needsPermission
                ? Icons.settings_outlined
                : _downloadedFile == null
                    ? Icons.download_rounded
                    : Icons.install_mobile_rounded,
          ),
          label: Text(
            _needsPermission
                ? 'Buka izin'
                : _downloadedFile == null
                    ? 'Download update'
                    : 'Install sekarang',
          ),
        ),
      ],
    );
  }
}
