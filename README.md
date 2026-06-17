# MARK6

MARK6 is the next version of the MARK5 lightweight CMS.

The project keeps the original ideas:

- Lightweight CGI-first architecture, mainly Perl.
- Easy backup and restore with plain files.
- No SQL database dependency.

MARK6 changes the data layer from MARK5's delimiter-separated `.cgi` data files to JSON files, and redesigns admin authentication so login credentials are never stored in client-side cookies.

## First Milestone

The first implementation milestone is a minimal CMS loop:

1. Public article list and article detail pages.
2. Admin login with server-side sessions.
3. Article create/edit/delete using JSON files.
4. MARK5 data migration script.
5. File backup by copying `dat/`, `file/`, `img/`, and config files.

## Documents

- `docs/MARK6_SPEC.md`
- `docs/MIGRATION_FROM_MARK5.md`
- `docs/DATA_SCHEMA.md`
- `docs/SECURITY.md`
- `docs/AI_INTEGRATION.md`

