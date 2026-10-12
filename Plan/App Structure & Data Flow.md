# App Structure & Data Flow

*Sub-plan of [Global Plan](Global%20Plan.md). Scope: how the app is organised on screen, how and when it calls external APIs (rate limits), settings, and how optional features behave when not configured. Planning started 2026-10-11.*

## API budgets

| API | Limit | What we need |
|---|---|---|
| YouTube Data API v3 | 10,000 units/day per user's key | Uploads-playlist scan: 1 unit per 50 videos. ~7 channels × a few pages ≈ 20–40 units per full refresh |
| football-data.org (free) | **10 requests/minute** per user's key | `/competitions/{code}/matches?season=YYYY` returns **a whole season's fixtures + results in one request**. Standings for a past date/round: 1 request each (future table feature) |

- The 10/minute limit counts **requests**, not keys. A full refresh of all core competitions is ~6–7 requests (one per competition), so it fits within a single minute.
- The old app's real problem was refetching *every* competition on every page load with no cache. The rules below avoid that.

### Rules

- [DECIDED] **Local cache first.** The UI always renders from a local store and never waits on the network. Refreshes update the store in the background.
- [DECIDED] **Refresh policy:** on launch, and on a manual "Refresh" button, only if the last refresh is older than N minutes (e.g. 15). Fixtures change rarely, so refresh them at most daily, plus around match days.
- [DECIDED] **One football-data request per competition per refresh** (the season endpoint). Never one request per match.
- [DECIDED] **Client-side throttle:** a small request queue that never exceeds 10 requests/min. **football-data's maintainer explicitly asks LLM-written clients to throttle from the response headers** (welcome email, 2026-10-11), so this is mandatory.
  - Headers actually returned (verified 2026-10-11): `x-requests-available-minute` (requests left in the current window) and `X-RequestCounter-Reset` (seconds until the window resets). The docs' lookup table names them `X-RequestsAvailable` / `X-RequestCounter-Reset`, so read both spellings, case-insensitively.
  - Before each request: if requests available is 0 (or unknown and the local count is at 10), wait `X-RequestCounter-Reset` seconds.
  - On HTTP 429, wait the reset time and retry once. Never retry in a tight loop.
  - Requests are serialised through one queue, never fired in parallel.
- [DECIDED] **Standings (future table feature):** fetched once per (competition, round) and cached permanently, since past tables don't change (apart from point deductions).
- [DECIDED] YouTube data is cached and refreshed within 30 days (ToS DP III.E.4.c), which happens automatically through normal use.

### Effect on UI organisation

- With caching and the season endpoint, **the rate limit doesn't constrain the organisation choice**. Both "all leagues at once" and "one league at a time" cost the same ~7 requests per refresh. The choice below is a UX decision.

## Organisation (UI)

- [DECIDED] **Per-league drill-down, three screens.** *(user, 2026-10-11; the unified inbox and Mail-style sidebar options were rejected)*
  1. **Competition selector (landing page):** all configured competitions, each clickable.
  2. **Rounds screen** (inside a competition): the **most recent round at the top as the largest panel**; earlier rounds below, reachable by scrolling. **No table on this screen.**
  3. **Round screen** (after clicking a round): **fixtures on one side, league table on the other.**
- [DECIDED] Implemented as a navigation stack (`NavigationStack`) with a back button / breadcrumbs. This works the same on Mac and iPad.

- [DECIDED] **Choose which leagues appear on the home page** *(user, 2026-10-12)*: as leagues are added, the landing page gets crowded, so it gets an **"Add/remove leagues"** button that opens a list of every supported league with an on/off toggle each. Only enabled leagues show on the home page. Timing: not yet scheduled (planned alongside the new leagues).
  - [OPEN] Details to settle when it's built: which leagues are on by default for a new user; whether turning a league off also stops fetching its data (saves quota) or only hides it; whether the toggles live on the home page, in Settings, or both.

### Open details for these screens

- [DECIDED] **Unwatched counts** on competition tiles and on each round panel. *(user, 2026-10-11)* "Unwatched" counts highlight videos available but not yet watched; "No highlights available" rows don't count.
- [DECIDED] **"Mark all as watched"** on all three screens *(user, 2026-10-11)*:
  - Competition screen: per competition, marks the whole competition.
  - Rounds screen: per round panel.
  - Round screen: the current round.
  - [DECIDED] Provide undo (or a confirmation for the competition-wide action), since it can touch dozens of matches.
- [DECIDED] **Competition order** *(user, 2026-10-11)*:
  - Two sections: **"New stuff to watch"** (≥ 1 unwatched highlight) first, then **"Nothing new"**.
  - Within each section: Champions League, Premier League, La Liga, Bundesliga, Serie A, Ligue 1, then any others (order unimportant; e.g. Carabao Cup).
- [DECIDED] **Two-legged ties: each leg is its own round** (e.g. "Round of 16 · 1st leg", "Round of 16 · 2nd leg"). **The second-leg round shows the first-leg score** for each tie. *(user, 2026-10-11)*
  - [DECIDED] Spoiler rule *(user, 2026-10-11)*: show the first-leg score automatically if the user has **watched or revealed** that first-leg match; otherwise show "1st leg: hidden · Reveal". This is needed because a user can open the 2nd-leg round without having watched the 1st leg.
- [DECIDED] **Round panels** show the round name ("Matchweek 7" / "League Phase MD 2"), date range, and the unwatched count / mark-all button.
- [DECIDED] **Flow without a football-data key: option (b), date-based "rounds"** (weekend / midweek windows), so it works the same as with a key. *(user, 2026-10-11)* Options that were considered:
  - (a) Skip the rounds screen: competition → one list of all its videos. The user's suggestion.
  - (b) Keep the same three screens, but build "rounds" from upload dates: a weekend or midweek window, e.g. "Weekend of 10–11 Oct".
  - Agent's view: (a) isn't hard to build, but (b) is the better design. It keeps one navigation flow and one set of screens to test, keeps long competitions scrollable by week instead of one ever-growing list, and keeps per-round "mark all as watched" working. Its weakness is that a postponed midweek game lands in the wrong group, which is acceptable in the degraded mode.
- [DECIDED] **Where the video plays:** a dedicated **player screen** (back returns to the round), with a **full-screen button** like YouTube's. *(user, 2026-10-11)*
  - [DECIDED] (2026-10-12) Full screen, play/pause, seeking, subtitles and keyboard shortcuts come from **YouTube's own player controls** (see [In-App Player](In-App%20Player.md)). Any app controls stay in a bar **below** the video, never on top of it (ToS).

## Queue

- [DECIDED] **Queue** *(user, 2026-10-12)*: while browsing the normal screens, the user can add any number of highlights to a queue, then press a button to start it. The queue plays in order on the player screen.
  - [DECIDED] A video is marked watched only when the player **reaches** it, not when it's added to the queue.
  - [DECIDED] The queue can be opened, **reordered by dragging**, and emptied with a **Clear queue** button.
  - [DECIDED] **Start queue button on screen** *(user, 2026-10-12)*: whenever the queue has videos, a "Start queue" button floats in the bottom-right of the browsing screens (in addition to the one in the queue popover).
  - [DECIDED] **"Queue all unwatched"** on each round (matchweek): queues that round's unwatched highlights in chronological order (the order rows are listed in). *(user, 2026-10-12)*

## Table in the player

- [DECIDED] **"Show table" button inside the player screen** opens the round's pre-round table on the right of the video, to check the table during the game; it can be closed again. *(user, 2026-10-12)*

## Match rows

- [DECIDED] Each match shows a neutral title (teams + competition + round where known), a watched checkbox and a play action. *(earlier decisions)*
- [DECIDED] **Missing highlights:** if a fixture has been played but no in-app highlight exists (e.g. ESPN FC skipped it), show the match as **"No highlights available"**. *(user, 2026-10-11)*
- [DECIDED] **Fallback to YouTube in the browser where possible**: e.g. a La Liga match ESPN FC skipped could link to the official LALIGA video, which can't be embedded. *(user, 2026-10-11)*
  - [DECIDED] The button is labelled **"Open on YouTube (may show score)"**. *(user, 2026-10-11)*
  - Note: knowing a match was played but has no highlight requires **fixture data**. Without a football-data key, the app only knows about matches that have videos, so "no highlights" rows can't appear.
- [DECIDED] **Video length shown by default**, with a toggle in **Advanced Settings** to hide durations. *(user, 2026-10-11)*
- [DECIDED] **Fallback label for an unmatched video** *(user, 2026-10-11)*. Normally each video is matched to a fixture in football-data (by competition, date and team names) to get the round number and official team names. Matching can fail:
  - an unusual team spelling ("Wolves" vs "Wolverhampton Wanderers FC");
  - a changed title format;
  - a competition not covered by the free tier (Carabao Cup);
  - no football-data key configured.

  Rule:
  - (1) Show the teams parsed from the video title, without a round: "Arsenal v Leeds United · Premier League".
  - (2) If even the teams can't be parsed: "Premier League highlight · Sat 10 Oct".
  - Always shown, never hidden (per "show every video").

## Settings

- [DECIDED] **No sync of watched status** (iCloud etc.) for now. *(user, 2026-10-11)* Watched state is stored locally.
- [DECIDED] Advanced Settings includes "Hide video durations" (default off).
- [DECIDED] **API keys are entered and edited in the app's Settings.** *(user, 2026-10-11)* Settings links to where each key is obtained: [Google Cloud Console → Credentials](https://console.cloud.google.com/apis/credentials) / the YouTube Data API v3 page for the YouTube key, and [football-data.org registration](https://www.football-data.org/client/register) for the fixture key. Ideally also a link to the README's step-by-step guide.
- [DECIDED] Keys are stored in the macOS/iPadOS Keychain. `.env` is only a developer convenience: a user who downloads the app has no project folder, and an iPad has no `.env`. The README key guides will point to Settings once the app exists.
  - [DECIDED] Developer builds also read `.env`, for convenience.

## Optional features when not configured

- [DECIDED] Fixture data (football-data key) is **optional**. *(user, 2026-10-11)*
- [DECIDED] (direction) Where a key-dependent feature would appear, show it **greyed out with a message**, e.g. in the table panel: *"Add a football-data.org key in Settings to see league tables and round numbers."*, with a button that opens Settings. *(user, 2026-10-11)*
- [DECIDED] Other things that degrade without the key: no round numbers in titles, no "no highlights available" rows, team names come from video titles.
- [DECIDED] A YouTube key is **required**. Without it, the first launch shows a setup screen that links to the guide.
