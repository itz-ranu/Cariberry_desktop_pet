// Stamps Cariberry's icon and version details onto Cariberry.exe. electron-builder normally does this with
// rcedit, which needs Wine when you build on a Mac; this does the same job in plain JavaScript (resedit) so the
// installer can be built anywhere.
const fs = require('node:fs')
const path = require('node:path')

exports.default = async function afterPack(context) {
  if (context.electronPlatformName !== 'win32') return

  // the licence, privacy policy, terms and third-party notices travel with the app: <install folder>\resources\legal
  const legal = path.join(context.appOutDir, 'resources', 'legal')
  fs.mkdirSync(legal, { recursive: true })
  const proj = context.packager.projectDir
  for (const [from, to] of [['../LICENSE', 'LICENSE.txt'], ['../PRIVACY.md', 'PRIVACY.md'], ['../TERMS.md', 'TERMS.md'], ['THIRD_PARTY_NOTICES.md', 'THIRD_PARTY_NOTICES.md']]) {
    fs.copyFileSync(path.join(proj, from), path.join(legal, to))
  }
  const ResEdit = await import('resedit')
  const exePath = path.join(context.appOutDir, `${context.packager.appInfo.productFilename}.exe`)
  const info = context.packager.appInfo
  const exe = ResEdit.NtExecutable.from(fs.readFileSync(exePath))
  const res = ResEdit.NtExecutableResource.from(exe)

  // the icon: swap the pictures inside the existing icon group
  const iconFile = ResEdit.Data.IconFile.from(fs.readFileSync(path.join(context.packager.projectDir, 'build', 'icon.ico')))
  const group = ResEdit.Resource.IconGroupEntry.fromEntries(res.entries)[0]
  ResEdit.Resource.IconGroupEntry.replaceIconsForResource(res.entries, group ? group.id : 1, group ? group.lang : 1033, iconFile.icons.map((i) => i.data))

  // the details shown in Task Manager and the file's Properties
  const [vi] = ResEdit.Resource.VersionInfo.fromEntries(res.entries)
  const [major, minor, patch] = String(info.version).split('.').map((n) => Number(n) || 0)
  vi.setFileVersion(major, minor, patch, 0, 1033)
  vi.setProductVersion(major, minor, patch, 0, 1033)
  vi.setStringValues({ lang: 1033, codepage: 1200 }, {
    FileDescription: 'Cariberry, a desktop pet that keeps you focused', ProductName: 'Cariberry', CompanyName: 'Ranveer Sanghvi',
    LegalCopyright: 'Copyright © Ranveer Sanghvi', OriginalFilename: 'Cariberry.exe', InternalName: 'Cariberry',
  })
  vi.outputToResourceEntries(res.entries)
  res.outputResource(exe)
  fs.writeFileSync(exePath, Buffer.from(exe.generate()))
  console.log(`  • stamped ${path.basename(exePath)} with the Cariberry icon and version details`)
}
