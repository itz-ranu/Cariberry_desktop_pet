// The only bridge between the web pages and the app. Pages never get Node.
const { contextBridge, ipcRenderer } = require('electron')
contextBridge.exposeInMainWorld('cari', {
  invoke: (channel, ...args) => ipcRenderer.invoke(channel, ...args),
  send: (channel, ...args) => ipcRenderer.send(channel, ...args),
  on: (channel, cb) => {
    const f = (_e, ...a) => cb(...a)
    ipcRenderer.on(channel, f)
    return () => ipcRenderer.removeListener(channel, f)
  },
  platform: process.platform,
})
