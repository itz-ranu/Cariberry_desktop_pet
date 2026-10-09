# Cariberry Privacy Policy

_Last updated: 9 October 2026_

Cariberry is a free desktop pet for Mac and Windows made by Ranveer Sanghvi ("I", "me"). This page says what the app and
the website do with information, in plain words. The short version: **I run no servers for the app, I collect nothing from
you, and there are no accounts, ads, analytics or trackers.** What the app learns about you stays on your computer, with
one optional exception that you switch on yourself (chat with an online AI service, see section 4).

Questions or requests: open an issue at <https://github.com/itz-ranu/Cariberry/issues>, or write to
**ranu.try7@gmail.com**.

## 1. Who this is for

Cariberry is meant for people **13 or older**. It is not directed at children under 13 and I do not knowingly collect
anything from them (I collect nothing from anyone). If you are under the age of digital consent where you live (13 to 16,
depending on the country), please ask a parent or guardian before installing it. The optional online chat services in
section 4 have their own, often higher, age limits (some require 18).

## 2. What stays on your computer

These are saved only on your own computer, in the app's data folder (`%APPDATA%\Cariberry` on Windows, the app's
`Application Support` and preferences on Mac). I never receive them:

- your pet, outfits, berries, XP, badges and settings;
- your focus sessions, streaks, habits, to-dos and the day's mood check-in;
- the rules that decide what counts as work or a distraction.

To erase everything, quit Cariberry, uninstall it and delete that folder.

## 3. What she looks at while she runs

These features read information on your computer, process it **in memory only**, and do not store it or send it anywhere:

| Feature | What she reads | Notes |
|---|---|---|
| Focus coaching | the name of the program in front, and its window title (Mac and Windows) | matched against your rules, then dropped |
| Browser awareness (can be switched off in Settings) | your browser tab's title and web address | used to tell, for example, Reels from homework; Mac asks for **Automation** permission, Windows needs none |
| "Bop to my music" (can be switched off) | the loudness and beat of the sound your computer is playing | she does not record, keep or listen to the content; Mac asks for **Screen Recording** permission because that is how macOS exposes system audio |
| "Hey Cranberry" voice (Mac, optional) | your microphone | processed on your Mac by Apple's on-device speech recognition; audio is not recorded, saved or sent. If your Mac cannot recognise speech on-device, voice stays off |
| Cursor and app control (Mac) | where apps are in the Dock | used only to open or close the app you ask for |
| Any other local data | system events, files, inputs | processed entirely locally on your device; never uploaded unless explicitly sent to a third-party AI provider chosen by you |

You can refuse or later withdraw any of these permissions in your system settings; she keeps working without them.

## 4. Optional online chat ("chat brain")

By default chat runs on your computer. **Only if you choose it** in Settings can chat use an online AI service:

- **Ollama** runs on your own computer, so nothing leaves it.
- **ChatGPT / OpenAI** or **Gemini / Google** need **your own API key**. When you pick one, each message you type in the chat is
  sent to that company, together with a short line that tells the model who she is (her name, kind of animal, personality,
  the coaching style you picked and the mood you chose at check-in) and the last few turns of the conversation. **Nothing
  else** is sent: not your screen, files, browsing, tabs or voice.

That company then handles the data under **its own** privacy policy and terms, and you pay any API charges to it, not to me.
Check their rules before use, including minimum ages. I am not their partner and cannot see, change or delete what they hold.
Your API key is stored in the macOS Keychain (Mac) or encrypted for your Windows account (Windows), never in plain text,
never in this repository and never sent anywhere except to the provider you chose.

If you never pick one of these services, the app makes **no network requests of its own** other than local ones on your
machine.

## 5. Downloads and the website

- The installers are downloaded from GitHub, and the website is hosted on GitHub Pages. GitHub may log technical data such as
  your IP address under [its privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
  I do not get that data.
- The website has no cookies, no analytics and no third-party trackers. Its fonts are served from the site itself.
- The README on GitHub shows images from third-party services (badges and banners). Your browser, via GitHub, may request
  them; see those services for their policies.

## 6. Support and Contact Data

If you contact me for support via email or GitHub, you voluntarily provide your email address, GitHub username, and any other data you include in your message. This data is used exclusively to assist you and resolve your issue. It is not used for marketing, shared with third parties, or added to any mailing list.

## 7. Your rights

Because I hold no personal data about you other than direct support correspondence, there is nothing for me to look up, correct or delete centrally. Everything the app keeps is
in the folder described in section 2 and under your control. If you are in the EU/UK, California or elsewhere with privacy
laws, you keep every right you have; write to me if you think I hold something about you and I will answer.

## 8. Security

I take care to keep keys encrypted and to request only the permissions the features need. No software is perfect: report
problems via [SECURITY.md](SECURITY.md).

## 9. Changes

If this changes I will update the date above and note it in the release notes. The history is public in the repository.
