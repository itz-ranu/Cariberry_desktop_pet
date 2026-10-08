// What counts as work and what counts as a distraction. First matching rule wins, so the file
// is ordered most-specific first. The Mac app matches bundle ids; on Windows a rule matches the
// program's file name (chrome.exe), its friendly name and the window title, so each list carries
// both kinds of term and one rules file serves both.
import { uuid } from './util.js'

export const rule = (name, mode, apps, urls, delay, severity, lines = []) => ({ name, mode, apps, urls, delay, severity, lines })

export const DEFAULT_RULES = [
  rule('Reels & short-form video', 'distraction',
    ['com.zhiliaoapp.musically', 'tiktok'],
    ['instagram.com/reels', '/reels/', 'instagram.com/stories', 'youtube.com/shorts', '/shorts/', 'tiktok.com',
      'facebook.com/reel', 'snapchat.com/spotlight', '· reels', 'reels ·', 'tiktok', 'instagram reels', '- shorts', 'youtube shorts'],
    20, 2,
    ['BARK! 🐶 reels again?! eyes UP', 'woof!! that\'s 20 seconds you\'re not getting back 😤', 'scrolling is not a personality. FOCUS 🐾',
      'BARK BARK! the algorithm is winning 😡', 'put. the. phone-website. down. 🐕']),
  rule('Social media', 'distraction',
    ['com.burbn.instagram', 'com.facebook', 'com.atebits.tweetie', 'twitter', 'reddit'],
    ['instagram.com', 'twitter.com', 'x.com/home', 'facebook.com', 'reddit.com', 'threads.net', '9gag', 'pinterest.com', 'tumblr.com',
      'instagram', '/ x', 'facebook', 'reddit', 'pinterest', 'tumblr', 'threads'],
    40, 2,
    ['hey! 🐶 you said you\'d focus today', 'woof — the internet will still be there later', 'BARK! close the tab, I believe in you 💪']),
  rule('Streaming & twitch', 'distraction',
    ['com.netflix', 'tv.twitch', 'com.spotify.client.video'],
    ['netflix.com/watch', 'hulu.com/watch', 'twitch.tv', 'primevideo.com', 'disneyplus.com', 'hotstar.com', 'crunchyroll.com/watch',
      'netflix', 'twitch', 'prime video', 'disney+', 'hotstar', 'crunchyroll', 'hulu'],
    60, 2,
    ['is this a study break or a season finale? 🐕', 'BARK! one more episode… said the human, 4 hours ago 😤']),
  rule('Music & media', 'neutral',
    ['com.spotify.client', 'com.apple.music', 'com.apple.itunes', 'com.apple.podcasts', 'soundcloud', 'spotify.exe', 'itunes.exe', 'applemusic'],
    ['music.apple.com', 'music.youtube.com', 'soundcloud.com', 'open.spotify.com', 'spotify'],
    999, 0),
  rule('YouTube (might be learning, might not)', 'distraction', [],
    ['youtube.com/watch', 'youtube.com/feed', '- youtube'], 150, 1,
    ['…is this a tutorial? 👀 (I\'m watching)', '*soft whine* 🥺 it\'s been a while on YouTube', 'woof? still learning something? 🐾']),
  rule('Games', 'distraction',
    ['com.valvesoftware.steam', 'com.epicgames', 'com.riotgames', 'minecraft', 'com.blizzard', 'discord',
      'steam.exe', 'steamwebhelper', 'epicgameslauncher', 'riotclient', 'leagueclient', 'valorant', 'robloxplayer', 'battle.net', 'javaw.exe'],
    ['chess.com', 'poki.com', 'roblox.com'], 90, 1,
    ['gaming already? 🐶 did we finish the thing?', 'woof! I want to play too — after your work 🎾']),
  rule('Coding', 'work',
    ['com.apple.dt.xcode', 'com.microsoft.vscode', 'com.todesktop', 'cursor', 'com.jetbrains', 'dev.zed', 'com.sublimetext', 'com.apple.terminal',
      'com.googlecode.iterm2', 'com.mitchellh.ghostty', 'dev.warp', 'neovim', 'com.figma.desktop', 'com.postmanlabs', 'com.docker.docker',
      'com.tinyapp.tablepro', 'android studio',
      'code.exe', 'devenv.exe', 'idea64', 'pycharm', 'webstorm', 'clion', 'rider64', 'goland', 'windowsterminal', 'powershell', 'cmd.exe',
      'wt.exe', 'figma.exe', 'postman', 'docker desktop', 'sublime_text', 'notepad++', 'zed.exe', 'githubdesktop'],
    ['github.com', 'gitlab.com', 'stackoverflow.com', 'developer.apple.com', 'leetcode.com', 'localhost:', '127.0.0.1', 'docs.', 'mdn web docs',
      'github', 'stack overflow', 'leetcode', 'developer.mozilla'],
    0, 0,
    ['look at you writing code 💗', 'my human is a genius 🥹 keep going', '*curls up next to the keyboard* 🐾',
      'I don\'t understand any of this but I\'m SO proud 💕', 'compile it! I believe in you ✨']),
  rule('Studying & writing', 'work',
    ['com.apple.preview', 'com.adobe.acrobat', 'com.apple.pages', 'com.microsoft.word', 'com.apple.notes', 'md.obsidian', 'notion',
      'com.literatureandlatte.scrivener', 'com.apple.iBooksX', 'goodnotes', 'com.apple.numbers', 'com.microsoft.excel', 'anki',
      'winword', 'excel.exe', 'powerpnt', 'onenote', 'acrord32', 'acrobat.exe', 'obsidian.exe', 'notion.exe', 'sumatrapdf', 'kindle', 'anki.exe'],
    ['notion.so', 'overleaf.com', 'coursera.org', 'khanacademy.org', 'wikipedia.org', 'scholar.google', 'arxiv.org', 'canvas.', 'brightspace',
      'quizlet.com', 'docs.google.com', 'notion', 'overleaf', 'coursera', 'khan academy', 'wikipedia', 'google scholar', 'arxiv', 'quizlet', 'google docs'],
    0, 0,
    ['study mode 📚 I\'ll keep you company', 'you\'re so smart it\'s unfair 🥹', '*rests head on your notes* 💗', 'every page is a win 🐾',
      'future you is going to thank present you ✨']),
]

export const GUARD_PRESETS = [
  { id: 'tiktok', emoji: '🎵', name: 'TikTok', apps: ['com.zhiliaoapp.musically', 'tiktok'], urls: ['tiktok.com', 'tiktok'] },
  { id: 'instagram', emoji: '📸', name: 'Instagram', apps: ['com.burbn.instagram', 'instagram'], urls: ['instagram.com', 'instagram'] },
  { id: 'youtube', emoji: '▶️', name: 'YouTube', apps: ['youtube'], urls: ['youtube.com', '- youtube'] },
  { id: 'shein', emoji: '🛍️', name: 'Shein', apps: ['shein'], urls: ['shein.com', 'shein.in', 'shein'] },
  { id: 'pinterest', emoji: '📌', name: 'Pinterest', apps: ['pinterest'], urls: ['pinterest.'] },
  { id: 'netflix', emoji: '🍿', name: 'Netflix', apps: ['com.netflix', 'netflix'], urls: ['netflix.com', 'netflix'] },
  { id: 'roblox', emoji: '🎮', name: 'Roblox', apps: ['roblox'], urls: ['roblox.com'] },
  { id: 'twitter', emoji: '🐦', name: 'X / Twitter', apps: ['com.atebits.tweetie', 'twitter'], urls: ['twitter.com', 'x.com/', '/ x'] },
  { id: 'reddit', emoji: '👽', name: 'Reddit', apps: ['reddit'], urls: ['reddit.com', 'reddit'] },
  { id: 'snapchat', emoji: '👻', name: 'Snapchat', apps: ['snapchat'], urls: ['snapchat.com'] },
]
export const guardRuleName = (p) => `Guard: ${p.name}`

export class RuleBook {
  constructor(rules = DEFAULT_RULES, onChange = () => {}) {
    this.rules = structuredClone(rules)
    this.onChange = onChange
  }
  save() { this.onChange(this.rules) }
  reset() { this.rules = structuredClone(DEFAULT_RULES); this.save() }

  addBlock(term) {
    const t = term.trim().toLowerCase()
    if (!t) return
    this.rules = this.rules.filter((r) => r.name !== `Blocked: ${t}`)
    this.rules.unshift(rule(`Blocked: ${t}`, 'distraction', [t], [t], 5, 2, [
      `BARK! 😡 ${t} is BANNED, you know this`, `woof!! we agreed — no ${t} 😤`, `put it away, ${t} is off limits 🐕`,
      'BARK BARK! I saw that. close it. 😠', 'you blocked this yourself! close it 🚫']))
    this.save()
  }
  removeBlock(term) { this.rules = this.rules.filter((r) => r.name !== `Blocked: ${term}`); this.save() }
  get customBlocks() { return this.rules.filter((r) => r.name.startsWith('Blocked: ')).map((r) => r.name.slice(9)) }

  setGuard(preset, on) {
    this.rules = this.rules.filter((r) => r.name !== guardRuleName(preset))
    if (on) this.rules.unshift(rule(guardRuleName(preset), 'distraction', preset.apps, preset.urls, 25, 2))
    this.save()
  }
  isGuarded(preset) { return this.rules.some((r) => r.name === guardRuleName(preset)) }

  /** What are you doing right now? `info` is {exe, name, title, url}. First matching rule wins. */
  evaluate(info) {
    const exe = (info.exe || '').toLowerCase()
    const appName = info.name || info.exe || 'something'
    const page = (info.url || '').toLowerCase()
    const hay = `${page} ${info.title || ''}`.toLowerCase()
    const appHay = `${exe} ${appName}`.toLowerCase()
    const siteKey = hostOf(page) || appName
    for (const r of this.rules) {
      let hit = r.apps.some((a) => a && appHay.includes(a.toLowerCase()))
      if (!hit && hay.trim()) hit = r.urls.some((u) => u && hay.includes(u.toLowerCase()))
      if (hit) {
        return { kind: r.mode === 'distraction' ? 'distraction' : r.mode === 'work' ? 'work' : 'neutral',
          label: shorten(info.title) || appName, siteKey, ruleName: r.name, delay: r.delay, lines: r.lines, severity: r.severity }
      }
    }
    return { kind: 'neutral', label: appName, siteKey, ruleName: '—', delay: 999, lines: [], severity: 0 }
  }
}

function shorten(t) { return !t ? '' : (t.length > 42 ? t.slice(0, 42) + '…' : t) }
function hostOf(u) {
  try { return new URL(u.includes('://') ? u : `https://${u}`).host.replace(/^www\./, '') } catch { return '' }
}
