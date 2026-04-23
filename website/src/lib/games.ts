import { readdir, readFile, stat } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

export interface GameEntry {
  id: string
  title: string
  entry: string
  width: number
  height: number
  luaSource: string
  gameSource: string
  runtimeGameSource: string
  runtimeFiles: Array<{
    path: string
    source: string
  }>
  assetArchivePath?: string | null
}

const repoRoot = path.resolve(fileURLToPath(new URL('../../..', import.meta.url)))
const sourceDir = path.join(repoRoot, 'src')

function titleize(name: string): string {
  return name
    .split(/[_\-\s]+/)
    .filter(Boolean)
    .map(part => part.slice(0, 1).toUpperCase() + part.slice(1))
    .join(' ')
}

function unquote(value: string): string {
  const trimmed = value.trim()
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) || (trimmed.startsWith('\'') && trimmed.endsWith('\''))) {
    return trimmed.slice(1, -1)
  }
  return trimmed
}

function parseConfig(source: string) {
  let title: string | undefined
  let entry: string | undefined
  let width = 640
  let height = 480

  for (const line of source.split(/\r?\n/)) {
    const match = line.match(/^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+?)\s*$/)
    if (!match) {
      continue
    }

    const [, rawKey, rawValue] = match
    const key = rawKey.toLowerCase()
    const value = rawValue.trim()

    if (key === 'window_title') {
      title = unquote(value)
    }
    else if (key === 'entry') {
      entry = unquote(value)
    }
    else if (key === 'width') {
      const parsed = Number.parseInt(value, 10)
      if (Number.isFinite(parsed)) {
        width = parsed
      }
    }
    else if (key === 'height') {
      const parsed = Number.parseInt(value, 10)
      if (Number.isFinite(parsed)) {
        height = parsed
      }
    }
  }

  return {
    title,
    entry,
    width,
    height,
  }
}

function buildRuntimeGameSource(source: string): string {
  const lines = source.split(/\r?\n/)
  let replaced = false

  const normalized = lines.map((line) => {
    if (/^\s*entry\s*:/.test(line)) {
      replaced = true
      return 'entry : main.lua'
    }
    return line
  })

  if (!replaced) {
    normalized.unshift('entry : main.lua')
  }

  return `${normalized.join('\n').trimEnd()}\n`
}

function exists(filePath: string): Promise<boolean> {
  return stat(filePath).then(() => true, () => false)
}

export async function loadGames(): Promise<GameEntry[]> {
  const sourceFiles = (await readdir(sourceDir))
    .sort((left, right) => left.localeCompare(right))
  const luaFiles = sourceFiles.filter(name => name.endsWith('.lua'))
  const gameIds = new Set(
    sourceFiles
      .filter(name => name.endsWith('.game'))
      .map(name => name.slice(0, -5)),
  )
  const sharedLuaFiles = luaFiles.filter(name => !gameIds.has(name.slice(0, -4)))
  const sharedLuaSources = new Map(
    await Promise.all(
      sharedLuaFiles.map(async (name) => [
        name,
        await readFile(path.join(sourceDir, name), 'utf8'),
      ]),
    ),
  )

  return Promise.all(
    luaFiles.map(async (name) => {
      const id = name.slice(0, -4)
      if (!gameIds.has(id)) {
        return null
      }

      const luaSource = await readFile(path.join(sourceDir, name), 'utf8')
      const gamePath = path.join(sourceDir, `${id}.game`)
      const gameSource = await readFile(gamePath, 'utf8')
      const config = parseConfig(gameSource)

      return {
        id,
        title: config.title || titleize(id),
        entry: config.entry || name,
        width: config.width,
        height: config.height,
        luaSource,
        gameSource,
        runtimeGameSource: buildRuntimeGameSource(gameSource),
        runtimeFiles: sharedLuaFiles.map(sharedName => ({
          path: sharedName,
          source: sharedLuaSources.get(sharedName) || '',
        })),
        assetArchivePath: await exists(path.join(sourceDir, 'asset', id)) ? `runtime/assets/${id}.zip` : null,
      }
    }),
  ).then(entries => entries.filter(entry => entry !== null))
}
