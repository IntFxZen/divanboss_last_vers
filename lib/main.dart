import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color.fromRGBO(40, 40, 40, 100),
    ));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Divan BOSS',
      theme: ThemeData(useMaterial3: true),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late final WebViewController controller;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    NotificationService.startPolling();
  }

  @override
  void dispose() {
    NotificationService.stopPolling();
    super.dispose();
  }

  void _initializeWebView() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => isLoading = true),
          onPageFinished: (_) => setState(() => isLoading = false),
          onNavigationRequest: _handleNavigation,
        ),
      )
      ..loadRequest(Uri.parse('https://divanboss.ru/'));
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;

    if (uri.host != 'divanboss.ru' || request.url.startsWith('intent:')) {
      _launchExternal(request.url);
      return NavigationDecision.prevent;
    }

    if (uri.scheme == 'tg' || uri.scheme == 'vk') {
      _launchExternal(request.url);
      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  Future<void> _launchExternal(String url) async {
    final parsedUrl = url.replaceFirst('intent://', 'https://');
    final uri = Uri.parse(parsedUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<bool> _onWillPop() async {
    if (await controller.canGoBack()) {
      controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: controller),
            if (isLoading)
              const Center(
                child: CupertinoActivityIndicator(
                  color: Colors.black87,
                  radius: 16,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
