"""Configuration setup flows; all requests and test values stay local."""
import json
import os
import shutil
import threading
import unittest
from functools import partial
from http.server import ThreadingHTTPServer
from pathlib import Path

from playwright.sync_api import expect, sync_playwright
from test_app import CONFIGURATION, ROOT, SilentHandler


class ConfigurationSetupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), partial(SilentHandler, directory=str(ROOT)))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f"http://127.0.0.1:{cls.server.server_port}"
        cls.pw = sync_playwright().start()
        executable = os.environ.get("CHROMIUM_PATH") or shutil.which("chromium")
        cls.browser = cls.pw.chromium.launch(
            **({"executable_path": executable} if executable else {}),
            headless=True, args=["--no-sandbox"])

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.pw.stop()
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        self.context = self.browser.new_context(accept_downloads=True)
        self.page = self.context.new_page()
        self.errors, self.requests = [], []
        self.page.on("pageerror", lambda error: self.errors.append(str(error)))
        self.page.on("request", lambda request: self.requests.append(request.url)
                     if request.url.startswith(("https://", "http://"))
                     and not request.url.startswith(self.url) else None)
        self.page.goto(self.url + CONFIGURATION)

    def tearDown(self):
        self.context.close()
        self.assertEqual(self.errors, [])
        self.assertEqual(self.requests, [])

    def preview(self):
        return json.loads(self.page.locator("#prev").text_content())

    def upload(self, data):
        self.page.locator("#load").set_input_files({"name": "config.json",
            "mimeType": "application/json", "buffer": json.dumps(data).encode()})
        expect(self.page.locator("#load")).to_have_value("")

    def prepare_query(self):
        self.page.locator('[data-preset="AzureQuery"]').click()
        self.page.locator("#TenantId").fill("11111111-1111-1111-1111-111111111111")
        self.page.locator("#ClientId").fill("22222222-2222-2222-2222-222222222222")
        self.page.locator("#CertificateThumbprint").fill("aa:" * 19 + "aa")
        self.page.locator("#CostCenterTag").fill("Kostenstelle")

    def test_sources_first_and_only_relevant_sections_visible(self):
        self.assertTrue(self.page.evaluate("!!(document.querySelector('#sourcesCard').compareDocumentPosition(document.querySelector('#authCard')) & Node.DOCUMENT_POSITION_FOLLOWING)"))
        expect(self.page.locator("#authCard")).to_be_visible()
        for source in ["Azure", "PPAC", "GitHub"]:
            expect(self.page.locator(f'section[data-src="{source}"]')).to_be_hidden()
        self.page.locator('[data-preset="PPAC"]').click()
        expect(self.page.locator("#authCard")).to_be_hidden()
        expect(self.page.locator('section[data-src="PPAC"]')).to_be_visible()
        expect(self.page.locator("#dl")).to_be_enabled()

    def test_switching_source_preserves_existing_credentials_and_settings(self):
        self.page.locator("#TenantId").fill("11111111-1111-1111-1111-111111111111")
        self.page.locator("#OutputPath").fill("my-output")
        self.page.locator('[data-preset="AzureExport"]').click()
        expect(self.page.locator("#authCard")).to_be_hidden()
        expect(self.page.locator("#status .e")).to_have_count(0)
        expect(self.page.locator("#dl")).to_be_enabled()
        self.assertEqual(self.preview()["CostCenterTag"], "")
        self.page.locator("#CostCenterTag").fill("Kostenstelle")
        self.assertEqual(self.preview()["TenantId"], "11111111-1111-1111-1111-111111111111")
        self.assertEqual(self.preview()["OutputPath"], "my-output")
        self.assertEqual(self.preview()["EnabledSources"], ["Azure"])
        self.page.locator('.src[value="Graph"]').check()
        expect(self.page.locator("#authCard")).to_be_visible()

    def test_query_deduplicates_guid_and_scope_case_and_downloads_once(self):
        self.prepare_query()
        guid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        self.page.locator("#AzureSubs").fill(guid + "\n/SUBSCRIPTIONS/" + guid.upper())
        expect(self.page.locator("#status .e")).to_have_count(0)
        expect(self.page.locator("#status")).to_contain_text("nur einmal gespeichert")
        with self.page.expect_download() as event:
            self.page.locator("#dl").click()
        data = json.loads(Path(event.value.path()).read_text())
        self.assertEqual(data["AzureScopes"], ["/subscriptions/" + guid])
        self.assertEqual(data["CertificateThumbprint"], "AA" * 20)

    def test_invalid_scope_blocks_download_and_preserves_hint_association(self):
        self.prepare_query()
        self.page.locator("#AzureSubs").fill("/subscriptions/not-a-guid")
        expect(self.page.locator("#dl")).to_be_disabled()
        expect(self.page.locator("#AzureSubs")).to_have_attribute("aria-invalid", "true")
        described = self.page.locator("#AzureSubs").get_attribute("aria-describedby")
        self.assertIn("AzureSubsHint", described)
        self.assertIn("AzureSubsError", described)
        expect(self.page.locator("#AzureSubsError")).to_contain_text("gültige Abonnement-ID")

    def test_import_preserves_legacy_nested_and_placeholder_values(self):
        self.upload({"EnabledSources": ["PPAC"], "Pseudonymize": False,
                     "Custom": {"enabled": True}, "TenantId": "<tenant-id>",
                     "PpacColumnMap": {"Date": "Date", "Environment": "Environment",
                                       "Agent": "Agent", "Credits": "Credits", "FutureColumn": "Keep"},
                     "EnvironmentToDepartment": {"<environment>": "<department>"}})
        data = self.preview()
        self.assertFalse(data["Pseudonymize"])
        self.assertEqual(data["Custom"], {"enabled": True})
        self.assertEqual(data["TenantId"], "<tenant-id>")
        self.assertEqual(data["PpacColumnMap"]["FutureColumn"], "Keep")
        self.assertEqual(data["EnvironmentToDepartment"], {"<environment>": "<department>"})

    def test_mobile_expanded_guidance_and_preview_do_not_overflow(self):
        self.page.set_viewport_size({"width": 320, "height": 844})
        self.page.locator(".intro summary").click()
        self.page.locator("#previewDetails summary").click()
        self.assertTrue(self.page.evaluate("document.documentElement.scrollWidth <= innerWidth"))


if __name__ == "__main__":
    unittest.main()
