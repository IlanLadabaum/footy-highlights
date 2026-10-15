# League Table Context

*Sub-plan of [Global Plan](Global%20Plan.md). Requested by the developer 2026-10-11. **Now in the first build** (developer changed their mind, 2026-10-11).*

## Features (user ideas, 2026-10-11)

- [DECIDED] **(v1) Pre-round table**, shown on the round screen beside the fixtures: when viewing a round's highlights, show the league table **as it stood before that round**, for context (title race, relegation fight) without revealing results.
- [DECIDED] **(v1) "Show score & update table" checkbox** *(user, 2026-10-11)* per match, next to the "watched" checkbox. Ticking it reveals that match's score and applies the result to the displayed table. The table then reflects exactly the matches the user has chosen to reveal.
- [DECIDED] **(v1) Hover highlighting** *(user, 2026-10-11)*: hovering over a match in the list highlights both teams' rows in the table.
- [DECIDED] **"Update table with all scores from this matchweek"** *(user, 2026-10-12)*: a button at the top of the table viewer that reveals every finished match in the round at once and applies them all to the table (the same as ticking every "Show score & update table" box).
- [DECIDED] **Browse a team's previous results** *(user, 2026-10-14; built 2026-10-14)*. Same context as the table: how a team has been doing coming into the round.
  - [DECIDED] UI *(user, 2026-10-14)*: **click a team in the table** to open a small box listing its previous results. The box has an **✕** to close it. This works anywhere the table appears: the round screen and the player's table panel.
  - [DECIDED] Each line reads **`<date>  <Home team> v <Away team>  [score]`**. The **score sits in a colour-coded box**, green (the selected team won), yellow/gold (draw), red (lost), from that team's point of view. This replaces a separate W/D/L marker and also shows home/away. *(user, 2026-10-14)*
  - [DECIDED] **Newest first.** *(user, 2026-10-14)*
  - [DECIDED] **All of the season's results in this competition**, in a smallish window showing about **5–10 results at a time; scroll within the box** for more. *(user, 2026-10-14)*
  - [DECIDED] **This competition only** for now. *(user, 2026-10-14)*
  - [DECIDED] **No links to highlights** from the box for now. *(user, 2026-10-14)*
  - [DECIDED] **Unwatched results are not hidden.** The table already counts them. *(user, 2026-10-14)*
  - [DECIDED] Spoiler rule (follows from the table's rules): show only results the pre-round table already counts, i.e. kickoff before the round's cut-off, plus matches the user has revealed in this round. Never results from this round or later that haven't been revealed.
- These also settle the "manual reveal" question in [Spoiler Protection](Spoiler%20Protection.md).

## How to build the table

- User's suggestion: load the current table and **back-calculate** by removing the results of the current period's games.
- **Verified 2026-10-11 with the developer's key:** football-data.org returns past standings with `/competitions/PL/standings?season=2026&matchday=3` (every team at 3 games played) and with `?date=2026-09-01`. **Pitfall: `matchday` is silently ignored unless `season` is also given**; without it you get the *current* table, which would be a spoiler. Always send `season`, and verify `playedGames` in the response. So the historical table comes from the API, and back-calculation becomes the fallback rather than the main path.
- [DECIDED] Combined approach:
  1. Base table = standings as of just before the earliest kickoff of the round (from the API by date, or by back-calculating from current standings minus later results).
  2. For each match the user has revealed, apply its result to the base table and re-sort. The same code serves both the reveal checkbox and back-calculation (subtracting a result is the reverse operation).
- Pitfalls found in research:
  - football-data's historical standings are computed from results only and **ignore point deductions**. Apply deductions from current standings by hand, or note this limitation.
  - **Postponed games:** "matchday N" doesn't line up with dates. Define "before the round" as "matches with kickoff before the earliest kickoff of round N".
  - **Tiebreakers differ by league** (PL: goal difference; La Liga and Serie A: head-to-head). Re-sorting after a reveal must follow each league's rules.
  - Champions League league-phase table: same idea, 36 teams. Knockouts have no table.

## Competitions without a league table

What football-data provides (verified 2026-10-11):
- **UCL league phase:** a full 36-team table (`stage: LEAGUE_STAGE`, plus home/away splits), so it's treated like a league.
- **UCL knockouts:** matches only, with `stage` = `PLAYOFFS`, `LAST_16`, `QUARTER_FINALS`, `SEMI_FINALS`, `FINAL`. Each leg is a separate match; there's no aggregate field (the app sums legs itself); `score.winner` and `duration` (extra time / penalties) are included.
- **Carabao Cup:** not on the free tier at all, so there's no data for any visualiser.

- [DECIDED] **Bracket only when the path to the final is fixed** *(user, 2026-10-11)*. While a competition still has a draw after the current round, there's no bracket, and the fixtures use the full width. A bracket appears only once every remaining path to the final is set (no more draws), because only then does it mean something.
  - In the current UCL format the bracket is fixed from the **round of 16** onward, so the bracket shows on R16, QF, SF and Final rounds. Earlier knockout rounds (play-offs) have no bracket. Cups that draw every round (Carabao Cup, FA Cup) never get one before the final.
  - [PROPOSED] Spoiler rule: show the bracket **as it stood before the round being viewed**. Later slots read "Winner of A v B" and never show who advanced. Results of earlier rounds show only for matches the user has watched or revealed.
  - [OPEN] **Data risk:** football-data lists knockout matches by stage but may not say which R16 tie feeds which quarter-final *before* the quarter-final fixtures exist. Check this when the knockouts are drawn (around Feb 2027); a hand-maintained bracket file per season is the fallback.
  - [PROPOSED] Timing: **after v1**, since UCL knockouts start around February.
- [DECIDED] Carabao Cup (and other cups without data): fixtures use the full width; no visualiser.

## Spoiler constraints

- [DECIDED] Never show current standings, form guides ("W W L D") or goal difference that include unrevealed matches.
- [DECIDED] Settled by the screen design: each round screen shows the table as it stood **before that round**, so being several rounds behind is handled one round at a time.
- [DECIDED] The standings response includes a `form` field (recent W/D/L). It's only safe from a pre-round (historical) request; never take it from a current-standings call.

## Dependency on the core design

- [DECIDED] The core app already links each video to a structured fixture (competition, season, round, home, away, kickoff, fixture ID) from the fixture data source, so this feature plugs in without a redesign.
