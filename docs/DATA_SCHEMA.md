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
    "shop": false,
    "ai": false
  },
  "display": {
    "articles_per_page": 20,
    "mini_articles": 15
  },
  "shop": {
    "title": "Shop",
    "paypal_id": ""
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
  "ai": {
    "summary": "",
    "suggested_tags": [],
    "last_processed_at": ""
  },
  "source": {
    "mark5_id": "",
    "mark5_line": ""
  }
}
```

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

