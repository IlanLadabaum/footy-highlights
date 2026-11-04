# Video Sources

*Sub-plan of [Global Plan](Global%20Plan.md). Scope: where highlight videos come from, per competition and region, how to identify and name them, and where fixture data comes from. Research done 2026-10-11 with the YouTube Data API (US region) plus web research.*

## Principles

- [DECIDED] **The pipeline should be competition-agnostic.** Competitions, channels and title rules are *configuration*, so adding a competition later should be trivial. The first build covers only the core competitions. *(user, 2026-10-11)*
- [DECIDED] **Prefer extended highlights** when a match has both normal and extended versions. *(user, 2026-10-11)*
  - [PROPOSED] (future) A setting to prefer extended or normal.
- [DECIDED] [BUILT 2026-10-21] **Extended / normal toggle per match** *(user, 2026-10-21; supersedes "one entry per match, extended preferred")*. When a match has both cuts, the row gets a toggle between them, showing the selected cut's length. Queue / Queue all unwatched add whichever cut is selected. A Settings option picks the default (extended or normal).
  - Today only beIN (Ligue 1) posts both cuts, and only for some matches. CBS posts extended only; NBC, USA Sports and ESPN FC post one version. (Future: Liga Portugal and Süper Lig on beIN also have both.)
  - [DECIDED] **The toggle shows only on matches that have both cuts.** The hint this gives (which matches got an extended cut) is accepted. *(user, 2026-10-21)*
  - [DECIDED] The choice is remembered per match; watching either cut marks the match watched; the player and queue use whichever cut was selected when it was opened or queued. *(user, 2026-10-21)*
- [DECIDED] **YouTube is the video platform.** Answer to "can we avoid YouTube?" (2026-10-11): every other source (Peacock, Paramount+, ESPN+, league websites) is paid, DRM-protected and has no public API, so using it would mean scraping against its terms. YouTube is the only free, legal, API-backed source. The app's real value is the spoiler-free, fixture-based layer *on top* of the videos.
  - [DECIDED] The code still treats "video provider" as an interface, so another provider could be added if one ever appears.
- [PROPOSED] **Region-specific source configs.** The US-only problem (deferred by the user) is mostly a configuration issue. Official league channels cover most other countries (see the per-league notes). Each user (or region preset) picks a source set.

## Access method

- [DECIDED] **YouTube Data API v3, uploads playlist** (`playlistItems.list`, 1 quota unit per 50 videos; the free daily quota is 10,000 units). Scan newest-first and stop at a date cutoff.
- RSS feeds were checked and **rejected**: they return only the latest 15 uploads, and busy multi-sport channels (NBC Sports, USA Sports) push football out within hours.
- Compliance (see [In-App Player](In-App%20Player.md)):
  - Each user supplies their own API key, and the repo never contains one (DP III.D.1.d).
  - Cached API data must be refreshed or deleted within 30 days (DP III.E.4.c).

## Core competitions (US sources)

| Competition | Channel | Title format (example) | Coverage | Duration / versions | Spoilers in title? | Status |
|---|---|---|---|---|---|---|
| **Premier League** | NBC Sports `UCqZQlzSHbVJrwrn5XvzrzcA` | `Arsenal v. Leeds United \| PREMIER LEAGUE HIGHLIGHTS \| 10/10/2026 \| NBC Sports` | Every match | ~9–12 min, one version | No | [DECIDED] use |
| **Champions League** | CBS Sports Golazo `UCET00YnetHT7tOpu12v8jxg` | `Napoli vs. Arsenal: Extended Highlights \| UCL League Phase MD 1 \| CBS Sports Golazo` | Every match | ~8–11 min, extended | No; **round is in the title** | [DECIDED] use |
| Serie A | CBS Sports Golazo | `Inter vs. Parma: Extended Highlights \| Serie A \| …` | Every match | extended | No | [DECIDED] use |
| Carabao Cup | CBS Sports Golazo | `… : Extended Highlights \| Carabao Cup \| …` | Every match | extended | No | [DECIDED] use |
| Ligue 1 | beIN SPORTS USA `UC0YatYmg5JRYzXJPxIdRd8g` | `PSG vs Le Mans \| EXTENDED HIGHLIGHTS Ligue 1 \| 10/10/2026 \| beIN SPORTS USA` | Every match | `HIGHLIGHTS` ~11 min; `EXTENDED HIGHLIGHTS` ~18–24 min for some matches → take the extended one when it exists | No | [DECIDED] use |
| **Bundesliga** | **USA Sports** `UC9u0o8uDT5Z6IsrXp2Grs9Q`. US English rights moved from ESPN to USA Sports (Versant) for 2026-27 to 2030-31 | `Borussia Dortmund v. SV Werder Bremen \| BUNDESLIGA HIGHLIGHTS \| USA Sports` | Every match (9/9 in MD1–4) | ~17–18 min, long cut | No | [DECIDED] use |
| **La Liga** | ESPN FC (incomplete; see below) | `Sevilla vs. Barcelona \| LALIGA Highlights \| ESPN FC` | ~60–75% of matches | 9–25 min | Sometimes teaser prefixes | [DECIDED] use |

Common caveats:
- Multi-sport channels (NBC Sports, USA Sports) need strict title filters.
- Title formats drift (`v` / `v.`, a date sometimes included).
- Team names vary ("Leeds" / "Leeds United", "Man. United", "FC Cologne" / "1. FC Köln").
- USA Sports sometimes gets **home and away reversed** in titles. Matching to fixture data (below) fixes both of these.

### La Liga options

| Option | Coverage | Problem |
|---|---|---|
| ESPN FC `UC6c1z7bA__85CIWZ_jpCK-Q` | **Incomplete**: 6/10 and 3/4 in recent rounds | Titles often have teaser prefixes ("RED CARD DRAMA ‼️"). These leak through the ~3 s title flash at the start of playback |
| LALIGA EA SPORTS (official) `UCTv-XvfzLX3i4IGWAm4sbmA` | Complete (10/10) | **Can't be played in-app at all:** LaLiga blocks third-party embedding (player error 150, verified 2026-10-11), despite `embeddable: true`. Also, the score is in every title, so "open on YouTube" would spoil it. **Ruled out.** |
| ESPN Deportes | Seems complete | Spanish; narrative titles that spoil the result |
| Hybrid: ESPN FC, falling back to LALIGA | Complete | Inherits both problems |

- The hybrid option is gone because the official LALIGA videos can't be embedded (see above). ESPN Deportes is likely the only "complete" US option, but its titles spoil the result.
- [DECIDED] **La Liga via ESPN FC**, accepting gaps and the occasional teaser-title flash. Skipped matches show "No highlights available", with a fallback to open the official LALIGA video on YouTube in the browser where one exists (details and spoiler warning in [App Structure & Data Flow](App%20Structure%20%26%20Data%20Flow.md#match-rows)). *(user, 2026-10-11)*
- [PROPOSED] Re-check later whether ESPN FC's coverage improves, and whether new sources appear.
- **ESPN Deportes re-check (2026-10-21, at the developer's request; counts only).** Channel `UC08mnbiC4FykqpHqbEWgFcg` (@ESPNDeportes), Spanish. Measured against football-data's 89 finished La Liga 2026-27 matches (MD1–9):
  - **Coverage: 85/89** matches have an 8–25 min highlight video (typically 11–16 min) within 5 days of kickoff. Every matchday 8–10 of 10.
  - **Embeddable and playable in the US: all 85** (`embeddable: true`; not yet test-played in the app's player).
  - **Titles spoil: 64/85 contain a score or a result word** ("golea", "remontada", "empate"…); the rest are narrative ("doblete de…") and probably hint too. With YouTube's controls the original title shows for ~3 s at the start and whenever the mouse is over the video, so **almost every Deportes video would show its result on screen**.
  - **Titles have no fixed format** (free-form Spanish sentence, then `| LaLiga`). Matching would rely on team names + fixture date window + duration, so it needs the football-data key; without it, Deportes can't be parsed reliably.
  - Busy channel (~2,700 uploads since 1 Aug): first scan ~55 YouTube units, then incremental. Big clubs get many clips per match, so the duration filter matters.
- [DECIDED] [BUILT 2026-10-21; Settings → Leagues] **La Liga source order is a setting** *(user, 2026-10-21)*. The user picks either source as the priority, with the other as a fallback for matches the first one skipped, or uses just one. Each source has a one-line pros/cons note in Settings, e.g.:
  - ESPN FC: English; misses about a third of matches; titles mostly clean (occasional teaser).
  - ESPN Deportes: Spanish; almost every match; the title shows the result at the start and on hover.
  - Deportes videos (as primary or fallback) carry the "may show score at start" flag.
  - [DECIDED] Default for new users and existing installs: ESPN FC first, ESPN Deportes as fallback. *(user, 2026-10-21)*
  - [DECIDED] Without a football-data key, Deportes titles can't be matched to matches (no fixed format), so Deportes is unavailable without the key, shown greyed with the usual "add a football-data key" message. *(user, 2026-10-21)*
  - [DECIDED] Keep "Open on YouTube (may show score)" (official LALIGA video) only for matches neither chosen source has. *(user, 2026-10-21)*

### Bundesliga alternatives (non-US region configs)

- Official Bundesliga `UC6UL29enLNe4mqwTfAyeNuw`: plays everywhere except DE/AT/CH/LU/LI. Short 1–4 min videos, clickbait outcome hints in titles ("INCREDIBLE Comeback"). A candidate default outside the US.
- Telemundo Deportes `UCjZ7QPKb89R-4SxzBoceyOg`: Spanish, US, complete, no scores in titles.
- DAZN Football `UCSZ21xyG8w_33KriMM69IxQ`: Canada only, big matches only.

## Leagues to add (after v1)

Decided additions, not yet scheduled in the Build Plan. Each still needs its source and fixture-data details checked before building.

| League | Decided | Known US source | Fixture data (football-data free tier) |
|---|---|---|---|
| NWSL, WSL | 2026-10-12 | Not researched (see below) | Neither covered |
| **EFL Championship, League One, League Two** | 2026-11-01 *(user)* | CBS Sports Golazo (same title format as UCL) | Championship yes (`ELC`); League One/Two no (no-key behaviour, like the Carabao Cup) |
| **Turkish Süper Lig** | 2026-11-01 *(user)* | beIN SPORTS USA (normal + extended, so the extended/normal toggle applies); ESPN FC (teaser titles) | No (no-key behaviour) |

- [OPEN] For the EFL and Süper Lig: confirm coverage (every match?), title formats, spoilers in titles and embeddability, as was done for the v1 leagues.

### Women's leagues (requested 2026-10-12)

- [DECIDED] **Add support for the NWSL and the WSL** (Barclays Women's Super League). *(user, 2026-10-12)* Timing: after v1 (not yet scheduled in the Build Plan).
- [OPEN] **Highlight sources (US):** not researched yet. To check: the NWSL's own channel and its US broadcasters' channels; the WSL's official channel and its US rights holder. For each: coverage, title format, spoilers in titles, embeddability.
- [OPEN] **Fixture data:** football-data.org's free tier doesn't list either league (its free list is BL1, BSA, CL, CLI, DED, EC, ELC, FL1, PD, PL, PPL, SA, WC). Unless another free source turns up, both would use the no-key behaviour (date-based rounds, teams parsed from titles, no table, no "no highlights" rows), like the Carabao Cup.

## Bonus competitions (held for later)

- [DECIDED] Listed here; **not included until the core app works**. *(user, 2026-10-11)* The EFL leagues and the Turkish Süper Lig moved to [Leagues to add](#leagues-to-add-after-v1) on 2026-11-01.

| Competition | Known US source |
|---|---|
| Coppa Italia | CBS Sports Golazo |
| UCL qualifying rounds | CBS Sports Golazo |
| Scottish Premiership (SPFL) | CBS Sports Golazo (sparse) |
| Liga Portugal | beIN SPORTS USA (normal + extended) |
| MLS | ESPN FC (teaser titles); MLS's own channel not yet checked |
| Europa / Conference League, FA Cup | Not yet researched |

## Fixture data

Researched 2026-10-11.

- [DECIDED] **Primary: [football-data.org](https://www.football-data.org) v4, free tier** *(user, 2026-10-11; key configured and verified)*. Each user registers their own free key. Sharing the developer's key isn't viable: it would be public in an open-source app, and every user would share one 10-calls/min limit.
- [DECIDED] The fixture key is **optional** *(user, 2026-10-11)*. Without it, the app falls back to names parsed from titles (no round for PL/Serie A/Ligue 1/Bundesliga, no league table), so a user can start with just a YouTube key.
  - Covers PL, UCL, Serie A, La Liga, Bundesliga, Ligue 1, Championship and Primeira Liga.
  - `matchday` and `stage` fields; stable team IDs with `shortName` / `tla`; full-time and half-time scores.
  - **Standings by `?matchday=` or `?date=`** (directly supports the future league table).
  - Limit 10 calls/min; one call returns a whole season's matches.
  - Free-tier data is "delayed", which is fine for highlights.
  - **Missing on the free tier:** Carabao Cup, FA Cup, Coppa Italia, Europa League, MLS.
- [PROPOSED] (later, if needed) **Fallback for cups: TheSportsDB.** Its free key is for testing (5-row table limit). It lagged a round behind in testing.
- Rejected:
  - API-Football: its free plan excludes the current season.
  - Sportmonks: its free plan has no big leagues.
  - openfootball: no UCL or cups, and ~3 weeks stale when tested. Kept as a possible offline fixture source.
  - ESPN's undocumented API, FotMob, SofaScore: no licence, or their terms forbid automated access.
- [DECIDED] **Mislabelled videos are hidden** *(user, 2026-10-12, reported as a bug)*: in a competition with fixture data, a video whose teams don't play in that competition at all (e.g. a CBS upload of Southampton v Portsmouth labelled "Serie A") isn't shown. A video with at least one recognised team still shows, per "show every video".
- [DECIDED] Match each video to a fixture by (competition, date window, team aliases). Show **teams and home/away from the fixture**, not from the video title. This fixes the reversed USA Sports titles and inconsistent names.
- **football-data competition codes for v1:** PL (Premier League), CL (Champions League), PD (La Liga), BL1 (Bundesliga), SA (Serie A), FL1 (Ligue 1). Free plan, verified with the developer's key 2026-10-11: BL1, BSA, CL, CLI, DED, EC, ELC, FL1, PD, PL, PPL, SA, WC. The Carabao Cup exists as **FLC** but returns **403 (restricted)** on the free plan. Bonus-list note: Championship (ELC), Primeira Liga (PPL) and Copa Libertadores (CLI) are free.
- Useful enums (docs, Lookup Tables):
  - Match `status`: SCHEDULED, TIMED, IN_PLAY, PAUSED, EXTRA_TIME, PENALTY_SHOOTOUT, FINISHED, SUSPENDED, POSTPONED, CANCELLED, AWARDED. **"No highlights available" rows apply only to FINISHED/AWARDED matches.** Postponed/cancelled matches show their status, which isn't a result spoiler.
  - `score.duration`: REGULAR, EXTRA_TIME, PENALTY_SHOOTOUT. Used when revealing scores and showing first-leg scores (e.g. "a.e.t." / "pens").
- [DECIDED] Carabao Cup has no free fixture data: it **always uses the no-key behaviour** (date-based rounds, teams parsed from titles, no table, no "no highlights" rows). *(approved interpretation, 2026-10-11)*
