/// A price override that applies to selected menu items at a recurring local
/// day and time. Weekdays use [DateTime.weekday]: Monday is 1, Sunday is 7.
class ScheduledPromotion {
  const ScheduledPromotion({
    required this.id,
    required this.outletId,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.activeWeekdays,
    required this.isActive,
    required this.priority,
    required this.updatedAt,
    required this.items,
  });

  final String id;
  final String outletId;
  final String name;
  final String startTime;
  final String endTime;
  final Set<int> activeWeekdays;
  final bool isActive;
  final int priority;
  final DateTime updatedAt;
  final List<ScheduledPromotionItem> items;

  /// A schedule uses the local time on the cashier device. The editor only
  /// allows same-day windows, so [endTime] is always later than [startTime].
  bool isActiveAt(DateTime localNow) {
    if (!isActive || !activeWeekdays.contains(localNow.weekday)) return false;
    final startMinutes = _minutesSinceMidnight(startTime);
    final endMinutes = _minutesSinceMidnight(endTime);
    if (startMinutes == null || endMinutes == null || endMinutes <= startMinutes) {
      return false;
    }
    final nowMinutes = localNow.hour * 60 + localNow.minute;
    return nowMinutes >= startMinutes && nowMinutes < endMinutes;
  }

  ScheduledPromotionItem? itemForProduct(String productId) {
    for (final item in items) {
      if (item.productId == productId) return item;
    }
    return null;
  }
}

class ScheduledPromotionItem {
  const ScheduledPromotionItem({
    required this.id,
    required this.promotionId,
    required this.productId,
    required this.promoPrice,
  });

  final String id;
  final String promotionId;
  final String productId;
  final double promoPrice;
}

/// The single promotion selected for an item at checkout.
///
/// We intentionally choose one schedule rather than stacking discounts. When
/// an owner creates overlapping schedules, the higher priority wins; if their
/// priorities match, the most recently saved schedule wins deterministically.
class ScheduledPromotionMatch {
  const ScheduledPromotionMatch({
    required this.promotion,
    required this.item,
  });

  final ScheduledPromotion promotion;
  final ScheduledPromotionItem item;

  double discountForBasePrice(double basePrice) {
    if (!basePrice.isFinite || basePrice <= item.promoPrice) return 0;
    return basePrice - item.promoPrice;
  }
}

ScheduledPromotionMatch? resolveScheduledPromotion({
  required Iterable<ScheduledPromotion> promotions,
  required String productId,
  required double basePrice,
  required DateTime localNow,
}) {
  if (!basePrice.isFinite || basePrice < 0) return null;

  final candidates = <ScheduledPromotionMatch>[];
  for (final promotion in promotions) {
    if (!promotion.isActiveAt(localNow)) continue;
    final item = promotion.itemForProduct(productId);
    if (item == null || !item.promoPrice.isFinite || item.promoPrice >= basePrice) {
      continue;
    }
    candidates.add(ScheduledPromotionMatch(promotion: promotion, item: item));
  }
  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    final priority = b.promotion.priority.compareTo(a.promotion.priority);
    if (priority != 0) return priority;
    final updatedAt = b.promotion.updatedAt.compareTo(a.promotion.updatedAt);
    if (updatedAt != 0) return updatedAt;
    return a.promotion.id.compareTo(b.promotion.id);
  });
  return candidates.first;
}

int? _minutesSinceMidnight(String raw) {
  final parts = raw.trim().split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}
