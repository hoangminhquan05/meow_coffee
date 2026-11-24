import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../providers/cart_provider.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meow_ui.dart';
import '../auth/register_screen.dart' show VerifyAccountArgs;

/// Tài khoản cho khách và shipper: thông tin, xác minh, đổi SĐT,
/// sửa thông tin, đổi mật khẩu, đăng xuất.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final cart = context.read<CartProvider>();
    final session = context.read<SessionProvider>();
    final navigator = Navigator.of(context);
    final ok = await showMeowConfirmDialog(
      context,
      title: 'Đăng xuất',
      message: 'Bạn có chắc muốn đăng xuất?',
      confirmLabel: 'Đăng xuất',
      icon: Icons.logout_rounded,
    );
    if (!ok) return;
    await session.signOut();
    cart.clear();
    navigator.pushNamedAndRemoveUntil('/login', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final user = session.user;
    if (user == null) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator(color: AppColors.brand)),
      );
    }
    final isCustomer = user.role == UserRole.customer;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: user.avtUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: user.avtUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => Image.asset(
                                'assets/images/user_df.jpg',
                                fit: BoxFit.cover),
                          )
                        : Image.asset('assets/images/user_df.jpg',
                            fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(user.role.label,
                          style: const TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (isCustomer && !user.isVerified)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: AppColors.warning),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Xác minh SĐT hoặc email để đặt đơn online.',
                        style: TextStyle(color: AppColors.warning),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/verify_account'),
                      child: const Text('Xác minh'),
                    ),
                  ],
                ),
              ),
            MeowCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.mail_outline_rounded,
                    label: 'Email',
                    value: user.email,
                    verified: isCustomer ? user.emailVerified : null,
                  ),
                  const Divider(height: 1),
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Số điện thoại',
                    value: user.phone.isEmpty ? 'Chưa có' : user.phone,
                    verified: isCustomer ? user.phoneVerified : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _Action(
              icon: Icons.edit_outlined,
              title: 'Sửa thông tin',
              onTap: () => Navigator.pushNamed(context, '/editUserInfo',
                  arguments: user.uid),
            ),
            if (isCustomer) ...[
              _Action(
                icon: Icons.location_on_outlined,
                title: 'Sổ địa chỉ',
                subtitle: 'Tối đa 3 địa chỉ giao hàng',
                onTap: () => Navigator.pushNamed(context, '/addresses'),
              ),
              // Xác minh được cả SĐT lẫn email, mục nào chưa xong thì hiện mục đó.
              if (!user.phoneVerified || !user.emailVerified)
                _Action(
                  icon: Icons.verified_user_outlined,
                  title: !user.phoneVerified && !user.emailVerified
                      ? 'Xác minh tài khoản'
                      : !user.phoneVerified
                          ? 'Xác minh số điện thoại'
                          : 'Xác minh email',
                  subtitle: user.isVerified
                      ? 'Không bắt buộc – đã đặt đơn được'
                      : 'Cần xác minh trước khi đặt đơn',
                  onTap: () => Navigator.pushNamed(context, '/verify_account'),
                ),
              _Action(
                icon: Icons.phone_iphone_rounded,
                title: 'Đổi số điện thoại',
                subtitle: 'Cần mã OTP gửi tới số mới',
                onTap: () => Navigator.pushNamed(
                  context,
                  '/verify_account',
                  arguments: const VerifyAccountArgs(changePhone: true),
                ),
              ),
            ],
            _Action(
              icon: Icons.lock_outline_rounded,
              title: 'Đổi mật khẩu',
              onTap: () => Navigator.pushNamed(context, '/change_password'),
            ),
            _Action(
              icon: Icons.logout_rounded,
              title: 'Đăng xuất',
              danger: true,
              onTap: () => _logout(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  /// null = không hiện trạng thái xác minh.
  final bool? verified;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.verified,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (verified != null)
            Text(
              verified! ? 'Đã xác minh' : 'Chưa xác minh',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: verified! ? AppColors.success : AppColors.warning,
              ),
            ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool danger;
  final VoidCallback onTap;

  const _Action({
    required this.icon,
    required this.title,
    this.subtitle,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.inkSlate;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MeowCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: danger ? AppColors.danger : AppColors.brand),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: color)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color),
          ],
        ),
      ),
    );
  }
}
