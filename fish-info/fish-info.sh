#!/bin/bash

# ============================================================
# fish-info.sh
#
# 指定した場所・日付・時間の釣り向け情報を Markdown テーブルで出力する
#
# 取得項目:
# - 天気
# - 気温
# - 風向
# - 風速
# - 気圧
# - 波高
# - 波向
# - 波周期
# - 日の出 / 日の入
# - 月齢
# - 潮名
# - 満潮 / 干潮（WORLDTIDES_API_KEY がある場合）
#
# 動作環境:
# - macOS
# - Bash 3.x
# - curl
# - python3
#
# 使い方:
#   ./fish-info.sh "小田原"
#   ./fish-info.sh "小田原" --date 2026-03-27 --hour 6
#   ./fish-info.sh --lat 35.253018 --lon 139.170312 --place "小田原" --date 2026-03-22 --hour 12
#
# 環境変数:
#   WORLDTIDES_API_KEY=xxxxx   # 任意。ある場合のみ満潮/干潮を取得
#
# Author:
#   Toshihiko Arai
#   https://araisun.com
# ============================================================

set -u

PLACE=""
LAT=""
LON=""
TIMEZONE="Asia/Tokyo"
TARGET_DATE=""
TARGET_HOUR=""
TODAY_JST="$(TZ=Asia/Tokyo date +%F)"
CURRENT_HOUR_JST="$(TZ=Asia/Tokyo date +%H | sed 's/^0//')"

usage() {
  cat <<USAGE
usage:
  $0 "場所名" [--date YYYY-MM-DD] [--hour HH]
  $0 --lat <latitude> --lon <longitude> [--place <name>] [--date YYYY-MM-DD] [--hour HH]

example:
  $0 "小田原"
  $0 "小田原" --date 2026-03-27 --hour 6
  $0 --lat 35.2556 --lon 139.1597 --place "小田原" --date 2026-03-27 --hour 18
USAGE
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "command not found: $1" >&2
    exit 1
  }
}

need_cmd curl
need_cmd python3

while [ $# -gt 0 ]; do
  case "$1" in
    --lat)
      LAT="${2:?--lat requires value}"
      shift 2
      ;;
    --lon)
      LON="${2:?--lon requires value}"
      shift 2
      ;;
    --place)
      PLACE="${2:?--place requires value}"
      shift 2
      ;;
    --date)
      TARGET_DATE="${2:?--date requires YYYY-MM-DD}"
      shift 2
      ;;
    --hour)
      TARGET_HOUR="${2:?--hour requires 0-23}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [ -z "$PLACE" ]; then
        PLACE="$1"
      else
        echo "unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$LAT" ] || [ -z "$LON" ]; then
  if [ -z "$PLACE" ]; then
    usage >&2
    exit 1
  fi
fi

[ -n "$TARGET_DATE" ] || TARGET_DATE="$TODAY_JST"
[ -n "$TARGET_HOUR" ] || TARGET_HOUR="$CURRENT_HOUR_JST"

validate_datetime() {
  python3 - "$TARGET_DATE" "$TARGET_HOUR" <<'PY'
import sys
from datetime import datetime

date_str = sys.argv[1]
hour_str = sys.argv[2]

try:
    datetime.strptime(date_str, "%Y-%m-%d")
except ValueError:
    print("--date must be YYYY-MM-DD", file=sys.stderr)
    raise SystemExit(1)

if not hour_str.isdigit():
    print("--hour must be 0-23", file=sys.stderr)
    raise SystemExit(1)

hour = int(hour_str)
if not (0 <= hour <= 23):
    print("--hour must be 0-23", file=sys.stderr)
    raise SystemExit(1)

print(hour)
PY
}

TARGET_HOUR="$(validate_datetime)" || exit 1
TARGET_HOUR_PADDED="$(printf '%02d' "$TARGET_HOUR")"
TARGET_DATETIME="${TARGET_DATE}T${TARGET_HOUR_PADDED}:00"

urlencode() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1]))
PY
}

resolve_lat_lon() {
  if [ -n "$LAT" ] && [ -n "$LON" ]; then
    return 0
  fi

  local q
  local geo_url
  local geo_json

  q="$(urlencode "$PLACE")"
  geo_url="https://geocoding-api.open-meteo.com/v1/search?name=${q}&count=1&language=ja&format=json"
  geo_json="$(curl -fsSL "$geo_url")" || {
    echo "場所の解決に失敗しました: $PLACE" >&2
    exit 1
  }

  eval "$(printf '%s' "$geo_json" | python3 -c '
import json, sys
j = json.load(sys.stdin)
r = (j.get("results") or [])
if not r:
    print("echo \"場所が見つかりませんでした\" >&2; exit 1")
    raise SystemExit
x = r[0]
name = x.get("name") or ""
admin1 = x.get("admin1") or ""
country = x.get("country") or ""
lat = x.get("latitude")
lon = x.get("longitude")
if lat is None or lon is None:
    print("echo \"緯度経度を取得できませんでした\" >&2; exit 1")
    raise SystemExit
place = name
if admin1 and admin1 not in place:
    place = f"{place}, {admin1}"
if country and country not in place:
    place = f"{place}, {country}"
print("LAT=%r" % str(lat))
print("LON=%r" % str(lon))
print("PLACE=%r" % place)
' )"
}

weather_code_to_text() {
  python3 - "$1" <<'PY'
import sys
code = int(float(sys.argv[1]))
MAP = {
    0: '快晴',
    1: '晴れ',
    2: '薄曇り',
    3: '曇り',
    45: '霧',
    48: '着氷性の霧',
    51: '弱い霧雨',
    53: '霧雨',
    55: '強い霧雨',
    56: '弱い着氷性霧雨',
    57: '強い着氷性霧雨',
    61: '弱い雨',
    63: '雨',
    65: '強い雨',
    66: '弱い着氷性の雨',
    67: '強い着氷性の雨',
    71: '弱い雪',
    73: '雪',
    75: '大雪',
    77: '雪粒',
    80: '弱いにわか雨',
    81: 'にわか雨',
    82: '激しいにわか雨',
    85: '弱いにわか雪',
    86: '強いにわか雪',
    95: '雷雨',
    96: '弱い雹を伴う雷雨',
    99: '強い雹を伴う雷雨',
}
print(MAP.get(code, str(code)))
PY
}

wind_dir_to_text() {
  python3 - "$1" <<'PY'
import sys
x = float(sys.argv[1]) % 360
labels = ['北','北北東','北東','東北東','東','東南東','南東','南南東','南','南南西','南西','西南西','西','西北西','北西','北北西']
idx = int((x + 11.25) // 22.5) % 16
print(labels[idx])
PY
}

wave_dir_to_text() {
  wind_dir_to_text "$1"
}

calc_moon_age() {
  python3 - "$TARGET_DATE" <<'PY'
import sys
from datetime import datetime, timezone

dt = datetime.strptime(sys.argv[1], '%Y-%m-%d').replace(tzinfo=timezone.utc)
base = datetime(2000, 1, 6, 18, 14, tzinfo=timezone.utc)
synodic = 29.53058867
age = ((dt - base).total_seconds() / 86400.0) % synodic
print(f'{age:.1f}')
PY
}

calc_tide_name() {
  python3 - "$TARGET_DATE" <<'PY'
import sys
from datetime import datetime, timezone

synodic = 29.53058867
base = datetime(2000, 1, 6, 18, 14, tzinfo=timezone.utc)
dt = datetime.strptime(sys.argv[1], '%Y-%m-%d').replace(tzinfo=timezone.utc)
age = ((dt - base).total_seconds() / 86400.0) % synodic

if age < 1.5 or age >= 28.0:
    name = '大潮'
elif age < 4.0:
    name = '中潮'
elif age < 6.0:
    name = '小潮'
elif age < 9.0:
    name = '長潮'
elif age < 10.5:
    name = '若潮'
elif age < 13.0:
    name = '中潮'
elif age < 16.0:
    name = '大潮'
elif age < 19.0:
    name = '中潮'
elif age < 21.0:
    name = '小潮'
elif age < 24.0:
    name = '長潮'
elif age < 25.5:
    name = '若潮'
else:
    name = '中潮'
print(name)
PY
}

pick_hourly_value() {
  local json="$1"
  local key="$2"

  printf '%s' "$json" | python3 -c '
import json, sys

target = sys.argv[1]
key = sys.argv[2]

try:
    j = json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit

hourly = j.get("hourly") or {}
times = hourly.get("time") or []
values = hourly.get(key) or []

try:
    idx = times.index(target)
except ValueError:
    print("")
    raise SystemExit

if idx >= len(values):
    print("")
    raise SystemExit

v = values[idx]
print("" if v is None else v)
' "$TARGET_DATETIME" "$key"
}

pick_daily_time() {
  local json="$1"
  local key="$2"

  printf '%s' "$json" | python3 -c '
import json, sys

target_date = sys.argv[1]
key = sys.argv[2]

try:
    j = json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit

daily = j.get("daily") or {}
dates = daily.get("time") or []
values = daily.get(key) or []

try:
    idx = dates.index(target_date)
except ValueError:
    print("")
    raise SystemExit

if idx >= len(values):
    print("")
    raise SystemExit

v = values[idx]
if not v:
    print("")
else:
    s = str(v)
    print(s[11:16] if len(s) >= 16 else s)
' "$TARGET_DATE" "$key"
}

set_default_values() {
  TEMPERATURE="-"
  WEATHER_CODE="-"
  WIND_SPEED="-"
  WIND_DIRECTION="-"
  PRESSURE="-"
  SUNRISE="-"
  SUNSET="-"
  WAVE_HEIGHT="-"
  WAVE_DIRECTION="-"
  WAVE_PERIOD="-"
  TIDE_HIGH="-"
  TIDE_LOW="-"
}

check_supported_range() {
  python3 - "$TARGET_DATE" "$TODAY_JST" <<'PY'
import sys
from datetime import date

target = date.fromisoformat(sys.argv[1])
today = date.fromisoformat(sys.argv[2])
days = (target - today).days

# Open-Meteo forecast API は過去 past_days と未来 forecast_days を使う。
# ここでは実用上の範囲として、過去92日〜未来16日を許可する。
if days < -92 or days > 16:
    print("指定日がサポート範囲外です。過去92日〜未来16日で指定してください。", file=sys.stderr)
    raise SystemExit(1)
PY
}

fetch_weather() {
  local url
  local json

  url="https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}&timezone=Asia%2FTokyo&past_days=92&forecast_days=16&hourly=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,surface_pressure&daily=sunrise,sunset"
  json="$(curl -fsSL "$url" 2>/dev/null || true)"

  [ -z "$json" ] && return 0

  local v

  v="$(pick_hourly_value "$json" temperature_2m)"
  [ -n "$v" ] && TEMPERATURE="$v"

  v="$(pick_hourly_value "$json" weather_code)"
  [ -n "$v" ] && WEATHER_CODE="$v"

  v="$(pick_hourly_value "$json" wind_speed_10m)"
  [ -n "$v" ] && WIND_SPEED="$v"

  v="$(pick_hourly_value "$json" wind_direction_10m)"
  [ -n "$v" ] && WIND_DIRECTION="$v"

  v="$(pick_hourly_value "$json" surface_pressure)"
  [ -n "$v" ] && PRESSURE="$v"

  v="$(pick_daily_time "$json" sunrise)"
  [ -n "$v" ] && SUNRISE="$v"

  v="$(pick_daily_time "$json" sunset)"
  [ -n "$v" ] && SUNSET="$v"
}

fetch_marine() {
  local url
  local json
  local v

  url="https://marine-api.open-meteo.com/v1/marine?latitude=${LAT}&longitude=${LON}&timezone=Asia%2FTokyo&past_days=92&forecast_days=16&hourly=wave_height,wave_direction,wave_period"
  json="$(curl -fsSL "$url" 2>/dev/null || true)"

  [ -z "$json" ] && return 0

  v="$(pick_hourly_value "$json" wave_height)"
  [ -n "$v" ] && WAVE_HEIGHT="$v"

  v="$(pick_hourly_value "$json" wave_direction)"
  [ -n "$v" ] && WAVE_DIRECTION="$v"

  v="$(pick_hourly_value "$json" wave_period)"
  [ -n "$v" ] && WAVE_PERIOD="$v"
}

fetch_tide() {
  if [ -z "${WORLDTIDES_API_KEY:-}" ]; then
    return 0
  fi

  local url
  local json

  url="https://www.worldtides.info/api/v3?extremes&date=${TARGET_DATE}&days=1&lat=${LAT}&lon=${LON}&localtime&key=${WORLDTIDES_API_KEY}"
  json="$(curl -fsSL "$url" 2>/dev/null || true)"

  [ -z "$json" ] && return 0

  eval "$(printf '%s' "$json" | python3 -c '
import json, sys
try:
    j = json.load(sys.stdin)
except Exception:
    print("TIDE_HIGH='"'"'-'"'"'")
    print("TIDE_LOW='"'"'-'"'"'")
    raise SystemExit
ext = j.get("extremes") or []
high = []
low = []
for x in ext:
    dt = x.get("date", "")
    tm = dt[11:16] if len(dt) >= 16 else "-"
    typ = (x.get("type") or "").lower()
    if typ == "high":
        high.append(tm)
    elif typ == "low":
        low.append(tm)
print("TIDE_HIGH=%r" % (" / ".join(high) if high else "-"))
print("TIDE_LOW=%r" % (" / ".join(low) if low else "-"))
' )"
}

format_numeric() {
  python3 - "$1" <<'PY'
import sys
s = sys.argv[1]
if s == '-':
    print('-')
    raise SystemExit
try:
    x = float(s)
except Exception:
    print(s)
    raise SystemExit
if x.is_integer():
    print(str(int(x)))
else:
    print(f"{x:.1f}")
PY
}

resolve_lat_lon
check_supported_range || exit 1
set_default_values
fetch_weather
fetch_marine
fetch_tide

WEATHER_TEXT="$(weather_code_to_text "$WEATHER_CODE" 2>/dev/null || echo '-')"
WIND_DIR_TEXT="$(wind_dir_to_text "$WIND_DIRECTION" 2>/dev/null || echo '-')"
WAVE_DIR_TEXT="$(wave_dir_to_text "$WAVE_DIRECTION" 2>/dev/null || echo '-')"
MOON_AGE="$(calc_moon_age 2>/dev/null || echo '-')"
TIDE_NAME="$(calc_tide_name 2>/dev/null || echo '-')"

TEMPERATURE="$(format_numeric "$TEMPERATURE")"
WIND_SPEED="$(format_numeric "$WIND_SPEED")"
PRESSURE="$(format_numeric "$PRESSURE")"
WAVE_HEIGHT="$(format_numeric "$WAVE_HEIGHT")"
WAVE_PERIOD="$(format_numeric "$WAVE_PERIOD")"

[ "$TEMPERATURE" != "-" ] && TEMPERATURE="${TEMPERATURE}℃"
[ "$WIND_SPEED" != "-" ] && WIND_SPEED="${WIND_SPEED}m/s"
[ "$PRESSURE" != "-" ] && PRESSURE="${PRESSURE}hPa"
[ "$WAVE_HEIGHT" != "-" ] && WAVE_HEIGHT="${WAVE_HEIGHT}m"
[ "$WAVE_PERIOD" != "-" ] && WAVE_PERIOD="${WAVE_PERIOD}s"

cat <<TABLE
| 項目 | 値 |
|---|---|
| 日付 | ${TARGET_DATE} |
| 時間 | ${TARGET_HOUR_PADDED}:00 |
| 場所 | ${PLACE} |
| 緯度 | ${LAT} |
| 経度 | ${LON} |
| 天気 | ${WEATHER_TEXT} |
| 気温 | ${TEMPERATURE} |
| 風向 | ${WIND_DIR_TEXT} |
| 風速 | ${WIND_SPEED} |
| 気圧 | ${PRESSURE} |
| 波高 | ${WAVE_HEIGHT} |
| 波向 | ${WAVE_DIR_TEXT} |
| 波周期 | ${WAVE_PERIOD} |
| 潮名 | ${TIDE_NAME} |
| 満潮 | ${TIDE_HIGH} |
| 干潮 | ${TIDE_LOW} |
| 日の出 | ${SUNRISE} |
| 日の入 | ${SUNSET} |
| 月齢 | ${MOON_AGE} |
TABLE
