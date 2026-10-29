# Thrustbound 🚀

*Defy gravity. Stick the landing.*

Thrustbound is a portrait game where you pilot a small rocket through 80 levels. Gravity always pulls you down. You steer with a stick, fire the engine with a **GAS** button, and have to touch down gently on the green landing pad without crashing or running out of fuel. You can also build your own levels in the **Level Maker**, publish them, and play, like and rate other pilots' levels in **Community**.

It runs on **iPhone** (native app), **Android** (APK) and **in the browser**:

- **Play in the browser:** https://99mac88-afk.github.io/rocket/
- **iPhone:** [Thrustbound.ipa](https://github.com/99mac88-afk/rocket/releases/latest/download/Thrustbound.ipa) (sideload, see below)
- **Android:** [Thrustbound.apk](https://github.com/99mac88-afk/rocket/releases/latest/download/Thrustbound.apk)

The website looks at the visitor's device and recommends the right download (the iPhone app on iPhones, the APK on Android, both on a computer). Levels and accounts are shared: a level published from an iPhone can be played on Android or the web, and the other way round.

<p align="center"><img src="Thrustbound/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="160" alt="Thrustbound icon"></p>

## How to play

| Control | What it does |
| --- | --- |
| **Stick** (bottom left) | Point the rocket's nose in any direction. If you touch anywhere on the left half of the screen, the stick moves under your thumb. |
| **GAS** (bottom right) | Fires the engine and pushes the rocket the way its nose points. The whole right half of the screen works as the button. |

- **Land** on the green pad slowly (the speed meter must not be in the red) and upright, then hold still for a moment.
- **Fuel** is limited. Only thrust burns fuel; rotating is free. Orange cans refill the tank.
- **Stars**: every level has 3. Collect them and land to keep them (240 in total).
- **Red means danger**: spikes, mines, spinning blades and lasers destroy the rocket. Hitting rock too fast does too, but gentle scrapes are fine.
- **Wind** zones (blue streams) push you around. **Keys** open the door of the same colour.

## Worlds

1. **Launch Bay**: learn to hover, steer and land.
2. **Crystal Caverns**: jagged caves, spikes, updrafts, downdrafts and crosswinds.
3. **Reactor Core**: timed lasers, spinners, patrolling mines, keys and doors.
4. **Deep Void**: long levels that combine everything, ending with a 3,300-point climb.
5. **Emerald Mines**: tight tunnels and mazes, with much smaller fuel tanks.
6. **Acid Falls**: wind torrents, geysers and patrolling mines.
7. **Nebula Gardens**: blades, laser lattices, keys and doors.
8. **Event Horizon**: the final frontier, ending with a 3,600-point climb.

Worlds 5 to 8 are built to be tight on fuel. Each tank there is only a little bigger than what a perfect flight needs, so wasted thrust means running dry.

The game is available in **English and Russian**. It follows the iPhone's language automatically (Russian when the system language is Russian, English otherwise), and *Settings → Language* lets you force either one.

Levels unlock one after another. You can turn on *Settings → Unlock all levels* if you want to jump around. There is also a left-handed option that swaps the stick and the GAS button.

## Level Maker

*Main menu → LEVEL MAKER → NEW LEVEL* opens a grid editor.

- **Rock / Erase**: drag a finger to draw or clear rock. **Two fingers** pan and pinch-zoom anywhere. **Move** pans with one finger.
- **Start / Goal**: tap a floor to place the launch pad and the landing pad (each needs two rock cells below and room above).
- **Star** (up to 3), **Fuel** can, **Spikes** (they stick to the nearest rock, tap again to turn them), **Mine**, **Patrol** mine (tap it, then tap where it should move to), **Blade**, **Laser** (across or up–down, reaches the rock), **Wind** (pick a direction), **Key** and **Door** (three colours).
- **Undo / Redo**, and the **settings** button (name, look, width, height, fuel tank, delete).
- **TEST** flies the level right away. Land on the goal once and the level is marked *Tested*. Your landing time becomes the level's par.
- **PUBLISH** uploads a tested level to Community (you need an account). Changing a level after testing makes it untested again, so every published level is known to be beatable.

Levels are saved on the iPhone (`Documents/MyLevels`).

## Community (accounts, likes and views)

*Main menu → COMMUNITY* lists published levels in four tabs: **New**, **Top** (most likes), **Most viewed** and **Mine**. Open a level to see its views and likes, **PLAY** it (that counts a view), and **Like** it (once per account; tap again to unlike). You can also like a level from the screen you see after landing on it. Liking and publishing need an account (username, email and password). Browsing and playing don't.

**Admin:** the first account ever created on the server is the admin. Admins see a **Delete for everyone** button on every community level. Authors can delete their own levels too. Admins can make other players admins from the Supabase SQL editor with `select set_admin('username', true);` while signed in as an admin, or with `update profiles set is_admin = true where username = 'name';`.

### Setting up the server (one time, free)

The apps and the website ship connected to the Thrustbound server (`Thrustbound/Resources/backend.json`), so Community works out of the box. The steps below are for running a server of your own. Community runs on a free [Supabase](https://supabase.com) project. All the rules (who can publish, delete, like, and the view and like counters) are enforced by the database itself in [`backend/schema.sql`](backend/schema.sql).

1. Create a free account at supabase.com and a **New project** (any name and region; save the database password somewhere).
2. Open **SQL Editor → New query**, paste the whole of [`backend/schema.sql`](backend/schema.sql) and press **Run**. It is safe to run again after updates.
3. Open **Authentication → Sign In / Providers → Email** and turn **off** "Confirm email", so new pilots can play right after signing up. If you leave it on, players must click the link in their email before they can sign in.
4. Open **Project Settings → API Keys** and copy the public key: the **anon** key (on the *Legacy API keys* tab) or the newer **publishable** key. Copy the **Project URL** too (*Project Settings → Data API*, it looks like `https://abcdefgh.supabase.co`). These are meant to be public, because the database rules protect everything. Never put the *service_role* or *secret* key in the app.
5. Put them into the game, either way works:
   - **In the app**: *Community → Sign in (top right) → Server*, paste both and tap *Save server*. This works with any build, but every phone has to do it once.
   - **Built in**: add two repository secrets, `SUPABASE_URL` and `SUPABASE_ANON_KEY` (*GitHub → Settings → Secrets and variables → Actions*), then run the *iOS Build* workflow with a release tag. The IPA it builds connects automatically.
6. **Create your account first** (*Community → Sign in → Create account*). The first account becomes the admin.

`backend/test/` checks the rules in two ways. `run_tests.sh` uses plain PostgreSQL. `run_api_tests.sh` starts Supabase's own Postgres and Auth images in Docker, adds PostgREST, and replays every request the app makes: sign up, sign in, publishing, the New/Top/Most viewed/Mine lists, views, likes, permission checks and admin delete. The *Backend Check* workflow runs both on every change to `backend/`.

## Play in the browser

The web version (`web/`) is the same game: the same physics (a line-by-line port of `GameWorld.swift`), all 80 levels, the level maker, Community and both languages. On a phone it uses the same touch controls; on a computer use **← →** (or A/D) to steer, **↑ / W / Space** for gas, **↓** to point the nose up, **Esc** to pause and **R** to restart. Progress is saved in the browser.

It is published to GitHub Pages by the *Build apps* workflow on every push to `main` (the repository has to be public, with *Settings → Pages → Source: GitHub Actions*). To try it locally:

```sh
python3 tools/build_web.py            # -> build/web
python3 -m http.server -d build/web 8000
```

## Install on Android

Download `Thrustbound.apk` from the latest release on your phone, open it, and allow your browser to install apps when Android asks. Android 7 or later.

The Android app (`android/`) is a small native wrapper that runs the web version from inside the APK, so it works offline (Community needs the internet). The back button goes back a screen or pauses the game.

**Android signing:** an Android app can only update over an older version signed with the same key. Add these repository secrets once (*Settings → Secrets and variables → Actions*) so every build is signed with your own key:

```sh
keytool -genkeypair -keystore thrustbound.keystore -alias thrustbound -keyalg RSA -keysize 2048 -validity 12000
base64 -w0 thrustbound.keystore    # paste the output as ANDROID_KEYSTORE_BASE64
```

Then add `ANDROID_KEYSTORE_PASSWORD` (the password you chose) and `ANDROID_KEY_ALIAS` (`thrustbound`). Keep the keystore file and password somewhere safe and never commit them. Without these secrets the APK is signed with a temporary key: it installs fine, but to install a newer version you have to uninstall the old one first (which deletes saved progress).

## Install on your iPhone (sideload)

Every push builds the app on GitHub Actions. Tagged versions are published as an **unsigned `.ipa`** on the [Releases](../../releases) page.

1. Download `Thrustbound-vX.Y.Z.ipa` from the latest release.
2. Install it with a sideloading tool, which signs it with your own Apple ID:
   - **Sideloadly** (Windows or macOS): plug in your iPhone, drag the IPA in, enter your Apple ID, press *Start*.
   - **AltStore / SideStore**: open the IPA with AltStore (*My Apps → +*).
   - **TrollStore** (on supported iOS versions): open the IPA with TrollStore.
3. On iOS 16 or later, enable **Settings → Privacy & Security → Developer Mode** when iOS asks for it.

With a free Apple ID, sideloaded apps must be refreshed every 7 days. AltStore and SideStore can refresh automatically. You need iOS 15 or later.

## Building

The Xcode project is generated from [`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open Thrustbound.xcodeproj
```

CI (`.github/workflows/ios.yml`) does the following on every push:

1. generates the project,
2. runs the unit tests on an iOS simulator (physics, landing, hazards, keys and doors, a check that the rocket can rest safely on every launch pad, and the level maker: grid tracing, every tool, undo, saving and the community data formats),
3. builds a Release `.ipa` without code signing and uploads it as a workflow artifact,
4. builds the Android APK and the website (and runs the web tests),
5. on `main`, publishes the website to GitHub Pages (public repositories),
6. for a `v*` tag, or a manual run with a `release_tag`, publishes the IPA and the APK to GitHub Releases, each under a versioned name and a fixed one (`Thrustbound.ipa`, `Thrustbound.apk`) that the website links to.

To cut a release: **Actions → iOS Build → Run workflow**, then enter a tag such as `v1.0.1`. Pushing a tag such as `git tag v1.0.1 && git push origin v1.0.1` does the same.

## Project layout

```
Thrustbound/
  App/            SwiftUI app entry, navigation, saved progress (AppModel) and translations (Localization*.swift)
  Game/           Simulation (GameWorld), SpriteKit rendering (GameScene, LevelRenderer), controls, art
  Maker/          Level maker: grid model, compiler to game levels, editor canvas and screens, local saves
  Online/         Supabase client, account (sign up / sign in, Keychain) and community store
  UI/             Menus, level select, HUD and overlays, community, account, settings, how-to
  Services/       Sound effects and haptics
  Resources/      levels.json, sound effects, optional backend.json (community server)
  Assets.xcassets App icon and colours
ThrustboundTests/ Unit tests
web/              The browser version (plain JavaScript modules, no build step) and its tests
android/          Android app: a WebView wrapper around the web version
backend/          schema.sql for the community server, plus its tests
tools/            Level DSL, validator, autopilot, icon and sound generators (Python)
```

### Level design tools

The levels are written in Python in [`tools/levels.py`](tools/levels.py) using a small DSL (rooms, tunnels, rocks, pads, hazards). The build script turns them into `Thrustbound/Resources/levels.json` and checks every level. It verifies that the pads sit on solid ground, and runs a flood fill sized to the rocket to confirm that the goal, every star, fuel can and key can be reached, with doors only opening once their key is collected. Finally, an autopilot ([`tools/autopilot.py`](tools/autopilot.py)) flies every level using a Python copy of the game's physics. It collects all three stars and lands. In worlds 1 to 4, each tank is sized so the autopilot needs at most about 60% of it. In worlds 5 to 8 ([`tools/levels2.py`](tools/levels2.py)) the tanks are much tighter. They are sized from what the autopilot burns, aiming for it to use 78% (Emerald Mines) up to 90% (Event Horizon) of the tank, and then checked by flying the level again with that tank.

```sh
pip install numpy scipy shapely pillow
python3 tools/build_levels.py --render previews   # rebuild + validate + PNG previews
python3 tools/make_assets.py                      # regenerate app icon + sounds
```

The app icon and all sound effects are generated procedurally by `tools/make_assets.py`.
