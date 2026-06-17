# Migration From MARK5

## Source Summary

MARK5 source path reviewed:

```text
D:\projects\mark5\MARK5 1.0
```

Important MARK5 data files inferred from the code:

- `dat/user.cgi`
- `dat/ini.cgi`
- `dat/index.cgi`
- `dat/article.cgi`
- `dat/article_log.cgi`
- `dat/shop_article.cgi`
- `dat/extra.cgi`
- `dat/meta.cgi`
- `dat/handf.cgi`
- `dat/lang_set.cgi`
- `dat/lang_set_jp.cgi`
- `dat/lang_set_en.cgi`
- `dat/access_log.cgi`
- `dat/login_log.cgi`
- `cart/*.cgi`

MARK5 article line format:

```text
id==tags==pic==title==intro==body==writer==admit
```

MARK5 shop article line format:

```text
id==tags==pic==title==intro==body==price==stock==admit
```

MARK5 user line format:

```text
user_id==rank==user==crypt_password
```

## Migration Rules

### Escapes

MARK5 stores escaped content:

- `<equal>` means `=`
- `<br>` means newline in article fields
- `<return>` means newline in larger template/meta fields

The migration script must decode these tokens into normal JSON strings.

### Articles

MARK5 `dat/article.cgi` should become one JSON file per article:

```text
dat/articles/<id>.json
```

Each article should store:

- `id`
- `title`
- `slug`
- `tags`
- `image`
- `intro`
- `body`
- `writer_id`
- `status`
- `created_at`
- `updated_at`
- `source.mark5_line`

`admit == 1` becomes `status: "published"`.
`admit == 0` becomes `status: "draft"`.

### Users

MARK5 password hashes should not be reused as-is for new logins.

Migration options:

1. Import user names and ranks only, then require password reset.
2. Temporarily keep the MARK5 hash in `legacy_password_hash` and upgrade on next successful login.

Recommended default: option 1.

### Settings

MARK5 `dat/ini.cgi` should become `dat/config.json`.

Known keys:

- `site_title`
- `number_miniart`
- `tag_sw`
- `tag_title`
- `shop_sw`
- `shop_title`
- `paypal_id`
- `news_sw`
- `rank_sw`

### Logs

MARK5 logs can be preserved as archived text or converted to JSON Lines:

```text
dat/logs/access.jsonl
dat/logs/login.jsonl
```

Keep raw source copies under:

```text
dat/legacy/mark5/
```

## Migration Tool Plan

`tools/migrate_mark5.pl` should accept:

```text
perl tools/migrate_mark5.pl --from D:\projects\mark5\MARK5 1.0 --to D:\projects\mark6
```

The tool should:

1. Validate source files.
2. Create MARK6 `dat/` directories.
3. Decode MARK5 escaped fields.
4. Write JSON with stable key order.
5. Copy `img/` and `file/` content when present.
6. Produce a migration report.

