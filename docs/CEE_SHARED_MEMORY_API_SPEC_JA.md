# CEE Shared Memory API 仕様書

CEE01 / CEE02 の記憶をMARK6の同一記事ストア `dat/articles/` に保存します。専用DBは不要です。CEE01の既存クライアント `brain_v2/mark6_client.py` の形式を維持します。

## 有効化と認証

`public/cee.cgi` を配置し、CGI実行環境に `CEE_SECRET_TOKEN` を設定すると利用できます。32文字以上のランダムな秘密値を推奨します。Pi側の `CEE_MARK6_TOKEN` に同じ値を設定します。

```text
Authorization: Bearer <secret>
```

任意で `CEE_WRITE_TOKEN` と `CEE_READ_TOKEN` を設定すると、それぞれ書き込み・読み取りの専用鍵が共通鍵より優先されます。専用鍵が未設定の操作は `CEE_SECRET_TOKEN` を使用します。CEE01の現行クライアントは共通鍵1個で動作します。

`CEE_API_ENABLED=0`（または `false` / `off`）で停止できます。停止しても記事は保持され、公開判定・承認保護はMARK6本体で有効です。鍵の未設定時は401、明示的な停止時は404です。CGIの `REDIRECT_` / `REDIRECT_REDIRECT_` 付き環境変数も扱います。

## エンドポイント

| Method | Path | 内容 |
| --- | --- | --- |
| POST | /cee/write | 記憶を未承認・非公開で保存 |
| GET | /cee/recent?limit=20 | 新しい順の要約一覧 |
| GET | /cee/article?id=cee-... | 記憶本文の取得 |
| POST | /cee/update | 将来用。現在は404 |

直接CGIを利用する場合は `public/cee.cgi?op=write` 等でも同じ認証が必要です。

### POST /cee/write

```json
{
  "client_event_id": "session_01",
  "title": "CEE Memory: 岡城跡公園",
  "description_html": "短い要約",
  "body_html": "場所: 岡城跡公園<br>石垣と木々が見える。",
  "source": "cee01",
  "status": "draft"
}
```

- `Content-Type: application/json` が必要です。本文はUTF-8、最大20,000バイトです。
- `client_event_id` は必須。英数字・ハイフン・アンダースコアの1～96文字です。CEE01 / CEE02間でも重複しないUUID等を使ってください。
- `body_html` は空白以外の文字が必要で、最大10,000文字です。
- `title` は最大180文字（省略時 `CEE Memory`）、`description_html` は最大600文字、`source` は最大32文字（省略時 `cee`）です。文字列以外や超過値は400です。
- 互換用の `status` は入力値にかかわらず `draft` 固定です。`image` は受け取っても保存しません。その他の未対応項目は400です。
- HTMLはエスケープして保存し、属性のない `<br>` / `<br/>` だけ改行として保持します。スクリプト等は実行されません。
- 同じイベントIDの再送は200で既存IDと `duplicate: true` を返します。同時再送も排他制御し、管理者の編集・承認内容を上書きしません。
- 同じIDのCEE記憶以外の記事が存在する場合は400で保存を拒否します。

初回の応答は201です。

```json
{ "ok": true, "id": "cee-session_01" }
```

### GET /cee/recent

`limit` は正の整数、既定20、最大100です。0・負数・非数値は400です。

```json
{ "ok": true, "articles": [
  { "id": "cee-session_01", "title": "CEE Memory", "summary": "短い要約", "updated_at": "2026-10-23T00:00:00Z", "source": "cee01" }
] }
```

本文は返しません。CEE以外の記事は含めません。

### GET /cee/article

```json
{ "ok": true, "article": {
  "id": "cee-session_01", "title": "CEE Memory", "summary": "短い要約",
  "body_html": "本文", "updated_at": "2026-10-23T00:00:00Z"
} }
```

CEE以外の記事・存在しない記事は404、不正なIDは400です。

## 保存と公開

新規記事は `status=draft`、`visibility=private`、`review_required=true`、`review.state=pending` で保存します。APIは承認・公開の操作を提供しません。

既存の管理画面でmaster管理者が内容を確認して手動で公開した場合だけ公開できます。未承認は、公開URL直打ち・公開API・RSS・サイトマップ・検索から見えません。認証済みCEE APIは未承認の記憶も取得できます。

既存のCEE記憶の内容・承認状態は自動変更しません。新しい保護項目はこのAPIで新規保存した記事に付与されます。旧記事を扱う場合は既存の下書き状態を確認してください。

## HTTPステータスと個人情報

| Status | 意味 |
| --- | --- |
| 200 / 201 | 成功 / 新規保存 |
| 400 | 不正な本文・必須項目不足・ID衝突 |
| 401 | 認証失敗・鍵未設定 |
| 404 | API停止・未対応操作・記事なし |

API応答は `Cache-Control: no-store` です。エラーは本文・秘密値・内部パスを返しません。

記憶本文の個人情報を自動判定・匿名化する機能はありません。共有鍵または読み取り鍵を持つ接続先はCEE記憶全体を取得できるため、信頼できる機器だけに設定します。顔・声サンプル、録音、画像をAPIで保存する機能はありません。公開前に管理者が本文と要約を確認してください。

CEE側の通信は身体制御から分離します。失敗時は既存の `data/mark6_queue/` に退避し、次回起動時に再送します。API未設定でも会話・安全制御を停止しません。
