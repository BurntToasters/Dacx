import assert from "node:assert/strict";
import { test } from "node:test";

import {
  flutterTestOutputLooksFailed,
  flutterTestOutputLooksFullyPassed,
  flutterTestRunSucceeded,
} from "./test-all.js";

test("accepts a normal flutter test success summary", () => {
  const output = "00:10 +85: All tests passed!\n";
  assert.equal(flutterTestOutputLooksFullyPassed(output), true);
  assert.equal(flutterTestOutputLooksFailed(output), false);
  assert.equal(flutterTestRunSucceeded(output, 0), true);
});

test("rejects load failures even when the process exits 0", () => {
  const output = [
    'Failed to load "test/screens/player_screen_pump_test.dart":',
    "Compilation failed",
    "00:00 +0 -2: Some tests failed.",
  ].join("\n");
  assert.equal(flutterTestOutputLooksFailed(output), true);
  assert.equal(flutterTestRunSucceeded(output, 0), false);
});

test("rejects progress lines that include a failure count", () => {
  const output =
    "00:52 +924 -1: UpdatePendingMarker writes, reads, and clears pending update marker [E]\n";
  assert.equal(flutterTestOutputLooksFailed(output), true);
  assert.equal(flutterTestRunSucceeded(output, 1), false);
});

test("rejects a zero exit without All tests passed", () => {
  const output = "00:01 +12: loading next file\n";
  assert.equal(flutterTestOutputLooksFullyPassed(output), false);
  assert.equal(flutterTestRunSucceeded(output, 0), false);
});

test("ignores load-failure wording logged by a passing run", () => {
  const output = [
    "01:03 +1000: test/widgets/artwork_test.dart: Artwork shows fallback",
    "Image provider failed to load: file:///missing.png",
    "Failed to load native library mpv-2.dll, using stub",
    "01:05 +1019: All tests passed!",
  ].join("\n");
  assert.equal(flutterTestOutputLooksFailed(output), false);
  assert.equal(flutterTestRunSucceeded(output, 0), true);
});

test("ignores failure wording inside a passing test name", () => {
  const output = [
    "00:04 +12: test/report_test.dart: banner says some tests failed when counts drop",
    "00:05 +13: All tests passed!",
  ].join("\n");
  assert.equal(flutterTestOutputLooksFailed(output), false);
  assert.equal(flutterTestRunSucceeded(output, 0), true);
});

test("ignores a negative-count progress line without [E]", () => {
  const output = [
    "00:52 +924 -1: UpdatePendingMarker writes, reads, and clears pending update marker",
    "00:53 +925: All tests passed!",
  ].join("\n");
  assert.equal(flutterTestOutputLooksFailed(output), false);
  assert.equal(flutterTestRunSucceeded(output, 0), true);
});

test("handles Windows CRLF output", () => {
  const passing =
    "01:04 +1018: dropped files play\r\n01:05 +1019: All tests passed!\r\n";
  assert.equal(flutterTestRunSucceeded(passing, 0), true);

  const failing =
    "00:52 +924 -1: marker test [E]\r\n00:53 +925 -1: Some tests failed.\r\n";
  assert.equal(flutterTestOutputLooksFailed(failing), true);
  assert.equal(flutterTestRunSucceeded(failing, 0), false);
});

test("accepts a passing summary with skipped tests", () => {
  const output = "00:10 +85 ~2: All tests passed!\n";
  assert.equal(flutterTestRunSucceeded(output, 0), true);
});

test("rejects a real load failure line on its own", () => {
  const output = [
    '  Failed to load "C:/Users/main/github/DACX/test/foo_test.dart":',
    "  Compilation failed",
  ].join("\n");
  assert.equal(flutterTestOutputLooksFailed(output), true);
  assert.equal(flutterTestRunSucceeded(output, 0), false);
});

test("rejects a failing final summary", () => {
  const output = [
    "00:10 +84: some test",
    "00:11 +84 ~1 -1: Some tests failed.",
  ].join("\n");
  assert.equal(flutterTestOutputLooksFailed(output), true);
  assert.equal(flutterTestRunSucceeded(output, 0), false);
});

test("rejects All tests passed that only appears inside a log line", () => {
  const output = [
    "00:01 +3: test/report_test.dart: prints All tests passed! in the banner",
    "00:02 +4: loading next file",
  ].join("\n");
  assert.equal(flutterTestOutputLooksFullyPassed(output), false);
  assert.equal(flutterTestRunSucceeded(output, 0), false);
});

test("rejects output that stops before the final summary", () => {
  const output =
    "01:03 +1000: test/widgets/transport_controls_test.dart: dropdown\n";
  assert.equal(flutterTestOutputLooksFullyPassed(output), false);
  assert.equal(flutterTestRunSucceeded(output, 0), false);
});
