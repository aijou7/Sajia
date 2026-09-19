import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/data/local/app_database.dart';
import 'package:pos_mobile/domain/scheduled_promotion.dart';

ScheduledPromotion _promotion({
  required String id,
  required DateTime updatedAt,
  int priority = 0,
  Set<int> weekdays = const {1, 2, 3, 4, 5, 6, 7},
  String scheduleMode = 'WEEKLY',
  DateTime? startDate,
  DateTime? endDate,
  bool active = true,
  double promoPrice = 15000,
}) =>
    ScheduledPromotion(
      id: id,
      outletId: 'outlet-1',
      name: id,
      startTime: '08:00',
      endTime: '11:00',
      activeWeekdays: weekdays,
      scheduleMode: scheduleMode,
      startDate: startDate,
      endDate: endDate,
      isActive: active,
      priority: priority,
      updatedAt: updatedAt,
      items: [
        ScheduledPromotionItem(
          id: '$id:item',
          promotionId: id,
          productId: 'kopi-susu',
          promoPrice: promoPrice,
        ),
      ],
    );

void main() {
  group('scheduled promotion pricing', () {
    test('uses the start boundary and excludes the end boundary', () {
      final promo = _promotion(id: 'morning', updatedAt: DateTime(2026));

      expect(
        resolveScheduledPromotion(
          promotions: [promo],
          productId: 'kopi-susu',
          basePrice: 20000,
          localNow: DateTime(2026, 9, 14, 8), // Monday
        ),
        isNotNull,
      );
      expect(
        resolveScheduledPromotion(
          promotions: [promo],
          productId: 'kopi-susu',
          basePrice: 20000,
          localNow: DateTime(2026, 9, 14, 11),
        ),
        isNull,
      );
    });

    test('never applies an inactive or price-increasing promo', () {
      final inactive = _promotion(
        id: 'off',
        updatedAt: DateTime(2026),
        active: false,
      );
      final higherPrice = _promotion(
        id: 'higher',
        updatedAt: DateTime(2026),
        promoPrice: 20000,
      );

      expect(
        resolveScheduledPromotion(
          promotions: [inactive, higherPrice],
          productId: 'kopi-susu',
          basePrice: 20000,
          localNow: DateTime(2026, 9, 14, 9),
        ),
        isNull,
      );
    });

    test('selects one deterministic promo when schedules overlap', () {
      final older = _promotion(
        id: 'older',
        updatedAt: DateTime(2026, 9, 10),
        promoPrice: 16000,
      );
      final newer = _promotion(
        id: 'newer',
        updatedAt: DateTime(2026, 9, 11),
        promoPrice: 15000,
      );
      final priority = _promotion(
        id: 'priority',
        updatedAt: DateTime(2026, 9, 1),
        priority: 1,
        promoPrice: 14000,
      );

      final match = resolveScheduledPromotion(
        promotions: [older, newer, priority],
        productId: 'kopi-susu',
        basePrice: 20000,
        localNow: DateTime(2026, 9, 14, 9),
      );

      expect(match?.promotion.id, 'priority');
      expect(match?.discountForBasePrice(20000), 6000);
    });

    test('date-range promo runs every day through the inclusive end date', () {
      final promo = _promotion(
        id: 'ten-days',
        updatedAt: DateTime(2026),
        scheduleMode: 'DATE_RANGE',
        startDate: DateTime(2026, 9, 20),
        endDate: DateTime(2026, 9, 29),
        weekdays: const {},
      );

      expect(
        resolveScheduledPromotion(
          promotions: [promo],
          productId: 'kopi-susu',
          basePrice: 20000,
          localNow: DateTime(2026, 9, 20, 9),
        ),
        isNotNull,
      );
      expect(
        resolveScheduledPromotion(
          promotions: [promo],
          productId: 'kopi-susu',
          basePrice: 20000,
          localNow: DateTime(2026, 9, 29, 10, 59),
        ),
        isNotNull,
      );
      expect(
        resolveScheduledPromotion(
          promotions: [promo],
          productId: 'kopi-susu',
          basePrice: 20000,
          localNow: DateTime(2026, 9, 30, 9),
        ),
        isNull,
      );
    });
  });

  test('promotion cache replaces an outlet atomically', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await database.promotionDao.replacePromotionsForOutlet(
      outletId: 'outlet-1',
      promotions: [
        {
          'id': 'promo-1',
          'name': 'Happy Hour Pagi',
          'start_time': '08:00:00',
          'end_time': '11:00:00',
          'active_days': [1, 2, 3, 4, 5],
          'schedule_mode': 'WEEKLY',
          'is_active': true,
          'priority': 0,
          'updated_at': '2026-09-12T00:00:00Z',
        },
      ],
      items: [
        {
          'id': 'promo-1:product-1',
          'promotion_id': 'promo-1',
          'product_id': 'product-1',
          'promo_price': 15000,
        },
      ],
    );

    var promotions = await database.promotionDao.getPromotions('outlet-1');
    expect(promotions, hasLength(1));
    expect(promotions.single.items.single.promoPrice, 15000);

    await database.promotionDao.replacePromotionsForOutlet(
      outletId: 'outlet-1',
      promotions: const [],
      items: const [],
    );
    promotions = await database.promotionDao.getPromotions('outlet-1');
    expect(promotions, isEmpty);
  });
}
