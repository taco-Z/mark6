# MARK6 AI Integration Plan

AI support should be optional and file-based, so MARK6 remains usable without an API key or database.

## Phase 1

Admin-side assist features:

- Generate article title ideas.
- Generate article summary.
- Suggest tags.
- Rewrite intro from body.
- Extract SEO description.

Store generated metadata in each article JSON:

```json
{
  "ai": {
    "summary": "",
    "suggested_tags": [],
    "seo_description": "",
    "last_processed_at": ""
  }
}
```

## Phase 2

Batch tools:

- Reprocess all articles for summaries and tags.
- Find articles with missing images or missing intro.
- Generate migration reports from MARK5 data.

## Phase 3

Drafting workflow:

- Admin writes rough notes.
- AI proposes title, intro, tags, and draft body.
- Human must explicitly save/publish.

## Design Rules

- AI must never publish automatically.
- AI output should be stored as draft suggestions until accepted.
- API keys must never be stored in public files.
- Keep provider integration isolated under `lib/Mark6/AI/`.

