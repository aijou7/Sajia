import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme.dart';

class ProCheckoutPage extends StatefulWidget {
  final String checkoutUrl;
  final String successUrl;

  const ProCheckoutPage({
    super.key,
    required this.checkoutUrl,
    required this.successUrl,
  });

  @override
  State<ProCheckoutPage> createState() => _ProCheckoutPageState();
}

class _ProCheckoutPageState extends State<ProCheckoutPage> {
  late final WebViewController _controller;
  var _loading = true;

  bool _isAllowedNavigation(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (url.startsWith(widget.successUrl)) return true;
    return uri.scheme == 'https';
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            if (request.url.startsWith(widget.successUrl)) {
              Navigator.of(context).pop(true);
              return NavigationDecision.prevent;
            }
            if (!_isAllowedNavigation(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pembayaran Sajia'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: _controller.reload,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const LinearProgressIndicator(
              color: AppTheme.primary,
              backgroundColor: AppTheme.primaryLight,
            ),
        ],
      ),
    );
  }
}
