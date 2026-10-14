# In-App Player

*Sub-plan of [Global Plan](Global%20Plan.md). Scope: playing YouTube highlight videos inside the app without exposing anything that could spoil a result, while staying within YouTube's terms.*

## Goals and constraints

- [DECIDED] Play videos inside the app, with no original title, annotations/cards, or suggested-video titles or thumbnails, **as far as the rules allow**. *(user, 2026-10-11)*
- [DECIDED] **The app must comply with YouTube's Terms of Service and API policies.** It will be published as open source on GitHub. **Minor residual spoiler risk is acceptable; ToS violations are not.** *(user, 2026-10-11)*

## What the YouTube terms allow (researched 2026-10-11)

Sources: [Developer Policies](https://developers.google.com/youtube/terms/developer-policies) (DP), [Required Minimum Functionality](https://developers.google.com/youtube/terms/required-minimum-functionality) (RMF), [Player parameters](https://developers.google.com/youtube/player_parameters).

| Technique | Verdict | Basis |
|---|---|---|
| Overlaying app UI on the player | **Forbidden** | RMF: no "overlays, frames, or other visual elements in front of any part of a YouTube embedded player" |
| Injecting CSS/JS into the player to hide elements | **Forbidden** | RMF: no changes "not explicitly described by the API documentation"; DP III.I.6 |
| Downloading with yt-dlp and playing natively | **Forbidden** | DP III.E.1.a (no downloading/caching of audiovisual content) |
| Offline downloads for watching later (user request, 2026-10-13) | **Forbidden, declined** | DP III.E.1.a. Only YouTube's own apps (Premium) may download |
| `pointer-events:none` on the iframe (blocks hover reveals) | **Likely forbidden** | DP III.I.6 "block any portion or functionality". Not used. |
| `controls=0` plus our own controls placed *outside* the player | Allowed | Documented parameter |
| Creating the player only after our own Play button, then autoplaying | Allowed | RMF allows autoplay once the player is visible |
| `player.destroy()` when the video ends, or stopping early | Allowed | Documented API calls |
| Destroying the player on pause and recreating it at the same time on resume | Gray area | Built only from documented calls, but its purpose is to hide YouTube's pause UI |
| Our own neutral title instead of the YouTube title in our list | Gray area, defensible | DP III.F.2.a: must make clear YouTube is the source. Mitigate: label it as the app's match info, show channel name + YouTube attribution, offer "show original title" |
| Minimum player size | **Required:** ≥ 200×200 px; recommended ≥ 480×270 | RMF |
| Embedding in WKWebView | Required: send an HTTP Referer. Use `loadHTMLString(_:baseURL:)` with `baseURL = https://<bundle-id>` | RMF "Set the Referer" (added July 2025; otherwise error 152/153) |

- Approaches A (CSS injection), B (overlays) and C (yt-dlp) from the earlier draft are **rejected** as non-compliant. Only the documented-API approach below remains.

## Spike results (2026-10-11)

A throwaway test page lives at `spikes/player/index.html` (run it via `.claude/launch.json` → `player-spike`). It played one NBC (Premier League) and one CBS (Serie A) video in the IFrame API from `localhost`, using only compliant techniques. **Embedding works** for both channels.

What actually appeared:

| Surface | `controls=1` | `controls=0` |
|---|---|---|
| Poster thumbnail before play | Never shown: the player is created only on our Play click and autoplays | same |
| Title bar (original title + channel) | On hover, and for ~3 s at start | **Still shown** for ~3 s at start and whenever the mouse is over the player |
| "More videos" button with a thumbnail (bottom right) | On hover | **Still shown** on hover |
| Seek bar + storyboard previews | On hover | **Gone** |
| Pause with the mouse away from the player | Clean frame (no big "More videos" grid seen) | same |
| **Outro / end-screen elements (last ~20 s)** | Both channels end with a promo outro. **CBS's outro shows "Watch more videos" cards whose titles contained another match's score.** NBC's showed a playlist card | same |
| Related-videos grid after ENDED | Never seen: player destroyed on ENDED | same |

**Embedding check per source (2026-10-11, `controls=0`, muted):** NBC (PL), CBS (UCL), ESPN FC (La Liga, 2 videos), USA Sports (Bundesliga) and beIN (Ligue 1 extended) all **play**. **Official LALIGA channel: error 150**, "This video contains content from LaLiga, who has blocked it from display on this website or application", even though the Data API reports `embeddable: true`. So `status.embeddable` is not reliable; the app must handle player errors 101/150/152/153 gracefully.

**Can YouTube's in-player title be hidden or replaced legally?** No. There's no player parameter for it (`showinfo` was removed in 2018), and overlays or injection are forbidden. The app can only control *its own* list, where the neutral title is shown.

Takeaways:
1. **The outro is the biggest spoiler surface found.** A compliant fix exists (stop before the end), but the developer doesn't want it as a rule. See "Outro handling" below.
2. **The mouse is the main remaining leak.** Hovering over the player shows the original title and a "More videos" thumbnail. That can't be blocked compliantly. Mitigation: all app controls sit *below* the player and keyboard shortcuts are supported, so there's no reason to move the mouse over the video.
3. **The title bar shows for ~3 s at start.** This is unavoidable. Harmless for NBC, CBS and beIN, whose titles have no scores, but a **real leak for ESPN FC**, whose titles start with spoiler phrases. Source choice therefore matters (see [Video Sources](Video%20Sources.md)).

## Playback design

- [DECIDED] SwiftUI view containing a WKWebView that loads a local HTML page with `baseURL = https://<bundle-id>` (Referer requirement). The page uses the IFrame Player API with `enablejsapi=1, controls=1, fs=1, rel=0, iv_load_policy=3, playsinline=1, autoplay=1, origin`.
- [DECIDED] **Use YouTube's own player controls (`controls=1`)** instead of app-drawn ones, so subtitles, quality, speed and YouTube's full screen are available. *(user, 2026-10-12: the title shows most of the time anyway; users can be trusted not to hover the seek bar; losing in-player duration hiding is accepted.)* **Annotations stay off** (`iv_load_policy=3`, documented). Supersedes the earlier `controls=0` / app-drawn-controls decisions.
- [DECIDED] The player is created only when the user presses Play in the app, so no thumbnail ever appears.
- ~~[DECIDED] App-drawn controls below the player~~ — superseded 2026-10-12 by YouTube's controls (above). The app keeps only a bar below the video for its own functions (queue: up next / skip; mark watched).
- [DECIDED] Destroy the player on ENDED and show the app's own "finished" panel (removes the related-videos grid).
- **Outro handling:** [PROPOSED] **not to be implemented.** *(user, 2026-10-11: dislikes "stop 20 s before the end" as a rule.)* The idea: auto-stop when ~20 s remain, so the channel's outro cards (which can contain other matches' scores) never appear. Variants: a per-channel outro length, or a user setting. **Agent note: raise this again if the developer complains about spoilers at the end of videos.**
- [DECIDED] Player at least 480×270.
- [DECIDED] **Pausing is a required feature.** *(user, 2026-10-11)*
- [DECIDED] Implement it as plain `pauseVideo()`/`playVideo()`; the spike showed a clean frame when paused with the mouse away. The gray-area alternative (destroy on pause, recreate on resume) is not used.
- [DECIDED] The Advanced Settings "Hide video durations" toggle (default off) hides durations in the app's lists only. *(user, 2026-10-12: hiding it inside YouTube's player is no longer possible with `controls=1`; loss accepted.)*

## Tech stack

- [DECIDED] **Swift + SwiftUI, one multiplatform app target (macOS first, iPadOS later)**, using WKWebView for the player. *Decision delegated to the agent by the user ("Language is your call, fully"), 2026-10-11.* Rationale:
  - The user mainly targets Mac, with a possible iPad app for the user's brother. SwiftUI shares nearly all code between the two.
  - WKWebView is the web view YouTube's own guidance names for native apps, and setting the Referer is documented for it.
  - It gives native look and feel, small app size and no runtime to bundle.
  - Cross-platform web stacks (Tauri, Electron) only pay off for Windows/Linux, which nobody needs yet.
- [DECIDED] **Tooling: full Xcode.** The developer will update macOS (currently 14.3; Xcode 16+ needs ≥ 14.5) and install Xcode when asked. *(user, 2026-10-11)* Only the Command Line Tools (Swift 5.9.2) are present today.
