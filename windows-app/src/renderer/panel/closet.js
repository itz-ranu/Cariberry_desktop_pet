// The Closet tab, three pages: Her (who she is), Outfit (what she's wearing) and Shop (berries buy rugs, clothes and decor).
import { html, useState, Icon, Label, Card, Chip, Seg, CritterCanvas, rgbCss, centered } from '../ui/kit.js'

const PAGES = [['her', 'Her'], ['outfit', 'Outfit'], ['shop', 'Shop']]
// the eight dress-up slots in the order people reach for them, with short names that fit on one row
const SLOT_ORDER = [['body', 'Clothes'], ['head', 'Hats'], ['hair', 'Hair'], ['face', 'Face'], ['neck', 'Neck'], ['held', 'Hold'], ['aura', 'Aura'], ['rug', 'Rug']]

// ---------------------------------------------------------------- her

function SpeciesCard({ sp, s, call }) {
  const selected = s.species === sp.id
  const coat = selected ? s.coatIndex : (s.coats?.[sp.id] ?? 0)
  const scale = 0.34
  return html`
    <button class="press species sel ${selected ? 'on' : ''}" title=${sp.blurb} aria-label=${`${sp.name}. ${sp.blurb}`} aria-pressed=${selected}
      onClick=${() => call('do', 'chooseSpecies', sp.id)}>
      <${CritterCanvas} species=${sp.id} coat=${coat} pose=${{ emotion: 'happy', phase: 0.4, outfit: s.outfit }} scale=${scale} w=${68} h=${66} ...${centered(68, 66, scale, 0, 3)} />
      <div class="nm">${sp.name}</div>
      ${selected && html`<div class="tick"><${Icon} name="checkCircle" size=${9} sw=${3.5} /></div>`}
    </button>`
}

function Her({ s, cat, call, welcome }) {
  const [name, setName] = useState(s.name)
  const sp = cat.species.find((x) => x.id === s.species)
  return html`
    ${welcome && html`
      <div class="welcome vs g6">
        <div style="font-size:17px;font-weight:900">Welcome to Cariberry ✨</div>
        <div style="font-size:12.5px;font-weight:700;opacity:.95;line-height:1.35">Pick your bestie below. She'll keep you company, cheer when you focus, and bark when you doom-scroll. You can change her any time.</div>
      </div>`}
    <${Card}><div class="vs g10"><${Label}>Pick your bestie<//><div class="grid cols4 gap8">${cat.species.map((x) => html`<${SpeciesCard} sp=${x} s=${s} call=${call} />`)}</div></div><//>
    <${Card}>
      <div class="vs g12">
        <div class="vs g10"><${Label}>Colour<//>
          <div class="hs g10">${sp.coats.map((c, i) => html`
            <button class="vs g4" style="align-items:center" onClick=${() => call('do', 'chooseCoat', i)} aria-label=${`${c.name} colour`} aria-pressed=${s.coatIndex === i}>
              <div class="swatch ${s.coatIndex === i ? 'on' : ''}"><i style=${{ background: `linear-gradient(135deg, ${rgbCss(c.light)}, ${rgbCss(c.mid)}, ${rgbCss(c.shade)})` }} /></div>
              <span style=${{ fontSize: '11px', fontWeight: s.coatIndex === i ? 800 : 600, color: s.coatIndex === i ? 'var(--ink)' : 'var(--ink-soft)' }}>${c.name}</span>
            </button>`)}</div>
        </div>
        <div class="vs g8"><${Label}>Size on screen<//>
          <${Seg} options=${s.sizeNames.map((n, i) => [i, n])} value=${s.sizeLevel} onChange=${(v) => call('do', 'chooseSize', v)} /></div>
        <div class="vs g8"><${Label}>Name<//>
          <div class="hs g8">
            <input class="field" value=${name} maxlength="24" onInput=${(e) => setName(e.target.value)} onKeyDown=${(e) => e.key === 'Enter' && call('rename', name)} aria-label="Name" />
            <${Chip} disabled=${!name.trim() || name === s.name} onClick=${() => call('rename', name)}>Save<//>
          </div>
        </div>
      </div>
    <//>`
}

// ---------------------------------------------------------------- outfit

function Item({ a, s, call, goShop }) {
  const selected = s.outfit[a.slot] === a.id
  const owned = a.price === 0 || s.owned.includes(a.id)
  return html`
    <button class="press tile sel ${selected ? 'on' : ''}" style=${{ opacity: owned ? 1 : 0.55 }}
      title=${owned ? (selected ? `Take off ${a.title.toLowerCase()}` : `Put on ${a.title.toLowerCase()}`) : `${a.title}: ${a.price} berries in the Shop`}
      aria-label=${owned ? a.title : `${a.title}, ${a.price} berries`} aria-pressed=${selected}
      onClick=${() => (owned ? call('do', 'wear', a.id) : goShop())}>
      <div style="font-size:20px;line-height:1.2">${a.emoji}</div>
      <div class="ell nm">${a.title}</div>
      ${!owned && html`<div class="soft" style="font-size:11px;font-weight:800">🍓 ${a.price}</div>`}
    </button>`
}

function Outfit({ s, cat, call, goShop }) {
  const slots = SLOT_ORDER.map(([id, short]) => ({ ...cat.slots.find((x) => x.id === id), short })).filter((x) => x.items)
  const [slotId, setSlot] = useState(slots[0].id)
  const slot = slots.find((x) => x.id === slotId) || slots[0]
  const worn = Object.values(s.outfit).filter((v) => v && v !== 'none').length
  return html`
    <${Card}>
      <div class="hs g14">
        <div class="avatar" style="width:84px;height:84px">
          <${CritterCanvas} animate=${true} species=${s.species} coat=${s.coatIndex} pose=${{ emotion: s.emotion, outfit: s.outfit, collarTier: s.collarTier }} scale=${0.46} w=${84} h=${84} circle=${true} ...${centered(84, 84, 0.46, -3, -8)} />
        </div>
        <div class="vs g6 grow">
          <${Label}>Today's look<//>
          <div style="font-size:13px;font-weight:700">${worn === 0 ? 'Nothing on yet. Tap things below ✨' : `${worn} thing${worn === 1 ? '' : 's'} on`}</div>
          ${worn > 0 && html`<div><${Chip} tint="var(--second)" onClick=${() => call('do', 'clearOutfit')}>Take all off<//></div>`}
        </div>
      </div>
    <//>
    <div class="chips">${slots.map((x) => html`<button class="chipbtn ${x.id === slot.id ? 'on' : ''}" aria-pressed=${x.id === slot.id} title=${x.title} onClick=${() => setSlot(x.id)}>${x.short}</button>`)}</div>
    <${Card}><div class="grid cols4 gap8">${slot.items.map((a) => html`<${Item} a=${a} s=${s} call=${call} goShop=${goShop} />`)}</div><//>`
}

// ---------------------------------------------------------------- shop

function ShopTile({ emoji, title, price, owned, active, berries, onClick }) {
  const afford = berries >= price
  return html`
    <button class="press tile sel ${active ? 'on' : ''}" style="padding:10px 2px" onClick=${onClick} aria-label=${owned ? `${title}, owned` : `${title}, ${price} berries`}>
      <div style="font-size:24px;line-height:1.15">${emoji}</div>
      <div class="ell nm">${title}</div>
      <div class="price ${!owned && afford ? 'afford' : ''}">${owned ? (active ? 'on show ✓' : 'owned') : `🍓 ${price}`}</div>
    </button>`
}

function Shop({ s, cat, call }) {
  const [msg, setMsg] = useState(null)
  const note = (ok, title) => {
    if (!ok) return setMsg(null)
    setMsg(`got the ${title.toLowerCase()}! 🎉`)
    setTimeout(() => setMsg(null), 2500)
  }
  const buy = async (method, id, title) => { const before = s.berries; const out = await call('do', method, id); note(out && out.berries < before, title) }
  return html`
    <${Card}>
      <div class="hs g12">
        <div style="font-size:32px">🍓</div>
        <div class="vs g2"><div style="font-size:21px;font-weight:900">${s.berries} berries</div>
          <div class="note">Earn them by focusing: 1 a minute, +3 a task, +10 a session, +25 for your goal.</div></div>
      </div>
    <//>
    ${msg && html`<div class="shopmsg">${msg}</div>`}
    <${Card}>
      <div class="vs g10"><${Label}>Rugs & clothes<//>
        <div class="grid cols3 gap8">${cat.forSale.map((a) => html`
          <${ShopTile} emoji=${a.emoji} title=${a.title} price=${a.price} owned=${s.owned.includes(a.id)} berries=${s.berries} onClick=${() => buy('buy', a.id, a.title)} />`)}</div>
      </div>
    <//>
    <${Card}>
      <div class="vs g10"><${Label}>Decor & weather<//>
        <div class="note">Little things that sit beside her, and soft particles that drift through her corner. One kind of weather at a time.</div>
        <div class="grid cols3 gap8">${cat.decor.map((d) => {
          const owned = s.owned.includes(`decor.${d.id}`)
          return html`<${ShopTile} emoji=${d.emoji} title=${d.title} price=${d.price} owned=${owned} active=${s.decorOn.includes(d.id)} berries=${s.berries}
            onClick=${() => (owned ? call('do', 'toggleDecor', d.id) : buy('buyDecor', d.id, d.title))} />`
        })}</div>
      </div>
    <//>`
}

export function Closet(p) {
  const [page, setPage] = useState('her')
  return html`
    <div class="pages" role="tablist">${PAGES.map(([id, label]) => html`
      <button class=${page === id ? 'on' : ''} role="tab" aria-selected=${page === id} onClick=${() => setPage(id)}>${id === 'shop' ? `Shop · 🍓 ${p.s.berries}` : label}</button>`)}</div>
    ${page === 'her' && html`<${Her} ...${p} />`}
    ${page === 'outfit' && html`<${Outfit} ...${p} goShop=${() => setPage('shop')} />`}
    ${page === 'shop' && html`<${Shop} ...${p} />`}`
}
