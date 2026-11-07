#!/usr/bin/python3
"""News — the bottom bar's news pill + panel (NewsPopup.qml). RSS/Atom feeds
(Google News, BBC, ESPNcricinfo, ANN, arXiv, lab blogs …), no API keys.

    news.py status          waybar-style JSON for the pill (newspaper glyph,
                            tooltip = the newest headlines of the current
                            category); refreshes that category when stale
    news.py json [CAT]      everything for the panel: categories, CAT's
                            sub-categories (+ which are on) and its items,
                            straight from the cache (stale = true → run refresh)
    news.py refresh [CAT]   fetch CAT's feeds now (default: the current one)
    news.py set CAT [OFF]   CAT becomes the current category; OFF = the
                            comma-separated sub-categories hidden in it
                            ("" = all shown, the default)
    news.py seen            the panel was opened: the pill stops glowing
    news.py paywall [CAT]   check the articles of sites that mark paywalls per
                            article (Indian Express, Mint, New Scientist,
                            Nature) — read their isAccessibleForFree flag
    news.py add CAT         show CAT in the panel's category list (the "More"
                            tab's catalogue: CATS + EXTRA)
    news.py remove CAT      hide it again (never the last one)

Each headline carries "acc": free | paid | limited (metered: a few free
articles a month / a free sign-up, then a subscription) and "accWhy" — from
the article itself when it says so (STAT+, LWN [$], ET Prime, the page check
above, cached in ~/.cache/news/access.json), else the site (ACCESS_* below),
else free (no paywall known).

Categories / sub-categories are CATS (shown by default) and EXTRA (the "More"
tab: added on request) below — add feeds there. A sub-category is one or more
feeds; ANN's single feed is split by its <category> tags.

Cache: ~/.cache/news/<cat>.json (per feed; a feed that fails keeps its last
items). Prefs: ~/.local/state/news/prefs.json ("shown" = the category list,
in order; missing = CATS).
"""

import concurrent.futures as cf
import datetime as dt
import email.utils
import gzip
import html
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

HYPR = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "news")
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "news")
PREFS = os.path.join(STATE_DIR, "prefs.json")
UA = "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
TTL = 20 * 60                 # news feeds
SLOW_TTL = 3 * 3600           # arXiv / blogs: daily-ish
PER_FEED = 30                 # items kept per feed
MAX_ITEMS = 250               # per category, newest first


def gn(path="", q=None, ed="IN"):
    """A Google News RSS URL (India edition unless ed='US')."""
    loc = {"IN": "hl=en-IN&gl=IN&ceid=IN:en", "US": "hl=en-US&gl=US&ceid=US:en"}[ed]
    if q is not None:
        return "https://news.google.com/rss/search?q=" + urllib.request.quote(q + " when:3d") + "&" + loc
    return "https://news.google.com/rss" + path + "?" + loc


def gn_topic(t, ed="IN"):
    return gn("/headlines/section/topic/" + t, ed=ed)


def bbc(path):
    return "https://feeds.bbci.co.uk/" + path + "/rss.xml"


def arxiv(c):
    return "https://rss.arxiv.org/rss/" + c


ANN = "https://www.animenewsnetwork.com/all/rss.xml?ann-edition=w"


def weather_place():
    try:
        with open(os.path.join(HYPR, "weather-location")) as f:
            return json.load(f)["name"].split(",")[0].strip()
    except Exception:
        return ""


PLACE = weather_place() or "Chennai"

# id, label, glyph (Material Design nerd-font), sub-categories:
#   (id, label, [feed, …]); a feed is a URL or (URL, {"ann": [categories]})
CATS = [
    ("indian", "Indian", "\U000F0240", [
        ("top", "Top stories", [gn()]),
        ("nation", "Nation", [gn_topic("NATION"), "https://www.thehindu.com/news/national/feeder/default.rss"]),
        ("local", PLACE, [gn("/headlines/section/geo/" + urllib.request.quote(PLACE))]),
        ("business", "Business", [gn_topic("BUSINESS")]),
        ("tech", "Tech", [gn_topic("TECHNOLOGY")]),
        ("science", "Science", [gn_topic("SCIENCE")]),
        ("health", "Health", [gn_topic("HEALTH")]),
        ("entertainment", "Entertainment", [gn_topic("ENTERTAINMENT")]),
    ]),
    ("world", "International", "\U000F01E7", [
        ("top", "Top stories", [gn_topic("WORLD", "US"), bbc("news/world")]),
        ("asia", "Asia", [bbc("news/world/asia")]),
        ("europe", "Europe", [bbc("news/world/europe")]),
        ("americas", "Americas", [bbc("news/world/us_and_canada"), bbc("news/world/latin_america")]),
        ("mideast", "Middle East", [bbc("news/world/middle_east")]),
        ("africa", "Africa", [bbc("news/world/africa")]),
        ("business", "Business", [bbc("news/business")]),
        ("tech", "Tech", [bbc("news/technology")]),
        ("science", "Science", [bbc("news/science_and_environment")]),
    ]),
    ("sports", "Sports", "\U000F0538", [
        ("cricket", "Cricket", ["https://www.espncricinfo.com/rss/content/story/feeds/0.xml"]),
        ("football", "Football", [bbc("sport/football")]),
        ("f1", "Formula 1", [bbc("sport/formula1")]),
        ("tennis", "Tennis", [bbc("sport/tennis")]),
        ("chess", "Chess", ["https://www.chess.com/rss/news"]),
        ("badminton", "Badminton", [gn(q="badminton")]),
        ("nba", "Basketball", [gn(q="NBA", ed="US")]),
        ("india", "Indian sports", [gn_topic("SPORTS")]),
    ]),
    ("anime", "Anime", "\U0000EEE6", [
        ("anime", "Anime", [(ANN, {"ann": ["Anime", "Animation"]})]),
        ("manga", "Manga & novels", [(ANN, {"ann": ["Manga", "Novels", "Manhua", "Comics", "Korean"]})]),
        ("games", "Games", [(ANN, {"ann": ["Games"]})]),
        ("live", "Live-action", [(ANN, {"ann": ["Live-Action"]})]),
        ("industry", "Industry & events", [(ANN, {"ann": ["Industry", "People", "Events", "Merch", "Just for Fun"]})]),
        ("crunchyroll", "Crunchyroll", ["https://cr-news-api-service.prd.crunchyrollsvc.com/v1/en-US/rss"]),
        ("mal", "MyAnimeList", ["https://myanimelist.net/rss/news.xml"]),
    ]),
    ("ai", "AI research", "\U000F09D1", [
        ("papers", "Trending papers", ["hf-papers"]),
        ("labs", "Lab blogs", ["https://openai.com/news/rss.xml", "https://deepmind.google/blog/rss.xml",
                               "https://research.google/blog/rss/", "https://bair.berkeley.edu/blog/feed.xml",
                               "https://www.microsoft.com/en-us/research/feed/", "https://huggingface.co/blog/feed.xml"]),
        ("news", "AI news", ["https://news.mit.edu/rss/topic/artificial-intelligence2",
                             "https://www.technologyreview.com/topic/artificial-intelligence/feed",
                             "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml",
                             "https://arstechnica.com/ai/feed/",
                             "https://techcrunch.com/category/artificial-intelligence/feed/"]),
        ("cs.AI", "arXiv · AI", [arxiv("cs.AI")]),
        ("cs.LG", "arXiv · ML", [arxiv("cs.LG")]),
        ("cs.CL", "arXiv · NLP", [arxiv("cs.CL")]),
        ("cs.CV", "arXiv · Vision", [arxiv("cs.CV")]),
        ("cs.RO", "arXiv · Robotics", [arxiv("cs.RO")]),
    ]),
]

# The "More" tab: categories the panel offers to add (prefs "shown"). Same
# shape as CATS.
HINDU = "https://www.thehindu.com/{}/feeder/default.rss"
EXTRA = [
    ("tech", "Tech & gadgets", "\U000F0121", [
        ("top", "Top stories", ["https://www.theverge.com/rss/index.xml", "https://feeds.arstechnica.com/arstechnica/index"]),
        ("phones", "Phones & gadgets", ["https://www.gsmarena.com/rss-news-reviews.php3", "https://www.engadget.com/rss.xml"]),
        ("india", "Indian tech", ["https://feeds.feedburner.com/gadgets360-latest"]),
        ("startups", "Startups", ["https://techcrunch.com/feed/", "https://inc42.com/feed/"]),
        ("wired", "WIRED", ["https://www.wired.com/feed/rss"]),
    ]),
    ("dev", "Programming", "\U000F0169", [
        ("hn", "Hacker News", ["https://hnrss.org/frontpage"]),
        ("best", "HN best", ["https://hnrss.org/best"]),
        ("lobsters", "Lobsters", ["https://lobste.rs/rss"]),
        ("devto", "DEV", ["https://dev.to/feed"]),
        ("github", "GitHub", ["https://github.blog/feed/"]),
        ("langs", "Python · Rust · Go", ["https://blog.python.org/feeds/posts/default?alt=rss",
                                          "https://blog.rust-lang.org/feed.xml", "https://go.dev/blog/feed.atom"]),
    ]),
    ("linux", "Linux & open source", "\U000F033D", [
        ("phoronix", "Phoronix", ["https://www.phoronix.com/rss.php"]),
        ("lwn", "LWN", ["https://lwn.net/headlines/rss"]),
        ("distros", "Distros", ["https://9to5linux.com/feed", "https://www.omgubuntu.co.uk/feed",
                                "https://archlinux.org/feeds/news/"]),
        ("itsfoss", "It's FOSS", ["https://itsfoss.com/rss/"]),
        ("releases", "Kernel & Hyprland", ["https://www.kernel.org/feeds/kdist.xml",
                                           "https://github.com/hyprwm/Hyprland/releases.atom"]),
    ]),
    ("science", "Science", "\U000F0093", [
        ("quanta", "Quanta", ["https://www.quantamagazine.org/feed/", "https://www.quantamagazine.org/mathematics/feed/",
                              "https://www.quantamagazine.org/computer-science/feed/"]),
        ("physics", "Physics", ["https://phys.org/rss-feed/physics-news/"]),
        ("biology", "Biology", ["https://phys.org/rss-feed/biology-news/"]),
        ("journals", "Nature & Science", ["https://www.nature.com/nature.rss", "https://www.science.org/rss/news_current.xml"]),
        ("newsci", "New Scientist", ["https://www.newscientist.com/feed/home/"]),
        ("daily", "ScienceDaily", ["https://www.sciencedaily.com/rss/all.xml"]),
        ("india", "Indian science", [HINDU.format("sci-tech/science")]),
    ]),
    ("space", "Space", "\U000F14DE", [
        ("nasa", "NASA", ["https://www.nasa.gov/news-release/feed/"]),
        ("isro", "ISRO", [gn(q="ISRO")]),
        ("launches", "Launches", ["https://spaceflightnow.com/feed/"]),
        ("astro", "Astronomy", ["https://www.universetoday.com/feed/", "https://www.space.com/feeds/all"]),
        ("industry", "Space industry", ["https://spacenews.com/feed/"]),
    ]),
    ("games", "Gaming", "\U000F0297", [
        ("top", "Top stories", ["https://www.polygon.com/rss/index.xml", "https://feeds.ign.com/ign/all"]),
        ("pc", "PC", ["https://www.pcgamer.com/rss/", "https://www.rockpapershotgun.com/feed"]),
        ("nintendo", "Nintendo", ["https://www.nintendolife.com/feeds/latest"]),
        ("playstation", "PlayStation", ["https://www.pushsquare.com/feeds/latest"]),
        ("xbox", "Xbox", ["https://www.purexbox.com/feeds/latest"]),
        ("eurogamer", "Eurogamer", ["https://www.eurogamer.net/feed"]),
    ]),
    ("movies", "Movies & TV", "\U000F0FCE", [
        ("hollywood", "Hollywood", ["https://variety.com/feed/", "https://www.hollywoodreporter.com/feed/"]),
        ("industry", "Box office & deals", ["https://deadline.com/feed/"]),
        ("indian", "Indian cinema", [HINDU.format("entertainment/movies")]),
        ("indie", "IndieWire", ["https://www.indiewire.com/feed/"]),
        ("streaming", "Streaming", ["https://www.whats-on-netflix.com/feed/"]),
    ]),
    ("business", "Business & markets", "\U000F012A", [
        ("markets", "Indian markets", ["https://www.livemint.com/rss/markets",
                                       "https://economictimes.indiatimes.com/markets/rssfeeds/1977021501.cms"]),
        ("economy", "Economy", [HINDU.format("business/Economy")]),
        ("startups", "Startups", ["https://inc42.com/feed/", "https://yourstory.com/feed"]),
        ("global", "Global", ["https://www.cnbc.com/id/100003114/device/rss/rss.html", bbc("news/business")]),
        ("crypto", "Crypto", ["https://www.coindesk.com/arc/outboundfeeds/rss/"]),
    ]),
    ("security", "Cybersecurity", "\U000F099D", [
        ("news", "Security news", ["https://www.bleepingcomputer.com/feed/", "https://feeds.feedburner.com/TheHackersNews"]),
        ("ars", "Ars security", ["https://arstechnica.com/security/feed/"]),
        ("krebs", "Krebs", ["https://krebsonsecurity.com/feed/"]),
        ("schneier", "Schneier", ["https://www.schneier.com/feed/atom/"]),
        ("cisa", "CISA advisories", ["https://www.cisa.gov/cybersecurity-advisories/all.xml"]),
    ]),
    ("tn", "Tamil Nadu", "\U000F0146", [
        ("chennai", "Chennai", [HINDU.format("news/cities/chennai")]),
        ("state", "Tamil Nadu", [HINDU.format("news/national/tamil-nadu")]),
        ("iitm", "IIT Madras", [gn(q='"IIT Madras"')]),
    ]),
    ("education", "Education", "\U000F0474", [
        ("india", "Indian education", [HINDU.format("education"), "https://indianexpress.com/section/education/feed/"]),
        ("exams", "JEE · GATE · NEET", [gn(q="JEE OR GATE OR NEET exam")]),
        ("iitm", "IIT Madras", [gn(q='"IIT Madras"')]),
    ]),
    ("health", "Health", "\U000F05F6", [
        ("news", "Health news", [bbc("news/health")]),
        ("medicine", "Medicine", ["https://www.statnews.com/feed/"]),
        ("research", "Research", ["https://www.sciencedaily.com/rss/health_medicine.xml"]),
        ("wellness", "Wellness", ["https://rss.nytimes.com/services/xml/rss/nyt/Well.xml"]),
    ]),
    ("climate", "Climate & environment", "\U000F032A", [
        ("climate", "Climate", ["https://www.carbonbrief.org/feed/"]),
        ("world", "World", ["https://www.theguardian.com/environment/rss"]),
        ("india", "India", ["https://india.mongabay.com/feed/", HINDU.format("sci-tech/energy-and-environment")]),
    ]),
    ("music", "Music", "\U000F075A", [
        ("news", "Music news", ["https://www.rollingstone.com/music/music-news/feed/", "https://www.nme.com/news/music/feed"]),
        ("pitchfork", "Pitchfork", ["https://pitchfork.com/feed/feed-news/rss"]),
        ("kpop", "K-pop", ["https://www.soompi.com/feed"]),
    ]),
    ("ev", "Cars & EVs", "\U000F0B6C", [
        ("electrek", "Electrek", ["https://electrek.co/feed/"]),
        ("insideevs", "InsideEVs", ["https://insideevs.com/rss/news/all/"]),
    ]),
    ("reads", "Long reads & opinion", "\U000F05DA", [
        ("aeon", "Aeon", ["https://aeon.co/feed.rss"]),
        ("atlantic", "The Atlantic", ["https://www.theatlantic.com/feed/all/"]),
        ("longread", "Guardian long read", ["https://www.theguardian.com/news/series/the-long-read/rss"]),
        ("opinion", "Indian opinion", [HINDU.format("opinion"), "https://indianexpress.com/section/opinion/feed/"]),
    ]),
]
CAT_IDS = [c[0] for c in CATS]              # shown until the user changes the list
ALL = CATS + EXTRA
ALL_IDS = [c[0] for c in ALL]
DEFAULT_CAT = "indian"


def cat_def(cid):
    for c in ALL:
        if c[0] == cid:
            return c
    return CATS[0]


def shown_of(prefs):
    return [c for c in prefs.get("shown", CAT_IDS) if c in ALL_IDS] or list(CAT_IDS)


# ── prefs ───────────────────────────────────────────────────────────────────
def load_prefs():
    try:
        with open(PREFS) as f:
            p = json.load(f)
    except Exception:
        p = {}
    p["shown"] = shown_of(p)
    p.setdefault("cat", DEFAULT_CAT)
    if p["cat"] not in p["shown"]:
        p["cat"] = p["shown"][0]
    p.setdefault("off", {})
    p.setdefault("seen", 0)
    return p


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


# ── fetching / parsing ──────────────────────────────────────────────────────
def get(url, timeout=20):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
        if r.headers.get("Content-Encoding") == "gzip" or data[:2] == b"\x1f\x8b":
            data = gzip.decompress(data)
        return data


def fetch_feed(url):
    # one retry: big feeds (OpenAI's is ~800 KB) now and then time out or
    # arrive cut short
    try:
        return fetch_once(url)
    except Exception:
        time.sleep(1)
        return fetch_once(url)


TAG_RE = re.compile(r"<[^>]+>")


def clean(s):
    s = html.unescape(TAG_RE.sub(" ", s or ""))
    return re.sub(r"\s+", " ", s).strip()


def parse_date(s):
    if not s:
        return 0
    s = s.strip()
    try:
        return email.utils.parsedate_to_datetime(s).timestamp()
    except Exception:
        pass
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return 0


def local(tag):
    return tag.rsplit("}", 1)[-1]


def child(el, *names):
    for c in el:
        if local(c.tag) in names:
            return c
    return None


def text_of(el, *names):
    c = child(el, *names)
    return (c.text or "") if c is not None else ""


def parse_feed(raw, feed_url):
    root = ET.fromstring(raw)
    chan = child(root, "channel")
    chan_date = parse_date(text_of(chan, "pubDate", "lastBuildDate", "date")) if chan is not None else 0
    feed_title = clean(text_of(chan if chan is not None else root, "title"))
    entries = [e for e in root.iter() if local(e.tag) in ("item", "entry")]
    out = []
    for e in entries:
        title = clean(text_of(e, "title"))
        if not title:
            continue
        link = text_of(e, "link").strip()
        if not link:                                           # Atom
            for c in e:
                if local(c.tag) == "link" and c.get("rel", "alternate") == "alternate":
                    link = c.get("href", "")
                    break
        ts = parse_date(text_of(e, "pubDate", "published", "updated", "date")) or chan_date
        cats = [clean(c.text) for c in e if local(c.tag) == "category" and c.text]
        # arXiv: skip replacements / cross-lists of old papers
        ann_type = text_of(e, "announce_type").strip()
        if ann_type and ann_type not in ("new",):
            continue
        src = clean(text_of(e, "source"))
        if re.search(r"://|[?=/]|^doi:", src):              # Space.com / PC Gamer / Nature put junk there
            src = ""
        if "news.google.com" in feed_url and " - " in title:
            t, _, s = title.rpartition(" - ")
            title, src = t.strip(), src or s.strip()
            # "… - GSMArena.com news" left over when the outlet repeats itself
            if " - " in title and title.rpartition(" - ")[2].lower().startswith(src.lower()[:6]):
                title = title.rpartition(" - ")[0].strip()
        if not src:
            src = short_source(feed_title, feed_url)
        out.append({"t": title, "link": link, "ts": ts, "src": src, "cats": cats})
    return out


SOURCES = [("bbc.co", "BBC"), ("espncricinfo", "ESPNcricinfo"), ("animenewsnetwork", "ANN"),
           ("crunchyroll", "Crunchyroll"), ("myanimelist", "MyAnimeList"), ("arxiv", "arXiv"),
           ("openai.com", "OpenAI"), ("deepmind", "Google DeepMind"), ("research.google", "Google Research"),
           ("bair.berkeley", "BAIR"), ("microsoft.com", "Microsoft Research"), ("huggingface.co/blog", "Hugging Face"),
           ("news.mit.edu", "MIT News"), ("technologyreview", "MIT Tech Review"), ("theverge", "The Verge"),
           ("arstechnica", "Ars Technica"), ("techcrunch", "TechCrunch"), ("thehindu", "The Hindu"), ("chess.com", "Chess.com"),
           ("gsmarena", "GSMArena"), ("engadget", "Engadget"), ("gadgets360", "Gadgets 360"), ("wired.com", "WIRED"),
           ("inc42", "Inc42"), ("hnrss", "Hacker News"), ("lobste.rs", "Lobsters"), ("dev.to", "DEV"),
           ("github.blog", "GitHub"), ("python.org", "Python"), ("rust-lang", "Rust"), ("go.dev", "Go"),
           ("phoronix", "Phoronix"), ("lwn.net", "LWN"), ("9to5linux", "9to5Linux"), ("omgubuntu", "OMG! Ubuntu"),
           ("archlinux", "Arch Linux"), ("itsfoss", "It's FOSS"), ("kernel.org", "kernel.org"), ("hyprwm", "Hyprland"),
           ("quantamagazine", "Quanta"), ("phys.org", "Phys.org"), ("nature.com", "Nature"), ("science.org", "Science"),
           ("newscientist", "New Scientist"), ("sciencedaily", "ScienceDaily"), ("nasa.gov", "NASA"),
           ("spaceflightnow", "Spaceflight Now"), ("universetoday", "Universe Today"), ("space.com", "Space.com"),
           ("spacenews", "SpaceNews"), ("polygon.com", "Polygon"), ("ign.com", "IGN"), ("pcgamer", "PC Gamer"),
           ("rockpapershotgun", "Rock Paper Shotgun"), ("nintendolife", "Nintendo Life"), ("pushsquare", "Push Square"),
           ("purexbox", "Pure Xbox"), ("eurogamer", "Eurogamer"), ("variety.com", "Variety"),
           ("hollywoodreporter", "Hollywood Reporter"), ("deadline.com", "Deadline"), ("indiewire", "IndieWire"),
           ("whats-on-netflix", "What's on Netflix"), ("livemint", "Mint"), ("economictimes", "Economic Times"),
           ("yourstory", "YourStory"), ("cnbc.com", "CNBC"), ("coindesk", "CoinDesk"),
           ("bleepingcomputer", "BleepingComputer"), ("TheHackersNews", "The Hacker News"), ("krebsonsecurity", "Krebs"),
           ("schneier", "Schneier"), ("cisa.gov", "CISA"), ("indianexpress", "Indian Express"), ("statnews", "STAT"),
           ("nytimes", "NYT"), ("carbonbrief", "Carbon Brief"), ("theguardian", "The Guardian"),
           ("mongabay", "Mongabay India"), ("rollingstone", "Rolling Stone"), ("nme.com", "NME"),
           ("pitchfork", "Pitchfork"), ("soompi", "Soompi"), ("electrek", "Electrek"), ("insideevs", "InsideEVs"),
           ("aeon.co", "Aeon"), ("theatlantic", "The Atlantic")]


def short_source(title, url):
    for k, v in SOURCES:
        if k in url:
            return v
    return title[:30] or "?"


def hf_papers():
    data = json.loads(get("https://huggingface.co/api/daily_papers?limit=40"))
    out = []
    for d in data:
        p = d.get("paper", {})
        pid = p.get("id")
        if not pid:
            continue
        out.append({"t": clean(p.get("title") or d.get("title")), "link": "https://huggingface.co/papers/" + pid,
                    "ts": parse_date(d.get("submittedOnDailyAt") or d.get("publishedAt") or p.get("publishedAt")),
                    "src": "HF · ▲" + str(p.get("upvotes", 0)), "cats": [], "up": p.get("upvotes", 0)})
    out.sort(key=lambda x: -x.get("up", 0))
    return out


def fetch_once(url):
    if url == "hf-papers":
        return hf_papers()
    return parse_feed(get(url), url)


def feeds_of(cat):
    """[(feed key, url)] for a category, each URL once."""
    seen = []
    for _sid, _label, feeds in cat[3]:
        for f in feeds:
            u = f[0] if isinstance(f, tuple) else f
            if u not in seen:
                seen.append(u)
    return seen


def ttl_of(url):
    return SLOW_TTL if ("arxiv" in url or url == "hf-papers" or "/blog" in url or "research" in url) else TTL


def cache_path(cid):
    return os.path.join(CACHE_DIR, cid + ".json")


def load_cache(cid):
    try:
        with open(cache_path(cid)) as f:
            return json.load(f)
    except Exception:
        return {"feeds": {}}


def is_stale(cat, cache, now=None):
    now = now or time.time()
    feeds = cache.get("feeds", {})
    for u in feeds_of(cat):
        f = feeds.get(u)
        if not f or now - f.get("at", 0) > ttl_of(u):
            return True
    return False


def refresh(cid, force=True):
    cat = cat_def(cid)
    cache = load_cache(cat[0])
    feeds = cache.setdefault("feeds", {})
    now = time.time()
    todo = [u for u in feeds_of(cat) if force or now - feeds.get(u, {}).get("at", 0) > ttl_of(u)]
    if not todo:
        return cache
    with cf.ThreadPoolExecutor(12) as ex:
        futs = {ex.submit(fetch_feed, u): u for u in todo}
        for fut in cf.as_completed(futs):
            u = futs[fut]
            try:
                items = fut.result()
                feeds[u] = {"at": now, "ok": True, "items": items}
            except Exception as e:
                old = feeds.get(u, {})
                # keep the last items; retry after 5 min instead of the full TTL
                feeds[u] = {"at": now - ttl_of(u) + 300, "ok": False, "why": str(e)[:120],
                            "items": old.get("items", [])}
    cache["at"] = now
    save_json(cache_path(cat[0]), cache)
    return cache


# ── free or paid ────────────────────────────────────────────────────────────
# by site: a Google News item's link is a news.google.com redirect, so its
# outlet NAME is matched; direct links match by domain
ACCESS_PAID = {
    "names": {"wsj", "the wall street journal", "bloomberg", "bloomberg.com", "financial times", "ft",
              "the economist", "economist", "the information", "barron's", "haaretz", "the ken",
              "the times", "the telegraph", "the morning context", "the athletic"},
    "domains": ("wsj.com", "bloomberg.com", "ft.com", "economist.com", "theinformation.com", "barrons.com",
                "haaretz.com", "the-ken.com", "thetimes.co.uk", "telegraph.co.uk", "themorningcontext.com",
                "theathletic.com"),
}
ACCESS_LIMITED = {
    "names": {"the hindu", "businessline", "the hindu businessline", "frontline", "nyt", "the new york times",
              "new york times", "the atlantic", "wired", "new scientist", "mit tech review",
              "mit technology review", "the washington post", "washington post", "business standard",
              "forbes", "fortune", "business insider", "the new yorker", "scientific american", "medscape",
              "nature", "los angeles times", "the boston globe", "medium"},
    "domains": ("thehindu.com", "thehindubusinessline.com", "nytimes.com", "theatlantic.com", "wired.com",
                "newscientist.com", "technologyreview.com", "washingtonpost.com", "business-standard.com",
                "forbes.com", "fortune.com", "businessinsider.com", "newyorker.com", "scientificamerican.com",
                "medscape.com", "nature.com", "latimes.com", "bostonglobe.com", "medium.com"),
}
ACCESS_FREE_FIRST = ("sportstar.thehindu.com",)        # free corners of the sites above
# sites whose pages say per article (schema.org isAccessibleForFree) and
# mean it — The Hindu says false on everything (metered), WIRED true on
# everything (metered too), so those two go by the tables above
ACCESS_CHECK = ("indianexpress.com", "livemint.com", "newscientist.com", "nature.com")
ACCESS_CACHE = os.path.join(CACHE_DIR, "access.json")
ACCESS_KEEP = 21 * 86400
WHY = {
    "free": "Free to read — no paywall known for this site",
    "paid": "Subscribers only",
    "limited": "Limited — a few free articles a month (or a free sign-up), then a subscription",
}


def domain_of(link):
    try:
        return urllib.parse.urlparse(link).netloc.lower()
    except Exception:
        return ""


def on_site(dom, sites):
    """dom is one of sites or a subdomain (microsoft.com is not ft.com)."""
    return any(dom == d or dom.endswith("." + d) for d in sites)


def site_access(item):
    dom = domain_of(item["link"])
    if on_site(dom, ACCESS_FREE_FIRST):
        return "free"
    name = item["src"].strip().lower()
    for state, table in (("paid", ACCESS_PAID), ("limited", ACCESS_LIMITED)):
        if name in table["names"] or on_site(dom, table["domains"]):
            return state
    return "free"


def load_access():
    try:
        with open(ACCESS_CACHE) as f:
            return json.load(f)
    except Exception:
        return {}


def access_of(item, checked):
    """(free|paid|limited, why) for one headline."""
    t, link = item["t"], item["link"]
    if item["src"] == "STAT" and t.startswith("STAT+"):
        return "paid", "STAT+ — subscribers only"
    if t.startswith("[$]"):
        return "paid", "LWN subscribers only for a week, then free"
    if "economictimes.indiatimes.com/prime/" in link:
        return "paid", "ET Prime — subscribers only"
    if "/toi-plus/" in link:
        return "paid", "TOI+ — subscribers only"
    c = checked.get(link)
    if c and c[0] in ("free", "paid"):
        return c[0], ("This article is free to read (the site says so)" if c[0] == "free"
                      else "This article is for subscribers (the site says so)")
    a = site_access(item)
    return a, WHY[a]


def needs_check(link, checked):
    return link not in checked and on_site(domain_of(link), ACCESS_CHECK)


FREE_RE = re.compile(rb'"isAccessibleForFree"\s*:\s*"?(true|false)', re.I)


def page_access(url):
    """free | paid | "" — reads the page only until the flag shows up."""
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "text/html"})
    buf = b""
    with urllib.request.urlopen(req, timeout=20) as r:
        if r.headers.get("Content-Encoding") == "gzip":
            buf = gzip.decompress(r.read())
            m = FREE_RE.search(buf)
            return ("free" if m.group(1).lower() == b"true" else "paid") if m else ""
        while len(buf) < 3_000_000:
            chunk = r.read(65536)
            if not chunk:
                break
            buf += chunk
            m = FREE_RE.search(buf)
            if m:
                return "free" if m.group(1).lower() == b"true" else "paid"
    return ""


def cmd_paywall(cid=None):
    cat = cat_def(cid or load_prefs()["cat"])
    checked = load_access()
    todo = [i["link"] for i in items_of(cat, load_cache(cat[0])) if needs_check(i["link"], checked)][:80]
    if not todo:
        return
    now = time.time()
    with cf.ThreadPoolExecutor(8) as ex:
        for link, res in zip(todo, ex.map(lambda u: _try(page_access, u), todo)):
            checked[link] = [res or "?", now]
    # re-read: another category's check may have written meanwhile
    merged = load_access()
    merged.update({k: v for k, v in checked.items() if k in todo})
    save_json(ACCESS_CACHE, {k: v for k, v in merged.items() if now - v[1] < ACCESS_KEEP})


def _try(fn, *a):
    try:
        return fn(*a)
    except Exception:
        return ""


def items_of(cat, cache):
    """Merged, de-duplicated, newest first: [{t, link, ts, src, sub}]."""
    feeds = cache.get("feeds", {})
    out, seen = [], set()
    for sid, _label, fl in cat[3]:
        for f in fl:
            url, opt = (f if isinstance(f, tuple) else (f, {}))
            items = feeds.get(url, {}).get("items", [])
            if url == "hf-papers":
                pass
            elif opt.get("ann"):
                want = set(opt["ann"])
                items = [i for i in items if want & set(i.get("cats", []))]
            # arXiv lists hundreds a day, news feeds dozens: keep each feed short
            for i in items[:PER_FEED]:
                key = re.sub(r"\W+", "", i["t"].lower())[:80]
                if key in seen:
                    continue
                seen.add(key)
                out.append({"t": i["t"], "link": i["link"], "ts": i["ts"], "src": i["src"], "sub": sid})
    # newest first (stable: trending papers keep their upvote order within a day)
    out.sort(key=lambda x: -x["ts"])
    return out[:MAX_ITEMS]


def age(ts, now=None):
    if not ts:
        return ""
    s = max(0, int((now or time.time()) - ts))
    if s < 3600:
        return "%dm" % max(1, s // 60)
    if s < 86400:
        return "%dh" % (s // 3600)
    return "%dd" % (s // 86400)


# ── commands ────────────────────────────────────────────────────────────────
def cmd_json(cid=None):
    prefs = load_prefs()
    cat = cat_def(cid or prefs["cat"])
    cache = load_cache(cat[0])
    off = set(prefs["off"].get(cat[0], []))
    now = time.time()
    items = items_of(cat, cache)
    counts = {}
    checked = load_access()
    unchecked = 0
    for i in items:
        counts[i["sub"]] = counts.get(i["sub"], 0) + 1
        i["age"] = age(i["ts"], now)
        i["acc"], i["accWhy"] = access_of(i, checked)
        unchecked += needs_check(i["link"], checked)
    feeds = cache.get("feeds", {})
    failed = [u for u in feeds_of(cat) if u in feeds and not feeds[u].get("ok", True)]
    out = {
        "ok": True,
        "cat": cat[0],
        "cats": [{"id": c[0], "label": c[1], "icon": c[2]} for c in map(cat_def, prefs["shown"])],
        # the "More" tab: every category, added or not, with its sub-categories
        "more": [{"id": c[0], "label": c[1], "icon": c[2], "on": c[0] in prefs["shown"],
                  "extra": c[0] not in CAT_IDS, "subs": [s[1] for s in c[3]]} for c in ALL],
        "subs": [{"id": s[0], "label": s[1], "on": s[0] not in off, "count": counts.get(s[0], 0)} for s in cat[3]],
        "items": items,
        "cached": bool(feeds),
        "stale": is_stale(cat, cache, now),
        "age": int((now - cache["at"]) // 60) if cache.get("at") else -1,
        "failed": len(failed),
        "unchecked": unchecked,                # → news.py paywall CAT
        "feeds": len(feeds_of(cat)),
    }
    print(json.dumps(out))


def cmd_status():
    prefs = load_prefs()
    cat = cat_def(prefs["cat"])
    cache = load_cache(cat[0])
    if is_stale(cat, cache):
        try:
            cache = refresh(cat[0], force=False)
        except Exception:
            pass
    off = set(prefs["off"].get(cat[0], []))
    items = [i for i in items_of(cat, cache) if i["sub"] not in off]
    fresh = any(i["ts"] > prefs.get("seen", 0) for i in items[:20]) if items else False
    lines = ["<b>News · %s</b>" % html.escape(cat[1])]
    now = time.time()
    for i in items[:5]:
        t = i["t"] if len(i["t"]) <= 70 else i["t"][:69] + "…"
        lines.append("• " + html.escape(t) + "  <i>" + html.escape(i["src"]) + " · " + age(i["ts"], now) + "</i>")
    if not items:
        lines.append("nothing yet" if not cache.get("feeds") else "everything here is switched off")
    print(json.dumps({"text": "\U000F1004", "tooltip": "\n".join(lines),
                      "class": "fresh" if fresh else ("empty" if not items else "read")}), flush=True)


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "status"
    if cmd == "status":
        cmd_status()
    elif cmd == "json":
        cmd_json(argv[2] if len(argv) > 2 and argv[2] else None)
    elif cmd == "refresh":
        cid = argv[2] if len(argv) > 2 and argv[2] else load_prefs()["cat"]
        refresh(cid, force=True)
    elif cmd == "set":
        prefs = load_prefs()
        cid = argv[2] if len(argv) > 2 else prefs["cat"]
        if cid not in ALL_IDS:
            sys.exit("unknown category " + cid)
        prefs["cat"] = cid
        if cid not in prefs["shown"]:
            prefs["shown"].append(cid)
        if len(argv) > 3:
            subs = {s[0] for s in cat_def(cid)[3]}
            off = [s for s in argv[3].split(",") if s in subs]
            if off:
                prefs["off"][cid] = off
            else:
                prefs["off"].pop(cid, None)
        save_json(PREFS, prefs)
    elif cmd == "paywall":
        cmd_paywall(argv[2] if len(argv) > 2 and argv[2] else None)
    elif cmd in ("add", "remove"):
        prefs = load_prefs()
        cid = argv[2] if len(argv) > 2 else ""
        if cid not in ALL_IDS:
            sys.exit("unknown category " + cid)
        shown = prefs["shown"]
        if cmd == "add" and cid not in shown:
            shown.append(cid)
        elif cmd == "remove" and cid in shown and len(shown) > 1:
            shown.remove(cid)
            if prefs["cat"] == cid:
                prefs["cat"] = shown[0]
        save_json(PREFS, prefs)
    elif cmd == "seen":
        prefs = load_prefs()
        prefs["seen"] = time.time()
        save_json(PREFS, prefs)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
