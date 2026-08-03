import os
import unittest
from datetime import datetime, timezone, timedelta
import user_config

class TestCreditsAndSubscription(unittest.TestCase):
    def setUp(self):
        self.test_user_id = 999888777
        # Clean up existing test entry if present
        if str(self.test_user_id) in user_config._configs:
            del user_config._configs[str(self.test_user_id)]
            user_config.save(user_config._configs)

    def tearDown(self):
        if str(self.test_user_id) in user_config._configs:
            del user_config._configs[str(self.test_user_id)]
            user_config.save(user_config._configs)

    def test_initial_credits(self):
        credits = user_config.get_user_credits(self.test_user_id)
        self.assertEqual(credits, 3, "New users should start with 3 free credits")
        self.assertFalse(user_config.is_subscription_active(self.test_user_id))

    def test_credit_deduction(self):
        self.assertTrue(user_config.deduct_credit(self.test_user_id))
        self.assertEqual(user_config.get_user_credits(self.test_user_id), 2)
        
        self.assertTrue(user_config.deduct_credit(self.test_user_id))
        self.assertEqual(user_config.get_user_credits(self.test_user_id), 1)

        self.assertTrue(user_config.deduct_credit(self.test_user_id))
        self.assertEqual(user_config.get_user_credits(self.test_user_id), 0)

        # 4th deduction attempt should fail
        self.assertFalse(user_config.deduct_credit(self.test_user_id))
        self.assertEqual(user_config.get_user_credits(self.test_user_id), 0)

    def test_subscription_grant(self):
        self.assertFalse(user_config.is_subscription_active(self.test_user_id))
        
        expiry_str = user_config.grant_subscription(self.test_user_id, days=30)
        self.assertTrue(user_config.is_subscription_active(self.test_user_id))
        
        # When sub is active, deduct_credit should always return True without reducing credits
        user_config.get_user_credits(self.test_user_id) # 3
        self.assertTrue(user_config.deduct_credit(self.test_user_id))
        self.assertEqual(user_config.get_user_credits(self.test_user_id), 3)

    def test_payment_submission_workflow(self):
        user_config.add_pending_payment(self.test_user_id, "TX123456", amount=500)
        cfg = user_config._configs[str(self.test_user_id)]
        payments = cfg.get("pending_payments", [])
        self.assertEqual(len(payments), 1)
        self.assertEqual(payments[0]["tx_id"], "TX123456")
        self.assertEqual(payments[0]["status"], "PENDING")

        user_config.update_payment_status(self.test_user_id, "TX123456", "APPROVED")
        payments = cfg.get("pending_payments", [])
        self.assertEqual(payments[0]["status"], "APPROVED")

if __name__ == "__main__":
    unittest.main()
