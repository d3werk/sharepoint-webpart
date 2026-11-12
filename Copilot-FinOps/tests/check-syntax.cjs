"use strict";
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { TaskUtils, DefaultSettings } = require("@microsoft/powerquery-parser");
const root = path.resolve(__dirname, "..");
(async () => {
  for (const file of ["04_Dashboard/copilot-cost-dashboard.html", "02_Konfiguration/Konfiguration-CopilotFinOps.html"]) {
    const html = fs.readFileSync(path.join(root, file), "utf8");
    const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)];
    if (!scripts.length) throw new Error(`No inline scripts found: ${file}`);
    scripts.forEach((match, index) => new vm.Script(match[1], { filename: `${file}:${index + 1}` }));
    console.log(`PASS JavaScript syntax: ${file}`);
  }
  for (const file of fs.readdirSync(path.join(root, "05_PowerBI")).filter(name => name.endsWith(".pq"))) {
    const text = fs.readFileSync(path.join(root, "05_PowerBI", file), "utf8");
    const task = await TaskUtils.tryLexParse(DefaultSettings, text);
    if (task.resultKind !== "Ok") throw new Error(`${file}: ${task.error?.message || task.resultKind}`);
    console.log(`PASS Power Query syntax (Microsoft parser): ${file}`);
  }
  console.log("Syntax only: Power BI refresh, DAX execution and RLS require Power BI.");
})().catch(error => { console.error(error); process.exitCode = 1; });
