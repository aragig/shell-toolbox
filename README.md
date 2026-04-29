# shell-toolbox

小さなシェルコマンド集です。

## インストール

リポジトリを clone していない場合は、次のコマンドでインストールできます。

```bash
curl -fsSL https://raw.githubusercontent.com/aragig/shell-toolbox/main/install.sh | bash
```

既定では本体を `$HOME/.local/share/shell-toolbox` に配置し、選択したコマンドだけ `$HOME/.local/bin` にシンボリックリンクします。

既存のインストールがある場合は、最初に更新するか確認されます。

```text
Update source tree before command selection? [y/N]
```

`y` を選ぶと、最新のリモートコードを取得し直します。古い本体ディレクトリは `shell-toolbox.backup.YYYYmmdd_HHMMSS` として残します。`n` を選ぶと、手元にある本体コードのままコマンド選択だけをやり直せます。

clone 済みの場合は、リポジトリ直下で次を実行します。

```bash
./install.sh
```

各コマンドごとに `Install <command>? [y/N]` と確認されるので、入れたいものだけ `y` を入力してください。インストール処理は `$HOME/.local/bin/<command>` から各スクリプトへのシンボリックリンクを作成します。

既に別のファイルやリンクがある場合は、置き換える前に追加で確認します。

リポジトリ内の `bin` ディレクトリは使いません。

## PATH 設定

インストーラの最後に、コマンド用ディレクトリを PATH に追加するためのコマンドが表示されます。表示された内容を使って、利用中のシェルに合わせて設定してください。
