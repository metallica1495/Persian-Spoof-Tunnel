import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("panel_app", Path(__file__).with_name("app.py"))
APP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(APP)


class PanelTests(unittest.TestCase):
    def test_service_state_translation(self):
        self.assertEqual(APP.translate_state("active"), "فعال")
        self.assertEqual(APP.translate_state("inactive"), "متوقف")
        self.assertEqual(APP.translate_state(""), "نامشخص")

    def test_page_escapes_title(self):
        rendered = APP.page("<script>alert(1)</script>", "<p>داشبورد</p>")
        self.assertNotIn("<title><script>", rendered)
        self.assertIn("&lt;script&gt;", rendered)
        self.assertIn('lang="fa" dir="rtl"', rendered)

    def test_verify_valid_and_invalid_password(self):
        password = "a-very-long-test-password"
        salt = b"0123456789abcdef"
        digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, APP.ITERATIONS)
        with tempfile.TemporaryDirectory() as tmp:
            auth = Path(tmp) / "auth.json"
            auth.write_text(json.dumps({
                "username": "admin",
                "salt": salt.hex(),
                "hash": digest.hex(),
                "iterations": APP.ITERATIONS,
            }), encoding="utf-8")
            with patch.object(APP, "AUTH_FILE", auth):
                self.assertTrue(APP.verify("admin", password))
                self.assertFalse(APP.verify("admin", "wrong-password"))
                self.assertFalse(APP.verify("other", password))

    def test_verify_fails_closed_for_missing_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(APP, "AUTH_FILE", Path(tmp) / "missing.json"):
                self.assertFalse(APP.verify("admin", "password"))


if __name__ == "__main__":
    unittest.main()
