"""Offline regression tests. Run: python -m unittest discover -s tests -v."""
import csv
import datetime
import io
import json
import os
import shutil
import subprocess
import tempfile
import threading
import unittest
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from playwright.sync_api import expect, sync_playwright

ROOT = Path(os.environ.get("FINOPS_TEST_ROOT", Path(__file__).resolve().parents[1]))
DASHBOARD = "/04_Dashboard/copilot-cost-dashboard.html"
CONFIGURATION = "/02_Konfiguration/Konfiguration-CopilotFinOps.html"


def product(**overrides):
    return {"produktId": "P1", "produkt": "Testprodukt", "produktfamilie": "Testfamilie",
            "skuId": "test", "abrechnungsart": "ProUser", "einheit": "User/Monat",
            "kundenpreis": 10, "listenpreis": 20, "waehrung": "EUR", "preisbasis": "Monat",
            "gueltigAb": "2026-01-01", "gueltigBis": None, "datenquelle": "Manuell",
            "zuordnungsschluessel": {}, **overrides}


def catalog(*products):
    return {"version": "test", "waehrungStandard": "EUR", "produkte": list(products or [product()])}


def fact(**overrides):
    return {"monat": "2026-02", "produktId": "P1", "fachbereich": "IT", "region": "DE",
            "menge": 10, "kostenIst": None, "zugewiesen": 10, "aktiv": 8,
            "unlizenziert": 0, **overrides}


class SilentHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


class BrowserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), partial(SilentHandler, directory=str(ROOT)))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f"http://127.0.0.1:{cls.server.server_port}"
        cls.pw = sync_playwright().start()
        executable = os.environ.get("CHROMIUM_PATH") or shutil.which("chromium")
        cls.browser = cls.pw.chromium.launch(
            **({"executable_path": executable} if executable else {}), headless=True,
            args=["--no-sandbox"])

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
        self.errors, self.dialogs, self.external_requests = [], [], []
        self.page.on("pageerror", lambda error: self.errors.append(str(error)))
        self.page.on("dialog", self.handle_dialog)
        self.page.on("request", lambda request: self.external_requests.append(request.url)
                     if request.url.startswith(("https://", "http://"))
                     and not request.url.startswith(self.url) else None)
        self.page.goto(self.url + DASHBOARD)

    def handle_dialog(self, dialog):
        self.dialogs.append(dialog.message)
        dialog.dismiss()

    def tearDown(self):
        self.context.close()
        self.assertEqual(self.errors, [], "Uncaught browser exceptions")
        self.assertEqual(self.external_requests, [], "Offline app made external requests")

    def upload(self, files, selector="#file"):
        self.page.locator(selector).set_input_files([
            {"name": name, "mimeType": "application/json", "buffer":
             (data if isinstance(data, bytes) else json.dumps(data, ensure_ascii=False).encode())}
            for name, data in files])
        expect(self.page.locator(selector)).to_have_value("")

    def load_data(self, facts=None, cat=None, extra=()):
        self.upload([("facts.json", facts if facts is not None else [fact()]),
                     ("lizenzkatalog.json", cat if cat is not None else catalog()), *extra])

    def kpis(self):
        return self.page.locator("#kpis .v").all_text_contents()

    def csv(self):
        with self.page.expect_download() as event:
            self.page.locator("#csv").click()
        return Path(event.value.path()).read_text(encoding="utf-8-sig")

    def test_demo_navigation_theme_and_mobile(self):
        expect(self.page.locator("#stand")).to_contain_text("Beispieldaten")
        self.assertEqual(len(self.kpis()), 5)
        for target in ["lizenzen", "credits", "katalog", "uebersicht"]:
            self.page.locator(f'#nav button[data-p="{target}"]').click()
            expect(self.page.locator(f"#p-{target}")).to_be_visible()
            self.assertEqual(self.page.locator(".page:visible").count(), 1)
        before = self.page.locator("html").get_attribute("data-theme")
        self.page.locator("#theme").click()
        self.assertNotEqual(before, self.page.locator("html").get_attribute("data-theme"))
        self.page.set_viewport_size({"width": 390, "height": 844})
        self.assertTrue(self.page.evaluate("document.documentElement.scrollWidth <= innerWidth"))
        self.page.emulate_media(media="print")
        self.assertEqual(self.page.locator(".page:visible").count(), 4)

    def test_own_data_clears_demo_budget_and_capacity(self):
        self.load_data()
        self.assertIn("100", self.kpis()[0])
        self.assertNotIn("Vertrieb", self.page.locator("#tbBudget").inner_text())
        self.assertNotIn("100.000", self.page.locator("#credKpi").inner_text())
        self.assertNotIn("Beispieldaten", self.page.locator("#stand").inner_text())

    def test_catalog_only_never_displays_demo_facts_as_real(self):
        self.upload([("lizenzkatalog.json", catalog())])
        self.assertIn("0", self.kpis()[0])
        self.assertEqual(self.page.locator("#fFb option").count(), 1)

    def test_facts_and_catalog_import_order_independent(self):
        self.upload([("lizenzkatalog.json", catalog()), ("facts.json", [fact()])])
        self.assertIn("100", self.kpis()[0])

    def test_atomic_batch_import_keeps_previous_data_on_parse_failure(self):
        self.load_data()
        before = self.kpis()
        self.upload([("facts.json", [fact(menge=999)]), ("kapazitaet.json", b"{broken")])
        self.page.locator("#fVon").dispatch_event("change")
        self.assertEqual(self.kpis(), before)

    def test_invalid_fact_values_rejected_without_losing_previous_data(self):
        self.load_data()
        before = self.kpis()
        for change in [{"monat": "2026-13"}, {"menge": "10"}, {"menge": -1}, {"aktiv": 11},
                       {"kostenIst": "100"}, {"produktId": ""}]:
            with self.subTest(change=change):
                self.upload([("facts.json", [fact(**change)])])
                self.assertEqual(self.kpis(), before)

    def test_duplicate_product_ids_rejected(self):
        self.load_data()
        before = self.kpis()
        self.upload([("lizenzkatalog.json", catalog(product(), product(kundenpreis=900)))])
        self.assertEqual(self.kpis(), before)
        self.upload([("lizenzkatalog.json", catalog(product(), product(produktId="p1")))])
        self.assertEqual(self.kpis(), before)

    def test_missing_price_actual_cost_zero_and_annual_price(self):
        self.load_data(cat=catalog(product(kundenpreis="[prüfen]", listenpreis="[prüfen]")))
        self.assertIn("0", self.kpis()[0])
        self.assertEqual(self.kpis()[4], "1")
        self.load_data(facts=[fact(kostenIst=0)], cat=catalog(product(kundenpreis="[prüfen]", listenpreis="[prüfen]")))
        self.assertEqual(self.kpis()[4], "0")
        self.load_data(cat=catalog(product(kundenpreis=120, preisbasis="Jahr")))
        self.assertIn("100", self.kpis()[0])
        self.load_data(cat=catalog(product(kundenpreis="[prüfen]", listenpreis=3)))
        self.assertIn("30", self.kpis()[0])

    def test_price_validity_is_month_start_date(self):
        self.load_data(cat=catalog(product(gueltigAb="2026-02-15")))
        self.assertEqual(self.kpis()[4], "1")
        self.assertIn("0", self.kpis()[0])

    def test_unknown_activity_never_becomes_fake_savings(self):
        self.load_data(facts=[fact(aktiv=None)])
        text = self.page.locator("#tbLiz").inner_text()
        self.assertRegex(text.lower(), "unbekannt|nicht verfügbar|keine nutzungsdaten")
        self.assertNotIn("100 %", text)

    def test_unused_license_pool_does_not_hide_known_usage(self):
        self.load_data(facts=[fact(), fact(fachbereich="Pool (nicht zugewiesen)",
                                         zugewiesen=0, aktiv=None)])
        text = self.page.locator("#tbLiz").inner_text()
        self.assertIn("80 %", text)
        self.assertNotIn("nicht verfügbar", text)

    def test_product_lookup_matches_case_insensitive_collector_and_powerbi(self):
        self.load_data(facts=[fact(produktId="p1")])
        self.assertIn("100", self.kpis()[0])
        self.assertEqual(self.kpis()[4], "0")

    def test_special_department_keys_and_html_are_safe(self):
        self.load_data(facts=[fact(fachbereich="__proto__"), fact(fachbereich="constructor"),
                              fact(fachbereich='<img src=x onerror="window.injected=true">')])
        self.assertIn("300", self.kpis()[0])
        for department in ["__proto__", "constructor"]:
            self.assertIn(department, self.page.locator("#tbBudget").inner_text())
        self.assertIsNone(self.page.evaluate("window.injected"))
        self.assertEqual(self.page.locator("#tbBudget img").count(), 0)

    def test_csv_is_filtered_and_escapes_formulas_quotes_newlines(self):
        self.load_data(facts=[fact(fachbereich='=HYPERLINK("https://example.invalid")', agent='A;"B\nC'),
                              fact(fachbereich="Vertrieb", menge=20)])
        text = self.csv()
        self.assertIn("'=HYPERLINK", text)
        self.assertIn('"A;""B\nC"', text)
        self.page.locator("#fFb").select_option("Vertrieb")
        self.assertNotIn("HYPERLINK", self.csv())

    def test_empty_facts_and_reversed_date_range(self):
        self.load_data(facts=[])
        self.assertIn("Keine Daten", self.page.locator("#chTrend").inner_text())
        self.load_data(facts=[fact(monat="2026-01"), fact(monat="2026-03", menge=20)])
        self.page.locator("#fVon").fill("2026-03")
        self.page.locator("#fBis").fill("2026-01")
        self.page.locator("#fBis").dispatch_event("change")
        self.assertIn("300", self.kpis()[0])

    def test_configuration_offline_source_without_tenant_credentials(self):
        self.page.goto(self.url + CONFIGURATION)
        self.page.locator('.src[value="Graph"]').uncheck()
        self.page.locator('.src[value="PPAC"]').check()
        expect(self.page.locator("#status .e")).to_have_count(0)
        config = json.loads(self.page.locator("#prev").inner_text())
        self.assertEqual(config["EnabledSources"], ["PPAC"])
        self.assertEqual(config["TenantId"], "")

    def test_configuration_mobile_has_no_horizontal_page_overflow(self):
        self.page.set_viewport_size({"width": 390, "height": 844})
        self.page.goto(self.url + CONFIGURATION)
        self.assertTrue(self.page.evaluate("document.documentElement.scrollWidth <= innerWidth"))

    def test_configuration_invalid_numeric_inputs_not_silently_clamped(self):
        self.page.goto(self.url + CONFIGURATION)
        self.page.locator('.src[value="Graph"]').uncheck()
        self.page.locator('.src[value="PPAC"]').check()
        expect(self.page.locator("#status .e")).to_have_count(0)
        for value in ["0", "2.5", "100", ""]:
            with self.subTest(value=value):
                self.page.locator("#MinGroupSize").fill(value)
                self.assertGreater(self.page.locator("#status .e").count(), 0)
                self.assertNotEqual(self.page.locator("#MinGroupSize").input_value(), "5")

    def test_configuration_malformed_import_is_atomic(self):
        self.page.goto(self.url + CONFIGURATION)
        self.page.locator("#OutputPath").fill("keep-me")
        before = self.page.locator("#prev").inner_text()
        self.upload([("config.json", {"OutputPath": "replaced", "EnabledSources": ["PPAC"],
                                      "AzureScopes": [123]})], "#load")
        self.assertEqual(self.page.locator("#prev").inner_text(), before)

    def test_configuration_unknown_fields_and_special_mapping_roundtrip(self):
        self.page.goto(self.url + CONFIGURATION)
        data = {"EnabledSources": ["PPAC"], "OutputPath": "out", "CatalogPath": "lizenzkatalog.json",
                "EnvironmentToDepartment": {"__proto__": "IT", "constructor": "Forschung"},
                "CustomSetting": {"keep": True}}
        self.upload([("config.json", data)], "#load")
        preview = json.loads(self.page.locator("#prev").inner_text())
        self.assertEqual(preview["EnvironmentToDepartment"], data["EnvironmentToDepartment"])
        self.assertEqual(preview["CustomSetting"], data["CustomSetting"])

    def test_currency_filter_prevents_mixed_sums_and_budget_conversion(self):
        self.load_data(facts=[fact(), fact(produktId="USD1", menge=20)],
                       cat=catalog(product(), product(produktId="USD1", waehrung="USD")),
                       extra=[("budget.json", {"IT": 1000})])
        self.assertIn("100", self.kpis()[0])
        self.assertEqual(self.page.locator("#fCur option").count(), 2)
        self.page.locator("#fCur").select_option("USD")
        self.assertIn("200", self.kpis()[0])
        self.assertIn("$", self.kpis()[0])
        self.assertIn("nicht hinterlegt", self.kpis()[3])
        rows = list(csv.reader(io.StringIO(self.csv()), delimiter=";"))
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[1][-1], "USD")

    def test_explicit_fact_currency_overrides_product_currency(self):
        self.load_data(facts=[fact(kostenIst=12.5, waehrung="USD")])
        self.assertEqual(self.page.locator("#fCur").input_value(), "USD")
        self.assertIn("12,50", self.kpis()[0])
        self.assertIn("$", self.kpis()[0])

    def test_mismatched_currency_never_relabels_catalog_prices(self):
        self.load_data(facts=[fact(waehrung="USD")])
        self.assertIn("0", self.kpis()[0])
        self.assertEqual(self.kpis()[4], "1")
        self.assertIn("keine Umrechnung", self.page.locator("#status").inner_text())
        self.assertNotIn("$", self.page.locator("#tbLiz tbody td").last.inner_text())

    def test_ytd_includes_earlier_months_than_visible_range(self):
        self.load_data(facts=[fact(monat="2026-01"), fact(monat="2026-02")])
        self.page.locator("#fVon").fill("2026-02")
        self.page.locator("#fVon").dispatch_event("change")
        self.assertIn("100", self.kpis()[0])
        self.assertIn("200", self.kpis()[1])
        self.assertIn("1.200", self.kpis()[2])

    def test_calendar_gap_forecast_and_insufficient_history(self):
        self.load_data()
        self.assertIn("nicht verfügbar", self.kpis()[2])
        self.load_data(facts=[fact(monat="2026-01"), fact(monat="2026-03", menge=30)])
        # Jan 100, Mar 300: slope 100 per calendar month; Apr..Dec = 400..1200.
        self.assertIn("7.600", self.kpis()[2])

    def test_zero_budget_is_distinct_from_missing_budget(self):
        self.load_data(extra=[("budget.json", {"IT": 0})])
        self.assertIn("überschritten", self.page.locator("#tbBudget").inner_text())
        self.assertNotIn("nicht hinterlegt", self.kpis()[3])

    def test_zero_packs_are_known_zero_capacity_and_detect_overage(self):
        self.load_data(cat=catalog(product(produktId="P1", abrechnungsart="Kapazitaet",
                                           kapazitaetJeEinheit=100, einheit="Credit")),
                       extra=[("kapazitaet.json", {"produktId": "P1", "packs": 0})])
        self.assertIn("bereits überschritten", self.page.locator("#credKpi").inner_text())
        self.assertNotIn("[prüfen]", self.page.locator("#credKpi").inner_text())

    def test_distinct_capacity_units_are_never_summed(self):
        self.load_data(facts=[fact(), fact(produktId="SCU", menge=3)],
                       cat=catalog(product(abrechnungsart="Kapazitaet", einheit="Credit"),
                                   product(produktId="SCU", abrechnungsart="Kapazitaet", einheit="SCU")))
        self.assertIn("Mehrere Kapazitätsprodukte", self.page.locator("#status").inner_text())
        self.assertIn("Keine Daten", self.page.locator("#tbAgent").inner_text())
        self.upload([("kapazitaet.json", {"produktId": "SCU", "packs": 1})])
        self.assertIn("SCU", self.page.locator("#credKpi").inner_text())
        self.assertIn("IT", self.page.locator("#tbAgent").inner_text())

    def test_negative_actual_cost_is_a_credit_and_charts_stay_finite(self):
        self.load_data(facts=[fact(kostenIst=-12.5, menge=-1)])
        self.assertIn("-12,50", self.kpis()[0])
        self.assertNotRegex(self.page.locator("#chProd").inner_html(), "NaN|Infinity")
        widths = self.page.locator("#chProd rect").evaluate_all("els => els.map(e => +e.getAttribute('width'))")
        self.assertTrue(all(width >= 0 for width in widths))

    def test_bom_import_and_unknown_product_warning(self):
        data = ("\ufeff" + json.dumps([fact(produktId="UNKNOWN")])).encode()
        self.upload([("facts.json", data), ("lizenzkatalog.json", catalog())])
        self.assertEqual(self.kpis()[4], "1")
        self.assertIn("Unbekannte Produkt", self.page.locator("#status").inner_text())

    def test_configuration_import_resets_stale_values(self):
        self.page.goto(self.url + CONFIGURATION)
        self.upload([("config.json", {"EnabledSources": ["Graph"],
                                      "TenantId": "11111111-1111-1111-1111-111111111111"})], "#load")
        self.upload([("config.json", {"EnabledSources": ["PPAC"]})], "#load")
        self.assertEqual(self.page.locator("#TenantId").input_value(), "")
        self.assertEqual(json.loads(self.page.locator("#prev").inner_text())["EnabledSources"], ["PPAC"])

    def test_configuration_duplicate_environment_names_are_reported(self):
        self.page.goto(self.url + CONFIGURATION)
        self.page.locator('.src[value="Graph"]').uncheck()
        self.page.locator('.src[value="PPAC"]').check()
        self.page.locator("#envT input").nth(0).fill("Prod")
        self.page.locator("#envT input").nth(1).fill("IT")
        self.page.locator("#addEnv").click()
        self.page.locator("#envT input").nth(2).fill("prod")
        self.page.locator("#envT input").nth(3).fill("Vertrieb")
        self.assertGreater(self.page.locator("#status .e").count(), 0)

    def test_configuration_valid_download_contains_checked_values(self):
        self.page.goto(self.url + CONFIGURATION)
        self.page.locator('.src[value="Graph"]').uncheck()
        self.page.locator('.src[value="PPAC"]').check()
        expect(self.page.locator("#status .e")).to_have_count(0)
        with self.page.expect_download() as event:
            self.page.locator("#dl").click()
        data = json.loads(Path(event.value.path()).read_text())
        self.assertEqual(data["EnabledSources"], ["PPAC"])
        self.assertEqual(data["MinGroupSize"], 5)

    def test_real_ppac_collector_output_loads_in_dashboard(self):
        engine = os.environ.get("PWSH_PATH") or shutil.which("pwsh")
        if not engine:
            self.skipTest("Set PWSH_PATH or install PowerShell for the collector/browser integration")
        with tempfile.TemporaryDirectory(prefix="finops-integration-") as directory:
            folder = Path(directory)
            (folder / "ppac").mkdir()
            data = catalog(product(abrechnungsart="Kapazitaet", einheit="Credit",
                                   kundenpreis=3, kapazitaetJeEinheit=100, datenquelle="PPAC-CSV"))
            (folder / "catalog.json").write_text(json.dumps(data), encoding="utf-8")
            (folder / "ppac/usage.csv").write_text(
                'Date;Environment;Agent;Credits\n'
                f'{datetime.date.today().isoformat()};Env|A;=1+1;4\n', encoding="utf-8")
            config = {"OutputPath": "out", "CatalogPath": "catalog.json", "EnabledSources": ["PPAC"],
                      "PpacImportFolder": "ppac", "PpacProduktId": "P1", "CsvDelimiter": ";",
                      "PpacColumnMap": {"Date": "Date", "Environment": "Environment",
                                        "Agent": "Agent", "Credits": "Credits"},
                      "EnvironmentToDepartment": {"Env|A": "IT|DE"}}
            (folder / "config.json").write_text(json.dumps(config), encoding="utf-8")
            result = subprocess.run([engine, "-NoProfile", "-File",
                                     str(ROOT / "03_Collector/Collect-CopilotCosts.ps1"),
                                     "-ConfigPath", str(folder / "config.json")],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            facts = json.loads((folder / "out/facts.json").read_text(encoding="utf-8-sig"))
            self.assertEqual(facts[0]["agent"], "=1+1")
            self.load_data(facts=facts, cat=data)
            self.assertIn("12", self.kpis()[0])
            self.assertIn("IT|DE", self.page.locator("#tbAgent").inner_text())
            self.assertIn("'=1+1", self.csv())


class SchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = json.loads((ROOT / "02_Konfiguration/lizenzkatalog.schema.json").read_text())
        Draft202012Validator.check_schema(cls.schema)
        cls.validator = Draft202012Validator(cls.schema, format_checker=FormatChecker())

    def test_shipped_catalog_and_examples_are_valid(self):
        data = json.loads((ROOT / "02_Konfiguration/lizenzkatalog.json").read_text())
        self.validator.validate(data)
        for path in (ROOT / "02_Konfiguration/Beispiele").glob("*.json"):
            self.assertIsInstance(json.loads(path.read_text()), dict)

    def test_catalog_rejects_invalid_prices_dates_currency_and_empty_ids(self):
        for change in [{"kundenpreis": -1}, {"kundenpreis": "12 EUR"},
                       {"gueltigAb": "2026-02-30"}, {"produktId": ""}, {"waehrung": "Euro"}]:
            with self.subTest(change=change):
                self.assertTrue(list(self.validator.iter_errors(catalog(product(**change)))))


if __name__ == "__main__":
    unittest.main(verbosity=2)
