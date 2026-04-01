# dump_all_pgdbs.sh

`~/.pgpass` を使って PostgreSQL のDBをまとめてダンプし、`tar.gz` に圧縮します。

## 必要なもの

- macOS
- `pg_dump`

```bash
brew install postgresql@14
````

## 準備

`~/.pgpass` を作成します。

```bash
touch ~/.pgpass
chmod 600 ~/.pgpass
```

例:

```text
localhost:5432:sample_db:sample_user:password
localhost:5432:another_db:another_user:password
```

書式:

```text
host:port:database:user:password
```

## 使い方

```bash
./dump_all_pgdbs.sh
./dump_all_pgdbs.sh -o ~/Downloads/backups
./dump_all_pgdbs.sh --pgpass ~/.pgpass
./dump_all_pgdbs.sh --keep-dir
```

## オプション

```text
-o, --output-dir DIR
-p, --pgpass FILE
-k, --keep-dir
-h, --help
-v, --version
```
