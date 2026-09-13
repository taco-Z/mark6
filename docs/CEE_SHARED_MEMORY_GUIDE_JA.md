# CEE共有記憶 API 導入・運用手順

## 1. MARK6へ配置するもの

MARK6の public/cee.cgi を公開ディレクトリへ置きます。

続いてWebサーバーのRewrite設定へ、通常のMARK6公開ルートより先に次を追加します。

```apache
RewriteRule ^cee/(write|recent|article|update)$ public/cee.cgi?op=$1 [L,QSA]
```

同じ内容は docs/CEE_MEMORY_APACHE.conf にもあります。

## 2. トークンを設定する

MARK6サーバーのCGI実行環境へ、ランダムな長い秘密文字列を設定します。

```text
CEE_SECRET_TOKEN=ここに秘密文字列
```

Pi側には同じ値を設定します。

```bash
export CEE_MARK6_TOKEN='ここに同じ秘密文字列'
```

常用するなら、PiのRuntimeを起動するサービス設定またはログイン用環境設定へ保存してください。hardware.yaml やGitには書きません。

## 3. Pi側の有効化

config/hardware.yaml にMARK6設定は入っています。Pi上では、実運用用のローカル設定にURLを確認してから起動します。

```yaml
mark6:
  enabled: true
  base_url: https://ceelog.oita360.com
```

トークンまたはURLが無い場合、CEE01は安全に同期を止めるだけで、会話・STOP・Follow安全制御は動き続けます。

## 4. 動作確認

1. CEE01を起動する。
2. 「今、岡城跡公園にいるよ」のように場所を伝える。
3. Visionで一度観察する。
4. 「またね」または「終了」と言う。
5. MARK6管理画面の記事一覧に、下書きの CEE Memory: 岡城跡公園 ができていることを確認する。

通信が一時的に失敗した場合は、Piの data/mark6_queue/ にJSONが残ります。次回起動時に自動再送されます。

## 5. 運用上の注意

- CEE記憶記事は公開しない。MARK6でも下書きのまま確認・編集する。
- ロボットの身体制御はMARK6通信を待たない。
- CEE02接続は、同じトークンとこのAPIを使う。CEE02専用のDBは不要。
- /cee/update と画像保存はPhase 3 / Phase 2の拡張予定です。
