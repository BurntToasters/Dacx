import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const packageJsonPath = resolve(__dirname, "..", "package.json");
const packageJson = JSON.parse(readFileSync(packageJsonPath, "utf8"));
const appVersion = packageJson.version ?? "unknown";
const scriptVersion = "1.0.0";

const colors = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  blue: "\x1b[34m",
  green: "\x1b[32m",
  red: "\x1b[31m",
};
const defaultTimeoutMs = 300_000;

function createInitialResults() {
  return {
    analyze: { status: "pending" },
    format: { status: "pending" },
    test: { status: "pending", passed: null, failed: null },
  };
}

function stripAnsi(value) {
  return value.replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, "");
}

function printTail(output) {
  const cleanOutput = stripAnsi(output).trim();
  if (!cleanOutput) return;
  const lines = cleanOutput.split("\n");
  const tail = lines.slice(-20).join("\n");
  console.log(`${colors.red}${tail}${colors.reset}`);
}

function parseTest(output, results) {
  const cleanOutput = stripAnsi(output);
  const passedMatch = cleanOutput.match(/(\d+)\s+tests?\s+passed/i);
  const failedMatch = cleanOutput.match(/(\d+)\s+tests?\s+failed/i);
  const allPassedMatch = cleanOutput.match(/All\s+(\d+)\s+tests?\s+passed/i);
  const allPassedNoCount = /All\s+tests?\s+passed!?/i.test(cleanOutput);
  const progressMatches = [...cleanOutput.matchAll(/\+(\d+):/g)];
  const lastProgressCount = progressMatches.length
    ? parseInt(progressMatches[progressMatches.length - 1][1], 10)
    : null;

  if (allPassedMatch) {
    results.test.passed = parseInt(allPassedMatch[1], 10);
    results.test.failed = 0;
  } else if (allPassedNoCount) {
    results.test.passed = passedMatch
      ? parseInt(passedMatch[1], 10)
      : lastProgressCount;
    results.test.failed = 0;
  } else {
    results.test.passed = passedMatch ? parseInt(passedMatch[1], 10) : null;
    results.test.failed = failedMatch ? parseInt(failedMatch[1], 10) : 0;
  }
}

function runCommand(name, command, args, parser, results, options = {}) {
  console.log(`${colors.blue}${colors.bold}Running ${name}...${colors.reset}`);
  const timeout = options.timeout ?? defaultTimeoutMs;
  const run = spawnSync(command, args, {
    encoding: "utf8",
    stdio: "pipe",
    shell: process.platform === "win32",
    windowsHide: true,
    timeout,
  });

  const output = `${run.stdout || ""}${run.stderr || ""}`;
  if (parser) parser(output, results);

  if (!run.error && run.status === 0) {
    results[name].status = "passed";
    console.log(`${colors.green}✓ ${name} passed${colors.reset}\n`);
    return true;
  }

  results[name].status = "failed";
  const reason = run.error
    ? run.error.message
    : run.status === null
      ? `signal ${run.signal || "unknown"}`
      : `exit code ${run.status}`;
  console.log(`${colors.red}✗ ${name} failed (${reason})${colors.reset}`);
  printTail(output);
  console.log("");
  return false;
}

function printBanner() {
  console.log(`${colors.bold}${colors.blue}
╔══════════════════════════════════════╗
║         Dacx TEST SUITE              ║
╚══════════════════════════════════════╝
Dacx Version: ${appVersion}
Script Version: ${scriptVersion}
${colors.reset}`);
}

function printSummary(results) {
  console.log(`${colors.bold}${colors.blue}
╔══════════════════════════════════════╗
║               SUMMARY                ║
╚══════════════════════════════════════╝
${colors.reset}`);

  const allPassed = Object.values(results).every(
    (result) => result.status === "passed",
  );

  console.log(
    `${colors.bold}Analyze:${colors.reset}  ${
      results.analyze.status === "passed"
        ? `${colors.green}✓ PASS`
        : `${colors.red}✗ FAIL`
    }${colors.reset}`,
  );
  console.log(
    `${colors.bold}Format:${colors.reset}   ${
      results.format.status === "passed"
        ? `${colors.green}✓ PASS`
        : `${colors.red}✗ FAIL`
    }${colors.reset}`,
  );
  console.log(
    `${colors.bold}Tests:${colors.reset}    ${
      results.test.status === "passed"
        ? `${colors.green}✓ PASS`
        : `${colors.red}✗ FAIL`
    }${colors.reset} (${results.test.passed ?? "n/a"} passed${
      results.test.failed && results.test.failed > 0
        ? `, ${results.test.failed} failed`
        : ""
    })`,
  );

  console.log("");
  if (allPassed) {
    console.log(
      `${colors.green}${colors.bold}✓ All checks passed.${colors.reset}`,
    );
    return 0;
  }

  console.log(
    `${colors.red}${colors.bold}✗ Some checks failed. Review output above.${colors.reset}`,
  );
  return 1;
}

function main() {
  const results = createInitialResults();
  printBanner();

  runCommand("analyze", "dart", ["analyze"], null, results);
  runCommand("format", "dart", ["format", "--set-exit-if-changed", "lib/", "test/"], null, results);
  runCommand("test", "flutter", ["test"], parseTest, results);

  return printSummary(results);
}

process.exit(main());
