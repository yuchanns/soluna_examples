import process from 'node:process'
import { defineConfig } from 'astro/config'

const site = process.env.SITE_URL || 'https://example.github.io'
const configuredBase = process.env.SITE_BASE || '/'
const base = configuredBase.endsWith('/') ? configuredBase : `${configuredBase}/`

export default defineConfig({
  site,
  base,
  output: 'static',
})
