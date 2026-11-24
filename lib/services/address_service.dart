import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_paths.dart';
import '../models/address.dart';

/// Sổ địa chỉ của khách: `users/{uid}/addresses`.
class AddressService {
  AddressService._();

  static CollectionReference<Map<String, dynamic>> _col(String uid) =>
      FirebaseFirestore.instance
          .collection(FsCollections.users)
          .doc(uid)
          .collection('addresses');

  /// Mặc định lên đầu, còn lại mới nhất trước.
  static Stream<List<Address>> watch(String uid) =>
      _col(uid).snapshots().map((s) {
        final list = s.docs.map(Address.fromDoc).whereType<Address>().toList()
          ..sort((a, b) {
            if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
            final ta = a.createdAt ?? DateTime(2100);
            final tb = b.createdAt ?? DateTime(2100);
            return tb.compareTo(ta);
          });
        return list;
      });

  /// Thêm địa chỉ. Địa chỉ đầu tiên hoặc `makeDefault` → thành mặc định.
  static Future<void> add(
    String uid,
    Address address, {
    required bool makeDefault,
  }) async {
    final existing = await _col(uid).get();
    if (existing.size >= Address.maxPerUser) {
      throw StateError('Chỉ lưu tối đa ${Address.maxPerUser} địa chỉ');
    }
    final isDefault = makeDefault || existing.size == 0;
    final batch = FirebaseFirestore.instance.batch();
    if (isDefault) {
      for (final d in existing.docs) {
        if (d.data()['is_default'] == true) {
          batch.update(d.reference, {'is_default': false});
        }
      }
    }
    batch.set(_col(uid).doc(), {
      ...address.toMap(),
      'is_default': isDefault,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  static Future<void> update(
    String uid,
    Address address, {
    required bool makeDefault,
  }) async {
    final batch = FirebaseFirestore.instance.batch();
    if (makeDefault && !address.isDefault) {
      final existing = await _col(uid).where('is_default', isEqualTo: true).get();
      for (final d in existing.docs) {
        batch.update(d.reference, {'is_default': false});
      }
    }
    batch.update(_col(uid).doc(address.id), {
      ...address.toMap(),
      if (makeDefault) 'is_default': true,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  static Future<void> setDefault(String uid, String addressId) async {
    final all = await _col(uid).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final d in all.docs) {
      final shouldBe = d.id == addressId;
      if ((d.data()['is_default'] == true) != shouldBe) {
        batch.update(d.reference, {'is_default': shouldBe});
      }
    }
    await batch.commit();
  }

  /// Xóa; nếu là mặc định thì địa chỉ mới nhất còn lại thành mặc định.
  static Future<void> delete(String uid, Address address) async {
    final batch = FirebaseFirestore.instance.batch()
      ..delete(_col(uid).doc(address.id));
    if (address.isDefault) {
      final rest = (await _col(uid).get())
          .docs
          .where((d) => d.id != address.id)
          .toList()
        ..sort((a, b) {
          final ta = a.data()['created_at'];
          final tb = b.data()['created_at'];
          if (ta is! Timestamp || tb is! Timestamp) return 0;
          return tb.compareTo(ta);
        });
      if (rest.isNotEmpty) {
        batch.update(rest.first.reference, {'is_default': true});
      }
    }
    await batch.commit();
  }
}
