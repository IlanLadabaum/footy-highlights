# Spoiler Protection

*Sub-plan of [Global Plan](Global%20Plan.md). Scope: every place a match result could leak to the user, and the chosen mitigation for each.*

## Principle

- [DECIDED] The app must never reveal a result before the user chooses to see it.
- [DECIDED] **Show every video.** Protection comes from presentation, not from hiding videos. *(user, 2026-10-11)*
- [DECIDED] **YouTube ToS compliance beats spoiler protection.** Minor residual leaks are acceptable when the only fix would break the terms. *(user, 2026-10-11)*

## Leak vectors

1. **Title in the app's list.** [DECIDED] Never show the original; show a **neutral title: teams + competition + round where relevant**. *(user, 2026-10-11)*
   - [DECIDED] Teams, home/away and round come from fixture data where possible, not from the video title.
   - [DECIDED] Label it as the app's match info, show the channel name + "from YouTube", and offer a "show original title" action (ToS: DP III.F.2.a).
   - [DECIDED] Fallback label when a video can't be matched: teams parsed from the title without a round; if that also fails, "<Competition> highlight · <date>". See [App Structure & Data Flow](App%20Structure%20%26%20Data%20Flow.md#match-rows).
2. **Thumbnail.** [DECIDED] Never shown, in the list or as the player's poster. The player is created only on Play.
3. **Video duration.** NBC/CBS/beIN/USA Sports durations are fairly uniform; ESPN FC ranges from 9 to 25 min. [DECIDED] Shown by default; Advanced Settings has a toggle to hide them. *(user, 2026-10-11)*
4. **Description.** [DECIDED] Never fetched or shown.
5. **Related non-highlight videos** (reactions, recaps, press conferences). [DECIDED] Only match-highlight videos are listed, using strict per-channel filters.
6. **Player UI.** Measured in the spike; details in [In-App Player](In-App%20Player.md#spike-results-2026-10-11).
   - Fixed compliantly:
     - no poster (player created on Play);
     - ~~no seek-bar previews (`controls=0`)~~ — accepted risk since 2026-10-12: YouTube's controls are used, and users are trusted not to hover the seek bar;
     - no related-videos grid (destroy on end).
   - **Outro end-screen cards** (last ~20 s, can show other matches' scores): **not mitigated for now.** The developer doesn't want an auto-stop rule (2026-10-11). Raise it again if this causes a complaint (see [In-App Player](In-App%20Player.md)).
   - **Residual (accepted):**
     - The original title shows in the player for ~3 s at start and when the mouse hovers over the player.
     - Hovering also shows a "More videos" thumbnail.
     - Mitigation: choose sources whose titles carry no spoilers (see #7). (With YouTube's controls, the mouse is over the video whenever the user uses them.)
7. **Source titles that spoil.** Because of #6, a spoiler in the *original* title can flash during playback. Clean sources: NBC, CBS, beIN, USA Sports. Problem sources: ESPN FC (teaser prefixes), LALIGA official (scores; also can't be embedded, so ruled out). YouTube's in-player title can't be hidden or replaced legally (verified 2026-10-11). La Liga uses ESPN FC (decided); the browser fallback for skipped matches can expose official titles with scores, so it carries a warning. [DECIDED] Videos from problem sources get a visible "may show spoiler at start" flag.
8. **Normal vs extended versions.** [DECIDED] Prefer extended. [DECIDED] Show one entry per match, so whether an extended cut exists isn't visible as a separate item. [DECIDED] (2026-10-21, supersedes the line before) A per-match extended/normal toggle on matches that have both cuts; revealing which matches have an extended cut is accepted. See [Video Sources](Video%20Sources.md).
9. **Order and timing.** [OPEN] Probably low risk.
10. **League table (future).** Pre-round standings only; results are applied only for matches the user reveals. See [League Table Context](League%20Table%20Context.md).
11. **Notifications / badges.** If added later, they must use neutral wording.

## Reveal

- [DECIDED] (future) Manual reveal exists as the per-match **"show score & update table"** checkbox (see [League Table Context](League%20Table%20Context.md)).
