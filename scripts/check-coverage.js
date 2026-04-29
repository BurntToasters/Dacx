#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "..");
const lcovPath = path.join(root, "coverage", "lcov.info");
const minCoverage = Number.parseFloat(process.env.MIN_COVERAGE ?? "55");

function fail(message) {
  console.error(message);
  process.exit(1);
}

if (!Number.isFinite(minCoverage) || minCoverage < 0 || minCoverage > 100) {
  fail("Invalid MIN_COVERAGE value. Expected number between 0 and 100.");
}

if (!fs.existsSync(lcovPath)) {
  fail(`Coverage file not found: ${lcovPath}`);
}

const lines = fs.readFileSync(lcovPath, "utf8").split(/\r?\n/);
let linesFound = 0;
let linesHit = 0;

for (const line of lines) {
  if (line.startsWith("LF:")) {
    linesFound += Number.parseInt(line.slice(3), 10) || 0;
  } else if (line.startsWith("LH:")) {
    linesHit += Number.parseInt(line.slice(3), 10) || 0;
  }
}

if (linesFound <= 0) {
  fail("Coverage file does not contain any executable lines (LF=0).");
}

const coverage = (linesHit / linesFound) * 100;
const rendered = coverage.toFixed(2);

console.log(
  `Coverage: ${rendered}% (${linesHit}/${linesFound}) | minimum: ${minCoverage.toFixed(2)}%`,
);

if (coverage < minCoverage) {
  fail(`Coverage gate failed: ${rendered}% < ${minCoverage.toFixed(2)}%`);
}

console.log("Coverage gate passed.");
