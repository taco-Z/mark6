# MARK6 Data Schema

MARK6 stores all CMS data as UTF-8 JSON.

## Config

`dat/config.json`

```json
{
  "version": 1,
  "site": {
    "title": "MARK6 Site",
    "base_url": "",
    "language": "ja"
  },
  "features": {
    "tags": true,
    "newest": true,
    "popular": true,
    "ai": false
  },
  "display": {
    "articles_per_page": 20,
    "mini_articles": 15
  },
  "kiosk": {
    "provider": "amazon",
    "affiliate_tag": ""
  }
}
```

## Home

`dat/home.json`

```json
{
  "title": "Home",
  "body": "",
  "show_articles": true,
  "updated_at": ""
}
```

## Article

`dat/articles/<id>.json`

```json
{
  "id": "1710000000",
  "type": "article",
  "status": "published",
  "title": "",
  "slug": "",
  "tags": [],
  "image": "",
  "intro": "",
  "body": "",
  "writer_id": "",
  "created_at": "",
  "updated_at": "",
  "sort_order": 10,
  "ai": {
    "summary": "",
    "suggested_tags": [],
    "last_processed_at": ""
  },
  "kiosk": {
    "enabled": true,
    "items": [
      {
        "label": "Search label",
        "keyword": "search keyword"
      }
    ]
  },
  "source": {
    "mark5_id": "",
    "mark5_line": ""
  }
}
```

`sort_order` is optional. Lower numbers appear first in article lists. Existing articles without `sort_order` continue to fall back to the legacy newest-first order until an admin reorder operation writes explicit values.

`kiosk` is a lightweight post-article search link component. MARK6 does not store product price, stock, reviews, or images. Site-specific product wording belongs in each article JSON item; core rendering only checks `enabled`, reads `label` and `keyword`, URL-encodes the keyword, and generates an Amazon search URL. When `dat/config.json` has `kiosk.affiliate_tag`, MARK6 appends it as the Amazon `tag` parameter.

## Users

`dat/users.json`

```json
{
  "version": 1,
  "users": [
    {
      "id": "1710000000",
      "name": "admin",
      "rank": "master",
      "password_hash": "",
      "legacy_password_hash": "",
      "password_reset_required": true,
      "created_at": "",
      "updated_at": ""
    }
  ]
}
```

## Sessions

`dat/sessions/<session_id>.json`

```json
{
  "id": "",
  "user_id": "",
  "created_at": "",
  "expires_at": "",
  "ip_hash": "",
  "user_agent_hash": "",
  "csrf_token_hash": ""
}
```

## Logs

Use JSON Lines for append-friendly logs:

```text
dat/logs/access.jsonl
dat/logs/login.jsonl
dat/logs/audit.jsonl
```

Each line is one JSON object.
