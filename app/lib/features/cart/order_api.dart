import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../session/session_controller.dart';
import 'cart_controller.dart';

final orderApiProvider = Provider((ref) => OrderApi(ref));

class PaymentDraft {
  PaymentDraft({required this.method, required this.amount, this.tendered}) : id = const Uuid().v4();

  /// UUID dibuat sekali per draf → tombol "Bayar" ditekan ulang tidak membuat pembayaran dobel.
  final String id;
  final String method; // cash | debit | qris
  final int amount;
  final int? tendered;

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'amount': amount,
        if (method == 'cash') 'tendered': tendered ?? amount,
      };
}

class Approval {
  const Approval(this.userId, this.pin);

  final String userId;
  final String pin;
}

/// Order sebagai JSON mentah dari server (OrderResource) — juga sumber data untuk struk.
typedef OrderJson = Map<String, dynamic>;

class OrderApi {
  OrderApi(this._ref);

  final Ref _ref;

  SessionController get _session => _ref.read(sessionProvider.notifier);

  /// Simpan isi keranjang sebagai order terbuka (idempotent per `cart.orderId`).
  Future<OrderJson> save(CartState cart, int expectedTotal, {Approval? approval}) async {
    final res = await _session.authed((api, token) => api.put('/orders/${cart.orderId}',
        token: token,
        data: {
          ...cart.toJson(expectedTotal),
          if (approval != null) 'approval': {'user_id': approval.userId, 'pin': approval.pin},
        }));
    return res['data'] as OrderJson;
  }

  Future<OrderJson> pay(String orderId, List<PaymentDraft> payments, int expectedTotal) async {
    final res = await _session.authed((api, token) => api.post('/orders/$orderId/pay',
        token: token,
        data: {'expected_total': expectedTotal, 'payments': payments.map((p) => p.toJson()).toList()}));
    return res['data'] as OrderJson;
  }

  Future<List<OrderJson>> openOrders() async {
    final res = await _session.authed((api, token) => api.get('/orders?status=open&per_page=50', token: token));
    return (res['data'] as List).cast<OrderJson>();
  }

  Future<OrderJson> get(String orderId) async {
    final res = await _session.authed((api, token) => api.get('/orders/$orderId', token: token));
    return res['data'] as OrderJson;
  }
}
