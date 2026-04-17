#!/usr/bin/env node
/**
 * clawfarm — CLI for the GigaClaw Orchestrator prototype.
 *
 * Each subcommand maps to a future Orchestrator operation (see roadmap):
 *   add-user  ← 3.1 /admin add-user + 2.3 createContainer
 *   remove    ← 3.1 /admin remove
 *   reset     ← 2.3 reset(user)  — rotate env / rebuild image
 *   stop      ← 3.1 /admin suspend
 *   start     ← 2.4
 *   logs      ← 2.4 containerLogs
 *   list      ← 3.1 /admin list-users
 */

// Load CLI config from orchestrator/.env before importing modules that read env vars.
// Supported vars: GIGACLAW_IMAGE, GIGACLAW_DATA_ROOT, GIGACLAW_BASE_PORT.
import * as path from 'path'
import * as dotenv from 'dotenv'
dotenv.config({ path: path.resolve(__dirname, '..', '.env') })

import { Command } from 'commander'
import {
  addUser,
  removeUser,
  reset,
  stopUser,
  startUser,
  logsUser,
  listUsers
} from './docker'

const program = new Command()

program
  .name('clawfarm')
  .description('GigaClaw Orchestrator prototype (local Docker API wrapper)')
  .version('0.1.0')

program.command('add-user <username>')
  .description('Provision + create + start user container')
  .requiredOption('-e, --env <file>', 'Path to .env file with user credentials')
  .action(async (username: string, opts: { env: string }) => {
    await addUser({ username, envFile: opts.env })
  })

program.command('remove <username>')
  .description('Stop and remove container (data volume kept on disk)')
  .action(async (username: string) => {
    await removeUser(username)
  })

program.command('reset <username>')
  .description('Recreate container (for env rotation or image update)')
  .requiredOption('-e, --env <file>', 'Path to .env file')
  .action(async (username: string, opts: { env: string }) => {
    await reset({ username, envFile: opts.env })
  })

program.command('stop <username>')
  .description('Stop a running container')
  .action(async (username: string) => {
    await stopUser(username)
  })

program.command('start <username>')
  .description('Start a stopped container')
  .action(async (username: string) => {
    await startUser(username)
  })

program.command('logs <username>')
  .description('Show container logs')
  .option('-n, --tail <n>', 'Number of lines from the end', '100')
  .option('-f, --follow', 'Follow log output', false)
  .action(async (username: string, opts: { tail: string; follow: boolean }) => {
    await logsUser(username, Number(opts.tail), opts.follow)
  })

program.command('list')
  .description('List all GigaClaw-managed containers')
  .action(async () => {
    const users = await listUsers()
    if (users.length === 0) {
      console.log('(no users)')
      return
    }
    console.table(users.map(u => ({
      username: u.username,
      state: u.state,
      status: u.status,
      port: u.port ?? '-',
      id: u.containerId
    })))
  })

program.parseAsync().catch((err: Error) => {
  console.error(`ERROR: ${err.message}`)
  process.exit(1)
})
