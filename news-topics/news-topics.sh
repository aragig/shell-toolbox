#!/bin/bash

# ============================================================
# news-topics.sh
#
# 信頼性が比較的高い複数ニュースソースのRSS/Atomを取得し、
# 1媒体に偏りすぎないように見出し一覧を整形して表示する。
#
# 主な仕様:
# - BBC / Reuters / NPR / DW / France 24 / Al Jazeera を既定採用
# - ソースごとの上限とラウンドロビンで偏りを抑制
# - 重複記事を除去
# - 見出しの日本語訳を付与可能
# - CLI / Markdown / TSV / JSON 出力対応
#
# 動作環境:
# - macOS
# - Bash 3.x
# - curl
# - python3
#
# usage:
#   ./news-topics.sh
#   ./news-topics.sh --count 18 --per-source 3
#   ./news-topics.sh --translate none
#   ./news-topics.sh --format tsv > news.tsv
#
# 翻訳:
# - --translate auto が既定
# - OPENAI_API_KEY があれば OpenAI を優先
# - なければ translate.googleapis.com を使う簡易翻訳へフォールバック
# - 翻訳に失敗した場合は原文見出しをそのまま表示
# ============================================================

set -euo pipefail

COUNT=12
PER_SOURCE=2
FORMAT="markdown"
TRANSLATE_MODE="auto"
TIMEOUT=15

usage() {
  cat <<'EOF'
usage:
  news-topics.sh [--count N] [--per-source N] [--format cli|markdown|tsv|json] [--translate auto|openai|google|none]

example:
  news-topics.sh
  news-topics.sh --count 18 --per-source 3
  news-topics.sh --translate none
  news-topics.sh --format tsv

option:
  --count N         表示件数の上限 (default: 12)
  --per-source N    1ソースあたりの最大件数 (default: 2)
  --format FORMAT   cli / markdown / tsv / json (default: markdown, ttyではcli風表示)
  --translate MODE  auto / openai / google / none (default: auto)
  --timeout SEC     各フィード取得タイムアウト秒 (default: 15)
  -h, --help        show help

environment:
  NEWS_TOPICS_PYTHON              Python interpreter override
  OPENAI_API_KEY                  OpenAI API key
  OPENAI_MODEL                    default: gpt-4o-mini
  NEWS_TOPICS_OPENAI_MODEL        OPENAI_MODEL より優先
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "command not found: $1" >&2
    exit 1
  }
}

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*)
      return 1
      ;;
    *)
      [ "$1" -gt 0 ]
      ;;
  esac
}

need_cmd curl

select_python() {
  local candidate
  for candidate in "${NEWS_TOPICS_PYTHON:-}" python3 /usr/bin/python3 python3.13 python3.12 python3.11 python3.10 python3.9; do
    [ -n "$candidate" ] || continue
    command -v "$candidate" >/dev/null 2>&1 || continue
    if "$candidate" - <<'PY' >/dev/null 2>&1
import xml.etree.ElementTree as ET
ET.fromstring("<root />")
PY
    then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "command not found: a Python 3 interpreter with working XML support" >&2
  return 1
}

PYTHON_BIN="$(select_python)"

while [ $# -gt 0 ]; do
  case "$1" in
    --count)
      COUNT="${2:?--count requires value}"
      shift 2
      ;;
    --per-source)
      PER_SOURCE="${2:?--per-source requires value}"
      shift 2
      ;;
    --format)
      FORMAT="${2:?--format requires value}"
      shift 2
      ;;
    --translate)
      TRANSLATE_MODE="${2:?--translate requires value}"
      shift 2
      ;;
    --timeout)
      TIMEOUT="${2:?--timeout requires value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

is_positive_int "$COUNT" || {
  echo "--count must be a positive integer" >&2
  exit 1
}

is_positive_int "$PER_SOURCE" || {
  echo "--per-source must be a positive integer" >&2
  exit 1
}

is_positive_int "$TIMEOUT" || {
  echo "--timeout must be a positive integer" >&2
  exit 1
}

case "$FORMAT" in
  cli|markdown|tsv|json) ;;
  *)
    echo "--format must be cli, markdown, tsv, or json" >&2
    exit 1
    ;;
esac

case "$TRANSLATE_MODE" in
  auto|openai|google|none) ;;
  *)
    echo "--translate must be auto, openai, google, or none" >&2
    exit 1
    ;;
esac

export NEWS_TOPICS_COUNT="$COUNT"
export NEWS_TOPICS_PER_SOURCE="$PER_SOURCE"
export NEWS_TOPICS_FORMAT="$FORMAT"
export NEWS_TOPICS_TRANSLATE="$TRANSLATE_MODE"
export NEWS_TOPICS_TIMEOUT="$TIMEOUT"

"$PYTHON_BIN" - <<'PY'
from __future__ import annotations

import email.utils
import html
import json
import os
import re
import shutil
import sys
import time
import textwrap
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from collections import defaultdict, deque
from datetime import datetime, timezone
from typing import Dict, List


SOURCES = [
    {
        "id": "bbc",
        "name": "BBC",
        "category": "public_broadcaster",
        "url": "https://feeds.bbci.co.uk/news/world/rss.xml",
    },
    {
        "id": "reuters",
        "name": "Reuters",
        "category": "wire",
        "url": "https://feeds.reuters.com/Reuters/worldNews",
    },
    {
        "id": "npr",
        "name": "NPR",
        "category": "public_radio",
        "url": "https://feeds.npr.org/1001/rss.xml",
    },
    {
        "id": "dw",
        "name": "DW",
        "category": "public_broadcaster",
        "url": "https://rss.dw.com/rdf/rss-en-top",
    },
    {
        "id": "france24",
        "name": "France 24",
        "category": "public_broadcaster",
        "url": "https://www.france24.com/en/rss",
    },
    {
        "id": "aljazeera",
        "name": "Al Jazeera",
        "category": "international_broadcaster",
        "url": "https://www.aljazeera.com/xml/rss/all.xml",
    },
]


COUNT = int(os.environ.get("NEWS_TOPICS_COUNT", "12"))
PER_SOURCE = int(os.environ.get("NEWS_TOPICS_PER_SOURCE", "2"))
FORMAT = os.environ.get("NEWS_TOPICS_FORMAT", "markdown")
TRANSLATE_MODE = os.environ.get("NEWS_TOPICS_TRANSLATE", "auto")
TIMEOUT = int(os.environ.get("NEWS_TOPICS_TIMEOUT", "15"))
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "").strip()
OPENAI_MODEL = (
    os.environ.get("NEWS_TOPICS_OPENAI_MODEL", "").strip()
    or os.environ.get("OPENAI_MODEL", "").strip()
    or "gpt-4o-mini"
)


SOURCE_COLORS = {
    "BBC": "196",
    "Reuters": "214",
    "NPR": "33",
    "DW": "39",
    "France 24": "45",
    "Al Jazeera": "220",
}


def fetch_text(url: str, timeout: int) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "shell-toolbox-news-topics/1.0 (+https://github.com/aragig/shell-toolbox)",
            "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.8",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        charset = resp.headers.get_content_charset() or "utf-8"
        return resp.read().decode(charset, errors="replace")


def strip_html(text: str) -> str:
    text = re.sub(r"<[^>]+>", " ", text or "")
    text = html.unescape(text)
    return re.sub(r"\s+", " ", text).strip()


def parse_date(value: str | None) -> str:
    if not value:
        return ""

    candidates = [value.strip()]
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%d"):
        try:
            dt = datetime.strptime(value.strip(), fmt)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        except ValueError:
            pass

    try:
        dt = email.utils.parsedate_to_datetime(value)
        if dt is not None:
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    except (TypeError, ValueError, IndexError):
        pass

    return value.strip()


def parse_feed(xml_text: str, source: Dict[str, str]) -> List[Dict[str, str]]:
    root = ET.fromstring(xml_text)
    items: List[Dict[str, str]] = []

    ns = {
        "atom": "http://www.w3.org/2005/Atom",
        "dc": "http://purl.org/dc/elements/1.1/",
        "content": "http://purl.org/rss/1.0/modules/content/",
        "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    }

    rss_items = root.findall(".//item")
    atom_entries = root.findall(".//atom:entry", ns)
    rdf_items = root.findall(".//rdf:item", ns)

    if rss_items:
      entries = rss_items
      mode = "rss"
    elif atom_entries:
      entries = atom_entries
      mode = "atom"
    elif rdf_items:
      entries = rdf_items
      mode = "rdf"
    else:
      return items

    seen_links = set()

    for entry in entries:
        if mode in ("rss", "rdf"):
            title = strip_html(entry.findtext("title"))
            link = (entry.findtext("link") or "").strip()
            if not link:
                link_el = entry.find("link")
                if link_el is not None and link_el.text:
                    link = link_el.text.strip()
            published = parse_date(
                entry.findtext("pubDate")
                or entry.findtext("published")
                or entry.findtext("updated")
                or entry.findtext("{http://purl.org/dc/elements/1.1/}date")
            )
            summary = strip_html(
                entry.findtext("description")
                or entry.findtext("{http://purl.org/rss/1.0/modules/content/}encoded")
                or ""
            )
        else:
            title = strip_html(entry.findtext("atom:title", default="", namespaces=ns))
            link = ""
            for link_el in entry.findall("atom:link", ns):
                href = (link_el.attrib.get("href") or "").strip()
                rel = (link_el.attrib.get("rel") or "alternate").strip()
                if href and rel == "alternate":
                    link = href
                    break
                if href and not link:
                    link = href
            published = parse_date(
                entry.findtext("atom:published", default="", namespaces=ns)
                or entry.findtext("atom:updated", default="", namespaces=ns)
            )
            summary = strip_html(
                entry.findtext("atom:summary", default="", namespaces=ns)
                or entry.findtext("atom:content", default="", namespaces=ns)
            )

        if not title or not link:
            continue

        if link in seen_links:
            continue
        seen_links.add(link)

        items.append(
            {
                "source_id": source["id"],
                "source": source["name"],
                "category": source["category"],
                "title": title,
                "title_ja": "",
                "link": link,
                "published": published,
                "summary": summary,
            }
        )

    return items


def normalize_title(title: str) -> str:
    title = title.lower()
    title = html.unescape(title)
    title = re.sub(r"\s+", " ", title)
    title = re.sub(r"[\"'`“”‘’]", "", title)
    return title.strip()


def choose_translate_backend() -> str:
    if TRANSLATE_MODE == "none":
        return "none"
    if TRANSLATE_MODE == "openai":
        return "openai"
    if TRANSLATE_MODE == "google":
        return "google"
    if OPENAI_API_KEY:
        return "openai"
    return "google"


def translate_google(text: str) -> str:
    query = urllib.parse.urlencode(
        {
            "client": "gtx",
            "sl": "auto",
            "tl": "ja",
            "dt": "t",
            "q": text,
        }
    )
    url = "https://translate.googleapis.com/translate_a/single?" + query
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "shell-toolbox-news-topics/1.0"},
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        data = json.loads(resp.read().decode("utf-8", errors="replace"))
    parts = []
    for row in data[0]:
        if row and row[0]:
            parts.append(row[0])
    return "".join(parts).strip()


def translate_openai(texts: List[str]) -> Dict[str, str]:
    if not OPENAI_API_KEY:
        raise RuntimeError("OPENAI_API_KEY is not set")

    payload = {
        "model": OPENAI_MODEL,
        "temperature": 0.2,
        "messages": [
            {
                "role": "system",
                "content": (
                    "Translate news headlines into concise, natural Japanese. "
                    "Keep proper nouns accurate. Return JSON only."
                ),
            },
            {
                "role": "user",
                "content": json.dumps(
                    {
                        "task": "Translate each English headline into Japanese.",
                        "headlines": texts,
                        "output_format": {
                            "items": [
                                {"original": "string", "translated_ja": "string"}
                            ]
                        },
                    },
                    ensure_ascii=False,
                ),
            },
        ],
        "response_format": {"type": "json_object"},
    }

    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {OPENAI_API_KEY}",
        },
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=max(TIMEOUT, 30)) as resp:
        body = json.loads(resp.read().decode("utf-8", errors="replace"))

    content = body["choices"][0]["message"]["content"]
    parsed = json.loads(content)
    result: Dict[str, str] = {}
    for item in parsed.get("items", []):
        original = (item.get("original") or "").strip()
        translated = (item.get("translated_ja") or "").strip()
        if original and translated:
            result[original] = translated
    return result


def attach_translations(items: List[Dict[str, str]]) -> None:
    backend = choose_translate_backend()
    if backend == "none":
        for item in items:
            item["title_ja"] = item["title"]
        return

    unique_titles = []
    seen = set()
    for item in items:
        title = item["title"]
        if title not in seen:
            seen.add(title)
            unique_titles.append(title)

    translations: Dict[str, str] = {}

    if backend == "openai":
        try:
            translations = translate_openai(unique_titles)
        except Exception:
            if TRANSLATE_MODE == "openai":
                raise
            backend = "google"

    if backend == "google":
        for title in unique_titles:
            try:
                translations[title] = translate_google(title)
                time.sleep(0.15)
            except Exception:
                translations[title] = ""

    for item in items:
        translated = translations.get(item["title"], "").strip()
        item["title_ja"] = translated or item["title"]


def fetch_all_items() -> List[Dict[str, str]]:
    all_items: List[Dict[str, str]] = []

    for source in SOURCES:
        try:
            xml_text = fetch_text(source["url"], timeout=TIMEOUT)
            all_items.extend(parse_feed(xml_text, source))
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ET.ParseError):
            continue

    return all_items


def dedupe_items(items: List[Dict[str, str]]) -> List[Dict[str, str]]:
    result = []
    seen_links = set()
    seen_titles = set()

    for item in items:
        link_key = item["link"].strip()
        title_key = normalize_title(item["title"])
        if link_key in seen_links or title_key in seen_titles:
            continue
        seen_links.add(link_key)
        seen_titles.add(title_key)
        result.append(item)

    return result


def balance_items(items: List[Dict[str, str]]) -> List[Dict[str, str]]:
    buckets = defaultdict(list)
    source_order = []
    seen_source = set()

    for item in items:
        buckets[item["source"]].append(item)
        if item["source"] not in seen_source:
            seen_source.add(item["source"])
            source_order.append(item["source"])

    for source in source_order:
        buckets[source] = buckets[source][: max(PER_SOURCE * 3, PER_SOURCE)]

    queues = {source: deque(buckets[source]) for source in source_order}
    selected = []
    selected_per_source = defaultdict(int)

    while len(selected) < COUNT:
        progressed = False
        for source in source_order:
            if len(selected) >= COUNT:
                break
            if selected_per_source[source] >= PER_SOURCE:
                continue
            if not queues[source]:
                continue
            selected.append(queues[source].popleft())
            selected_per_source[source] += 1
            progressed = True
        if not progressed:
            break

    if len(selected) < COUNT:
        for source in source_order:
            while queues[source] and len(selected) < COUNT:
                selected.append(queues[source].popleft())

    return selected[:COUNT]


def render_markdown(items: List[Dict[str, str]]) -> str:
    lines = []
    lines.append("# News Topics")
    lines.append("")
    lines.append(
        "_Sources: BBC / Reuters / NPR / DW / France 24 / Al Jazeera "
        "(balanced by source cap and round-robin)_"
    )
    lines.append("")
    for idx, item in enumerate(items, start=1):
        date_part = f" | {item['published']}" if item["published"] else ""
        lines.append(
            f"{idx}. [{item['title_ja']}]({item['link']})"
            f"  "
            f"`{item['source']}{date_part}`"
        )
        if item["title_ja"] != item["title"]:
            lines.append(f"   original: {item['title']}")
    return "\n".join(lines)


def supports_color() -> bool:
    if not sys.stdout.isatty():
        return False
    if os.environ.get("NO_COLOR"):
        return False
    term = os.environ.get("TERM", "")
    return term not in ("", "dumb")


def ansi(text: str, *codes: str, enable: bool) -> str:
    if not enable or not codes:
        return text
    return f"\033[{';'.join(codes)}m{text}\033[0m"


def wrap_block(text: str, width: int, prefix: str, subsequent: str) -> List[str]:
    if not text:
        return []
    return textwrap.wrap(
        text,
        width=max(width, 20),
        initial_indent=prefix,
        subsequent_indent=subsequent,
        break_long_words=False,
        break_on_hyphens=False,
    )


def render_cli(items: List[Dict[str, str]]) -> str:
    color = supports_color()
    width = max(shutil.get_terminal_size(fallback=(100, 24)).columns, 72)
    body_width = max(width - 4, 40)
    title_width = max(body_width - 4, 24)

    title = ansi("News Topics", "1", "38;5;15", enable=color)
    meta = ansi(
        f"{len(items)} items  |  balanced by source cap ({PER_SOURCE}/source)",
        "2",
        "38;5;246",
        enable=color,
    )

    lines = [title, meta, ansi("─" * min(width, 100), "38;5;240", enable=color), ""]

    for idx, item in enumerate(items, start=1):
        num = ansi(f"{idx:02d}.", "1", "38;5;250", enable=color)
        ja_title = item["title_ja"].strip() or item["title"]
        lines.extend(wrap_block(ja_title, title_width, f"{num} ", "    "))

        source_color = SOURCE_COLORS.get(item["source"], "81")
        source = ansi(f"[{item['source']}]", "1", f"38;5;{source_color}", enable=color)
        published = item["published"] or "date unknown"
        detail = f"{source}  {ansi(published, '2', '38;5;246', enable=color)}"
        lines.append(f"    {detail}")

        if item["title_ja"] != item["title"]:
            original = ansi("EN", "2", "38;5;244", enable=color)
            lines.extend(wrap_block(item["title"], body_width - 4, f"    {original} ", "       "))

        url_label = ansi("URL", "2", "38;5;111", enable=color)
        url_value = ansi(item["link"], "4", "38;5;117", enable=color)
        lines.extend(wrap_block(url_value, body_width - 5, f"    {url_label} ", "        "))
        lines.append("")

    return "\n".join(lines).rstrip()


def render_tsv(items: List[Dict[str, str]]) -> str:
    rows = ["source\tpublished\ttitle_ja\ttitle\tlink"]
    for item in items:
        cols = [
            item["source"],
            item["published"],
            item["title_ja"],
            item["title"],
            item["link"],
        ]
        rows.append("\t".join(col.replace("\t", " ").replace("\n", " ") for col in cols))
    return "\n".join(rows)


def render_json(items: List[Dict[str, str]]) -> str:
    return json.dumps(items, ensure_ascii=False, indent=2)


def main() -> int:
    items = fetch_all_items()
    items = dedupe_items(items)
    items = balance_items(items)

    if not items:
        print("error: ニュース取得に失敗しました。ネットワークまたは各RSS URLを確認してください。", file=sys.stderr)
        return 1

    attach_translations(items)

    if FORMAT == "cli":
        print(render_cli(items))
    elif FORMAT == "markdown":
        if sys.stdout.isatty():
            print(render_cli(items))
        else:
            print(render_markdown(items))
    elif FORMAT == "tsv":
        print(render_tsv(items))
    else:
        print(render_json(items))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
