"""Regression tests for source-specific reporting dates and the import workflow."""
import unittest

from playwright.sync_api import expect

import test_app as support


class DashboardReviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        support.BrowserTests.setUpClass.__func__(cls)

    @classmethod
    def tearDownClass(cls):
        support.BrowserTests.tearDownClass.__func__(cls)

    setUp = support.BrowserTests.setUp
    tearDown = support.BrowserTests.tearDown
    handle_dialog = support.BrowserTests.handle_dialog
    upload = support.BrowserTests.upload
    load_data = support.BrowserTests.load_data
    kpis = support.BrowserTests.kpis

    def test_capacity_uses_its_last_actual_month_when_another_source_is_newer(self):
        self.load_data(
            facts=[support.fact(monat="2026-09", menge=70),
                   support.fact(monat="2026-10", produktId="LICENSE")],
            cat=support.catalog(
                support.product(abrechnungsart="Kapazitaet", einheit="Credit", kapazitaetJeEinheit=100),
                support.product(produktId="LICENSE")),
            extra=[("kapazitaet.json", {"produktId": "P1", "packs": 1})])
        values = self.page.locator("#credKpi .v").all_text_contents()
        self.assertEqual(values[:3], ["100", "70", "30"])
        self.assertIn("Verbraucht 2026-09", self.page.locator("#credKpi").inner_text())
        self.assertIn("Andere Quellen reichen bis 2026-10", self.page.locator("#status").inner_text())

    def test_missing_capacity_month_is_not_reported_as_zero_consumption(self):
        self.load_data(
            facts=[support.fact(monat="2026-09", menge=70),
                   support.fact(monat="2026-10", produktId="LICENSE")],
            cat=support.catalog(
                support.product(abrechnungsart="Kapazitaet", einheit="Credit", kapazitaetJeEinheit=100),
                support.product(produktId="LICENSE")),
            extra=[("kapazitaet.json", {"produktId": "P1", "packs": 1})])
        self.page.locator("#fVon").fill("2026-10")
        self.page.locator("#fVon").dispatch_event("change")
        values = self.page.locator("#credKpi .v").all_text_contents()
        self.assertEqual(values[:3], ["100", "nicht verfügbar", "–"])
        self.assertIn("kein Nullverbrauch", self.page.locator("#status").inner_text())

    def test_license_and_unlicensed_rows_keep_their_own_reporting_month(self):
        self.load_data(
            facts=[support.fact(monat="2026-09"),
                   support.fact(monat="2026-09", produktId="CHAT", unlizenziert=4),
                   support.fact(monat="2026-10", produktId="AZURE", menge=9)],
            cat=support.catalog(support.product(),
                                support.product(produktId="CHAT", abrechnungsart="Kostenfrei"),
                                support.product(produktId="AZURE", abrechnungsart="Verbrauch")))
        self.assertIn("2026-09", self.page.locator("#licenseTitle").inner_text())
        self.assertIn("80 %", self.page.locator("#tbLiz").inner_text())
        self.assertIn("2026-09", self.page.locator("#unlicensedTitle").inner_text())
        self.assertIn("4", self.page.locator("#tbUnl").inner_text())
        self.assertIn("nicht verfügbar", self.page.locator("#tbUnl").inner_text())

    def test_supplemental_budget_import_preserves_filters_and_reset_restores_all(self):
        self.load_data(facts=[support.fact(), support.fact(fachbereich="Vertrieb", menge=20)])
        self.page.locator("#fFb").select_option("IT")
        self.upload([("budget.json", {"IT": 500})])
        self.assertEqual(self.page.locator("#fFb").input_value(), "IT")
        self.assertIn("100", self.kpis()[0])
        self.page.locator("#resetFilters").click()
        self.assertEqual(self.page.locator("#fFb").input_value(), "")
        self.assertIn("300", self.kpis()[0])

    def test_new_facts_reset_old_period_and_invalid_import_has_persistent_error(self):
        self.load_data()
        self.upload([("facts.json", [support.fact(monat="2026-09")])])
        self.assertEqual(self.page.locator("#fVon").input_value(), "2026-09")
        before = self.kpis()
        self.upload([("facts.json", b"{broken")])
        expect(self.page.locator("#importError")).to_be_visible()
        self.assertIn("facts.json", self.page.locator("#importError").inner_text())
        self.assertEqual(self.kpis(), before)
        self.assertEqual(self.dialogs, [])
        self.upload([("budget.json", {"IT": 500})])
        expect(self.page.locator("#importError")).to_be_hidden()

    def test_demo_and_loaded_files_are_explicit_without_external_requests(self):
        self.assertIn("Beispieldaten", self.page.locator("#dataMode").inner_text())
        self.assertIn("fiktiven Preisen", self.page.locator("#dataSummary").inner_text())
        self.upload([("lizenzkatalog.json", support.catalog())])
        self.assertIn("Fakten: nicht geladen", self.page.locator("#fileState").inner_text())
        self.assertIn("Lizenzkatalog: geladen", self.page.locator("#fileState").inner_text())
        self.upload([("facts.json", [support.fact()])])
        self.assertIn("1 von 1 Fakten", self.page.locator("#dataSummary").inner_text())
        self.assertFalse(self.page.locator("#importHelp").evaluate("el => el.open"))
        self.assertEqual(self.page.locator('#nav button[aria-pressed="true"]').count(), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
