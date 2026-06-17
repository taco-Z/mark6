# MARK6 Specification Draft

## Goal

MARK6 updates MARK5 while keeping the core spirit:

- Ultra-lightweight CMS.
- Perl-first CGI operation.
- File-based storage.
- Easy backup without SQL.
- Small enough to understand and repair manually.

## MARK5 Inventory

MARK5 has four main CGI entry points:

- `index.cgi`: public site, article list/detail, tags, shop/cart, access log write.
- `operation.cgi`: login, logout, first setup.
- `os.cgi`: admin dashboard, article/product editing, layout/CSS/meta/settings/user/log editing.
- `uploader.cgi`: file upload/list/delete.

Shared behavior is handled by:

- `lib/cgi-lib.pl`: CGI parameter parsing and upload handling.
- `lib/twlauncher5.pl`: HTML wrapper and column/window layout rendering.
- `lib/Jcode.pm` and `lib/mimew.pl`: older Japanese encoding/mail helpers.

MARK5 stores most data in `dat/*.cgi` with `==` field separators and escape tokens such as `<equal>`, `<br>`, and `<return>`.

## Preserve

- Public page rendering with articles, tags, newest list, popular list.
- Admin dashboard.
- User ranks: `master`, `staff`, `writer`.
- File/image upload workflow.
- Optional shop/cart concept, but keep it isolated so normal CMS use stays tiny.
- PC/smart responsive output concept.
- Backup by copying directories.

## Change

- Replace delimiter data files with JSON.
- Replace credential cookies with server-side sessions.
- Replace old `crypt()` password hashes with modern password hashes.
- Remove external HTTP script dependencies where possible.
- Separate public, admin, storage, rendering, and utility modules.
- Make migration from MARK5 repeatable.

## Proposed Directory Layout

```text
mark6/
  public/
    index.cgi
    assets/
      css/
      img/
  admin/
    index.cgi
    login.cgi
    upload.cgi
  lib/
    Mark6/
      App.pm
      Auth.pm
      Config.pm
      DataStore.pm
      Render.pm
      Security.pm
  dat/
    config.json
    home.json
    articles/
    users.json
    logs/
    sessions/
  file/
  img/
  tools/
    migrate_mark5.pl
  docs/
```

## First Implementation Order

1. Create JSON datastore helpers.
2. Create session-based auth.
3. Implement public article list/detail.
4. Implement admin article CRUD.
5. Implement MARK5 migration script.
6. Rebuild uploader.
7. Port layout/settings screens.
8. Decide whether shop/cart belongs in MARK6 core or an optional module.

## Compatibility Notes

MARK5 URLs use `index.cgi?order=focus&tar=<id>`.
MARK6 should initially keep compatible public aliases so migrated sites do not break:

- `order=index`
- `order=article`
- `order=focus&tar=<id>`

Internally, MARK6 can route these to cleaner handlers.

