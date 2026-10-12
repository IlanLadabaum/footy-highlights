# Footy Highlights

A free, open-source macOS app for catching up on football match highlights **without having the result spoiled**.

It finds official highlight videos that broadcasters post on YouTube and lists them under neutral titles (e.g. *Arsenal v Leeds United · Premier League · Matchweek 7*). It never shows the original video title, thumbnail, description or suggested videos, all of which often give the score away. Videos play inside the app in YouTube's official embedded player, created only when you press play and showing as little of YouTube's interface as YouTube's terms allow.

> **Status:** the app is being rewritten from scratch and is currently in the planning stage. Install and run instructions will be added once it is built. The design is documented in [`Plan/`](Plan/Global%20Plan.md).

## Competitions

Planned priority: **Premier League** and **UEFA Champions League**, then Serie A, Carabao Cup, Ligue 1, Bundesliga and La Liga. Highlights come from US broadcasters' YouTube channels (NBC Sports, CBS Sports Golazo, beIN SPORTS USA, USA Sports, ESPN FC), so **videos are currently only playable in the US**. Support for other regions is planned.

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

In the project folder, copy the template and paste your key in:

```bash
cp .env.example .env
```

```bash
open -e .env
```

Edit the file so it reads:

```
YOUTUBE_API_KEY=AIza...your-key-here...
```

`.env` is git-ignored, so the key stays on your machine and is never committed. **Don't put the key anywhere else** (source code, screenshots, issues).

### Football data key (optional, recommended)

Footy Highlights uses [football-data.org](https://www.football-data.org) to match each video to its fixture: the round (e.g. "Matchweek 7"), consistent team names and, later, league tables. It's free, and the app still works without it, just with less detail.

1. Register at [football-data.org/client/register](https://www.football-data.org/client/register) (name + email, free tier).
2. Your API token arrives by email. It's also shown on your account page.
3. Add it to `.env`:

```
FOOTBALL_DATA_API_KEY=your-token-here
```

The free tier allows 10 requests per minute, far more than the app needs. Each user needs their own token; tokens aren't shared or bundled with the app.

### YouTube quota

The free tier allows **10,000 quota units per day**. The app reads channel upload lists, which cost 1 unit per 50 videos, so normal use takes only a few dozen units a day. You can check usage under **APIs & Services → YouTube Data API v3 → Quotas** in the Cloud Console.

### Troubleshooting

- **`API key not valid`**: check for extra spaces or quotes around the key in `.env`.
- **`accessNotConfigured` / "API has not been used in project"**: the YouTube Data API v3 isn't enabled for the project the key belongs to (step 2). If you just enabled it, wait a few minutes.
- **`quotaExceeded`**: the daily quota is used up. It resets at midnight Pacific Time.
- **Videos won't play**: the highlight videos are restricted to the US.

## Project documentation

- [`Plan/Global Plan.md`](Plan/Global%20Plan.md): vision, decisions and open questions
- [`AGENTS.md`](AGENTS.md): instructions for AI coding agents working on this repo
- [`legacy/`](legacy/): the archived original implementation (reference only)

## License

[MIT](LICENSE)
