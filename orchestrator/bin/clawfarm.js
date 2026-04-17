#!/usr/bin/env node
/**
 * Shim: prefers compiled dist/cli.js, falls back to ts-node for dev.
 * This lets `npx clawfarm` work without an explicit build step.
 */
const path = require('path')
const fs = require('fs')

const distCli = path.join(__dirname, '..', 'dist', 'cli.js')
const srcCli = path.join(__dirname, '..', 'src', 'cli.ts')

if (fs.existsSync(distCli)) {
  require(distCli)
} else {
  require('ts-node/register')
  require(srcCli)
}
