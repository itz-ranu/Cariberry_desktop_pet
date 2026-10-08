// Builds build/icon.ico (16 to 256 px) from assets/icon.png, the same icon the Mac app uses.
//   npm run icons        (run through Electron only because it resizes images without any extra dependency)
const { app, nativeImage } = require('electron')
const fs = require('node:fs')
const path = require('node:path')

const SIZES = [16, 24, 32, 48, 64, 128, 256]
const root = path.join(__dirname, '..')

/** An .ico is a small directory of PNGs. */
function ico(entries) {
  const head = Buffer.alloc(6)
  head.writeUInt16LE(1, 2); head.writeUInt16LE(entries.length, 4)
  const dir = Buffer.alloc(16 * entries.length)
  let offset = 6 + dir.length
  entries.forEach((e, i) => {
    const o = i * 16
    dir[o] = e.size >= 256 ? 0 : e.size; dir[o + 1] = e.size >= 256 ? 0 : e.size
    dir.writeUInt16LE(1, o + 4); dir.writeUInt16LE(32, o + 6)
    dir.writeUInt32LE(e.png.length, o + 8); dir.writeUInt32LE(offset, o + 12)
    offset += e.png.length
  })
  return Buffer.concat([head, dir, ...entries.map((e) => e.png)])
}

app.whenReady().then(() => {
  const src = nativeImage.createFromPath(path.join(root, 'assets', 'icon.png'))
  if (src.isEmpty()) { console.error('assets/icon.png is missing'); app.exit(1); return }
  const entries = SIZES.map((size) => ({ size, png: src.resize({ width: size, height: size, quality: 'best' }).toPNG() }))
  fs.mkdirSync(path.join(root, 'build'), { recursive: true })
  fs.writeFileSync(path.join(root, 'build', 'icon.ico'), ico(entries))
  fs.writeFileSync(path.join(root, 'build', 'icon.png'), src.resize({ width: 512, height: 512, quality: 'best' }).toPNG())
  console.log('wrote build/icon.ico', SIZES.join(' '))
  app.quit()
})
