# news-topics.sh

複数の海外ニュースソースからRSS/Atomを取得して、偏りを抑えながら一覧表示するシェルです。

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
./news-topics.sh --format tsv
```

## オプション

```text
--count N
--per-source N
--format markdown|tsv|json
--translate auto|openai|google|none
--timeout SEC
```

## 翻訳の挙動

- `auto`:
  - `OPENAI_API_KEY` があれば OpenAI API を使用
  - なければ `translate.googleapis.com` を使う簡易翻訳へフォールバック
- `openai`: OpenAI API を強制
- `google`: 簡易翻訳を強制
- `none`: 翻訳しない

※ `google` は非公式寄りの簡易利用なので、安定性やポリシー面を厳密にしたいなら `openai` のほうが安全です。

## 出力例

```markdown
# News Topics

_Sources: BBC / Reuters / NPR / DW / France 24 / Al Jazeera (balanced by source cap and round-robin)_

1. [各国首脳が停戦協議を開始](https://example.com/...)
   `BBC | 2026-04-17 01:10 UTC`
   original: Leaders begin ceasefire talks
```
