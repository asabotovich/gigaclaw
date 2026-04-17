/**
 * Docker API wrapper for GigaClaw Orchestrator prototype.
 *
 * Mirrors roadmap tasks 2.3 (createContainer, reset) and 2.4 (start/stop/remove/logs).
 * In prod, this module lives inside the Orchestrator pod in OpenShift,
 * talking to Docker daemon on ClawFarm VM via SSH (variant A) or mTLS (variant B).
 * Locally, it talks to the local Docker daemon via Unix socket.
 */

import Docker, { Container, ContainerInfo } from 'dockerode'
import { parseEnvFile, envToDockerArray } from './envfile'

const IMAGE = process.env.GIGACLAW_IMAGE ?? 'gigaclaw:latest'
const DATA_ROOT = process.env.GIGACLAW_DATA_ROOT ?? '/data/users'
const BASE_PORT = Number(process.env.GIGACLAW_BASE_PORT ?? 18789)
const USER_LABEL = 'gigaclaw.user'

const docker = new Docker()

export type UserSpec = {
  username: string
  envFile: string
}

export type UserRecord = {
  username: string
  containerId: string
  status: string
  state: string
  port: number | null
}

function containerName(username: string): string {
  return `gigaclaw-${username}`
}

function dataDir(username: string): string {
  return `${DATA_ROOT}/${username}`
}

function extractHostPort(info: ContainerInfo): number | null {
  for (const p of info.Ports ?? []) {
    if (p.PrivatePort === 18789 && p.PublicPort) return p.PublicPort
  }
  return null
}

async function findContainer(username: string): Promise<Container | null> {
  const list = await docker.listContainers({
    all: true,
    filters: { label: [`${USER_LABEL}=${username}`] }
  })
  if (list.length === 0) return null
  return docker.getContainer(list[0].Id)
}

async function allocatePort(): Promise<number> {
  const used = new Set<number>()
  const list = await docker.listContainers({ all: true })
  for (const c of list) {
    for (const p of c.Ports ?? []) {
      if (p.PublicPort) used.add(p.PublicPort)
    }
  }
  let port = BASE_PORT
  while (used.has(port)) port++
  return port
}

async function ensureImagePresent(): Promise<void> {
  try {
    await docker.getImage(IMAGE).inspect()
  } catch {
    throw new Error(`Image '${IMAGE}' not found locally. Build it first: docker build -t ${IMAGE} .`)
  }
}

/**
 * One-shot `provision` container: renders templates into the user's data dir.
 * Equivalent to: docker run --rm -v <data>:/root/.openclaw --env-file <file> <image> provision
 */
async function provision({ username, envFile }: UserSpec): Promise<void> {
  const env = envToDockerArray(parseEnvFile(envFile))
  console.log(`[provision] ${username}`)

  await docker.run(IMAGE, ['provision'], process.stdout, {
    HostConfig: {
      AutoRemove: true,
      Binds: [`${dataDir(username)}:/root/.openclaw`]
    },
    Env: env
  })
}

/**
 * Create + start user container. Roadmap 2.3 `createContainer(user)`.
 */
export async function addUser(spec: UserSpec): Promise<UserRecord> {
  await ensureImagePresent()

  const existing = await findContainer(spec.username)
  if (existing) {
    throw new Error(`User '${spec.username}' already exists. Use 'reset' to recreate.`)
  }

  await provision(spec)

  const port = await allocatePort()
  const env = envToDockerArray(parseEnvFile(spec.envFile))

  console.log(`[create] ${spec.username} on host port ${port}`)
  const container = await docker.createContainer({
    Image: IMAGE,
    name: containerName(spec.username),
    Env: env,
    Labels: { [USER_LABEL]: spec.username },
    ExposedPorts: { '18789/tcp': {} },
    HostConfig: {
      Binds: [`${dataDir(spec.username)}:/root/.openclaw`],
      RestartPolicy: { Name: 'unless-stopped' },
      PortBindings: { '18789/tcp': [{ HostPort: String(port) }] }
    }
  })

  await container.start()
  console.log(`[start] ${spec.username} → http://127.0.0.1:${port}/`)

  return {
    username: spec.username,
    containerId: container.id,
    status: 'running',
    state: 'running',
    port
  }
}

/**
 * Stop + remove container. Data volume (bind mount) is preserved on disk.
 * Roadmap 3.1 `/admin remove`.
 */
export async function removeUser(username: string): Promise<void> {
  const c = await findContainer(username)
  if (!c) throw new Error(`User '${username}' not found`)
  console.log(`[remove] ${username}`)
  await c.remove({ force: true })
}

/**
 * Recreate container with fresh env. Data volume survives. Roadmap 2.3 `reset(user)`.
 */
export async function reset(spec: UserSpec): Promise<UserRecord> {
  const existing = await findContainer(spec.username)
  if (existing) {
    console.log(`[reset] removing existing ${spec.username}`)
    await existing.remove({ force: true })
  }
  return addUser(spec)
}

/**
 * Stop running container (keep it, for later start). Roadmap 3.1 `/admin suspend`.
 */
export async function stopUser(username: string): Promise<void> {
  const c = await findContainer(username)
  if (!c) throw new Error(`User '${username}' not found`)
  console.log(`[stop] ${username}`)
  await c.stop()
}

/**
 * Start a stopped container. Roadmap 2.4.
 */
export async function startUser(username: string): Promise<void> {
  const c = await findContainer(username)
  if (!c) throw new Error(`User '${username}' not found`)
  console.log(`[start] ${username}`)
  await c.start()
}

/**
 * Tail container logs. Roadmap 2.4 `containerLogs`.
 */
export async function logsUser(username: string, tail: number, follow: boolean): Promise<void> {
  const c = await findContainer(username)
  if (!c) throw new Error(`User '${username}' not found`)

  if (follow) {
    const stream = await c.logs({ stdout: true, stderr: true, tail, follow: true, timestamps: false })
    docker.modem.demuxStream(stream, process.stdout, process.stderr)
    await new Promise<void>(resolve => stream.on('end', resolve))
  } else {
    const buf = await c.logs({ stdout: true, stderr: true, tail, follow: false, timestamps: false })
    process.stdout.write(buf)
  }
}

/**
 * List all GigaClaw-managed containers. Roadmap 3.1 `/admin list-users`.
 */
export async function listUsers(): Promise<UserRecord[]> {
  const list = await docker.listContainers({
    all: true,
    filters: { label: [USER_LABEL] }
  })

  return list.map(info => ({
    username: info.Labels[USER_LABEL],
    containerId: info.Id.slice(0, 12),
    status: info.Status,
    state: info.State,
    port: extractHostPort(info)
  }))
}
