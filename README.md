# Footy Highlights

A free, open-source macOS app for catching up on football match highlights **without having the result spoiled**.

It finds official highlight videos that broadcasters post on YouTube and lists them under neutral titles (e.g. *Arsenal v Leeds United · Premier League · Matchweek 7*). It never shows the original video title, thumbnail, description or suggested videos, all of which often give the score away. Videos play inside the app in YouTube's official embedded player, created only when you press play and showing as little of YouTube's interface as YouTube's terms allow.

> **Status:** early release (v0.1). It works day to day, but expect rough edges. The design is documented in [`Plan/`](Plan/Global%20Plan.md).

## Download and install

Requires **macOS 14 (Sonoma) or later**, on Apple Silicon or Intel.

1. Download the latest `FootyHighlights-<version>.dmg` from the [**Releases page**](https://github.com/IlanLadabaum/footy-highlights/releases/latest).
2. Open the DMG and drag **Footy Highlights** onto the **Applications** folder.
3. Open Footy Highlights from Applications. The first time, macOS says it can't check the app for malicious software, because the app isn't signed with a paid Apple developer account. To allow it:
   1. Click **Done** (not "Move to Trash").
   2. Open **System Settings → Privacy & Security**, scroll down to the message about Footy Highlights and click **Open Anyway**.
   3. Confirm with your password or Touch ID, then click **Open Anyway** again.

   You only need to do this once.
4. On first launch the app asks which leagues you follow and for your YouTube API key (see [Setting up your YouTube API key](#setting-up-your-youtube-api-key) below).

### Updates

The app checks for a new version once a day when it opens and asks before installing it. You can also check at any time under **Settings → Advanced → Check for Updates…**. Updates install in place, so you don't need to approve "Open Anyway" again.

### Uninstall

Drag the app from Applications to the Trash. To remove its data too (watched status, cached video lists and your API keys), delete `~/Library/Application Support/io.github.ilanladabaum.footyhighlights`.

### Building from source

You need Xcode 16 or later. Clone the repo, open `FootyHighlights.xcodeproj` and run the **FootyHighlights** scheme, or run `scripts/build-app.sh --install` to build a Release copy into Applications. See [`AGENTS.md`](AGENTS.md) for tests and tooling.

## Competitions

**Premier League**, **UEFA Champions League**, La Liga, Bundesliga, Serie A, Ligue 1 and the Carabao Cup. Choose which ones you follow on first launch (and later under Settings → Leagues). Highlights come from US broadcasters' YouTube channels (NBC Sports, CBS Sports Golazo, beIN SPORTS USA, USA Sports, ESPN FC and, for La Liga gaps, ESPN Deportes in Spanish), so **videos are currently only playable in the US**. Support for other regions is planned.

## Setting up your YouTube API key

The app reads broadcasters' YouTube channels through the **YouTube Data API v3**, so you need your own API key. It's free, and you don't need to add a credit card.

### 1. Create a Google Cloud project

1. Go to the [Google Cloud Console](https://console.cloud.google.com/) and sign in with a Google account.
2. If prompted, accept the terms of service.
3. Click the **project picker** at the top of the page → **New Project**.
4. Name it something like `football-highlights` → **Create**, then make sure it's selected in the project picker.

### 2. Enable the YouTube Data API v3

1. Open the [YouTube Data API v3 page](https://console.cloud.google.com/apis/library/youtube.googleapis.com) (or go to **APIs & Services → Library** and search for "YouTube Data API v3").
2. Click **Enable**.

### 3. Create an API key

1. Go to **APIs & Services → [Credentials](https://console.cloud.google.com/apis/credentials)**.
2. Click **+ Create credentials → API key**.
3. Copy the key that appears (it starts with `AIza…`).

### 4. Restrict the key (recommended)

Restricting the key means that if it leaks, it can't be used for anything else.

1. On the Credentials page, click the new key's name (or **Edit API key**).
2. Under **API restrictions**, choose **Restrict key** and select only **YouTube Data API v3**.
3. Click **Save**.

### 5. Add the key to the app

Open Footy Highlights. On first launch it asks for the key; later you can change it under **Footy Highlights → Settings… → API Keys** (⌘,). Keys are saved on your Mac in a private file that only your user account can read (`~/Library/Application Support/io.github.ilanladabaum.footyhighlights/api-keys.json`).

**Developers** running a Debug build from Xcode can instead put keys in a git-ignored `.env` in the project folder (Debug builds read it before the saved keys):

```bash
cp .env.example .env
```

```
YOUTUBE_API_KEY=AIza...your-key-here...
```

**Don't put the key anywhere else** (source code, screenshots, issues).

### Football data key (optional, recommended)

Footy Highlights uses [football-data.org](https://www.football-data.org) to match each video to its fixture: the round (e.g. "Matchweek 7"), consistent team names and, later, league tables. It's free, and the app still works without it, just with less detail.

1. Register at [football-data.org/client/register](https://www.football-data.org/client/register) (name + email, free tier).
2. Your API token arrives by email. It's also shown on your account page.
3. Paste it into **Settings → API Keys → football-data.org key** (or, for Debug builds, add `FOOTBALL_DATA_API_KEY=your-token-here` to `.env`).

The free tier allows 10 requests per minute, far more than the app needs. Each user needs their own token; tokens aren't shared or bundled with the app.

### YouTube quota

The free tier allows **10,000 quota units per day**. The app reads channel upload lists, which cost 1 unit per 50 videos, so the first refresh of a season takes roughly 100–150 units and later refreshes only a few. You can check usage under **APIs & Services → YouTube Data API v3 → Quotas** in the Cloud Console.

### Troubleshooting

- **`API key not valid`**: re-paste the key in Settings (check for extra spaces or quotes if you use `.env`).
- **`accessNotConfigured` / "API has not been used in project"**: the YouTube Data API v3 isn't enabled for the project the key belongs to (step 2). If you just enabled it, wait a few minutes.
- **`quotaExceeded`**: the daily quota is used up. It resets at midnight Pacific Time.
- **Videos won't play**: the highlight videos are restricted to the US.

## Project documentation

- [`Plan/Global Plan.md`](Plan/Global%20Plan.md): vision, decisions and open questions
- [`AGENTS.md`](AGENTS.md): instructions for AI coding agents working on this repo
- [`legacy/`](legacy/): the archived original implementation (reference only)

## License

[MIT](LICENSE)
