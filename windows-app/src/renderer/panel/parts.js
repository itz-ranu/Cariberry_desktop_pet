// Small pieces the panel's tabs share.
import { html, useState, useEffect, Icon, Switch, Notice } from '../ui/kit.js'

/** Counts down between the panel's 2-second refreshes, so a running clock never looks stuck. `null` when no timer runs. */
export function useCountdown(timer, stamp) {
  const [, tick] = useState(0)
  useEffect(() => { const id = setInterval(() => tick((n) => n + 1), 1000); return () => clearInterval(id) }, [])
  if (timer.remaining === null) return null
  return Math.max(0, timer.remaining - (Date.now() - stamp) / 1000)
}

export const clock = (left) => `${Math.floor(left / 60)}:${String(Math.floor(left % 60)).padStart(2, '0')}`

/** A small heading with an optional action on the right ("More ›"). */
export const Heading = ({ children, right }) => html`<div class="hs" style="padding:0 4px"><div class="label">${children}</div><div class="sp" />${right}</div>`

/** A "More" toggle that shows or hides the rest of a section. */
export function Disclosure({ label = 'More', open, onToggle }) {
  return html`<button class="more ${open ? 'open' : ''}" aria-expanded=${open} onClick=${onToggle}>${label} <${Icon} name="chevronRight" size=${11} sw=${3} /></button>`
}

/** One setting: a title, a short line under it, and a switch. */
export const Toggle = ({ title, subtitle, on, onChange, enabled = true }) => html`
  <div class="row" style=${{ opacity: enabled ? 1 : 0.45, pointerEvents: enabled ? 'auto' : 'none' }}>
    <div class="vs g2 grow">
      <div class="t">${title}</div>
      ${subtitle && html`<div class="note" style="font-size:11.5px">${subtitle}</div>`}
    </div>
    <${Switch} on=${on} onChange=${onChange} label=${title} />
  </div>`

export { Notice }
