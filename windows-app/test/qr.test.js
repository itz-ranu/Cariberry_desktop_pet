import test from 'node:test'
import assert from 'node:assert/strict'
import { qrMatrix, qrDataUrl, reedSolomon } from '../src/renderer/ui/qr.js'

test('Reed-Solomon matches the worked example in the spec (version 1-M, 16 data bytes, 10 check bytes)', () => {
  const data = [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17]
  assert.deepEqual(reedSolomon(data, 10), [196, 35, 39, 119, 235, 215, 231, 226, 93, 23])
})

test('size grows with the text: 21 modules for a few bytes, then 25, 29...', () => {
  assert.equal(qrMatrix('hi').length, 21)
  assert.equal(qrMatrix('x'.repeat(15)).length, 25)
  assert.equal(qrMatrix('https://github.com/itz-ranu/Cariberry').length, 29)
  assert.equal(qrMatrix('x'.repeat(213)).length, 57)
  assert.throws(() => qrMatrix('x'.repeat(214)), /too long/)
})

test('the three finder squares, the timing lines and the dark module are where the spec puts them', () => {
  const m = qrMatrix('Cariberry')
  const n = m.length
  for (const [r0, c0] of [[0, 0], [0, n - 7], [n - 7, 0]]) {
    for (let r = 0; r < 7; r++) for (let c = 0; c < 7; c++) {
      const ring = r === 0 || r === 6 || c === 0 || c === 6 || (r >= 2 && r <= 4 && c >= 2 && c <= 4)
      assert.equal(m[r0 + r][c0 + c], ring)
    }
  }
  for (let i = 8; i < n - 8; i++) { assert.equal(m[6][i], i % 2 === 0); assert.equal(m[i][6], i % 2 === 0) }
  assert.equal(m[n - 8][8], true)
})

test('the same text always gives the same picture, and every mask gives a different one', () => {
  assert.deepEqual(qrMatrix('same'), qrMatrix('same'))
  const seen = new Set(Array.from({ length: 8 }, (_, k) => JSON.stringify(qrMatrix('masks', { mask: k }))))
  assert.equal(seen.size, 8)
})

test('the data URL is an SVG sized module-count x cell', () => {
  const url = qrDataUrl('https://example.com', 8, 0)
  assert.ok(url.startsWith('data:image/svg+xml,'))
  const svg = decodeURIComponent(url.slice('data:image/svg+xml,'.length))
  const side = qrMatrix('https://example.com').length
  assert.match(svg, new RegExp(`width="${side * 8}" height="${side * 8}" viewBox="0 0 ${side} ${side}"`))
})
