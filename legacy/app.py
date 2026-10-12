import streamlit as st
from pl_highlights_links import fetch_highlights, load_existing_flags, save_flags

st.set_page_config(page_title="Premier League Highlights", page_icon="⚽", layout="wide")

st.title("⚽ Premier League Highlights")
st.caption("Last 7 days from NBC Sports")

if "flags" not in st.session_state:
    st.session_state.flags = load_existing_flags()
    st.session_state.videos = []

if st.button("🔄 Fetch Latest Highlights"):
    st.session_state.videos = fetch_highlights()
    for v in st.session_state.videos:
        if v["videoId"] not in st.session_state.flags:
            st.session_state.flags[v["videoId"]] = "NOT_WATCHED"
    save_flags(st.session_state.flags)
    st.rerun()

if not st.session_state.videos:
    st.session_state.videos = fetch_highlights()
    for v in st.session_state.videos:
        if v["videoId"] not in st.session_state.flags:
            st.session_state.flags[v["videoId"]] = "NOT_WATCHED"
    save_flags(st.session_state.flags)

col1, col2, col3, col4 = st.columns([1, 4, 1, 2])

with col1:
    st.markdown("**Watched**")
with col2:
    st.markdown("**Title**")
with col3:
    st.markdown("**Link**")
with col4:
    st.markdown("**Uploaded**")

st.markdown("---")

for v in st.session_state.videos:
    vid = v["videoId"]
    dt = v["datetime_obj"]
    timestamp = dt.strftime("%A %-m/%-d, %-I:%M %p")
    timestamp = timestamp[:-2] + timestamp[-2:].lower()

    watched = st.session_state.flags.get(vid, "NOT_WATCHED") == "WATCHED"

    col1, col2, col3, col4 = st.columns([1, 4, 1, 2])

    with col1:
        new_state = st.checkbox(
            "Watched",
            value=watched,
            key=f"cb_{vid}",
            label_visibility="collapsed"
        )
        if new_state != watched:
            st.session_state.flags[vid] = "WATCHED" if new_state else "NOT_WATCHED"
            save_flags(st.session_state.flags)
            st.rerun()

    with col2:
        st.write(v["title"])

    with col3:
        st.link_button("▶ Watch", f"https://www.youtube.com/watch?v={vid}")

    with col4:
        st.caption(timestamp)

st.markdown("---")
st.caption(f"Showing {len(st.session_state.videos)} videos")
