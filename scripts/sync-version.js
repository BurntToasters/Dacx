#!/usr/bin/env node

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const version = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf-8")).version;

const pubspecPath = path.join(root, "pubspec.yaml");
let pubspec = fs.readFileSync(pubspecPath, "utf-8");

const versionPattern = /^(version:\s*)[\d]+\.[\d]+\.[\d]+(?:-[0-9A-Za-z.-]+)?(?:\+\d+)?/m;
const match = pubspec.match(versionPattern);

if (match) {
  const buildNumber = match[0].includes("+")
    ? match[0].split("+")[1]
    : "1";
  const newVersionLine = `${match[1]}${version}+${buildNumber}`;

  if (match[0] !== newVersionLine) {
    pubspec = pubspec.replace(versionPattern, newVersionLine);
    fs.writeFileSync(pubspecPath, pubspec);
    console.log(`pubspec.yaml → ${version}+${buildNumber}`);
  }
}
