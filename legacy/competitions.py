"""
Competition configurations.
Each competition needs:
- channel_id: YouTube channel ID that uploads their highlights
- include: phrases that MUST be in the title
- exclude: phrases that must NOT be in the title
"""

COMPETITIONS = {
    "Premier League": {
        "channel_id": "UCqZQlzSHbVJrwrn5XvzrzcA",
        "include": ["PREMIER LEAGUE", "HIGHLIGHTS"],
        "exclude": ["Top ", "Netbusters", "Matchweek", "Best Goals", "Week in", "Recap", "Goals of"],
    },
    "Serie A": {
        "channel_id": "UCET00YnetHT7tOpu12v8jxg",
        "include": ["EXTENDED HIGHLIGHTS", "SERIE A"],
        "exclude": ["Top ", "Best Goals", "Best Saves", "Baller League"],
    },
    "Champions League": {
        "channel_id": "UCET00YnetHT7tOpu12v8jxg",
        "include": ["EXTENDED HIGHLIGHTS", "UCL"],
        "exclude": ["Top ", "Best Goals", "Best Saves", "Baller League"],
    },
    "Carabao Cup": {
        "channel_id": "UCET00YnetHT7tOpu12v8jxg",
        "include": ["EXTENDED HIGHLIGHTS", "CARABAO CUP"],
        "exclude": ["Top ", "Best Goals", "Best Saves", "Baller League"],
    },
    "La Liga": {
        "channel_id": "UC6c1z7bA__85CIWZ_jpCK-Q",
        "include": ["LALIGA Highlights"],
        "exclude": [],
    },
    "Bundesliga": {
        "channel_id": "UC6c1z7bA__85CIWZ_jpCK-Q",
        "include": ["Bundesliga Highlights"],
        "exclude": [],
    },
    "Ligue 1": {
        "channel_id": "UC0YatYmg5JRYzXJPxIdRd8g",
        "include": ["HIGHLIGHTS Ligue 1"],
        "exclude": [],
    },
}

DEFAULT_EXCLUDE = ["Top ", "Best Goals", "Recap", "Week in", "Goals of"]

def matches_filter(title: str, competition: dict) -> bool:
    """Check if title matches competition filter criteria."""
    title_upper = title.upper()
    
    for phrase in competition.get("include", []):
        if phrase.upper() not in title_upper:
            return False
    
    for phrase in competition.get("exclude", []) + DEFAULT_EXCLUDE:
        if phrase.upper() in title_upper:
            return False
    
    return True

def parse_title(title: str, competition: dict) -> str:
    """Parse/clean title for display."""
    return title
