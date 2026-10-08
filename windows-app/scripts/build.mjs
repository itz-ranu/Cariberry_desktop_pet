// One command to build the Windows installer, on a Mac or on Windows itself:   npm run dist
//   1. makes the icon if it's missing,
//   2. packs the app and wraps it in an NSIS installer (electron-builder), once for each kind of PC:
//        CariberrySetup.exe          64-bit Windows 10/11 (what almost everyone has; it also runs on ARM PCs)
//        CariberrySetup-arm64.exe    Windows on ARM, natively (Surface Pro X, Snapdragon laptops)
//        CariberrySetup-32bit.exe    32-bit Windows 10
//   3. copies them into ../download/windows/ with a checksum each.
//   `npm run dist -- x64` builds just the main one (quicker).
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const bin = (name) => path.join(root, 'node_modules', '.bin', name + (process.platform === 'win32' ? '.cmd' : ''))
const run = (cmd, args) => {
  const r = spawnSync(cmd, args, { cwd: root, stdio: 'inherit', shell: process.platform === 'win32' })
  if (r.status !== 0) { console.error(`\n  ${path.basename(cmd)} failed`); process.exit(r.status || 1) }
}

if (!fs.existsSync(path.join(root, 'node_modules'))) { console.error('  run `npm install` in windows-app first'); process.exit(1) }

const ico = path.join(root, 'build', 'icon.ico'), png = path.join(root, 'assets', 'icon.png')
if (!fs.existsSync(ico) || fs.statSync(ico).mtimeMs < fs.statSync(png).mtimeMs) {
  console.log('  making the app icon')
  run(bin('electron'), ['scripts/make-icons.cjs'])
}

const builds = [
  { arch: 'x64', name: 'CariberrySetup.exe' },
  { arch: 'arm64', name: 'CariberrySetup-arm64.exe' },
  // Electron 44 no longer ships a 32-bit Windows build (43 was the last), so this one installer is built on 43
  { arch: 'ia32', name: 'CariberrySetup-32bit.exe', electron: '43.7.7' },
].filter((b) => !process.argv[2] || process.argv.slice(2).includes(b.arch))

const out = path.resolve(root, '..', 'download', 'windows')
fs.mkdirSync(out, { recursive: true })
for (const { arch, name, electron } of builds) {
  console.log(`  building ${name} (${arch}; a few minutes the first time: it downloads Electron)`)
  run(bin('electron-builder'), ['--win', `--${arch}`, `-c.win.artifactName=${name}`, `-c.nsis.artifactName=${name}`, ...(electron ? [`-c.electronVersion=${electron}`] : [])])
  const built = path.join(root, 'dist', name)
  if (!fs.existsSync(built)) { console.error(`  ${name} was not produced`); process.exit(1) }
  const dest = path.join(out, name)
  fs.copyFileSync(built, dest)
  const sum = crypto.createHash('sha256').update(fs.readFileSync(dest)).digest('hex')
  fs.writeFileSync(`${dest}.sha256`, `${sum}  ${name}\n`)
  console.log(`\n  built ${path.relative(path.resolve(root, '..'), dest)}  (${(fs.statSync(dest).size / 1e6).toFixed(0)} MB)\n  sha256 ${sum}\n`)
}
