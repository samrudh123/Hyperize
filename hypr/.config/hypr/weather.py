#!/usr/bin/python3
"""Weather — the bottom bar's weather pill (Open-Meteo, no API key).

    weather.py status       waybar-style JSON from the cache; fetches when the
                            cache is older than 15 min (the bar polls every 60 s)
    weather.py refresh      fetch now (left-click)
    weather.py locate       pick the place: fuzzel prompt → Open-Meteo geocoding
                            → choose among the matches (right-click)

The place lives in ~/.config/hypr/weather-location (JSON: name, lat, lon),
kept out of the dotfiles repo. IP geolocation is not used: it put this
machine hundreds of km away.

Cache: ~/.cache/weather/forecast.json. When a fetch fails the last forecast
stays up, marked stale, until it is 3 h old.
"""

import datetime as dt
import html
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

HYPR = os.path.dirname(os.path.abspath(__file__))
LOCATION = os.path.join(HYPR, "weather-location")
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "weather")
CACHE = os.path.join(CACHE_DIR, "forecast.json")
MAX_AGE = 15 * 60
STALE_LIMIT = 3 * 3600

# WMO weather codes → (description, day glyph, night glyph)
SUN, MOON = "\U000F0599", "\U000F0594"
PART_D, PART_N = "\U000F0595", "\U000F0F31"
CLOUD, FOG = "\U000F0590", "\U000F0591"
RAIN, POUR, SLEET = "\U000F0597", "\U000F0596", "\U000F067F"
SNOW, BOLT, BOLT_RAIN = "\U000F0598", "\U000F0593", "\U000F067E"
CODES = {
    0: ("Clear", SUN, MOON), 1: ("Mostly clear", PART_D, PART_N), 2: ("Partly cloudy", PART_D, PART_N),
    3: ("Overcast", CLOUD, CLOUD), 45: ("Fog", FOG, FOG), 48: ("Freezing fog", FOG, FOG),
    51: ("Light drizzle", RAIN, RAIN), 53: ("Drizzle", RAIN, RAIN), 55: ("Heavy drizzle", RAIN, RAIN),
    56: ("Freezing drizzle", SLEET, SLEET), 57: ("Freezing drizzle", SLEET, SLEET),
    61: ("Light rain", RAIN, RAIN), 63: ("Rain", RAIN, RAIN), 65: ("Heavy rain", POUR, POUR),
    66: ("Freezing rain", SLEET, SLEET), 67: ("Freezing rain", SLEET, SLEET),
    71: ("Light snow", SNOW, SNOW), 73: ("Snow", SNOW, SNOW), 75: ("Heavy snow", SNOW, SNOW),
    77: ("Snow grains", SNOW, SNOW), 80: ("Light showers", RAIN, RAIN), 81: ("Showers", POUR, POUR),
    82: ("Violent showers", POUR, POUR), 85: ("Snow showers", SNOW, SNOW), 86: ("Snow showers", SNOW, SNOW),
    95: ("Thunderstorm", BOLT_RAIN, BOLT_RAIN), 96: ("Thunderstorm, hail", BOLT_RAIN, BOLT_RAIN),
    99: ("Thunderstorm, hail", BOLT_RAIN, BOLT_RAIN),
}
WET = {51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99}


def code_info(code, day=True):
    desc, d, n = CODES.get(code, ("Unknown", CLOUD, CLOUD))
    return desc, d if day else n


def get_json(url, timeout=8):
    req = urllib.request.Request(url, headers={"User-Agent": "quickshell-weather/1"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def read_location():
    try:
        with open(LOCATION) as f:
            loc = json.load(f)
        return loc if "lat" in loc and "lon" in loc else None
    except (OSError, ValueError):
        return None


def fetch(loc):
    q = urllib.parse.urlencode({
        "latitude": loc["lat"], "longitude": loc["lon"], "timezone": "auto", "forecast_days": 4,
        "current": "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,"
                   "wind_speed_10m,precipitation",
        "hourly": "precipitation_probability,weather_code",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,"
                 "sunrise,sunset,uv_index_max",
    })
    data = get_json("https://api.open-meteo.com/v1/forecast?" + q)
    data["_fetched"] = time.time()
    data["_place"] = loc.get("name", "")
    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp = CACHE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, CACHE)
    return data


def read_cache():
    try:
        with open(CACHE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def rain_soon(d):
    """'Rain likely around 16:00' from the next 6 hours, or ''."""
    h = d.get("hourly", {})
    times, probs, codes = h.get("time", []), h.get("precipitation_probability", []), h.get("weather_code", [])
    now = d["current"]["time"][:13]
    try:
        i = next(k for k, t in enumerate(times) if t[:13] >= now)
    except StopIteration:
        return ""
    for k in range(i, min(i + 7, len(times))):
        if (probs[k] or 0) >= 50 and codes[k] in WET:
            when = "now" if k == i else "around " + times[k][11:16]
            return f"{code_info(codes[k])[0]} likely {when} ({probs[k]}%)"
    return ""


def render(d, stale=False):
    c, day = d["current"], d["daily"]
    is_day = bool(c.get("is_day", 1))
    desc, glyph = code_info(c["weather_code"], is_day)
    temp = round(c["temperature_2m"])
    dim = lambda s: f"<i>{s}</i>"     # no colours: the palette is themed, the script isn't
    lines = [f"<b>{html.escape(d.get('_place') or 'Weather')}</b>  {dim(desc)}",
             f"{temp}°C, feels like {round(c['apparent_temperature'])}°C",
             f"\U000F058E {c['relative_humidity_2m']}%   \U000F059D {round(c['wind_speed_10m'])} km/h"
             + (f"   UV {round(day['uv_index_max'][0])}" if day.get("uv_index_max") and day["uv_index_max"][0] is not None else "")]
    soon = rain_soon(d)
    if soon:
        lines.append("\U000F054A " + soon)
    lines.append(f"\U000F059C {day['sunrise'][0][11:16]}   \U000F059B {day['sunset'][0][11:16]}")
    lines.append("")
    for k, date in enumerate(day["time"]):
        name = "Today" if k == 0 else dt.date.fromisoformat(date).strftime("%a")
        ddesc, dglyph = code_info(day["weather_code"][k])
        rain = day["precipitation_probability_max"][k]
        lines.append(f"{name:<6} {dglyph}  {round(day['temperature_2m_max'][k]):>3}° / {round(day['temperature_2m_min'][k]):>3}°"
                     f"  {dim(ddesc + (f', {rain}%' if rain else ''))}")
    age = int((time.time() - d.get("_fetched", 0)) / 60)
    lines.append("")
    lines.append(dim(("Stale — couldn't update · " if stale else "") + f"updated {age} min ago · Open-Meteo"))
    lines.append(dim("Click: refresh · Right-click: change place"))
    classes = ["stale"] if stale else []
    classes.append("day" if is_day else "night")
    if c["weather_code"] in WET or soon:
        classes.append("rain")
    elif c["weather_code"] in (0, 1) and is_day:
        classes.append("sunny")
    return {"text": f"{glyph}  {temp}°", "tooltip": "\n".join(lines), "class": classes}


def cmd_status(force=False):
    loc = read_location()
    if loc is None:
        print(json.dumps({"text": "\U000F034E  set place", "class": ["unset"],
                          "tooltip": "No place set for the weather.\nRight-click to choose one."},
                         ensure_ascii=False))
        return
    d = read_cache()
    fresh = (d and d.get("_place") == loc.get("name", "")
             and time.time() - d.get("_fetched", 0) < MAX_AGE)
    stale = False
    if force or not fresh:
        try:
            d = fetch(loc)
        except Exception:
            stale = True
            if not d or time.time() - d.get("_fetched", 0) > STALE_LIMIT:
                print(json.dumps({"text": "\U000F0590  –", "class": ["error"],
                                  "tooltip": "Weather unavailable (offline?)\nClick to retry."},
                                 ensure_ascii=False))
                return
    print(json.dumps(render(d, stale), ensure_ascii=False))


def fuzzel(prompt, options=None):
    # no options = free text: --prompt-only hides the (empty) list
    args = ["fuzzel", "--dmenu", "--prompt-only" if options is None else "--prompt", prompt]
    r = subprocess.run(args, input="\n".join(options or []), capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def cmd_locate():
    query = fuzzel("Weather for: ")
    if not query:
        return
    try:
        res = get_json("https://geocoding-api.open-meteo.com/v1/search?"
                       + urllib.parse.urlencode({"name": query, "count": 8, "format": "json"}))
    except Exception as e:
        subprocess.run(["notify-send", "-a", "Weather", "Couldn't look that up", str(e)])
        return
    hits = res.get("results") or []
    if not hits:
        subprocess.run(["notify-send", "-a", "Weather", "No place found", query])
        return
    label = lambda h: ", ".join(x for x in (h.get("name"), h.get("admin1"), h.get("country")) if x)
    if len(hits) == 1:
        pick = hits[0]
    else:
        names = [f"{i + 1}. {label(h)}" for i, h in enumerate(hits)]
        choice = fuzzel("Which one? ", names)
        if not choice:
            return
        pick = hits[int(choice.split(".", 1)[0]) - 1]
    with open(LOCATION, "w") as f:
        json.dump({"name": pick["name"], "lat": round(pick["latitude"], 3),
                   "lon": round(pick["longitude"], 3)}, f)
        f.write("\n")
    cmd_status(force=True)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "status":
        cmd_status()
    elif cmd == "refresh":
        cmd_status(force=True)
    elif cmd == "locate":
        cmd_locate()
    else:
        sys.exit(__doc__)
