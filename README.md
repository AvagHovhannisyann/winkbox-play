# WinkBox Play

An iPhone game controller for the game console that runs on the Rostelecom WinkBox 2 (an Android TV box). The games run on the TV
itself; the phone is the controller: pick a game on the phone, or pick it on the TV and the controller opens on the phone.

- **A thin app around a web page.** The app finds the TV on the home Wi-Fi (Bonjour, `_winkbox._tcp`), pairs with it once, keeps the
  secure connection open, and shows the controller page the TV serves (`http://<tv>:8732/web/`) in a web view. The page draws the
  shelf of games and, for the running game, whatever controls that game asks for: floating sticks, buttons, a d-pad, a throttle,
  a trackpad, an item tray, tilt. So a game's controls change by updating the TV, not by reinstalling the app.
- **Pairing.** Once, with the 6-digit code the TV shows on screen (P-256 key agreement bound to the code, then a shared secret). The
  Play app pairs with the limited `play` role: it can start games and send controller input, and nothing else. It can't talk to the
  TV's assistant, press the TV's buttons, type, open apps or change settings.
- **Phone features used by games.** Haptics (a train horn buzzes the phone) and tilt (the phone as a steering wheel).

The TV side lives in the `assistant-tv` project (the WinkBox Assistant app): `Play.java` (the console), `PlayHub.java` (the shelf on the
TV), `GameActivity.java` (runs the built-in games), `VirtualPads.java` (a virtual gamepad for installed Android games).

## Building

Like the WinkBox Remote app this is built without Xcode on the user's Mac: every push to `main` builds it on GitHub's Macs
(`.github/workflows/build.yml` runs `build.sh`) and publishes `WinkPlay.ipa` as the
[latest release](../../releases/tag/latest). If a build fails, its log is published as the
[build-log](../../releases/tag/build-log) release.

`Tools/protocol` checks the phone's networking and cryptography against the real TV from a Mac, with no phone:
`swiftc -D WB_NO_KEYCHAIN App/Core/PlayLink.swift App/Core/WBCrypto.swift Tools/protocol/main.swift -o protocol && ./protocol <tv address>`.
`Tools/icon` draws the app icon during the build. `bash Tools/preview/run.sh <dir>` renders the app's own screens (looking for the TV,
welcome, the code, can't reach the TV) on a Mac, portrait and landscape, to check the design without a phone.

The build uses GitHub's macOS 26 machines (Xcode 26, the iOS 26 SDK), so on iOS 26 the app's own screens use Liquid Glass; on
iOS 16 to 18 they fall back to Apple's materials. The controller page itself (shelf, controls, guest PIN) is web, served by the TV.

## Installing

Download `WinkPlay.ipa` from the latest release and install it with [Sideloadly](https://sideloadly.io), signed in with your Apple ID.
An app signed with a free Apple ID stops opening after 7 days (installing it again renews it) and a free Apple ID can have 3 such apps
on a device at a time.

The first time it opens, iOS asks for the local network: allow it. Then tap "Connect to TV" and type the 6 numbers the TV shows.
