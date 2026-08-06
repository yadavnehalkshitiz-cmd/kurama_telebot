class UserProfile {
  final int userId;
  final int credits;
  final bool isPro;
  final DateTime? subscriptionExpiresAt;
  final int monthlyPriceNpr;
  final int dailyReward;
  final Map<String, String> paymentMethods;

  const UserProfile({
    required this.userId,
    required this.credits,
    required this.isPro,
    required this.subscriptionExpiresAt,
    required this.monthlyPriceNpr,
    required this.dailyReward,
    required this.paymentMethods,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final rawMethods = json['payment_methods'] as Map<String, dynamic>? ?? {};
    return UserProfile(
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      credits: (json['credits'] as num?)?.toInt() ?? 0,
      isPro: json['is_subscription_active'] as bool? ?? false,
      subscriptionExpiresAt:
          DateTime.tryParse(json['subscription_expires_at'] as String? ?? ''),
      monthlyPriceNpr: (json['monthly_price_npr'] as num?)?.toInt() ?? 0,
      dailyReward: (json['daily_reward'] as num?)?.toInt() ?? 2,
      paymentMethods: rawMethods.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      ),
    );
  }
}
