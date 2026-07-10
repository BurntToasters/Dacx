#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "..");
const lcovPath = path.join(root, "coverage", "lcov.info");
const minCoverage = Number.parseFloat(process.env.MIN_COVERAGE ?? "55");
const minOverallCoverage = Number.parseFloat(
  process.env.MIN_OVERALL_COVERAGE ?? "40",
);
const requiredSources = [
  "lib/services/audio_spectrum_service.dart",
  "lib/widgets/audio_waveform_visualizer.dart",
  "lib/screens/player_screen.dart",
];

function fail(message) {
  console.error(message);
  process.exit(1);
}

if (!Number.isFinite(minCoverage) || minCoverage < 0 || minCoverage > 100) {
  fail("Invalid MIN_COVERAGE value. Expected number between 0 and 100.");
}
if (
  !Number.isFinite(minOverallCoverage) ||
  minOverallCoverage < 0 ||
  minOverallCoverage > 100
) {
  fail("Invalid MIN_OVERALL_COVERAGE value. Expected number between 0 and 100.");
}

if (!fs.existsSync(lcovPath)) {
  fail(`Coverage file not found: ${lcovPath}`);
}

const lines = fs.readFileSync(lcovPath, "utf8").split(/\r?\n/);
let linesFound = 0;
let linesHit = 0;
let recordSource = null;
let recordFound = 0;
let recordHit = 0;
const coveredSources = new Set();
const sourceStats = new Map();

for (const line of lines) {
  if (line.startsWith("SF:")) {
    if (recordSource !== null) {
      sourceStats.set(recordSource, {
        found: recordFound,
        hit: recordHit,
      });
    }
    const raw = line.slice(3).trim();
    if (raw) {
      const absolute = path.isAbsolute(raw) ? raw : path.resolve(root, raw);
      const rel = path.relative(root, absolute).split(path.sep).join("/");
      coveredSources.add(rel);
      recordSource = rel;
      recordFound = 0;
      recordHit = 0;
    } else {
      recordSource = null;
      recordFound = 0;
      recordHit = 0;
    }
  } else if (line.startsWith("LF:")) {
    const value = Number.parseInt(line.slice(3), 10) || 0;
    linesFound += value;
    recordFound += value;
  } else if (line.startsWith("LH:")) {
    const value = Number.parseInt(line.slice(3), 10) || 0;
    linesHit += value;
    recordHit += value;
  } else if (line === "end_of_record") {
    if (recordSource !== null) {
      sourceStats.set(recordSource, {
        found: recordFound,
        hit: recordHit,
      });
    }
    recordSource = null;
    recordFound = 0;
    recordHit = 0;
  }
}
if (recordSource !== null) {
  sourceStats.set(recordSource, {
    found: recordFound,
    hit: recordHit,
  });
}

const missingRequired = requiredSources.filter((source) => !coveredSources.has(source));
if (missingRequired.length > 0) {
  fail(
    `Coverage file is missing required sources: ${missingRequired.join(", ")}. ` +
      "Ensure tests execute and import these files so uncovered lines count toward the gate.",
  );
}

if (linesFound <= 0) {
  fail("Coverage file does not contain any executable lines (LF=0).");
}

const coverage = (linesHit / linesFound) * 100;
const rendered = coverage.toFixed(2);

let scopedFound = 0;
let scopedHit = 0;
for (const [source, stats] of sourceStats.entries()) {
  if (requiredSources.includes(source)) continue;
  scopedFound += stats.found;
  scopedHit += stats.hit;
}
if (scopedFound <= 0) {
  fail("Coverage file does not contain executable lines for non-required sources.");
}
const scopedCoverage = (scopedHit / scopedFound) * 100;
const renderedScoped = scopedCoverage.toFixed(2);

console.log(
  `Coverage (overall): ${rendered}% (${linesHit}/${linesFound}) | minimum: ${minOverallCoverage.toFixed(2)}%`,
);
console.log(
  `Coverage (non-required sources): ${renderedScoped}% (${scopedHit}/${scopedFound}) | minimum: ${minCoverage.toFixed(2)}%`,
);

if (coverage < minOverallCoverage) {
  fail(
    `Overall coverage gate failed: ${rendered}% < ${minOverallCoverage.toFixed(2)}%`,
  );
}

if (scopedCoverage < minCoverage) {
  fail(
    `Scoped coverage gate failed: ${renderedScoped}% < ${minCoverage.toFixed(2)}%`,
  );
}

console.log("Coverage gate passed.");
