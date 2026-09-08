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
  "content_checker": {
    "profile": "default",
    "text_limits": {
      "default": { "description_min_chars": 100, "body_min_chars": 500 },
      "ja": { "description_min_chars": 60, "body_min_chars": 300 }
    },
    "slug_check": { "enabled": true, "allow_id_slug": false },
    "profiles": {
      "location_based": {
        "required_metadata": ["location.city"],
        "metadata_rules": { "location.city": { "level": "recommended" } }
      },
      "media_based": {
        "require_capabilities": { "video": "media.id" }
      }
    }
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
  },
  "navigation": {
    "header": {
      "ja": [{ "label": "このサイトについて", "url": "/about/", "enabled": true }],
      "en": [{ "label": "About", "url": "/en/about/", "enabled": true }]
    },
    "footer": {
      "ja": [{ "label": "プライバシー", "url": "/privacy/", "enabled": true }],
      "en": [{ "label": "Privacy", "url": "/en/privacy/", "enabled": true }]
    }
  },
  "free_space": {
    "home_bottom": {
      "ja": { "enabled": false, "html": "" },
      "en": { "enabled": false, "html": "" }
    },
    "article_end": {
      "ja": { "enabled": false, "html": "" },
      "en": { "enabled": false, "html": "" }
    },
    "after_kiosk": {
      "ja": { "enabled": false, "html": "" },
      "en": { "enabled": false, "html": "" }
    }
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
    "ja": {
      "enabled": true,
      "mode": "manual",
      "items": [
        {
          "label": "ガイドブック",
          "type": "amazon",
          "keyword": "大分 ガイドブック"
        }
      ]
    },
    "en": {
      "enabled": true,
      "mode": "manual",
      "items": [
        {
          "label": "Plan an Oita trip",
          "type": "url",
          "url": "https://example.com/oita"
        }
      ]
    }
  },
  "updated_at": ""
}
```

`home.kiosk` is keyed by the configured site languages. `mode: "manual"` displays that language's home-specific items. `mode: "auto"` reuses up to five unique Kiosk items from published articles in the same language. It never falls back to another language. The original flat home Kiosk structure remains readable as Japanese data.

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
    "kiosks": {
      "ja": {
        "lang": "ja",
        "items": [
          {
            "label": "Search label",
            "keyword": "search keyword",
            "reason": "Why this link fits the article"
          }
        ],
        "last_processed_at": ""
      }
    },
    "last_processed_at": ""
  },
  "kiosk": {
    "ja": {
      "enabled": true,
      "items": [
        {
          "label": "ガイドブック",
          "type": "amazon",
          "keyword": "大分 ガイドブック"
        }
      ]
    },
    "en": {
      "enabled": true,
      "items": [
        {
          "label": "Hotels near Oita",
          "type": "url",
          "url": "https://example.com/oita-hotels"
        }
      ]
    }
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

`kiosk` is a lightweight post-article link hub keyed by language. MARK6 never falls back to another language's Kiosk. `type: "amazon"` URL-encodes `keyword` and uses the configured Amazon search URL; `type: "url"` opens the stored HTTP or HTTPS URL unchanged. MARK6 does not store product price, stock, reviews, or images. When `dat/config.json` has `kiosk.affiliate_tag`, MARK6 appends it as the Amazon `tag` parameter.

The original flat article structure (`kiosk.enabled` and `kiosk.items`) remains readable as Japanese Kiosk data. Items without `type` are treated as Amazon items when they contain `keyword`. Editing and saving an old article upgrades its Kiosk to the language-keyed structure without requiring a batch migration.

AI Kiosk suggestions are stored separately under `ai.kiosks.<lang>.items` until an admin applies them. Older `kiosk_items` results remain readable for compatibility, but MARK6 writes new results with `items`. Japanese suggestions become Amazon items. Suggestions for other languages become incomplete URL items for an administrator to finish, so AI-generated URLs are never published automatically. The optional `reason` is kept only for admin review.

## Fixed Page

Fixed pages share `dat/articles/<id>.json` and the article editor, but use `"type": "page"`. They do not appear in article lists, feeds, related content, or tag results. The default-language URL is `/<slug>/`; other languages use `/<lang>/<slug>/`.

`navigation.header` and `navigation.footer` are keyed by language and never fall back to another language. Each item has `label`, `url`, and `enabled`. Internal root-relative URLs are combined with the configured site base URL; HTTP(S) URLs are kept as entered.

`free_space` supports only `home_bottom`, `article_end`, and `after_kiosk`. Each slot is keyed by language and never falls back. Its HTML is trusted administrator input and is rendered only when that language entry has `enabled: true`.

## Content Checker

The optional `content_checker` block controls the generic Content Check engine. The checker uses the configured profile and language-aware text limits, while profile rules describe optional capabilities and metadata. Site-specific rules belong here rather than in the checker code.

Issues are emitted with a structured code, severity (`P0`, `P1`, `P2`, `P3`, or `INFO`), field, category, and human-readable message. `INFO` provenance findings such as a missing imported source description do not increase `risk_score`.

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
