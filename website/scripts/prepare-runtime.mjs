import { copyFile, mkdir, readdir, readFile, rm, stat, writeFile } from 'node:fs/promises'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'
import { zipSync } from 'fflate'

const websiteDir = path.resolve(fileURLToPath(new URL('..', import.meta.url)))
const repoRoot = path.resolve(websiteDir, '..')
const solunaDir = path.join(repoRoot, 'soluna')
const runtimeDir = path.join(websiteDir, 'public', 'runtime')
const sourceDir = path.join(repoRoot, 'src')
const sourceAssetDir = path.join(sourceDir, 'asset')
const runtimeAssetDir = path.join(runtimeDir, 'assets')
const runtimeExtluaDir = path.join(runtimeDir, 'extlua')

function resolveRuntimePath(name, fallback) {
  const configuredPath = process.env[name]
  if (!configuredPath) {
    return fallback
  }
  if (path.isAbsolute(configuredPath)) {
    return configuredPath
  }
  return path.resolve(repoRoot, configuredPath)
}

function exists(filePath) {
  return stat(filePath).then(() => true, () => false)
}

function unquote(value) {
  const trimmed = value.trim()
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) || (trimmed.startsWith('\'') && trimmed.endsWith('\''))) {
    return trimmed.slice(1, -1)
  }
  return trimmed
}

function parseModuleList(value) {
  const normalized = value
    .trim()
    .replace(/^[\[{(]/, '')
    .replace(/[\]})]$/, '')

  return normalized
    .split(/[,\s]+/)
    .map(unquote)
    .filter(Boolean)
}

function normalizeExtluaModuleName(name) {
  const parts = name.split('.')
  if (parts.length === 0 || parts.some(part => !/^[A-Za-z0-9_-]+$/.test(part))) {
    throw new Error(`Invalid extlua module name: ${name}`)
  }
  return parts.join('/')
}

async function ensureFile(filePath, label) {
  if (!(await exists(filePath))) {
    throw new Error(`Missing ${label}: ${filePath}`)
  }
}

async function collectFiles(rootDir) {
  const files = []
  const entries = await readdir(rootDir, { withFileTypes: true })
  entries.sort((left, right) => left.name.localeCompare(right.name))
  for (const entry of entries) {
    const fullPath = path.join(rootDir, entry.name)
    if (entry.isDirectory()) {
      files.push(...await collectFiles(fullPath))
    }
    else if (entry.isFile()) {
      files.push(fullPath)
    }
  }
  return files
}

async function collectExtluaModules() {
  const entries = await readdir(sourceDir, { withFileTypes: true })
  const modules = new Set()

  for (const entry of entries) {
    if (!entry.isFile() || !entry.name.endsWith('.game')) {
      continue
    }

    const gameSource = await readFile(path.join(sourceDir, entry.name), 'utf8')
    for (const line of gameSource.split(/\r?\n/)) {
      const match = line.match(/^\s*extlua_preload\s*:\s*(.+?)\s*$/i)
      if (!match) {
        continue
      }
      for (const moduleName of parseModuleList(match[1])) {
        modules.add(moduleName)
      }
    }
  }

  return [...modules].sort()
}

async function copyExtluaModules() {
  const moduleNames = await collectExtluaModules()
  if (moduleNames.length === 0) {
    return 0
  }

  const extluaBinDir = resolveRuntimePath('EXTLUA_BIN_DIR', path.join(sourceDir, 'bin'))
  for (const moduleName of moduleNames) {
    const runtimePath = normalizeExtluaModuleName(moduleName)
    const sourcePath = path.join(extluaBinDir, `${runtimePath}.wasm`)
    const targetPath = path.join(runtimeExtluaDir, `${runtimePath}.wasm`)
    await ensureFile(sourcePath, `extlua wasm module ${moduleName}`)
    await mkdir(path.dirname(targetPath), { recursive: true })
    await copyFile(sourcePath, targetPath)
  }

  return moduleNames.length
}

async function buildAssetArchives() {
  if (!(await exists(sourceAssetDir))) {
    return 0
  }

  await mkdir(runtimeAssetDir, { recursive: true })
  const entries = await readdir(sourceAssetDir, { withFileTypes: true })
  let archiveCount = 0

  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue
    }

    const assetRoot = path.join(sourceAssetDir, entry.name)
    const files = await collectFiles(assetRoot)
    if (files.length === 0) {
      continue
    }

    const archiveEntries = {}
    for (const filePath of files) {
      const archivePath = path.relative(sourceDir, filePath).split(path.sep).join('/')
      archiveEntries[archivePath] = await readFile(filePath)
    }

    await writeFile(path.join(runtimeAssetDir, `${entry.name}.zip`), zipSync(archiveEntries))
    archiveCount = archiveCount + 1
  }

  return archiveCount
}

async function main() {
  const solunaJsPath = resolveRuntimePath('SOLUNA_JS_PATH', path.join(solunaDir, 'bin', 'emcc', 'release', 'soluna.js'))
  const solunaWasmPath = resolveRuntimePath('SOLUNA_WASM_PATH', path.join(solunaDir, 'bin', 'emcc', 'release', 'soluna.wasm'))
  const solunaWasmMapPath = resolveRuntimePath(
    'SOLUNA_WASM_MAP_PATH',
    path.join(solunaDir, 'bin', 'emcc', 'release', 'soluna.wasm.map'),
  )

  await ensureFile(solunaJsPath, 'soluna.js')
  await ensureFile(solunaWasmPath, 'soluna.wasm')

  await rm(runtimeDir, { recursive: true, force: true })
  await mkdir(runtimeDir, { recursive: true })

  await copyFile(solunaJsPath, path.join(runtimeDir, 'soluna.js'))
  await copyFile(solunaWasmPath, path.join(runtimeDir, 'soluna.wasm'))

  if (await exists(solunaWasmMapPath)) {
    await copyFile(solunaWasmMapPath, path.join(runtimeDir, 'soluna.wasm.map'))
  }

  const extluaCount = await copyExtluaModules()
  const archiveCount = await buildAssetArchives()
  process.stdout.write(
    `Prepared website runtime in ${runtimeDir} (${archiveCount} asset archive${archiveCount == 1 ? '' : 's'}, ${extluaCount} extlua module${extluaCount == 1 ? '' : 's'})\n`,
  )
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`)
  process.exitCode = 1
})
