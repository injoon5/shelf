# API response fixtures

Real response bodies, captured from the ij5.dev handlers (branch `shelf-apps`)
running over SQLite with every migration applied. Timestamps are epoch
milliseconds; `version` and the ETag are opaque strings. Every error body is
`{ "error": "<one sentence>", ...extra }`.

| File | Request | Status |
|---|---|---|
| `apps.json` | `GET /api/apps` (has `ETag: "…"`; `If-None-Match` with it, `W/` or not → `304`, empty body) | 200 |
| `app.json` | `GET /api/apps/{slug}` | 200 |
| `app-put.json` | `PUT /api/apps/{slug}` (JSON or `text/x-swift`) | 201 created / 200 updated |
| `app-revert.json` | `POST /api/apps/{slug}/revert` | 200 |
| `app-delete.json` | `DELETE /api/apps/{slug}` (`?data=delete` also deletes its data) | 200 |
| — | `GET /api/apps/{slug}/source` → raw file, `text/x-swift; charset=utf-8` | 200 |
| `data.json` | `GET /api/apps/{slug}/data` | 200 |
| `data-since.json` | `GET /api/apps/{slug}/data?since=1` (tombstone `value: null`) | 200 |
| `data-key.json` | `GET /api/apps/{slug}/data/{key}` (the bare JSON value) | 200 |
| `data-put.json` | `PUT /api/apps/{slug}/data/{key}` | 200 |
| `data-delete.json` | `DELETE /api/apps/{slug}/data/{key}` (idempotent) | 200 |
| `data-batch.json` | `POST /api/apps/{slug}/data` `{ set, delete }` | 200 |
| `install-key.json` | `POST /api/install-keys` `{ slug? }` | 201 |
| `install-key-status-waiting.json` | `GET /api/install-keys/{id}` | 200 |
| `install-key-status-used.json` | `GET /api/install-keys/{id}` after an install | 200 |
| `install-key-revoke.json` | `DELETE /api/install-keys/{id}` | 200 |
| `error-400.json` | body is not JSON | 400 |
| `error-401.json` | wrong admin token | 401 |
| `error-401-missing.json` | no `Authorization` header | 401 |
| `error-401-key.json` | any install-key failure (used, expired, burned, wrong, wrong slug or route) | 401 |
| `error-404.json` | unknown app (also unknown/revoked install key: "No install key with that id.") | 404 |
| `error-404-revert.json` | revert with no history | 404 |
| `error-409.json` | create key on a taken slug | 409 |
| `error-413.json` | app source over 256 KB | 413 |
| `error-413-data.json` | data value over 64 KB (also "An app can keep at most 1,000 keys." / "An app can store at most 5 MB of data.") | 413 |
| `error-422.json` | `text/x-swift` with no `// Name:` | 422 |
| `error-422-json.json` | invalid JSON fields | 422 |
| — | more than 20 live install keys | 429 |
