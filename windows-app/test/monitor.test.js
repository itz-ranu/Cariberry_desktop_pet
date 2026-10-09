import test from 'node:test'
import assert from 'node:assert/strict'
import { stripBrowserSuffix, isBrowserExe, browserName } from '../src/main/monitor.js'
import * as win32 from '../src/main/win32.js'

test('browser titles lose the browser\'s name', () => {
  assert.equal(stripBrowserSuffix('Reels • Instagram - Google Chrome'), 'Reels • Instagram')
  assert.equal(stripBrowserSuffix('Lo-fi beats - YouTube - Mozilla Firefox'), 'Lo-fi beats - YouTube')
  assert.equal(stripBrowserSuffix('Notes – Brave'), 'Notes')
  // Edge hides a zero-width space inside its name and may add a profile and a page count
  assert.equal(stripBrowserSuffix('Homework and 3 more pages - Personal - Microsoft Edge'), 'Homework')
  assert.equal(stripBrowserSuffix('Just a title'), 'Just a title')
  assert.equal(stripBrowserSuffix(''), '')
})

test('browsers are recognised by program name', () => {
  for (const exe of ['chrome.exe', 'msedge.exe', 'Firefox.exe', 'brave.exe', 'OPERA.EXE', 'vivaldi.exe', 'arc.exe']) assert.ok(isBrowserExe(exe), exe)
  for (const exe of ['code.exe', 'notepad.exe', '', undefined, 'chromedriver.exe']) assert.ok(!isBrowserExe(exe), String(exe))
  assert.equal(browserName('msedge.exe'), 'Microsoft Edge')
})

test('off Windows every Win32 call fails softly instead of throwing', () => {
  if (process.platform === 'win32') return
  assert.equal(win32.available(), false)
  assert.equal(win32.foreground(), null)
  assert.equal(win32.fullscreenAppRunning(), false)
  assert.equal(win32.sendKeys([win32.VK.CONTROL, win32.VK.W]), false)
  assert.equal(win32.closeWindow(123), false)
})
