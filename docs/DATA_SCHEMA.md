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
  "nodes": {
    "articles": {
      "nav": true,
      "labels": {
        "ja": "記事",
        "en": "Articles"
      }
    }
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
  "kiosk": {
    "enabled": true,
    "mode": "manual",
    "items": [
      {
        "label": "Search label",
        "keyword": "search keyword"
      }
    ]
  },
  "updated_at": ""
}
```

`home.kiosk` uses the same lightweight `label` and `keyword` item structure as article Kiosk. `mode: "manual"` displays the home-specific items stored in `home.kiosk.items`. `mode: "auto"` reuses up to five unique Kiosk items from published articles, so a site can switch from a curated home Kiosk to an article-driven home Kiosk without changing the public template.

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
  "tag_langs": {
    "ja": [],
    "en": []
  },
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
    "kiosk": {
      "kiosk_items": [
        {
          "label": "Search label",
          "keyword": "search keyword",
          "reason": "Why this search link fits the article"
        }
      ],
      "last_processed_at": ""
    },
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

`tag_langs` is optional. Public pages use `tag_langs[current_lang]` when available and fall back to `tags`.

`nodes` stores section display labels outside article JSON. The key is the URL segment used by `article.node`; `labels` is used in public navigation, and `nav` controls whether the section appears in the header.

`kiosk` is a lightweight post-article search link component. MARK6 does not store product price, stock, reviews, or images. Site-specific product wording belongs in each article JSON item; core rendering only checks `enabled`, reads `label` and `keyword`, URL-encodes the keyword, and generates an Amazon search URL. When `dat/config.json` has `kiosk.affiliate_tag`, MARK6 appends it as the Amazon `tag` parameter.

AI Kiosk suggestions are stored under `ai.kiosk.kiosk_items` until an admin applies them. Applying suggestions merges unique `label` and `keyword` pairs into `kiosk.items`; the optional `reason` is kept only for admin review.

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
