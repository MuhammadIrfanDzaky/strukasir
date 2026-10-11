import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../cart/cart_controller.dart';
import '../menu/menu_models.dart';
import 'loyalty_models.dart';

/// Pilih hadiah untuk ditukar dengan saldo member. Hadiah gratis produk butuh produknya ada di
/// keranjang (porsi pertama yang cocok digratiskan). Mengembalikan (hadiah, id baris) atau null.
Future<(LoyaltyReward, String?)?> pickReward(
  BuildContext context, {
  required LoyaltyProgram program,
  required int balance,
  required CartState cart,
  required Menu menu,
}) =>
    showDialog<(LoyaltyReward, String?)>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Tukar hadiah'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Saldo ${cart.customer?.name ?? 'member'}: $balance ${program.unit} ${program.name}',
                  style: AppType.body.copyWith(color: AppColors.inkMuted)),
              const SizedBox(height: AppSpace.s3),
              for (final r in program.rewards) _RewardTile(reward: r, program: program, balance: balance, cart: cart, menu: menu),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
      ),
    );

class _RewardTile extends StatelessWidget {
  const _RewardTile({required this.reward, required this.program, required this.balance, required this.cart, required this.menu});

  final LoyaltyReward reward;
  final LoyaltyProgram program;
  final int balance;
  final CartState cart;
  final Menu menu;

  @override
  Widget build(BuildContext context) {
    final product = reward.productId == null ? null : menu.product(reward.productId!);
    // Porsi yang digratiskan: baris produk itu yang belum didiskon, atau baris pertama.
    final matching = cart.lines.where((l) => l.product.id == reward.productId).toList();
    final line = matching.where((l) => l.discount == null).firstOrNull ?? matching.firstOrNull;
    final short = balance < reward.cost;
    final missing = reward.isFreeProduct && line == null;

    final String? blocker = short
        ? 'Kurang ${reward.cost - balance} ${program.unit}'
        : missing
            ? 'Tambahkan ${product?.name ?? 'produknya'} ke keranjang dulu'
            : null;

    final effect = reward.effect(product?.name);
    final details = [if (effect != reward.name) effect, ?blocker].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.s2),
      child: ListTile(
        enabled: blocker == null,
        onTap: blocker == null ? () => Navigator.pop(context, (reward, line?.id)) : null,
        title: Text(reward.name, style: AppType.bodyStrong),
        subtitle: details.isEmpty
            ? null
            : Text(details, style: AppType.caption.copyWith(color: blocker == null ? AppColors.inkMuted : AppColors.warning)),
        trailing: AppBadge('${reward.cost} ${program.unit}', tone: blocker == null ? AppTone.brand : AppTone.neutral),
      ),
    );
  }
}
