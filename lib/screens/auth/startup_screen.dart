import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';

/// Màn đầu tiên khi mở app (kể cả F5 trên web): chờ Firebase cho biết còn
/// phiên đăng nhập không và nạp hồ sơ, rồi vào thẳng trang chủ đúng vai trò
/// (khách / shipper / nhân viên – admin) hoặc màn đăng nhập.
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  Future<void> _go() async {
    final route = await context.read<SessionProvider>().startRoute();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('☕', style: TextStyle(fontSize: 48)),
            SizedBox(height: 8),
            Text(
              'Meow Coffee',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.inkSlate,
              ),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(color: AppColors.brand),
          ],
        ),
      ),
    );
  }
}
