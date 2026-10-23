# CEE共有記憶 API 導入・運用手順

## 1. MARK6側の配置

今回の変更対象は `D:\projects\mark6` です。本番サーバーへの配置は運用者が行います。

`public/cee.cgi` と既存の `lib/Mark6/` を配置し、MARK6同梱の `.htaccess` を更新します。CEE用URLのRewriteとBearer認証ヘッダーの引き継ぎは `.htaccess` に含まれています。

独自Apache設定を使用している場合は `docs/CEE_MEMORY_APACHE.conf` の内容をMARK6のcatch-allより先に追加します。`mod_rewrite`、CGIの実行、AuthorizationヘッダーのCGIへの転送が必要です。DocumentRootや公開ディレクトリが異なる構成ではパスを調整してください。

## 2. 鍵と停止スイッチ

CGI実行環境へ長いランダムな秘密値を設定します。

```text
CEE_SECRET_TOKEN=<secret>
```

Pi側では同じ値を `CEE_MARK6_TOKEN` に設定します。サービスの実行環境へ設定し、hardware.yaml・Git・公開ディレクトリに鍵を書きません。通信にはHTTPSを使用します。

一時停止は `CEE_API_ENABLED=0` です。再開は値を `1` にするか変数を解除します。停止中も記憶と非公開設定は保持されます。ファイル単位で取り外す場合は `public/cee.cgi` と専用Rewriteを外せます。

鍵を分離する独自クライアントでは `CEE_WRITE_TOKEN` / `CEE_READ_TOKEN` も使用できます。現行CEE01クライアントは `CEE_MARK6_TOKEN` 一つなので、通常は共通鍵で利用してください。

## 3. CEE01側

既存クライアントが対応しています。Piの実運用設定でURLを確認します。

```yaml
mark6:
  enabled: true
  base_url: https://ceelog.oita360.com
```

URL・鍵が無い場合は同期だけを止め、会話・STOP・Follow安全制御は動作を継続します。身体制御を動かすための追加設定・調整は不要です。

## 4. 配置後の確認

まず移動操作を伴わないAPI接続で、以下を確認します。

1. 鍵なしの `/cee/recent` が401になる。
2. `CEE_API_ENABLED=0` で404になり、再開すると認証済み読み取りができる。
3. 認証済みPOSTで `/cee/write` に記憶を保存し、201と記事IDが返る。
4. 同じイベントIDの再送で200と `duplicate: true` が返る。
5. `/cee/recent` と `/cee/article?id=...` で要約・本文を取得できる。
6. 管理画面では下書きで、公開URL・公開API・RSS・サイトマップから見えない。

その後、CEE01の通常の会話で場所を伝えてセッションを終了し、記憶保存を確認します。通信失敗時は `data/mark6_queue/` に残り、次回起動時の再送対象になります。

## 5. 運用

通常はCEE記憶を非公開のまま利用します。公開したい場合だけ、master管理者が個人情報を含め内容を確認し、既存管理画面から手動で公開します。新規API記事には未承認時の公開防止が適用されます。旧CEE記事は自動変更しないため、下書き状態を確認してください。

読み取り鍵・共有鍵を持つ機器はCEE記憶を横断取得できます。CEE01 / CEE02で共有する記憶の範囲と鍵の配布先を確認してください。画像保存・`/cee/update` は未実装です。

## ローカル検証

```text
prove -Ilib t/cee_api.t
prove -Ilib t
```

ローカルHTTP試験では既存CEE01クライアントによる保存・再送・一覧・本文・キュー再送を確認しています。実サーバーのApache構成、HTTPS、Pi上の実機接続は配置後の確認対象です。
