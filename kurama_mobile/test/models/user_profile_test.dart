import 'package:flutter_test/flutter_test.dart';
import 'package:kurama_mobile/models/user_profile.dart';

void main() {
  test('parses credits, PRO state, reward, and payment configuration', () {
    final profile = UserProfile.fromJson({
      'user_id': 91,
      'credits': 4,
      'is_subscription_active': true,
      'subscription_expires_at': '2026-09-01T00:00:00+00:00',
      'monthly_price_npr': 500,
      'daily_reward': 2,
      'payment_methods': {
        'esewa': '9800',
        'khalti': '9811',
        'bank': 'Kurama Bank 123',
      },
    });

    expect(profile.userId, 91);
    expect(profile.isPro, isTrue);
    expect(profile.dailyReward, 2);
    expect(profile.paymentMethods['khalti'], '9811');
  });
}
