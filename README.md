# shell-toolbox

小さなシェルコマンド集です。

## インストール

### clone していない場合

次のコマンドで GitHub から取得してインストールできます。

```bash
curl -fsSL https://raw.githubusercontent.com/aragig/shell-toolbox/main/install.sh | bash
```

既定では本体を `$HOME/.local/share/shell-toolbox` に配置し、選択したコマンドだけ `$HOME/.local/bin` にシンボリックリンクします。

既存のインストールがある場合は、最初に更新するか確認されます。

```text
Update source tree before command selection? [y/N]
```

`y` を選ぶと、最新のリモートコードを取得し直します。古い本体ディレクトリは `shell-toolbox.backup.YYYYmmdd_HHMMSS` として残します。`n` を選ぶと、手元にある本体コードのままコマンド選択だけをやり直せます。

特定のタグやコミットを使う場合は `SHELL_TOOLBOX_REF` を指定します。

```bash
curl -fsSL https://raw.githubusercontent.com/aragig/shell-toolbox/main/install.sh | SHELL_TOOLBOX_REF=v1.0.0 bash
curl -fsSL https://raw.githubusercontent.com/aragig/shell-toolbox/main/install.sh | SHELL_TOOLBOX_REF=323516d bash
```

インストール先を変える場合は次を指定できます。

```bash
curl -fsSL https://raw.githubusercontent.com/aragig/shell-toolbox/main/install.sh \
  | SHELL_TOOLBOX_INSTALL_DIR="$HOME/tools/shell-toolbox" SHELL_TOOLBOX_BIN_DIR="$HOME/bin" bash
```

### clone 済みの場合

リポジトリ直下で次を実行します。

```bash
./install.sh
```

各コマンドごとに `Install <command>? [y/N]` と確認されるので、入れたいものだけ `y` を入力してください。インストール処理は `$HOME/.local/bin/<command>` から各スクリプトへのシンボリックリンクを作成します。

既に別のファイルやリンクがある場合は、置き換える前に追加で確認します。

リポジトリ内の `bin` ディレクトリは使いません。コマンド用ディレクトリは `SHELL_TOOLBOX_BIN_DIR` で変更できます。

## PATH 設定

インストーラの最後に、コマンド用ディレクトリを PATH に追加するためのコマンドが表示されます。表示された内容を使って、利用中のシェルに合わせて設定してください。
