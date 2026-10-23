# 任意のMemory拡張

## 構成

MARK6本体は、記事の下書き・非公開・承認・公開判定を提供する。Memory APIは任意の追加ファイルに分離し、SATi固有のID・ノード名・認証鍵名は拡張内の接続プロファイルに閉じ込める。テーマ編集は拡張から独立している。

| ファイル | 役割 |
|---|---|
| lib/Mark6/Article.pm、admin/articles.cgi | 汎用の承認と非公開保護。撤去しない |
| lib/Mark6/Extensions.pm | 拡張ファイルの有無を確認して読み込む本体側の窓口 |
| admin/settings.cgi | インストール済みMemory拡張の設定を表示。変更はmasterのみ |
| extensions/memory/Extension.pm | 追加可能なMemory APIと設定項目、Generic／SATiプロファイル |
| public/memory.cgi | 任意のAPI入口 |
| public/sati.cgi | 旧URL互換の任意のAPI入口。同じ処理を呼ぶだけ |

APIは「拡張ファイルが存在する」「設定で有効」「操作に対応する有効な鍵」の3条件をすべて満たした時だけ利用できる。ファイルだけ追加しても、鍵だけ設定しても起動しない。フラグ省略時は無効。無効時や拡張フォルダがない時は、鍵が正しくても入口は404を返す。

拡張はアプリケーションのextensionsフォルダからだけ読み込み、datフォルダからは読み込まない。extensions自体へのHTTP配信はルートのApache設定で遮断する。

## 有効化

1. 今回修正したMARK6本体へ、追加パッケージの `extensions/memory/Extension.pm` と `public/memory.cgi` を配置する。旧URLを使う場合は `public/sati.cgi` も配置する。
2. masterでSettingsを開き、Memory extensionの「Enable authenticated memory API」をオンにする。
3. 接続プロファイルをGenericまたはSATiに選択して保存する。
4. サーバー環境変数へ追加用・取得用の別々の32文字以上のランダム鍵を設定する。鍵は画面やconfig.jsonに保存しない。

| プロファイル | 追加用鍵 | 取得用鍵 | 保存先ノード | ID接頭辞 |
|---|---|---|---|---|
| Generic | MEMORY_WRITE_TOKEN | MEMORY_READ_TOKEN | memory | memory- |
| SATi | SATI_WRITE_TOKEN | SATI_READ_TOKEN | sati-memory | sati- |

設定の形は次のとおり。enabledは初期状態では存在しないかfalse。以下はSATiを明示的に有効にする場合の例。

```json
{
  "extensions": {
    "memory": { "enabled": true, "profile": "sati" }
  }
}
```

`public/memory.cgi` と `public/sati.cgi` はどちらも設定された同一プロファイルを使う。URL名で別ストアや別権限に分かれることはない。Genericへの切替後はSATi名前空間の記憶をAPIから取得できないが、記事は削除されず、管理画面で引き続き管理できる。通常は保存開始時にプロファイルを決め、運用中の切替は意図した場合だけ行う。

## 停止・切り離し

- Settingsでスイッチをオフにして保存すると、追加・取得APIを停止する。
- ファイルごと外す場合は `extensions/memory` フォルダを撤去する。API入口が残っても404になる。入口CGIも撤去可能。
- フォルダと入口を戻し、スイッチをオンにすれば同じストアを再利用できる。元の承認状態は維持される。
- 保存済み記事は通常の `dat/articles` に残る。削除や別DBへの移動はしない。
- 未承認記事は本体の保護で非公開を維持する。承認済みで公開中の記事は公開を継続する。拡張の停止は記事公開の一括取消ではない。
- 拡張がない時は設定欄を表示しない。通常の設定保存で既存の拡張設定を消さない。

## 本体に残す保護

記事に `review_required`、`review`、または旧形式の `memory` 情報がある場合、本体は承認が必要な記事として扱う。ノード名やSATiというサービス名によって判定しない。旧形式のSATi記事はもともとmemory／review情報を持つため、移行・ファイル削除なしで保護される。

公開には `status: published`、非公開指定がないこと、`review.state: approved` と承認者記録が必要。masterが既存の記事編集画面でPublishedとして保存すると承認を記録し、Draftに戻すと承認を解除する。承認対象の記事を移動・編集しても承認必須の性質は保持する。本体は承認対象記事の外部AI処理を停止し、拡張撤去後もこの制限を維持する。

## API

- POST `public/memory.cgi?op=write`：追加用Bearer鍵。JSONはclient_event_id、title、summary、bodyのみ。未承認・非公開で同じ記事ストアへ保存。
- GET `public/memory.cgi?op=article&id=...`：取得用Bearer鍵。設定されたプロファイルの記事のみを取得。
- 記事の自動公開・APIからの承認・上書き更新は不可。同じイベントの再送は既存記事を上書きしない。

本文は平文として受信してHTMLをエスケープする。上限・認証・no-storeの条件は従来の初期APIから維持している。自動で個人情報を除去する機能ではないため、公開前に管理者が全言語の内容を確認する。

## 検証範囲

ファイル追加だけでは無効、有効化／停止／再有効化、master以外の設定変更拒否、CSRF、GenericとSATiの名前空間、拡張がない別のアプリコピーでの404と未承認非公開、承認済み記事の公開継続をテストする。OITA360と既存テーマを含む既存テストも実行する。

本番への配置、ブラウザでの設定画面操作、Apacheでの遮断確認、SATi送信元への組込みは未実施。

最終確認：全23本706件PASS。拡張未導入時には拡張専用テストをスキップする調整後も、対象2本101件PASS。元のD:/projects/mark6と本番データは変更していない。
