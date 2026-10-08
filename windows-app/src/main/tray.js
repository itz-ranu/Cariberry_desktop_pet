// The little face in the notification area. Left click opens the control panel; right click has the quick actions.
// Her face is redrawn by the pet page whenever her mood or outfit changes (the Mac's menu bar icon does the same).
import { Tray, Menu, nativeImage } from 'electron'

const SIZES = [1, 1.25, 1.5, 2, 2.5, 3]          // Windows picks the closest to the display's scale

function faceImage(dataUrl) {
  const src = nativeImage.createFromDataURL(dataUrl)
  const img = nativeImage.createEmpty()
  for (const sf of SIZES) {
    const px = Math.round(16 * sf)
    img.addRepresentation({ scaleFactor: sf, width: px, height: px, buffer: src.resize({ width: px, height: px, quality: 'best' }).toPNG() })
  }
  return img
}

export function createTray({ fallbackIcon, onToggle, items }) {
  const tray = new Tray(nativeImage.createFromPath(fallbackIcon).resize({ width: 16, height: 16, quality: 'best' }))
  tray.setToolTip('Cariberry')
  tray.setContextMenu(Menu.buildFromTemplate(items))
  tray.on('click', onToggle)
  return {
    tray,
    setFace: (dataUrl) => { try { tray.setImage(faceImage(dataUrl)) } catch { /* keep the old face */ } },
    setTip: (tip) => tray.setToolTip(tip.slice(0, 120)),
    destroy: () => tray.destroy(),
  }
}
