from flask import Flask, render_template, request, redirect, jsonify
from datetime import datetime, timedelta
from pl_highlights_links import fetch_highlights, load_existing_flags, save_flags
from competitions import COMPETITIONS, parse_title

app = Flask(__name__)

def format_videos(videos, flags, competition_name=None):
    comp = COMPETITIONS.get(competition_name, {})
    video_list = []
    for v in videos:
        vid = v["videoId"]
        dt = v["datetime_obj"]
        timestamp = dt.strftime("%A %-m/%-d, %-I:%M %p")
        timestamp = timestamp[:-2] + timestamp[-2:].lower()
        raw_title = v["title"]
        clean_title = parse_title(raw_title, comp)
        video_list.append({
            "videoId": vid,
            "title": clean_title,
            "rawTitle": raw_title,
            "timestamp": timestamp,
            "watched": flags.get(vid, "NOT_WATCHED") == "WATCHED"
        })
    return video_list

@app.route("/")
def index():
    competition = request.args.get("competition", "Premier League")
    show_all = request.args.get("show_all", "1") == "1"
    
    if competition not in COMPETITIONS:
        competition = "Premier League"
    
    # Find competitions with recent videos
    competitions_with_recent = []
    for comp_name in COMPETITIONS:
        try:
            videos = fetch_highlights(comp_name)
            if videos:
                competitions_with_recent.append(comp_name)
        except Exception:
            pass
    
    videos = fetch_highlights(competition)
    flags = load_existing_flags()
    for v in videos:
        if v["videoId"] not in flags:
            flags[v["videoId"]] = "NOT_WATCHED"
    save_flags(flags)
    
    return render_template("index.html", 
                         videos=format_videos(videos, flags, competition),
                         competitions=list(COMPETITIONS.keys()),
                         competitions_with_recent=competitions_with_recent if show_all else competitions_with_recent,
                         show_all=show_all,
                         current_competition=competition)

@app.route("/load_more")
def load_more():
    weeks_back = int(request.args.get("weeks", 1))
    competition = request.args.get("competition", "Premier League")
    end_date = datetime.utcnow() - timedelta(days=weeks_back * 7)
    start_date = end_date - timedelta(days=7)
    
    videos = fetch_highlights(competition, start_date, end_date)
    flags = load_existing_flags()
    for v in videos:
        if v["videoId"] not in flags:
            flags[v["videoId"]] = "NOT_WATCHED"
    save_flags(flags)
    
    return jsonify(format_videos(videos, flags, competition))

@app.route("/toggle", methods=["POST"])
def toggle():
    data = request.get_json()
    vid = data.get("videoId")
    watched = data.get("watched")
    
    if vid:
        flags = load_existing_flags()
        flags[vid] = "WATCHED" if watched else "NOT_WATCHED"
        save_flags(flags)
        return jsonify({"success": True})
    
    return jsonify({"success": False}), 400

@app.route("/refresh", methods=["POST"])
def refresh():
    return redirect("/")

if __name__ == "__main__":
    import webbrowser
    import threading
    
    def open_browser():
        webbrowser.open("http://127.0.0.1:5001")
    
    threading.Timer(1.5, open_browser).start()
    app.run(host="127.0.0.1", port=5001, debug=False)
