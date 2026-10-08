// Dev only: a static server that never caches, so the browser pane always sees the latest code.
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.wav': 'audio/wav', '.png': 'image/png' }
http.createServer((req, res) => {
  const f = path.join(root, decodeURIComponent(req.url.split('?')[0]))
  fs.readFile(f, (e, d) => {
    if (e) { res.writeHead(404); res.end('nope'); return }
    res.writeHead(200, { 'content-type': types[path.extname(f)] || 'application/octet-stream', 'cache-control': 'no-store' }); res.end(d)
  })
}).listen(8123)
