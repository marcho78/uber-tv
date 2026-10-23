"""Scores: today's games for one league, from ESPN's public scoreboard.
Live games first, then the ones still to come, then the finals. Its rows
are team logos (API 3): drawn whole, with space around them. Live (API 4):
while its screen or its Home row is on, games in progress update on their
own."""

from uber_tv import app, get_json, settings, Screen, Row, Item, Detail, AppError

LEAGUES = {
    "NFL": "football/nfl", "NBA": "basketball/nba", "MLB": "baseball/mlb",
    "NHL": "hockey/nhl", "Premier League": "soccer/eng.1", "MLS": "soccer/usa.1",
}


def logo(url):
    """A team's logo at a size for a card: ESPN's own resizer, on the same host
    (the originals are up to 4096 pixels square)"""
    if isinstance(url, str) and url.startswith("https://a.espncdn.com/i/"):
        return "https://a.espncdn.com/combiner/i?img=" + url[len("https://a.espncdn.com"):] + "&h=240&w=240"
    return url


def league():
    name = settings.get("league") or "NFL"
    return name, LEAGUES.get(name, LEAGUES["NFL"])


def scoreboard():
    name, path = league()
    return name, get_json("https://site.api.espn.com/apis/site/v2/sports/" + path + "/scoreboard")


def teams(event):
    comp = event["competitions"][0]
    home = next(t for t in comp["competitors"] if t["homeAway"] == "home")
    away = next(t for t in comp["competitors"] if t["homeAway"] == "away")
    return comp, home, away


def state(event):
    return event["competitions"][0]["status"]["type"]["state"]   # pre, in, post


def item(event):
    comp, home, away = teams(event)
    st = comp["status"]["type"]
    a, h = away["team"]["abbreviation"], home["team"]["abbreviation"]
    if st["state"] == "pre":
        title = a + " at " + h
    else:
        title = a + " " + str(away.get("score", "")) + " · " + h + " " + str(home.get("score", ""))
    badge = {"in": "LIVE", "post": "FINAL"}.get(st["state"], "")
    return Item(event["id"], title, subtitle=st.get("shortDetail", ""), image=logo(home["team"].get("logo")),
                badge=badge, kind="info")


def games():
    name, board = scoreboard()
    events = board.get("events", [])
    groups = {"in": [], "pre": [], "post": []}
    for e in events:
        try:
            groups.setdefault(state(e), []).append(e)
        except (KeyError, IndexError, StopIteration, TypeError):
            continue
    return name, groups


def items(events):
    """A card for each game; one ESPN sent without what a card needs is left
    out, never the rest with it"""
    out = []
    for e in events:
        try:
            out.append(item(e))
        except (KeyError, IndexError, StopIteration, TypeError, AttributeError):
            continue
    return out


ROWS = (("in", "Live now"), ("pre", "Coming up"), ("post", "Final"))


def rows_of(groups):
    """Its three rows, each there even when it's empty (the guide draws only
    the ones with games), so a live update can fill any of them"""
    return [Row(key, title, items(groups.get(key, [])), layout="grid", shape="logo") for key, title in ROWS]


@app.home
def home():
    name, groups = games()
    return Screen(name + " scores", rows=rows_of(groups), empty="No " + name + " games today.",
                  refresh=60 if groups.get("in") else 600, live=True)


@app.live
def live(view):
    """While its screen or its Home row is on the screen: every 15 seconds
    while a game is on (a minute while none is), today's games again,
    replacing its rows (or its Home row's cards)"""
    busy = True
    while view.sleep(15 if busy else 60):
        try:
            _, groups = games()
        except Exception:
            continue   # couldn't be fetched or read: tried again at the next turn
        busy = bool(groups.get("in"))
        if view.method == "homeRow":
            view.update(now_items(groups))
        else:
            view.update(rows_of(groups))


@app.details
def details(event_id):
    name, board = scoreboard()
    event = next((e for e in board.get("events", []) if e.get("id") == event_id), None)
    if not event:
        raise AppError("That game isn't on today's scoreboard any more.")
    comp, home, away = teams(event)
    st = comp["status"]["type"]
    facts = []
    for side in (away, home):
        rec = side.get("records") or []
        record = (" (" + rec[0]["summary"] + ")") if rec else ""
        facts.append((side["team"]["displayName"] + record, str(side.get("score", "")) if st["state"] != "pre" else ""))
    if comp.get("venue", {}).get("fullName"):
        facts.append(("Where", comp["venue"]["fullName"]))
    names = [n for b in comp.get("broadcasts", []) for n in b.get("names", [])]
    if names:
        facts.append(("On", ", ".join(names)))
    notes = [h.get("description") or h.get("shortLinkText") for h in comp.get("headlines", [])]
    text = "\n".join(n for n in notes if n)
    return Detail(event.get("name", "Game"), subtitle=st.get("detail", ""), text=text,
                  image=logo(home["team"].get("logo")), facts=facts)


def now_items(groups):
    now = groups.get("in", []) + groups.get("pre", [])
    return items(now or groups.get("post", []))[:20]


@app.home_row
def home_row(key):
    """Live games, then the ones coming up; with neither, today's finals"""
    name, groups = games()
    return now_items(groups)


app.run()
