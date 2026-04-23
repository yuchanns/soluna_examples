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

  const archiveCount = await buildAssetArchives()
  process.stdout.write(`Prepared website runtime in ${runtimeDir} (${archiveCount} asset archive${archiveCount == 1 ? '' : 's'})\n`)
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`)
  process.exitCode = 1
})
