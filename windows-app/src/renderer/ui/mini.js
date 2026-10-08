// The little UI engine behind the panel, the stats window and the cards, written for Cariberry.
//
//   html`<div class="card ${cls}" onClick=${go}>${items.map((i) => html`<${Row} key=${i.id} ...${i} />`)}</div>`
//
// `html` turns a template into elements ({type, props, key, ref}); `render` draws them into a container and, called again,
// changes only what differs; components are plain functions and keep their state in hooks (useState, useEffect, useRef,
// useMemo, useCallback). A state change redraws just the component that owns it, once, after the current event.
//
// Inside, every element, component and piece of text that is on screen has an "instance" (inst) that remembers its DOM and
// its children. Drawing is: make the new element list, match it against the old instances (by key, else by position and
// type), patch the ones that match, build the ones that are new, drop the rest, then put the DOM in order.

const TEXT = '#text'
export const Fragment = (props) => props.children

// ------------------------------------------------------------------ elements

/** h(type, props, ...children): `type` is a tag name or a component function. */
export function h(type, props, ...kids) {
  const p = {}
  let key = null, ref = null
  for (const k in props) {
    if (k === 'key') key = props[k]
    else if (k === 'ref') ref = props[k]
    else p[k] = props[k]
  }
  if (kids.length) p.children = kids.length === 1 ? kids[0] : kids
  return { type, props: p, key, ref }
}

/** Anything a component may return or a child may be -> a flat list of elements, with null kept for "nothing here"
 *  so that a child's position doesn't shift when something before it comes and goes. */
function kidsOf(x) {
  if (Array.isArray(x)) return x.map(one)
  return [one(x)]
}
function one(x) {
  if (x == null || x === true || x === false) return null
  if (typeof x === 'string' || typeof x === 'number' || typeof x === 'bigint') return { type: TEXT, props: String(x), key: null, ref: null }
  if (Array.isArray(x)) return { type: Fragment, props: { children: x }, key: null, ref: null }
  return x
}

// ------------------------------------------------------------------ the template tag

const cache = new WeakMap()

/** Reads the template's static strings once into a tree of {tag, attrs, kids}; the values are slotted in each time. */
function parse(strings) {
  const s = []                                   // characters, with {slot: n} where a ${value} sat
  strings.forEach((str, i) => { for (const ch of str) s.push(ch); if (i < strings.length - 1) s.push({ slot: i }) })
  const root = { kids: [] }
  const stack = [root]
  let i = 0
  const isCh = (c) => typeof c === 'string'
  const isSpace = (c) => c === ' ' || c === '\n' || c === '\t' || c === '\r'
  const top = () => stack[stack.length - 1]
  const addText = (txt) => { txt = txt.replace(/^\s*\n\s*|\s*\n\s*$/g, ''); if (txt) top().kids.push({ text: txt }) }

  let text = ''
  while (i < s.length) {
    const c = s[i]
    if (!isCh(c)) { addText(text); text = ''; top().kids.push({ slot: c.slot }); i++; continue }
    if (c !== '<') { text += c; i++; continue }
    addText(text); text = ''
    if (s[i + 1] === '!' && s[i + 2] === '-' && s[i + 3] === '-') {      // <!-- comment -->
      i += 4
      while (i < s.length && !(s[i] === '-' && s[i + 1] === '-' && s[i + 2] === '>')) i++
      i += 3
      continue
    }
    if (s[i + 1] === '/') {                                              // </tag> or <//>
      while (i < s.length && s[i] !== '>') i++
      i++
      if (stack.length > 1) stack.pop()
      continue
    }
    i++
    let tag
    if (!isCh(s[i])) { tag = { slot: s[i].slot }; i++ }                  // <${Component}
    else {
      let name = ''
      while (i < s.length && isCh(s[i]) && !isSpace(s[i]) && s[i] !== '>' && s[i] !== '/') name += s[i++]
      tag = name
    }
    const el = { tag, attrs: [], kids: [] }
    let selfClose = false
    for (;;) {
      while (i < s.length && isCh(s[i]) && isSpace(s[i])) i++
      if (i >= s.length) break
      const a = s[i]
      if (a === '>') { i++; break }
      if (a === '/' && s[i + 1] === '>') { selfClose = true; i += 2; break }
      if (a === '.' && s[i + 1] === '.' && s[i + 2] === '.' && !isCh(s[i + 3])) { el.attrs.push({ spread: s[i + 3].slot }); i += 4; continue }
      let name = ''
      while (i < s.length && isCh(s[i]) && !isSpace(s[i]) && s[i] !== '=' && s[i] !== '>' && !(s[i] === '/' && s[i + 1] === '>')) name += s[i++]
      if (!name) { i++; continue }
      while (i < s.length && isCh(s[i]) && isSpace(s[i])) i++
      if (s[i] !== '=') { el.attrs.push({ name, parts: [true] }); continue }          // <button disabled>
      i++
      while (i < s.length && isCh(s[i]) && isSpace(s[i])) i++
      const parts = []
      let lit = ''
      const q = s[i] === '"' || s[i] === "'" ? s[i++] : null
      while (i < s.length) {
        const ch = s[i]
        if (!isCh(ch)) { if (lit) { parts.push(lit); lit = '' } parts.push({ slot: ch.slot }); i++; continue }
        if (q ? ch === q : (isSpace(ch) || ch === '>' || (ch === '/' && s[i + 1] === '>'))) break
        lit += ch; i++
      }
      if (q) i++
      if (lit || !parts.length) parts.push(lit)
      el.attrs.push({ name, parts })
    }
    top().kids.push(el)
    if (!selfClose) stack.push(el)
  }
  addText(text)
  return root.kids
}

function build(node, values) {
  if (node.text !== undefined) return node.text
  if (node.slot !== undefined) return values[node.slot]
  const type = typeof node.tag === 'object' ? values[node.tag.slot] : node.tag
  const props = {}
  for (const a of node.attrs) {
    if (a.spread !== undefined) { Object.assign(props, values[a.spread]); continue }
    if (a.parts.length === 1 && typeof a.parts[0] !== 'string') props[a.name] = a.parts[0] === true ? true : values[a.parts[0].slot]
    else props[a.name] = a.parts.map((p) => (typeof p === 'string' ? p : String(values[p.slot] ?? ''))).join('')
  }
  const kids = node.kids.map((k) => build(k, values))
  return h(type, props, ...kids)
}

/** The template tag. One element comes back as itself, several as a list. */
export function html(strings, ...values) {
  let tree = cache.get(strings)
  if (!tree) cache.set(strings, (tree = parse(strings)))
  const out = tree.map((n) => build(n, values))
  return out.length > 1 ? out : out[0]
}

// ------------------------------------------------------------------ the DOM side

const SVG = 'http://www.w3.org/2000/svg'
const UNITLESS = /^(?:opacity|flex|flexGrow|flexShrink|order|zIndex|lineHeight|fontWeight|zoom|scale|aspectRatio|columns|columnCount|gridRow|gridColumn|gridArea|tabSize|orphans|widows|fillOpacity|strokeOpacity|stopOpacity|strokeWidth|animationIterationCount)$/

function setStyle(style, name, value) {
  if (value == null || value === false || value === '') { name.includes('-') ? style.removeProperty(name) : (style[name] = ''); return }
  if (name.includes('-')) style.setProperty(name, value)
  else style[name] = typeof value === 'number' && !UNITLESS.test(name) ? `${value}px` : value
}

function setProp(dom, name, value, old, isSvg) {
  if (name === 'children' || name === 'key' || name === 'ref') return
  if (name === 'style') {
    if (typeof value === 'string') { dom.style.cssText = value; return }
    if (typeof old === 'string') dom.style.cssText = ''
    const was = typeof old === 'object' && old ? old : {}
    const now = value || {}
    for (const k in was) if (!(k in now)) setStyle(dom.style, k, '')
    for (const k in now) if (was[k] !== now[k]) setStyle(dom.style, k, now[k])
    return
  }
  if (name === 'dangerouslySetInnerHTML') { const html = value?.__html ?? ''; if (dom.innerHTML !== html) dom.innerHTML = html; return }
  if (name[0] === 'o' && name[1] === 'n' && name.length > 2) {          // onClick -> a "click" listener; the newest handler is always the one called
    const lower = name.slice(2).toLowerCase()
    const type = `on${lower}` in dom ? lower : name.slice(2)
    const handlers = dom.__on || (dom.__on = {})
    if (!value) { if (handlers[type]) { dom.removeEventListener(type, proxy); delete handlers[type] } return }
    if (!handlers[type]) dom.addEventListener(type, proxy)
    handlers[type] = value
    return
  }
  if (!isSvg && name !== 'href' && name !== 'list' && name !== 'form' && name !== 'download' && name in dom) {
    try { dom[name] = value == null ? '' : value; return } catch { /* read-only: fall through to the attribute */ }
  }
  if (typeof value === 'function') return
  if (value != null && (value !== false || name.startsWith('aria-'))) dom.setAttribute(name, value)
  else dom.removeAttribute(name)
}
function proxy(e) { this.__on[e.type]?.(e) }

function setProps(dom, next, prev, isSvg) {
  for (const k in prev) if (!(k in next)) setProp(dom, k, null, prev[k], isSvg)
  for (const k in next) {
    if (k === 'value' || k === 'checked') continue                       // after the children (a <select> needs its options first)
    if (next[k] !== prev[k]) setProp(dom, k, next[k], prev[k], isSvg)
  }
}
function setControlled(dom, next) {
  if ('value' in next && next.value !== undefined && String(next.value) !== dom.value) dom.value = next.value
  if ('checked' in next && next.checked !== undefined && next.checked !== dom.checked) dom.checked = next.checked
}

function setRef(ref, value) {
  if (!ref) return
  if (typeof ref === 'function') ref(value)
  else ref.current = value
}

// ------------------------------------------------------------------ instances

const domsOf = (kids, out = []) => {
  for (const k of kids) {
    if (!k) continue
    if (k.dom) out.push(k.dom)
    else domsOf(k.kids, out)
  }
  return out
}

/** Puts the nodes in `parent`, in this order, ending just before `before`. Only moves what is out of place. */
function place(parent, doms, before) {
  let next = before
  for (let i = doms.length - 1; i >= 0; i--) {
    const d = doms[i]
    if (d.parentNode !== parent || d.nextSibling !== next) parent.insertBefore(d, next)
    next = d
  }
}

function mount(v, parentDom, isSvg, depth) {
  if (v.type === TEXT) return { type: TEXT, key: null, dom: document.createTextNode(v.props), props: v.props }
  if (typeof v.type === 'function') {
    const inst = { type: v.type, key: v.key, fn: v.type, props: v.props, kids: [], hooks: [], parentDom, isSvg, depth, dirty: false, dead: false }
    renderComp(inst)
    return inst
  }
  const svg = isSvg || v.type === 'svg'
  const dom = svg ? document.createElementNS(SVG, v.type) : document.createElement(v.type)
  const inst = { type: v.type, key: v.key, dom, props: v.props, kids: [], ref: v.ref, depth }
  setProps(dom, v.props, {}, svg)
  if (!v.props.dangerouslySetInnerHTML) {
    inst.kids = reconcile([], kidsOf(v.props.children), dom, svg && v.type !== 'foreignObject', depth + 1)
    place(dom, domsOf(inst.kids), null)
  }
  setControlled(dom, v.props)
  setRef(v.ref, dom)
  return inst
}

function patch(inst, v) {
  if (inst.type === TEXT) {
    if (inst.props !== v.props) { inst.props = v.props; inst.dom.data = v.props }
    return
  }
  if (inst.fn) { inst.props = v.props; renderComp(inst); return }
  const svg = inst.dom.namespaceURI === SVG
  setProps(inst.dom, v.props, inst.props, svg)
  if (v.props.dangerouslySetInnerHTML) { if (inst.kids.length) { unmountAll(inst.kids, false); inst.kids = [] } }
  else {
    inst.kids = reconcile(inst.kids, kidsOf(v.props.children), inst.dom, svg && v.type !== 'foreignObject', inst.depth + 1)
    place(inst.dom, domsOf(inst.kids), null)
  }
  setControlled(inst.dom, v.props)
  if (inst.ref !== v.ref) { setRef(inst.ref, null); setRef(v.ref, inst.dom); inst.ref = v.ref }
  inst.props = v.props
}

function unmount(inst, removeDom) {
  if (inst.fn) {
    inst.dead = true
    for (const hook of inst.hooks) if (hook.cleanup) { try { hook.cleanup() } catch (e) { console.error(e) } hook.cleanup = null }
    unmountAll(inst.kids, removeDom)
    return
  }
  if (inst.type !== TEXT) { setRef(inst.ref, null); unmountAll(inst.kids, false) }
  if (removeDom) inst.dom.remove()
}
function unmountAll(kids, removeDom) { for (const k of kids) if (k) unmount(k, removeDom) }

/** Matches the old instances to the new elements, patching, building and dropping as needed. Returns the new instances in order. */
function reconcile(old, next, parentDom, isSvg, depth) {
  const byKey = new Map()
  for (const o of old) if (o && o.key != null && !byKey.has(o.key)) byKey.set(o.key, o)
  const used = new Set()
  const out = new Array(next.length)
  for (let i = 0; i < next.length; i++) {
    const v = next[i]
    if (!v) { out[i] = null; continue }
    let hit = v.key != null ? byKey.get(v.key) : old[i]
    if (hit && (hit.type !== v.type || used.has(hit) || (v.key == null && hit.key != null))) hit = null
    if (hit) { used.add(hit); patch(hit, v); out[i] = hit }
    else out[i] = mount(v, parentDom, isSvg, depth)
  }
  for (const o of old) if (o && !used.has(o)) unmount(o, true)
  return out
}

// ------------------------------------------------------------------ components

let current = null            // the component being drawn, so hooks know whose they are
let hookAt = 0
let effects = []              // effects waiting for this round of drawing to finish

function renderComp(inst) {
  const outer = current, outerAt = hookAt
  current = inst; hookAt = 0; inst.dirty = false
  let out
  try { out = inst.fn(inst.props) } finally { current = outer; hookAt = outerAt }
  let kids = kidsOf(out)
  if (!kids.some(Boolean)) kids = [one('')]                              // a component always owns at least one DOM node, so it can find its place again
  inst.kids = reconcile(inst.kids, kids, inst.parentDom, inst.isSvg, inst.depth + 1)
}

const dirty = new Set()
let flushing = false

function schedule(inst) {
  if (inst.dead || inst.dirty) return
  inst.dirty = true
  dirty.add(inst)
  if (!flushing) { flushing = true; queueMicrotask(flush) }
}

function flush() {
  try {
    while (dirty.size) {
      const batch = [...dirty].sort((a, b) => a.depth - b.depth)         // parents first: they redraw their children anyway
      dirty.clear()
      for (const inst of batch) {
        if (inst.dead || !inst.dirty) continue
        const doms = domsOf(inst.kids)
        const last = doms[doms.length - 1]
        const before = last ? last.nextSibling : null
        renderComp(inst)
        place(inst.parentDom, domsOf(inst.kids), before)
      }
      runEffects()
    }
  } finally { flushing = false }
}

function runEffects() {
  const todo = effects
  effects = []
  for (const e of todo) if (!e.inst.dead && e.hook.cleanup) { const c = e.hook.cleanup; e.hook.cleanup = null; try { c() } catch (err) { console.error(err) } }
  for (const e of todo) if (!e.inst.dead) { try { const r = e.fn(); e.hook.cleanup = typeof r === 'function' ? r : null } catch (err) { console.error(err) } }
}

const roots = new WeakMap()

/** Draws `vnode` into `container`. Calling it again with the same container only changes what's different. */
export function render(vnode, container) {
  let root = roots.get(container)
  if (!root) { container.textContent = ''; roots.set(container, (root = { kids: [] })) }
  root.kids = reconcile(root.kids, kidsOf(vnode), container, container.namespaceURI === SVG, 0)
  place(container, domsOf(root.kids), null)
  runEffects()
}

// ------------------------------------------------------------------ hooks

const same = (a, b) => !!a && !!b && a.length === b.length && a.every((x, i) => Object.is(x, b[i]))

function hook(make) {
  const inst = current
  if (!inst) throw new Error('hooks can only be used while a component is drawing')
  const at = hookAt++
  return inst.hooks[at] || (inst.hooks[at] = make(inst))
}

export function useState(initial) {
  const s = hook((inst) => {
    const st = { value: typeof initial === 'function' ? initial() : initial }
    st.set = (v) => {
      const next = typeof v === 'function' ? v(st.value) : v
      if (Object.is(next, st.value)) return
      st.value = next
      schedule(inst)
    }
    return st
  })
  return [s.value, s.set]
}

export function useEffect(fn, deps) {
  const inst = current
  const first = !inst.hooks[hookAt]
  const e = hook(() => ({ deps: null, cleanup: null }))
  if (first || !deps || !same(deps, e.deps)) effects.push({ inst, hook: e, fn })
  e.deps = deps
}

export function useMemo(make, deps) {
  const m = hook(() => ({ deps: null, value: undefined }))
  if (!same(deps, m.deps)) { m.value = make(); m.deps = deps }
  return m.value
}

export const useCallback = (fn, deps) => useMemo(() => fn, deps)

export function useRef(initial) {
  return hook(() => ({ current: initial }))
}
