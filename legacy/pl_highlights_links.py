import os
from datetime import datetime, timedelta
from googleapiclient.discovery import build
from competitions import COMPETITIONS, matches_filter

# --- Configuration ---
def _load_env(path=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")):
    """Load KEY=VALUE lines from a local .env file into os.environ (no overwrite)."""
    if os.path.exists(path):
        with open(path, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, value = line.split("=", 1)
                    os.environ.setdefault(key.strip(), value.strip())

_load_env()
API_KEY = os.environ["YOUTUBE_API_KEY"]
OUTPUT_FILE = 'pl_highlights.html'
FLAGS_FILE = 'pl_flags.txt'
MAX_AGE_DAYS = 7

youtube = build('youtube', 'v3', developerKey=API_KEY)

def get_uploads_playlist_id(channel_id):
    response = youtube.channels().list(
        part="contentDetails",
        id=channel_id
    ).execute()
    return response["items"][0]["contentDetails"]["relatedPlaylists"]["uploads"]

def fetch_highlights(competition_name, start_date=None, end_date=None):
    """Fetch videos from a competition's uploads playlist within date range."""
    if competition_name not in COMPETITIONS:
        return []
    
    comp = COMPETITIONS[competition_name]
    uploads_playlist_id = get_uploads_playlist_id(comp["channel_id"])
    
    if end_date is None:
        end_date = datetime.utcnow()
    if start_date is None:
        start_date = end_date - timedelta(days=MAX_AGE_DAYS)
    
    highlights = []
    next_page_token = None
    stop_fetching = False

    while not stop_fetching:
        pl_response = youtube.playlistItems().list(
            part="snippet",
            playlistId=uploads_playlist_id,
            maxResults=50,
            pageToken=next_page_token
        ).execute()

        for item in pl_response.get("items", []):
            title = item["snippet"]["title"]
            dt = datetime.strptime(item["snippet"]["publishedAt"], "%Y-%m-%dT%H:%M:%SZ")

            if dt < start_date:
                stop_fetching = True
                continue

            if dt > end_date:
                continue

            if matches_filter(title, comp):
                highlights.append({
                    "videoId": item["snippet"]["resourceId"]["videoId"],
                    "title": title,
                    "datetime_obj": dt
                })

        next_page_token = pl_response.get("nextPageToken")
        if not next_page_token:
            break

    highlights.sort(key=lambda x: x["datetime_obj"], reverse=True)
    return highlights


def load_existing_flags():
    existing_flags = {}
    if os.path.exists(FLAGS_FILE):
        with open(FLAGS_FILE, "r") as f:
            for line in f:
                parts = line.strip().split(" | ")
                if len(parts) == 2:
                    vid, flag = parts
                    existing_flags[vid] = flag
    return existing_flags

def save_flags(flags):
    with open(FLAGS_FILE, "w") as f:
        for vid, flag in flags.items():
            f.write(f"{vid} | {flag}\n")

def save_html(videos, flags):
    """Generate HTML table with clickable links, watched checkboxes, and formatted timestamps."""
    html_header = """
    <html><head><title>Premier League Highlights</title>
    <style>
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ccc; padding: 8px; text-align: left; }
        th { background: #f4f4f4; }
    </style>
    </head><body>
    <h1>Premier League Highlights (Last 7 Days)</h1>
    <table>
        <tr><th>Watched</th><th>Title</th><th>Link</th><th>Uploaded</th></tr>
    """
    html_footer = "</table></body></html>"

    rows = ""
    for v in videos:
        watched_flag = flags.get(v["videoId"], "NOT_WATCHED")
        checked_attr = "checked" if watched_flag == "WATCHED" else ""
        link = f"https://www.youtube.com/watch?v={v['videoId']}"

        # Format timestamp from datetime_obj
        dt = v["datetime_obj"]
        formatted_dt = dt.strftime("%A %-m/%-d, %-I:%M %p")
        formatted_dt = formatted_dt[:-2] + formatted_dt[-2:].lower()  # lowercase AM/PM

        rows += (
            f'<tr>'
            f'<td><input type="checkbox" {checked_attr}></td>'
            f'<td>{v["title"]}</td>'
            f'<td><a href="{link}" target="_blank">Watch</a></td>'
            f'<td>{formatted_dt}</td>'
            f'</tr>\n'
        )

    with open(OUTPUT_FILE, "w") as f:
        f.write(html_header + rows + html_footer)

def main():
    flags = load_existing_flags()
    videos = fetch_highlights()

    # Ensure all new videos have a flag
    for v in videos:
        if v["videoId"] not in flags:
            flags[v["videoId"]] = "NOT_WATCHED"

    save_html(videos, flags)
    save_flags(flags)
    print(f"Saved {len(videos)} videos to {OUTPUT_FILE}.")

if __name__ == "__main__":
    main()
