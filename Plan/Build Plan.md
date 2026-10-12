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
- WKWebView + IFrame API (`baseURL = https://<bundle-id>`), player created on Play, `controls=0`.
- App controls below the video, full screen, keyboard shortcuts, pause.
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
- App icon, README install/run instructions, screenshots (spoiler-free!).
- GitHub repo (public).
- [DECIDED] **Distribution: an unsigned `.dmg` on GitHub Releases**, with no paid developer account. Users approve it manually under System Settings → Privacy & Security → "Open Anyway". The README must explain this step. *(user, 2026-10-11)*
  - Note: Apple Silicon requires at least ad-hoc code signing, which Xcode applies automatically. It's not the same as Developer ID notarization.

## Progress

- 2026-10-12: M0–M4 built overnight (commits on `main`, not pushed). M5 waiting. Agent decisions awaiting review are in `DEVIATIONS.md`.
