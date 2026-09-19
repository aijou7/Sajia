import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/scheduled_promotion.dart';
import '../app_database.dart';

/// Read-only local cache for owner-managed scheduled promos.
///
/// Promotions are never edited by the cashier app, so replacing one outlet's
/// cache with the authoritative Cloud response is safe and keeps deleted
/// promos from lingering on an offline device after its next sync.
class PromotionDao extends DatabaseAccessor<AppDatabase> {
  PromotionDao(super.db);

  final StreamController<void> _changes = StreamController<void>.broadcast();

  Stream<List<ScheduledPromotion>> watchPromotions(String outletId) async* {
    yield await getPromotions(outletId);
    await for (final _ in _changes.stream) {
      yield await getPromotions(outletId);
    }
  }

  Future<List<ScheduledPromotion>> getPromotions(String outletId) async {
    final rows = await customSelect(
      '''
      SELECT
        promotion.id AS promotion_id,
        promotion.outlet_id AS promotion_outlet_id,
        promotion.name AS promotion_name,
        promotion.start_time AS promotion_start_time,
        promotion.end_time AS promotion_end_time,
        promotion.active_days AS promotion_active_days,
        promotion.schedule_mode AS promotion_schedule_mode,
        promotion.start_date AS promotion_start_date,
        promotion.end_date AS promotion_end_date,
        promotion.is_active AS promotion_is_active,
        promotion.priority AS promotion_priority,
        promotion.updated_at AS promotion_updated_at,
        item.id AS item_id,
        item.promotion_id AS item_promotion_id,
        item.product_id AS item_product_id,
        item.promo_price AS item_promo_price
      FROM scheduled_promotions promotion
      LEFT JOIN scheduled_promotion_items item ON item.promotion_id = promotion.id
      WHERE promotion.outlet_id = ?
      ORDER BY promotion.priority DESC, promotion.updated_at DESC, promotion.id ASC, item.id ASC
      ''',
      variables: [Variable<String>(outletId)],
    ).get();
    return _mapPromotions(rows);
  }

  Future<void> replacePromotionsForOutlet({
    required String outletId,
    required List<Map<String, dynamic>> promotions,
    required List<Map<String, dynamic>> items,
  }) async {
    await transaction(() async {
      await customStatement(
        '''
        DELETE FROM scheduled_promotion_items
        WHERE promotion_id IN (
          SELECT id FROM scheduled_promotions WHERE outlet_id = ?
        )
        ''',
        [outletId],
      );
      await customStatement(
        'DELETE FROM scheduled_promotions WHERE outlet_id = ?',
        [outletId],
      );

      for (final promotion in promotions) {
        final id = promotion['id']?.toString();
        if (id == null || id.isEmpty) continue;
        await customStatement(
          '''
          INSERT INTO scheduled_promotions (
            id, outlet_id, name, start_time, end_time, active_days,
            schedule_mode, start_date, end_date,
            is_active, priority, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            id,
            outletId,
            promotion['name']?.toString() ?? 'Promo',
            _normaliseTime(promotion['start_time']?.toString()),
            _normaliseTime(promotion['end_time']?.toString()),
            _encodeWeekdays(promotion['active_days']),
            _normaliseScheduleMode(promotion['schedule_mode']?.toString()),
            _normaliseDate(promotion['start_date']?.toString()),
            _normaliseDate(promotion['end_date']?.toString()),
            promotion['is_active'] == false ? 0 : 1,
            _asInt(promotion['priority']),
            promotion['updated_at']?.toString() ??
                DateTime.now().toUtc().toIso8601String(),
          ],
        );
      }

      final knownPromotionIds = promotions
          .map((promotion) => promotion['id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final item in items) {
        final id = item['id']?.toString();
        final promotionId = item['promotion_id']?.toString();
        final productId = item['product_id']?.toString();
        if (id == null ||
            promotionId == null ||
            productId == null ||
            !knownPromotionIds.contains(promotionId)) {
          continue;
        }
        await customStatement(
          '''
          INSERT INTO scheduled_promotion_items (
            id, promotion_id, product_id, promo_price
          ) VALUES (?, ?, ?, ?)
          ''',
          [
            id,
            promotionId,
            productId,
            item['promo_price']?.toString() ?? '0',
          ],
        );
      }
    });
    _changes.add(null);
  }

  Future<void> deleteForOutletIds(Iterable<String> outletIds) async {
    for (final outletId in outletIds) {
      await customStatement(
        '''
        DELETE FROM scheduled_promotion_items
        WHERE promotion_id IN (
          SELECT id FROM scheduled_promotions WHERE outlet_id = ?
        )
        ''',
        [outletId],
      );
      await customStatement(
        'DELETE FROM scheduled_promotions WHERE outlet_id = ?',
        [outletId],
      );
    }
    _changes.add(null);
  }

  List<ScheduledPromotion> _mapPromotions(List<QueryRow> rows) {
    final byId = <String, _PromotionBuilder>{};
    for (final row in rows) {
      final id = row.read<String>('promotion_id');
      final builder = byId.putIfAbsent(
        id,
        () => _PromotionBuilder(
          id: id,
          outletId: row.read<String>('promotion_outlet_id'),
          name: row.read<String>('promotion_name'),
          startTime: _normaliseTime(row.read<String>('promotion_start_time')),
          endTime: _normaliseTime(row.read<String>('promotion_end_time')),
          activeWeekdays: _decodeWeekdays(row.read<String>('promotion_active_days')),
          scheduleMode: _normaliseScheduleMode(
            row.readNullable<String>('promotion_schedule_mode'),
          ),
          startDate: _parseDate(row.readNullable<String>('promotion_start_date')),
          endDate: _parseDate(row.readNullable<String>('promotion_end_date')),
          isActive: row.read<int>('promotion_is_active') != 0,
          priority: row.read<int>('promotion_priority'),
          updatedAt: DateTime.tryParse(row.read<String>('promotion_updated_at'))
                  ?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      final itemId = row.readNullable<String>('item_id');
      if (itemId == null) continue;
      builder.items.add(ScheduledPromotionItem(
        id: itemId,
        promotionId: row.read<String>('item_promotion_id'),
        productId: row.read<String>('item_product_id'),
        promoPrice: double.tryParse(row.read<String>('item_promo_price')) ?? 0,
      ));
    }
    return byId.values.map((builder) => builder.build()).toList();
  }
}

class _PromotionBuilder {
  _PromotionBuilder({
    required this.id,
    required this.outletId,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.activeWeekdays,
    required this.scheduleMode,
    required this.startDate,
    required this.endDate,
    required this.isActive,
    required this.priority,
    required this.updatedAt,
  });

  final String id;
  final String outletId;
  final String name;
  final String startTime;
  final String endTime;
  final Set<int> activeWeekdays;
  final String scheduleMode;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isActive;
  final int priority;
  final DateTime updatedAt;
  final List<ScheduledPromotionItem> items = [];

  ScheduledPromotion build() => ScheduledPromotion(
        id: id,
        outletId: outletId,
        name: name,
        startTime: startTime,
        endTime: endTime,
        activeWeekdays: activeWeekdays,
        scheduleMode: scheduleMode,
        startDate: startDate,
        endDate: endDate,
        isActive: isActive,
        priority: priority,
        updatedAt: updatedAt,
        items: List.unmodifiable(items),
      );
}

String _normaliseTime(String? value) {
  final raw = value?.trim() ?? '';
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(raw);
  if (match == null) return '00:00';
  final hour = int.tryParse(match.group(1)!) ?? 0;
  final minute = int.tryParse(match.group(2)!) ?? 0;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return '00:00';
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

String _normaliseScheduleMode(String? value) =>
    value?.trim().toUpperCase() == 'DATE_RANGE' ? 'DATE_RANGE' : 'WEEKLY';

String? _normaliseDate(String? value) {
  final parsed = _parseDate(value);
  if (parsed == null) return null;
  return '${parsed.year.toString().padLeft(4, '0')}-'
      '${parsed.month.toString().padLeft(2, '0')}-'
      '${parsed.day.toString().padLeft(2, '0')}';
}

DateTime? _parseDate(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(value.trim());
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}

String _encodeWeekdays(dynamic raw) {
  if (raw is String) {
    final decoded = _decodeWeekdays(raw);
    return jsonEncode(decoded.toList()..sort());
  }
  if (raw is Iterable) {
    final days = raw
        .map((value) => int.tryParse(value.toString()))
        .whereType<int>()
        .where((value) => value >= 1 && value <= 7)
        .toSet()
        .toList()
      ..sort();
    return jsonEncode(days);
  }
  return jsonEncode(const [1, 2, 3, 4, 5, 6, 7]);
}

Set<int> _decodeWeekdays(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Iterable) {
      final days = decoded
          .map((value) => int.tryParse(value.toString()))
          .whereType<int>()
          .where((value) => value >= 1 && value <= 7)
          .toSet();
      if (days.isNotEmpty) return days;
    }
  } catch (_) {
    // A malformed remote value must never activate a promotion.
  }
  return const <int>{};
}

int _asInt(dynamic value) => switch (value) {
      int number => number,
      num number => number.toInt(),
      _ => int.tryParse(value?.toString() ?? '') ?? 0,
    };
