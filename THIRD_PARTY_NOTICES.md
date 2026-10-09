# Third-party notices

Cariberry is MIT-licensed ([LICENSE](LICENSE)). It includes or builds on the third-party pieces below, each under its own
licence. The full licence texts ship with the app and are kept in this repository:

| Where | File with the licence texts |
|---|---|
| Cariberry for Mac (voice assistant) | [legal/mac-python-licenses.txt](legal/mac-python-licenses.txt), also inside the app at `Cariberry.app/Contents/Resources/` and in the `.dmg` |
| Cariberry for Windows | [windows-app/THIRD_PARTY_NOTICES.md](windows-app/THIRD_PARTY_NOTICES.md); the installer also puts it in `resources\legal`, next to `LICENSE.electron.txt` and `LICENSES.chromium.html` |
| The website | [web/public/licenses.txt](web/public/licenses.txt), served at `/licenses.txt` |

## Highlights

- **Mac app**: PyTorch, NumPy, SciPy, scikit-learn, librosa, numba/llvmlite, sounddevice, soundfile, PyObjC and friends
  (BSD, MIT, ISC, Apache-2.0 and similar permissive licences), packed with PyInstaller (GPL-2.0 with the bootloader
  exception, which allows use in any program) on the Python interpreter (PSF licence).
- **LGPL notice (libsoxr, via the `soxr` package, used by librosa)**: licensed under the GNU LGPL v2.1 or later. Its source
  is at <https://github.com/dofuuz/python-soxr> and <https://sourceforge.net/projects/soxr/>. In the Mac app it is a separate
  file inside `Cariberry.app/Contents/Resources/cranberry-brain/_internal`, so you may replace it with your own build of the
  library.
- **certifi** is MPL-2.0 (<https://github.com/certifi/python-certifi>).
- **Windows app**: Electron and Chromium (MIT, BSD and others), koffi (MIT).
- **Fonts** (all SIL Open Font License 1.1): Nunito, Patrick Hand (Windows app); Bagel Fat One, Caveat Brush, Figtree and
  Bricolage Grotesque (website).
- **Website**: React, Lenis, Zustand and others (MIT).
- **Emoji art in the README**: [Animated Fluent Emojis](https://github.com/Tarikul-Islam-Anik/Animated-Fluent-Emojis) by
  Tarikul Islam Anik, based on Microsoft Fluent Emoji (MIT).
- Her voices and the lo-fi music are made by Cariberry's own synthesiser, not recorded or sampled. The pets are drawn in code.

## Trademarks

Apple, macOS, Windows, Microsoft, Google, Chrome, Gemini, YouTube, OpenAI, ChatGPT, Ollama, Spotify, Instagram, TikTok,
Netflix, Discord, WhatsApp, Notion, GitHub and other names are trademarks of their owners. Cariberry is not affiliated with,
endorsed by or sponsored by them; the names are used only to say what the app works with.
