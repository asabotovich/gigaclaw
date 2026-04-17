import { readFileSync } from 'fs'

/**
 * Parse a .env file into a plain object. Handles quoted values, comments, blank lines.
 */
export function parseEnvFile(path: string): Record<string, string> {
  const content = readFileSync(path, 'utf-8')
  const result: Record<string, string> = {}

  for (const line of content.split('\n')) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue

    const match = trimmed.match(/^([A-Z_][A-Z0-9_]*)=(.*)$/)
    if (!match) continue

    const [, key, rawValue] = match
    // Strip matching surrounding quotes
    const value = rawValue.replace(/^(['"])(.*)\1$/, '$2')
    result[key] = value
  }

  return result
}

/**
 * Convert env object to Docker API's Env array format: ['KEY=value', ...]
 */
export function envToDockerArray(env: Record<string, string>): string[] {
  return Object.entries(env).map(([k, v]) => `${k}=${v}`)
}
