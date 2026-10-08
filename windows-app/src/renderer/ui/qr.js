// A QR code maker, written from the QR Code (ISO/IEC 18004) spec instead of pulled in as a library. It does the one thing
// the study card needs: a short piece of text, as bytes, with the "M" error-correction level (about 15% of the code can be
// damaged and it still reads). That is enough for a link of up to 213 bytes (versions 1 to 10, 21 to 57 modules a side).
//
//   qrDataUrl('https://example.com')  ->  'data:image/svg+xml,...'   (an <img src> that stays sharp at any size)
//   qrMatrix('https://example.com')   ->  array of rows, each an array of booleans (true is a dark module)

// ECC level M, per version: [error-correction codewords per block, blocks, data codewords per block, blocks, data codewords per block]
const BLOCKS = [
  null,
  [10, 1, 16, 0, 0], [16, 1, 28, 0, 0], [26, 1, 44, 0, 0], [18, 2, 32, 0, 0], [24, 2, 43, 0, 0],
  [16, 4, 27, 0, 0], [18, 4, 31, 0, 0], [22, 2, 38, 2, 39], [22, 3, 36, 2, 37], [26, 4, 43, 1, 44],
]
const ALIGNMENT = [null, [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]]
const MAX_VERSION = BLOCKS.length - 1

// ------------------------------------------------------------------ Reed-Solomon over GF(256)

const EXP = new Uint8Array(512)
const LOG = new Uint8Array(256)
for (let i = 0, x = 1; i < 255; i++) {
  EXP[i] = x; LOG[x] = i
  x <<= 1
  if (x & 0x100) x ^= 0x11d
}
for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255]
const mul = (a, b) => (a && b ? EXP[LOG[a] + LOG[b]] : 0)

/** The `n` error-correction codewords for one block of data. */
export function reedSolomon(data, n) {
  let gen = [1]                                                         // (x - a^0)(x - a^1)...(x - a^(n-1)), highest power first
  for (let i = 0; i < n; i++) {
    const next = new Array(gen.length + 1).fill(0)
    gen.forEach((g, j) => { next[j] ^= g; next[j + 1] ^= mul(g, EXP[i]) })
    gen = next
  }
  const rest = new Array(n).fill(0)
  for (const d of data) {
    const lead = d ^ rest.shift()
    rest.push(0)
    if (lead) for (let i = 0; i < n; i++) rest[i] ^= mul(gen[i + 1], lead)
  }
  return rest
}

// ------------------------------------------------------------------ the bits

/** Text -> the interleaved data and error-correction bytes of the smallest version that fits. */
function codewords(text) {
  const bytes = new TextEncoder().encode(text)
  let version = 1
  const capacity = (v) => { const b = BLOCKS[v]; return b[1] * b[2] + b[3] * b[4] }
  while (version <= MAX_VERSION && bytes.length + (version < 10 ? 2 : 3) > capacity(version)) version++     // mode + length + bytes
  if (version > MAX_VERSION) throw new Error(`that is too long for the QR code maker (${bytes.length} bytes, 213 at most)`)

  const bits = []
  const put = (value, count) => { for (let i = count - 1; i >= 0; i--) bits.push((value >>> i) & 1) }
  put(0b0100, 4)                                                        // byte mode
  put(bytes.length, version < 10 ? 8 : 16)
  for (const b of bytes) put(b, 8)
  const total = capacity(version) * 8
  put(0, Math.min(4, total - bits.length))                              // terminator
  while (bits.length % 8) bits.push(0)
  const data = []
  for (let i = 0; i < bits.length; i += 8) data.push(parseInt(bits.slice(i, i + 8).join(''), 2))
  for (let pad = 0xec; data.length < capacity(version); pad ^= 0xec ^ 0x11) data.push(pad)

  const [ecLen, n1, len1, n2, len2] = BLOCKS[version]
  const blocks = []
  let at = 0
  for (let i = 0; i < n1 + n2; i++) {
    const len = i < n1 ? len1 : len2
    const chunk = data.slice(at, at + len); at += len
    blocks.push({ data: chunk, ec: reedSolomon(chunk, ecLen) })
  }
  const out = []
  for (let i = 0; i < Math.max(len1, len2); i++) for (const b of blocks) if (i < b.data.length) out.push(b.data[i])
  for (let i = 0; i < ecLen; i++) for (const b of blocks) out.push(b.ec[i])
  return { version, out }
}

/** A value with `bits` check bits appended (BCH code): used for the format and version areas. */
function bch(value, generator, genBits) {
  let rest = value << (genBits - 1)
  for (let i = 31 - Math.clz32(rest); i >= genBits - 1; i--) if ((rest >>> i) & 1) rest ^= generator << (i - (genBits - 1))
  return (value << (genBits - 1)) | rest
}

// ------------------------------------------------------------------ the picture

const MASKS = [
  (r, c) => (r + c) % 2 === 0,
  (r) => r % 2 === 0,
  (r, c) => c % 3 === 0,
  (r, c) => (r + c) % 3 === 0,
  (r, c) => (Math.floor(r / 2) + Math.floor(c / 3)) % 2 === 0,
  (r, c) => ((r * c) % 2) + ((r * c) % 3) === 0,
  (r, c) => (((r * c) % 2) + ((r * c) % 3)) % 2 === 0,
  (r, c) => (((r * c) % 3) + ((r + c) % 2)) % 2 === 0,
]

/** The squares that never carry data (finders, timing, alignment, format and version areas) and which of them are dark. */
function frame(version) {
  const size = version * 4 + 17
  const dark = Array.from({ length: size }, () => new Array(size).fill(false))
  const fixed = Array.from({ length: size }, () => new Array(size).fill(false))
  const set = (r, c, on) => { if (r >= 0 && c >= 0 && r < size && c < size) { dark[r][c] = on; fixed[r][c] = true } }

  for (const [r0, c0] of [[0, 0], [0, size - 7], [size - 7, 0]]) {      // the three finder squares, each with its white margin
    for (let r = -1; r <= 7; r++) for (let c = -1; c <= 7; c++) {
      const inside = r >= 0 && r <= 6 && c >= 0 && c <= 6
      const ring = r === 0 || r === 6 || c === 0 || c === 6 || (r >= 2 && r <= 4 && c >= 2 && c <= 4)
      set(r0 + r, c0 + c, inside && ring)
    }
  }
  for (let i = 8; i < size - 8; i++) { set(6, i, i % 2 === 0); set(i, 6, i % 2 === 0) }     // timing lines
  const centres = ALIGNMENT[version]
  const last = centres.at(-1)
  for (const r of centres) for (const c of centres) {
    if ((r === 6 && c === 6) || (r === 6 && c === last) || (r === last && c === 6)) continue       // those three would sit on a finder square
    for (let dr = -2; dr <= 2; dr++) for (let dc = -2; dc <= 2; dc++) set(r + dr, c + dc, Math.max(Math.abs(dr), Math.abs(dc)) !== 1)
  }
  for (let i = 0; i < 9; i++) { fixed[8][i] = true; fixed[i][8] = true }        // room for the format bits
  for (let i = 0; i < 8; i++) { fixed[8][size - 1 - i] = true; fixed[size - 1 - i][8] = true }
  set(size - 8, 8, true)                                                       // the one module that is always dark
  if (version >= 7) {
    const info = bch(version, 0x1f25, 13)
    for (let i = 0; i < 18; i++) {
      const on = ((info >>> i) & 1) === 1
      set(Math.floor(i / 3), (i % 3) + size - 11, on)
      set((i % 3) + size - 11, Math.floor(i / 3), on)
    }
  }
  return { size, dark, fixed }
}

/** Runs of the same colour, 2x2 blocks, look-alikes of a finder square and an unbalanced mix: the spec's four penalties. */
function penalty(m) {
  const n = m.length
  let score = 0
  const lines = [...m, ...m.map((_, c) => m.map((row) => row[c]))]
  for (const line of lines) {
    let run = 1
    for (let i = 1; i <= n; i++) {
      if (i < n && line[i] === line[i - 1]) run++
      else { if (run >= 5) score += 3 + run - 5; run = 1 }
    }
    for (let i = 0; i + 11 <= n; i++) {                                  // dark-light-dark-dark-dark-light-dark with four light squares on a side
      const w = line.slice(i, i + 11).map((x) => (x ? 1 : 0)).join('')
      if (w === '10111010000' || w === '00001011101') score += 40
    }
  }
  for (let r = 0; r < n - 1; r++) for (let c = 0; c < n - 1; c++) if (m[r][c] === m[r][c + 1] && m[r][c] === m[r + 1][c] && m[r][c] === m[r + 1][c + 1]) score += 3
  const darkCount = m.reduce((a, row) => a + row.filter(Boolean).length, 0)
  score += Math.floor(Math.abs((darkCount * 100) / (n * n) - 50) / 5) * 10
  return score
}

function draw(version, bytes, mask) {
  const { size, dark, fixed } = frame(version)
  const m = dark.map((row) => row.slice())
  let bit = 0
  for (let col = size - 1, up = true; col > 0; col -= 2, up = !up) {      // two columns at a time, snaking up and down
    if (col === 6) col--
    for (let i = 0; i < size; i++) {
      const r = up ? size - 1 - i : i
      for (const c of [col, col - 1]) {
        if (fixed[r][c]) continue
        const on = bit < bytes.length * 8 && ((bytes[bit >> 3] >>> (7 - (bit & 7))) & 1) === 1
        m[r][c] = on !== MASKS[mask](r, c)
        bit++
      }
    }
  }
  const info = bch(mask, 0x537, 11) ^ 0x5412                             // error-correction level M is 00, then the mask number
  for (let i = 0; i < 15; i++) {
    const on = ((info >>> i) & 1) === 1
    m[i < 6 ? i : i < 8 ? i + 1 : size - 15 + i][8] = on
    m[8][i < 8 ? size - 1 - i : i < 9 ? 7 : 14 - i] = on
  }
  return m
}

/** The code as rows of booleans. `mask` (0 to 7) is for testing; left out, the best-looking one is picked. */
export function qrMatrix(text, { mask } = {}) {
  const { version, out } = codewords(text)
  if (mask !== undefined) return draw(version, out, mask)
  let best = null, bestScore = Infinity
  for (let k = 0; k < 8; k++) {
    const m = draw(version, out, k)
    const s = penalty(m)
    if (s < bestScore) { best = m; bestScore = s }
  }
  return best
}

/** The code as an SVG picture in a data: address, each module `cell` pixels wide with `margin` empty modules around it. */
export function qrDataUrl(text, cell = 8, margin = 0) {
  const m = qrMatrix(text)
  const side = m.length + margin * 2
  let path = ''
  m.forEach((row, r) => row.forEach((on, c) => { if (on) path += `M${c + margin} ${r + margin}h1v1h-1z` }))
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${side * cell}" height="${side * cell}" viewBox="0 0 ${side} ${side}" shape-rendering="crispEdges"><path d="${path}"/></svg>`
  return `data:image/svg+xml,${encodeURIComponent(svg)}`
}
