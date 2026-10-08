// The conversation in the chat drawer, kept here (in the app, not the window) so it survives closing and reopening
// it, like the Mac app's ChatState. A message goes through, in order: things she can just do herself ("focus 25",
// "dance"), desktop tasks ("open Spotify"), the chat brain you connected, and finally her own voice, so she always answers.
import { LLM, LLMError, parseChain, understand, runSteps, replyFor, webAppName } from './brain.js'
import { Ambience } from '../renderer/ambience.js'

const STATION_WORDS = [[/rain/i, 'rainy'], [/caf|jazz|coffee/i, 'cafe'], [/night|late/i, 'night']]
const pickStation = (query) => (STATION_WORDS.find(([re]) => re.test(query)) || [null, 'lofi'])[1]

export function createChat({ wm, rpc, actions, secrets, lastForeign, fetchFn }) {
  const llm = new LLM(fetchFn)
  const state = { messages: [], thinking: false, status: '', ctx: null }
  let busy = false

  const brainOnline = () => {
    const c = state.ctx
    return !!c && c.provider !== 'local' && (c.provider === 'ollama' || secrets.hasSecret(c.provider))
  }
  const snapshot = () => ({
    messages: state.messages, thinking: state.thinking, status: state.status, brain: brainOnline(),
    name: state.ctx?.name || 'Cariberry', species: state.ctx?.species || 'cat', coat: state.ctx?.coat || 0, outfit: state.ctx?.outfit || {}, emotion: state.ctx?.emotion || 'happy',
  })
  const push = () => { const w = wm.cards.chat; if (w && !w.isDestroyed()) w.webContents.send('chat:state', snapshot()) }
  const say = (role, text) => { state.messages.push({ role, text }); push() }
  const refresh = async () => { state.ctx = (await rpc('chatContext')) || state.ctx }

  async function open() {
    await refresh()
    if (!state.messages.length && state.ctx) state.messages.push({ role: 'pet', text: state.ctx.greeting })
    wm.sendPet('chat:open', true)
    return snapshot()
  }

  const env = () => ({
    actions,
    status: (t) => { state.status = t; push() },
    startFocus: (m) => rpc('startFocusFromChat', m),
    startRadio: async (q) => { const k = pickStation(q); await rpc('chooseAmbienceFromChat', k); return Ambience[k].title },
  })

  async function finish(text, mood) {
    state.thinking = false; state.status = ''
    say('pet', text)
    rpc('chatDone', text, mood)
  }

  async function send(raw) {
    const text = String(raw || '').trim().slice(0, 2000)
    if (!text || busy) return
    busy = true
    say('user', text)
    try {
      await refresh()
      // things she can just *do*, instantly, on any brain
      const cmd = await rpc('chatCommand', text)
      if (cmd) { say('pet', cmd); return }
      state.thinking = true; push()

      const steps = parseChain(text)
      if (steps.length) { await finish(await runSteps(steps, env()), 'proud'); return }

      const u = understand(text, actions.installedNames())
      if (u.intent === 'open_app') {
        const label = u.kind === 'url' ? webAppName(u.target) : u.target
        state.status = `🐾 opening ${label}...`; push()
        const ok = u.kind === 'url' ? await actions.openUrl(u.target) : await actions.openApp(u.target)
        await finish(ok ? replyFor('open_app', label) : `I couldn't open ${label} 🥺`, ok ? 'proud' : 'worried'); return
      }
      if (u.intent === 'close_app') {
        if (u.kind === 'window') {
          const fg = lastForeign()
          const ok = fg ? actions.closeFrontWindow(fg.hwnd) : false
          await finish(ok ? replyFor('close_window') : 'hmm, I couldn\'t find a window to close 🥺', ok ? 'proud' : 'worried'); return
        }
        state.status = `🐾 closing ${u.target}...`; push()
        const ok = await actions.closeApp(u.target)
        await finish(ok ? replyFor('close_app', u.target) : `I couldn't find ${u.target} running 🥺`, ok ? 'proud' : 'worried'); return
      }

      // the chat brain you connected
      if (brainOnline()) {
        const c = state.ctx
        const key = c.provider === 'ollama' ? '' : secrets.getSecret(c.provider)
        let started = false
        try {
          for await (const chunk of llm.stream({ provider: c.provider, model: c.model, key, text, persona: c.persona })) {
            if (!started) { started = true; state.thinking = false; state.messages.push({ role: 'pet', text: '' }) }
            state.messages[state.messages.length - 1].text += chunk
            push()
          }
          if (started) {
            state.thinking = false; push()
            rpc('chatDone', state.messages[state.messages.length - 1].text, 'happy')
            return
          }
        } catch (e) {
          if (!(e instanceof LLMError)) throw e
          state.status = `couldn't reach ${c.provider}, answering on this PC`
          if (started) { state.thinking = false; push(); return }          // part of a reply already went out: leave it
        }
      }
      // her own voice: a beat first, so it feels like she thought about it
      await new Promise((r) => setTimeout(r, 450))
      await finish((await rpc('localReply', text)) || 'mrow? 🐾', null)
    } catch (e) {
      console.error('[chat]', e)
      state.thinking = false; state.status = ''
      say('pet', 'oops, something tripped me up 🥺 try again?')
    } finally { busy = false; state.thinking = false; push() }
  }

  return { open, send, snapshot, brainOnline, reset: () => { state.messages = []; llm.reset(); push() } }
}
