import { copyFile, mkdir, rm, stat } from 'node:fs/promises'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

const websiteDir = path.resolve(fileURLToPath(new URL('..', import.meta.url)))
const repoRoot = path.resolve(websiteDir, '..')
const solunaDir = path.join(repoRoot, 'soluna')
const runtimeDir = path.join(websiteDir, 'public', 'runtime')

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

  process.stdout.write(`Prepared website runtime in ${runtimeDir}\n`)
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`)
  process.exitCode = 1
})
