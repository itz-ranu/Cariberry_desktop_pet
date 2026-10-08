import test from 'node:test'
import assert from 'node:assert/strict'
import { parseChain, understand, bestMatch, similarity, appSlot, webAppSlot, musicQuery, sseJson, LLM, LLMError, systemPrompt, runSteps, tokenize, closeScript } from '../src/main/brain.js'

test('a chained request becomes steps', () => {
  assert.deepEqual(parseChain('open Notion and start my study playlist'), [{ kind: 'open', arg: 'Notion' }, { kind: 'music', arg: 'study' }])
  assert.deepEqual(parseChain('Cranberry, open Chrome, then Spotify'), [{ kind: 'open', arg: 'Chrome' }, { kind: 'open', arg: 'Spotify' }])
  assert.deepEqual(parseChain('close discord & open word').map((s) => s.kind), ['close', 'open'])
})

test('focus and music commands are steps even alone; plain chat and single opens are not', () => {
  assert.deepEqual(parseChain('start a 45 minute focus'), [{ kind: 'focus', arg: '45' }])
  assert.deepEqual(parseChain('start a pomodoro'), [{ kind: 'focus', arg: '25' }])
  assert.equal(parseChain('play some lo-fi').length, 1)
  assert.deepEqual(parseChain('open spotify'), [])
  assert.deepEqual(parseChain('how are you today'), [])
})

test('music query drops the filler', () => {
  assert.equal(musicQuery('play my rainy lo-fi playlist'), 'rainy lo-fi')
  assert.equal(musicQuery('start the music'), 'study')
})

test('app names match whole words first, then strict typos', () => {
  assert.equal(appSlot('open whatsup'), 'WhatsApp')
  assert.equal(appSlot('please launch spotifiy'), 'Spotify')
  assert.equal(appSlot('open vscode'), 'VS Code')
  assert.equal(appSlot('open the calculator'), 'Calculator')
  // "mail" must never match inside "gmail"
  assert.equal(webAppSlot('open gmail'), 'https://mail.google.com')
  assert.equal(appSlot('open gmail'), null)
  assert.equal(appSlot('open mail'), 'Mail')
  assert.equal(appSlot('how is the weather'), null)
})

test('understanding open, close and "this window"', () => {
  assert.deepEqual(understand('open spotify'), { intent: 'open_app', kind: 'app', target: 'Spotify' })
  assert.deepEqual(understand('can you open youtube'), { intent: 'open_app', kind: 'url', target: 'https://youtube.com' })
  assert.deepEqual(understand('close chrome'), { intent: 'close_app', kind: 'app', target: 'Chrome' })
  assert.deepEqual(understand('close this window'), { intent: 'close_app', kind: 'window', target: null })
  assert.deepEqual(understand('tell me a joke'), { intent: 'chat' })
  assert.deepEqual(understand('open my unknown widget', ['Thing']), { intent: 'chat' }, 'an app that isn\'t named is not guessed at')
  assert.equal(understand('open obsidian', ['Obsidian']).target, 'Obsidian', 'apps found in the Start menu count too')
})

test('similarity is 1 for equal strings and low for unrelated ones', () => {
  assert.equal(similarity('spotify', 'spotify'), 1)
  assert.ok(similarity('spotifiy', 'spotify') >= 0.9)
  assert.ok(similarity('mail', 'gmail') < 0.9)
  assert.equal(similarity('', 'x'), 0)
  assert.deepEqual(tokenize("Open Who's 🐾"), ['open', "who's", '🐾'])
  assert.equal(bestMatch('zzz', { abc: 1 }), null)
})

// ---- the chat brains, against fake servers

const streamOf = (text) => new Response(new ReadableStream({ start(c) { for (const part of text.match(/[\s\S]{1,17}/g) || []) c.enqueue(new TextEncoder().encode(part)); c.close() } }))
const sse = (...events) => events.map((e) => `data: ${typeof e === 'string' ? e : JSON.stringify(e)}\n\n`).join('')
async function collect(iter) { let out = ''; for await (const c of iter) out += c; return out }

test('server-sent events survive being split mid-line', async () => {
  const body = streamOf(sse({ a: 1 }, '[DONE]', { b: 2 })).body
  const got = []
  for await (const e of sseJson(body)) got.push(e)
  assert.deepEqual(got, [{ a: 1 }, { b: 2 }])
})

test('OpenAI, Gemini and Ollama are streamed and remembered', async () => {
  const seen = {}
  const fake = async (url, init) => {
    const body = JSON.parse(init.body)
    if (url.includes('openai')) { seen.openai = { headers: init.headers, body }; return streamOf(sse({ choices: [{ delta: { content: 'he' } }] }, { choices: [{ delta: { content: 'y' } }] }, '[DONE]')) }
    if (url.includes('googleapis')) { seen.gemini = { headers: init.headers, body, url }; return streamOf(sse({ candidates: [{ content: { parts: [{ text: 'hi ' }, { text: 'there' }] } }] })) }
    seen.ollama = { body }; return streamOf(JSON.stringify({ message: { content: 'yo' } }) + '\n' + JSON.stringify({ message: { content: '!' }, done: true }) + '\n')
  }
  const llm = new LLM(fake)
  const persona = { name: 'Mochi', species: 'Kitten', voice: 'sassy', vibe: 'Gentle Cozy', mood: 'Stressed' }
  assert.equal(await collect(llm.stream({ provider: 'openai', key: 'k', text: 'hi', persona })), 'hey')
  assert.equal(await collect(llm.stream({ provider: 'openai', key: 'k', text: 'again', persona })), 'hey')
  assert.match(seen.openai.body.messages[0].content, /You are Mochi, a Kitten/)
  assert.match(seen.openai.body.messages[0].content, /Gentle Cozy/)
  assert.match(seen.openai.body.messages[0].content, /feel stressed today/)
  assert.equal(seen.openai.headers.authorization, 'Bearer k')
  assert.deepEqual(seen.openai.body.messages.map((m) => m.role), ['system', 'user', 'assistant', 'user'], 'earlier turns are carried along')
  assert.equal(await collect(llm.stream({ provider: 'gemini', key: 'g', text: 'x', persona })), 'hi there')
  assert.equal(seen.gemini.headers['x-goog-api-key'], 'g')
  assert.ok(!seen.gemini.url.includes('g&') && !seen.gemini.url.includes('key='), 'the key is never put in the address')
  assert.equal(await collect(llm.stream({ provider: 'ollama', text: 'x', persona })), 'yo!')
  assert.equal(seen.ollama.body.model, 'llama3.2')
})

test('a missing key, a server error and a dead server are all LLMErrors', async () => {
  await assert.rejects(collect(new LLM(async () => streamOf('')).stream({ provider: 'openai', key: '', text: 'x', persona: {} })), LLMError)
  const bad = async () => new Response('nope', { status: 401 })
  await assert.rejects(collect(new LLM(bad).stream({ provider: 'openai', key: 'k', text: 'x', persona: {} })), /HTTP 401/)
  const dead = async () => { throw Object.assign(new TypeError('fetch failed'), { cause: { code: 'ECONNREFUSED' } }) }
  await assert.rejects(collect(new LLM(dead).stream({ provider: 'ollama', text: 'x', persona: {} })), /nothing is listening/)
  await assert.rejects(collect(new LLM(bad).stream({ provider: 'nope', text: 'x', persona: {} })), LLMError)
})

test('a failed turn is not remembered', async () => {
  const llm = new LLM(async () => new Response('x', { status: 500 }))
  await assert.rejects(collect(llm.stream({ provider: 'openai', key: 'k', text: 'x', persona: {} })))
  assert.equal(llm.history.length, 0)
})

test('the persona prompt has the pet\'s name and stays gentle', () => {
  const p = systemPrompt({ name: 'Biscuit', species: 'Puppy', voice: 'a hype best friend' })
  assert.match(p, /You are Biscuit, a Puppy/); assert.match(p, /hype best friend/); assert.match(p, /decline gently/)
  assert.doesNotMatch(p, /Coaching style/)
})

test('running a chain calls the right actions and says what happened', async () => {
  const calls = []
  const env = {
    actions: { installedNames: () => ['Obsidian'], openApp: async (n) => (calls.push(['open', n]), true), openUrl: async (u) => (calls.push(['url', u]), true), closeApp: async (n) => (calls.push(['close', n]), false) },
    status: () => {}, startFocus: async (m) => calls.push(['focus', m]), startRadio: async () => 'Lo-fi Chill',
  }
  const text = await runSteps(parseChain('open obsidian, close discord, open youtube and start a 30 minute focus and play lo-fi'), env)
  assert.deepEqual(calls, [['open', 'Obsidian'], ['close', 'Discord'], ['url', 'https://youtube.com'], ['focus', 30]])
  assert.match(text, /^done! opened Obsidian, then couldn't close Discord, then opened YouTube, then started a 30 minute focus, then started Lo-fi Chill/)
})

test('closing an app only matches program names, and user text can never break out of the script', () => {
  const s = closeScript(['winword'])
  assert.match(s, /\$_\.ProcessName -like 'winword\*'/)
  assert.doesNotMatch(s, /MainWindowTitle -like/, 'window titles are never matched')
  assert.match(s, /notin @\('explorer','cariberry'/, 'never the shell or Cariberry herself')
  for (const bad of ["'", ';', '`', '(calc)', 'Remove-Item C:']) assert.ok(!closeScript([`x${bad}y`]).includes(`x${bad}y`), `a "${bad}" is stripped before it reaches the script`)
  assert.equal(closeScript(['']), null)
})
