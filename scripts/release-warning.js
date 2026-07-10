#!/usr/bin/env node
const red = '\x1b[31m';
const reset = '\x1b[0m';
const msg = '[NOTICE] Release scripts now require a clean branch before starting and no longer reset/clean your working tree.';
console.error(`\n${red}${msg}${reset}\n`);

setTimeout(() => {
	process.exit(0);
}, 3000);
