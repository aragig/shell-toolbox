# news-topics.sh

複数の海外ニュースソースからRSS/Atomを取得して、偏りを抑えながら一覧表示するシェルです。TTY では色付きの CLI 表示、リダイレクト時はプレーンなテキスト出力になります。

## ねらい

- `Yahooニュース` のようなポータル依存ではなく、一次配信に近い媒体を直接参照する
- 1媒体に並びが偏りすぎないようにする
- 見出しの日本語訳を付ける

## 既定の取得元

- BBC
- Reuters
- NPR
- DW
- France 24
- Al Jazeera

思想的な完全中立は不可能ですが、`通信社`、`公共放送系`、`地域視点の異なる国際メディア` を混ぜることで、見え方の偏りを少し抑える構成にしています。

## 使い方

```bash
./news-topics.sh
./news-topics.sh --count 18 --per-source 3
./news-topics.sh --translate none
./news-topics.sh --format cli
./news-topics.sh --format tsv
```

## オプション

```text
--count N
--per-source N
--format cli|markdown|tsv|json
--translate auto|openai|google|none
--timeout SEC
```

`--format markdown` は、端末に直接表示する場合は見やすい CLI レイアウトで出し、パイプやリダイレクト時は従来どおり Markdown を出します。

## 翻訳の挙動

- `auto`:
  - `OPENAI_API_KEY` があれば OpenAI API を使用
  - なければ `translate.googleapis.com` を使う簡易翻訳へフォールバック
- `openai`: OpenAI API を強制
- `google`: 簡易翻訳を強制
- `none`: 翻訳しない

※ `google` は非公式寄りの簡易利用なので、安定性やポリシー面を厳密にしたいなら `openai` のほうが安全です。

## Python の選択

`python3` の XML サポートが壊れている場合は、`/usr/bin/python3` など利用可能な Python 3 へ自動でフォールバックします。明示的に指定する場合は `NEWS_TOPICS_PYTHON=/path/to/python3` を設定してください。

## 出力例

```markdown
# News Topics

_Sources: BBC / Reuters / NPR / DW / France 24 / Al Jazeera (balanced by source cap and round-robin)_

1. [各国首脳が停戦協議を開始](https://example.com/...)
   `BBC | 2026-04-17 01:10 UTC`
   original: Leaders begin ceasefire talks
```

TTY では次のような見た目になります。

```text
News Topics
12 items  |  balanced by source cap (2/source)
────────────────────────────────────────────────────────────

01. 各国首脳が停戦協議を開始
    [BBC]  2026-04-17 01:10 UTC
    EN Leaders begin ceasefire talks
    URL https://example.com/...
```
