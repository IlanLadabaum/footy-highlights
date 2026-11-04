# Build Plan — v1

*Sub-plan of [Global Plan](Global%20Plan.md). Scope: the order in which v1 is built, and what "done" means for each step. **[DECIDED] Plan approved by the developer, 2026-10-11.** All v1-relevant details in the sub-plans were bulk-approved the same day; anything still [PROPOSED] is out of v1 scope.*

## v1 scope (from decisions so far)

- Mac app (SwiftUI, iPad-ready code), keys in Settings.
- Competitions: Champions League, Premier League, La Liga (ESPN FC), Bundesliga (USA Sports), Serie A, Ligue 1, Carabao Cup.
- Three screens + player screen; watched / unwatched / mark all.
- Pre-round table with reveal checkbox and hover highlight.
- Two-legged ties as separate rounds.
- No-key fallbacks (date-based rounds, greyed table panel).

**Not in v1:** UCL bracket, bonus competitions, non-US regions, extended/normal toggle, iPad build, watched-status sync.

## Build-run decisions (user, 2026-10-11)

- [DECIDED] **Overnight run of M0–M4**; M5 waits. Agent-made choices go in `DEVIATIONS.md`.
- [DECIDED] **Commit locally per milestone / sub-step** once it builds and tests pass. Never push.
- [DECIDED] **YouTube scan range: back to the current season's start** on the first refresh, then incremental (new uploads only).
- [DECIDED] **Dev tools via Homebrew: XcodeGen** (`project.yml` is the source of truth for the Xcode project) **and SwiftLint**; swift-format ships with Xcode.
- [OPEN] **Point deductions** in pre-round tables. The API has no deduction field; it can only be inferred from current standings (`points ≠ 3W + D`), without a date. Agent default pending the user's answer: results-only points plus a footnote when a deduction is detected (see `DEVIATIONS.md`).

## Milestones

### M0 — Tooling and project setup
- **Developer:** update macOS to ≥ 14.5, then install Xcode from the Mac App Store. [BUILT] macOS 27.0.1 + Xcode 27.0 installed and selected (verified 2026-10-11; signature valid). Licence accepted and first-launch setup done; Swift 6.4, macOS 27.0 SDK; a test package builds and passes, and SwiftUI + WebKit + SwiftData + Keychain compile for a macOS 14 target (verified 2026-10-11). **Tooling ready.**
- Create the Xcode project: multiplatform SwiftUI app "Footy Highlights", **deployment target macOS 14** (needed for SwiftData), [DECIDED] bundle ID **`io.github.ilanladabaum.footyhighlights`** (GitHub user `IlanLadabaum`, 2026-10-11).
  - The bundle ID matters: YouTube's Referer rule uses `https://io.github.ilanladabaum.footyhighlights`.
- Repo layout, Swift formatting/linting, a test target. Fill in AGENTS.md's code style / build / test section.
- Done when: an empty app builds and launches, tests run, and the first commit is made (on request).
- [BUILT] 2026-10-11: XcodeGen project, FootyKit package, SwiftLint/swift-format, app + package tests, first commit.

### M1 — Data layer (no UI)
- Competition config file (channels, title rules, football-data code, priority order).
- YouTube client: uploads-playlist scan with a date cutoff; prefer extended cuts.
- Title parsers per channel, unit-tested against **real titles collected during research**.
- football-data client: season matches + historical standings (`season` always sent), with a 10/min throttle and 429 backoff.
- Fixture matching + team-name aliases; fallback naming for unmatched videos.
- Local store (SwiftData): videos, fixtures, watched/revealed flags, standings cache, refresh timestamps.
- Keychain storage for keys; developer builds also read `.env`.
- Done when: a test/CLI run produces correct neutral titles and rounds for every v1 competition from live data.
- [BUILT] 2026-10-12: all of the above in `FootyKit` (40 unit tests incl. real 2025-26 titles/fixtures). Live `footy-cli` run: every v1 competition populated; 100% of PL/UCL/Bundesliga/Ligue 1/La Liga highlights matched to fixtures, 1 mislabelled CBS upload unmatched in Serie A. Standings are computed locally rather than fetched (see `DEVIATIONS.md` X1).

### M2 — Navigation screens
- Competition screen (two sections, priority order, unwatched counts, mark all).
- Rounds screen (latest round biggest; key-less date windows; per-round counts, mark all).
- Round screen fixtures column (watched checkbox, durations, "No highlights available", "Open on YouTube (may show score)", 1st-leg score rule).
- Settings: keys with "get a key" links, hide-durations toggle, first-launch setup if there's no YouTube key.
- Done when: the developer can browse every competition and mark things watched, with no player yet.
- [BUILT] 2026-10-12: all four screens, undo, Settings window, first-launch setup. Verified with offscreen snapshots of last season's data (see `DEVIATIONS.md` D26).

### M3 — Player screen
- WKWebView + IFrame API (`baseURL = https://<bundle-id>`), player created on Play, ~~`controls=0`~~ YouTube's controls (`controls=1`, decided 2026-10-12).
- ~~App controls below the video, full screen, keyboard shortcuts, pause~~ → provided by YouTube's player (2026-10-12).
- [DECIDED] (2026-10-12, added after M4) **Queue**: add from the normal screens, start with a button, marked watched only when reached, reorder by dragging, Clear queue. See [App Structure & Data Flow](App%20Structure%20%26%20Data%20Flow.md#queue). Includes **"Queue all unwatched"** per round.
- [DECIDED] (2026-10-12, added after M4) **"Show table" in the player**: a closeable panel with the round's pre-round table beside the video. See [App Structure & Data Flow](App%20Structure%20%26%20Data%20Flow.md#table-in-the-player).
- Destroy on end; errors 101/150/152/153 → message + YouTube fallback.
- [DECIDED] **Watched works like email read status:** a video is marked watched **when it's opened**, and "Mark watched" / "Mark unwatched" buttons are always available. *(user, 2026-10-11)*
- Done when: highlights from all v1 channels play correctly on the developer's Mac, re-checked against the spike's spoiler surfaces.
- [BUILT] 2026-10-12: player built. Headless check: all five in-app channels play, pause/resume, destroy on end; LALIGA error 150 handled. **The spoiler-surface re-check still needs the developer** (it needs a human watching real playback).

### M4 — League table
- Pre-round standings on the round screen; greyed "add key" panel without a key.
- Reveal checkbox: shows the score and applies it to the table, with per-league tiebreakers.
- Hover highlight of both teams.
- UCL league-phase table; full-width fixtures for cups and knockout rounds.
- Done when: the table for a past round matches the official table for that date.
- [BUILT] 2026-10-12: pre-round table, reveal checkbox, hover highlight, per-league tiebreakers, UCL league-phase table, full-width cups/knockouts. Done-when met by unit test (PL 2025-26 before MW11 = official table). Point deductions: detected but not applied, pending the developer ([OPEN] above).

### M5 — Polish and release
- [BUILT] 2026-10-13 (groundwork, at the user's request): `scripts/build-app.sh` builds the universal, ad-hoc-signed Release app that the DMG will contain, and `--install` puts it in `/Applications`. Version 0.1.0.
- App icon, README install/run instructions, screenshots (spoiler-free!).
- [DECIDED] **Make the repo public once Sparkle updates (and the DMG) are done** *(user, 2026-11-01)*. Before flipping it: scan the whole git history for secrets.
- [DECIDED] **GitHub repo: private for now** (`IlanLadabaum/footy-highlights`, created 2026-10-13). **It's made public only once the DMG and update checking below are done.** *(user, 2026-10-13)*
- [DECIDED] **"Check for updates" built into the app**, needed **before going public**. *(user, 2026-10-13)* [DECIDED] **Use Sparkle** *(user, 2026-11-01)*. [BUILT 2026-11-01, needs the developer's signing key before it's live] Sparkle 2 in the app (daily check on launch, asks before installing, "Check for Updates…" in Settings → Advanced) and `scripts/release.sh` (DMG + appcast; `--publish` creates the GitHub Release). Earlier design notes: e.g. compare the app version with the latest GitHub Release and offer to download the new DMG, or use the Sparkle framework (needs signing keys for its update feed); automatic check on launch vs a menu item; how unsigned-app updates get approved again in Privacy & Security.
  - [PROPOSED] (agent, 2026-11-01) **Sparkle 2**, the standard open-source Mac updater. It checks a small feed file (an "appcast", attached to each GitHub Release), shows "A new version is available" with release notes, then downloads, verifies, installs and relaunches with one click.
    - Works without a paid Apple account: updates are verified with a free EdDSA key pair. The private key is kept secret like the signing certificate, and backed up.
    - Because the app downloads the update itself, macOS doesn't attach the "downloaded from the internet" flag, so **users approve "Open Anyway" only once**, on first install, not on every update.
    - Alternative: a hand-written check against GitHub's "latest release" API that opens the DMG download in the browser. Less code to vendor, but every update would need dragging to Applications plus "Open Anyway" again.
    - Note: a private repo's releases can't be read without a login, so update checks only work once the repo is public (or against a public test repo).
    - Release side (M5): a script that builds the app, makes the DMG, signs it for Sparkle, updates the appcast and creates the GitHub Release.
    - [DECIDED] **Check automatically once a day, on launch; ask before installing.** *(user, 2026-11-01)*
    - [DECIDED] **Also a manual "Check for Updates…" in the Settings window.** *(user, 2026-11-01)*
- [DECIDED] **Distribution: an unsigned `.dmg` on GitHub Releases**, with no paid developer account. Users approve it manually under System Settings → Privacy & Security → "Open Anyway". The README must explain this step. *(user, 2026-10-11)*
  - Note: Apple Silicon requires at least ad-hoc code signing, which Xcode applies automatically. It's not the same as Developer ID notarization.
- [OPEN] (2026-11-01) **Probably no longer needed**: its only purpose was stable Keychain access, and keys now live in a private file. Sparkle doesn't need it either (it uses its own EdDSA key). Waiting for the developer to confirm dropping it.
- [DECIDED] **Sign every build with a self-signed code-signing certificate** (free, no paid account) *(user, 2026-10-15; not done yet, do before the first DMG)*.
  - Why: ad-hoc signing identifies the app only by a hash of that exact build, so macOS's "Always Allow" for the Keychain prompt is lost after every rebuild or update. Found 2026-10-15; the repeated prompts within one launch were a separate bug, fixed the same day.
  - A stable self-signed identity makes each new version count as the same app, so Keychain access survives updates for the developer and for users.
  - Gatekeeper still treats it as an unidentified developer, so the README's "Open Anyway" step remains.
  - To do: create the certificate (Keychain Access → Certificate Assistant, or `openssl` + `security import`, with the developer's OK since it changes their login keychain). Set `CODE_SIGN_IDENTITY` to it in `project.yml` and `scripts/build-app.sh`. Keep a secure backup of the private key: losing it means every user approves again once.
  - Later: if releases are built in CI, the certificate goes into CI secrets.
  - [OPEN] (2026-10-21) **The developer still gets 4 Keychain prompts on every launch** (two per key: "use your confidential information" and "access key"). **The prompts have no "Always Allow" button**, only a password field (developer, 2026-10-21), consistent with macOS having no stable identity to remember for an ad-hoc-signed app. The installed app is unchanged since 2026-10-15, so this isn't only the rebuild problem: the choice isn't being remembered even for the same build. Likely cause: ad-hoc signing. **Approved 2026-10-21: do the self-signed certificate now** (the agent's attempt to create it was blocked by Claude Code's permission system, so the developer runs the creation step), test it first on a throwaway Keychain item, then check the prompts stop after one "Always Allow". If they don't, fallback options for the developer to choose from: (a) store keys in a private file in Application Support (no prompts, less protected), or (b) accept one prompt per update.

## Progress

- 2026-10-12: M0–M4 built overnight (commits on `main`, not pushed). M5 waiting. Agent decisions awaiting review are in `DEVIATIONS.md`.
