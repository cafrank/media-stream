# media-service: paged search for the catalog, and RecordPool on top of it

- **Issue:** #16 (part of epic #1)
- **Date:** 2026-09-26
- **Status:** Implemented

## Goal

RecordPool loads one page of tracks at a time instead of the whole catalog. Search and the genre and version
filters run in MongoDB, not in the browser. Today `GET /api/media` returns all 40,147 documents (13.8 MB), and
RecordPool fetches them all, filters them in the browser and builds its dropdowns from them.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Endpoint | New `GET /api/media/search`, plus `GET /api/media/facets` | Planned in `docs/design/RecordPool.md` §4.3. `GET /api/media` keeps returning the full array, so `media-test.sh`, `record-pool-test.sh` and `MediaServiceApplicationTests` don't change. Spring matches the literal paths before `/{title}`, so a title lookup for the word "search" or "facets" no longer works. That is accepted. |
| Sort | Newest first: `_id` descending | Record pools show the latest releases first. An ObjectId starts with its creation time, so `_id` order is insert order. |
| `q` | Case-insensitive substring match on `title` OR `artist`, with the input escaped as a regex literal | Behaves the same as today's client-side search. Measured at 40–65 ms over 40k documents with no index. A text index is word-based, so "nirv" would stop matching "Nirvana". |
| `genre`, `version` | Exact match on `genre` and `remix` | Same as the current dropdowns. The genre values are messy ("AFRO BEATS", "AFROBEATS", ...) and are shown as stored. Cleaning them up is out of scope. |
| Page size | `size` defaults to 50, allowed 1–200. `page` counts from 0 and must be ≥ 0. | Anything else gets 400 |
| Paging | skip/limit plus `countDocuments` for `total` | skip 40,000 measured at 14 ms, so cursor paging isn't needed at this size |
| Indexes | `{genre: 1, _id: -1}` and `{remix: 1, _id: -1}`, created at startup with `ensureIndex` | Filtered pages come back already sorted. Boot 2.7 has `auto-index-creation` off, so they are created explicitly (`MongoIndexConfig`). `ensureIndex` is idempotent. radio-service reads the same collection, and extra indexes don't affect it. |
| Schema | No change to the Mongo documents | radio-service (NetRadio) maps the same `media` collection itself |

## API

`GET /api/media/search?q=&genre=&version=&page=0&size=50`

```json
{ "items": [ MediaResponse, ... ], "page": 0, "size": 50, "total": 40147 }
```

- **Parameters:** all are optional. An empty `q`, `genre` or `version` means no filter.
- **`items`:** the same `MediaResponse` JSON as `GET /api/media` (snake_case).
- **`total`:** counts every match, not just this page.
- **Bad `page` or `size`:** 400.

`GET /api/media/facets`

```json
{ "genres": ["AFRO BEATS", ...], "versions": ["Clean", ...] }
```

- **Values:** distinct non-empty `genre` and `remix` values, sorted.
- **Cost:** one `distinct` per field.

## media-service changes

- **`MediaService.search(q, genre, version, page, size)`** builds the query with `MongoTemplate`.
  - `MediaQueries.criteria(q, genre, version)` is a pure static function, so it can be tested without MongoDB.
  - The search runs `find` with sort, skip and limit, plus `count`, and returns a `MediaPage`.
- **`MediaService.facets()`** uses `findDistinct` on `genre` and `remix`, drops null and empty values, and sorts the rest.
- **New DTOs:** `MediaPage` (`items`, `page`, `size`, `total`) and `MediaFacets` (`genres`, `versions`). They use Lombok, like the existing DTOs.
- **`MediaController`:** `@GetMapping("/search")` and `@GetMapping("/facets")`. Parameter validation returns 400 through `ResponseStatusException`.
- **`config/MongoIndexConfig`:** ensures the two indexes when the application is ready.
- **Helm test:** `charts/media-service/templates/tests/test-connection.yaml` calls `/api/media/search?size=1` instead of `/api/media`, so `helm test` no longer pulls the whole catalog.

## RecordPool changes

- **`services/catalogApi.ts`:**
  - `searchTracks({q, genre, version, page, size}, signal)` returns `{tracks, page, size, total}`.
  - `fetchFacets(signal)` returns `{genres, versions}`.
  - `fetchTracks` (the full list) is removed.
- **`RecordPoolApp.tsx`:**
  - The dropdowns come from `fetchFacets`.
  - The list holds the pages loaded so far. `FlatList` `onEndReached` loads the next page while `tracks.length < total`.
  - Changing the search text (debounced 300 ms), the genre or the version resets to page 0 and aborts the request in flight, so a slow old response can't overwrite a new one.
  - A footer shows "Loading more..." during a page load. The count "N tracks" comes from `total`.
  - The in-browser filtering, `searchIndex` and `useDeferredValue` are removed.
  - `togglePlay` currently looks the track up in `tracks`. It keeps working, because the row being played is always one that has been loaded.

## Error handling

- **media-service:** 400 for bad paging parameters. Mongo errors produce the existing 500.
- **RecordPool:**
  - A failed page or facets request shows in the existing error banner.
  - The pages already loaded stay.
  - Scrolling again retries a page that failed.

## Testing

- **media-service unit tests** (plain JUnit and MockMvc with a mocked `MediaService`; no MongoDB):
  - `MediaQueries.criteria`:
    - no filters gives an empty criteria
    - `q` gives a case-insensitive regex on title OR artist
    - regex metacharacters in `q` (`a.b`, `(`, `*`) are matched literally
    - `genre` and `version` match exactly and combine with AND
  - Controller:
    - `/search` default and explicit paging is passed to the service
    - `size=0`, `size=201` and `page=-1` get 400
    - the response shape
    - `/facets` shape
- **Existing tests:** the two `@SpringBootTest` Testcontainers tests already error on this machine, because Testcontainers can't reach Docker 29. That is not caused by this change, and they are left as they are.
- **BorgCloud (real MongoDB):**
  - `media-test.sh` checks:
    - `/search?size=5` gives 5 items and `total` equal to the size of the full list
    - `/facets` is non-empty
    - `size=0` gives 400
  - Parity check (script): for several `q`, `genre` and `version` combinations, the server's `total` equals the count jq computes from the full `GET /api/media` list with the old client-side rules.
  - Timing: `/search?page=0&size=50` in < 100 ms, measured on the VIP.
- **Browser (headless Chrome):**
  - The first load transfers kilobytes instead of 13.8 MB.
  - Scrolling to the end loads page 2.
  - Typing "nirvana" shows the same tracks as before.
  - Picking a genre filters the list.

## Out of scope

- Cleaning up genre values.
- `{songId}` routes, entitlements and auth.
- Removing the unpaged `GET /api/media`. It stays until nothing depends on it.
- Fixing Testcontainers for Docker 29.
