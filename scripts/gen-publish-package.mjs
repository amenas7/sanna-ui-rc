/**
 * Genera un package.json listo para npm/git-install desde la raíz del artefacto
 * (sin carpeta dist/: main/module apuntan a los .js en el mismo directorio).
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'

const rootPkgPath = resolve(process.cwd(), 'package.json')
const outPath = resolve(process.cwd(), process.argv[2] || 'package.json')
mkdirSync(dirname(outPath), { recursive: true })

const pkg = JSON.parse(readFileSync(rootPkgPath, 'utf8'))

const publish = {
  name: pkg.name,
  version: pkg.version,
  description: pkg.description ?? '',
  type: pkg.type ?? 'module',
  main: 'sanna-ui-rc.cjs.js',
  module: 'sanna-ui-rc.es.js',
  types: 'src/index.d.ts',
  exports: {
    '.': {
      import: './sanna-ui-rc.es.js',
      require: './sanna-ui-rc.cjs.js',
      types: './src/index.d.ts',
    },
  },
  files: ['sanna-ui-rc.es.js', 'sanna-ui-rc.cjs.js', 'src'],
  peerDependencies: pkg.peerDependencies ?? {},
}

if (pkg.keywords) publish.keywords = pkg.keywords
if (pkg.author) publish.author = pkg.author
if (pkg.license) publish.license = pkg.license
if (pkg.repository) publish.repository = pkg.repository
if (pkg.bugs) publish.bugs = pkg.bugs
if (pkg.homepage) publish.homepage = pkg.homepage

writeFileSync(outPath, JSON.stringify(publish, null, 2) + '\n')
