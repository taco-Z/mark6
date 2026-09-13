# CEE Shared Memory API 仕様書

## 目的

CEE01 と将来の CEE02 が、MARK6 の既存「通常記事」をエピソード記憶として安全に読み書きするためのAPIです。専用データベースや公開記事は作りません。

保存先は dat/articles/ の通常記事JSONです。CEE記事には cee.source と cee.client_event_id のメタデータを付け、status は常に draft です。

## 認証

全エンドポイントで次のHTTPヘッダーが必須です。

```text
Authorization: Bearer <shared-secret>
```

MARK6サーバー環境変数 CEE_SECRET_TOKEN と、CEE本体環境変数 CEE_MARK6_TOKEN に同じ値を設定します。トークンや発話本文はログへ出力しません。

## エンドポイント

| Method | Path | 内容 |
| --- | --- | --- |
| POST | /cee/write | CEEメモリ記事を新規保存 |
| GET | /cee/recent?limit=20 | 新しい順の要約一覧 |
| GET | /cee/article?id=cee-... | 1記事の本文取得 |
| POST | /cee/update | Phase 3: CEE02向け。現段階では未実装 |

### POST /cee/write

```json
{
  "client_event_id": "一意なセッションID",
  "title": "CEE Memory: 岡城跡公園",
  "description_html": "短い要約",
  "body_html": "詳細本文",
  "source": "cee01",
  "status": "draft"
}
```

- client_event_id は必須で、同じ値の再送は重複保存せず既存記事IDを返します。
- status は入力値に関わらず draft 固定です。
- image はPhase 2以降です。現段階では受信・保存しません。

成功例:

```json
{ "ok": true, "id": "cee-<client_event_id>" }
```

### GET /cee/recent

返す項目は id、title、summary、updated_at、source。本文は返さないため、起動時でも軽量です。

### GET /cee/article

指定記事の id、title、summary、body_html、updated_at を返します。CEE記憶以外の通常記事は取得できません。

## HTTPステータス

| Status | 意味 |
| --- | --- |
| 200 / 201 | 成功 |
| 400 | 不正なJSONまたは必須項目不足 |
| 401 | トークン不一致・未設定 |
| 404 | 未対応の操作または記事なし |

## 安全性と失敗時

- CEEはネットワーク処理をFollow/Motor制御ループから分離します。
- 送信失敗時はPiの data/mark6_queue/*.json に退避し、次回起動時に再送します。
- API未設定時はロボット本体の会話・安全制御を止めません。
- APIアクセスでCEEのオーナー顔・声サンプル、録音、カメラ画像は送信しません。
