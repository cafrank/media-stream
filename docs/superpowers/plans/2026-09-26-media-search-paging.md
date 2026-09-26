# Paged catalog search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** media-service gets paged, filtered search (`GET /api/media/search`) and a facets endpoint (`GET /api/media/facets`). RecordPool loads one page at a time instead of the whole 40k-track catalog.

**Architecture:**
- **Queries:** a pure `MediaQueries.criteria` builds the Mongo `Criteria`. `MediaService` runs it through `MongoTemplate` with `_id`-descending sort, skip/limit and a count.
- **Indexes:** two compound indexes are ensured at startup.
- **RecordPool:** a `useTrackSearch` hook owns paging, the 300 ms debounce and request cancellation. `RecordPoolApp` renders its pages in the existing `FlatList`.

**Tech Stack:**
- media-service: Spring Boot 2.7.2, spring-data-mongodb 3.4.2, JUnit 5, Mockito, MockMvc, Lombok, Java 16
- RecordPool: Expo SDK 53 web (React Native Web, TypeScript)
- BorgCloud: bash test scripts with curl and jq, and headless Chrome through puppeteer-core

**Spec:** `docs/superpowers/specs/2026-09-26-media-search-paging-design.md`

## Global Constraints

- **Search endpoint:** `GET /api/media/search?q=&genre=&version=&page=0&size=50` returns `{ "items": [MediaResponse...], "page", "size", "total" }`.
- **Facets endpoint:** `GET /api/media/facets` returns `{ "genres": [...], "versions": [...] }`, with distinct non-empty values, sorted.
- **Parameters:**
  - `size` defaults to 50 and must be 1–200. `page` defaults to 0 and must be ≥ 0. Anything else gets 400.
  - An empty `q`, `genre` or `version` means no filter.
- **Matching:**
  - `q` is a case-insensitive substring match on `title` OR `artist`, and regex metacharacters in `q` are matched literally.
  - `genre` exactly matches Mongo field `genre`. `version` exactly matches Mongo field `remix`.
- **Sort:** `_id` descending (newest first).
- **Indexes:** `{genre: 1, _id: -1}` and `{remix: 1, _id: -1}`, ensured at application startup.
- **Unchanged:**
  - `GET /api/media` keeps returning the full JSON array.
  - The Mongo documents keep their shape. radio-service reads the same collection.
- **Deploy:** only from a clean git worktree of a commit. The main checkout has uncommitted `media-service/src/main/resources/application.properties` changes (port 8084, localhost Mongo) that must not go into an image.
- **Commits:** end every commit message with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Never `git add` the user's unrelated uncommitted files: `.gitignore`, `.idea/workspace.xml`, `README`, `docs/borg-cloud-runbook.md` (partly), `GcsSignUrl.java`, `application.properties`.
- **Stash:** don't use bare `git stash`. The user's working changes must not move.

## Review Focus

1. **`q` with regex metacharacters** (`a.b`, `(`, `*`, `\`): should match literally and return 200, not 500. Task 1 unit test; Task 5 cluster parity for `a.b` and `(`.
2. **A stale response overwriting a newer search:** type "nir", then "nirvana". The list must show the "nirvana" results even if the "nir" response arrives last. Task 6: abort on change, and only the current controller writes state.
3. **`onEndReached` firing twice** before the first page append re-renders: rows must not be duplicated. Task 6: a `loadingRef` guard. Task 6 browser check: no duplicate keys after scrolling.
4. **A filter that matches nothing** (`q=zzzzqqq`): `total: 0`, empty `items`, and "No Tracks Found" in the UI, not "Loading tracks..." forever. Task 3 controller test; Task 6 browser check.
5. **Non-numeric `size` or `page`** (`size=abc`): 400 from Spring's type conversion, not 500. Task 3 controller test.

---

## File Structure

**media-service** (`media-service/src/main/java/com/sparkle/mediaservice/...`):
- Create `service/MediaQueries.java`: pure criteria builder for q, genre and version.
- Create `dto/MediaPage.java`: `{items, page, size, total}`.
- Create `dto/MediaFacets.java`: `{genres, versions}`.
- Modify `service/MediaService.java`: add a `MongoTemplate` field and the `search(...)` and `facets()` methods.
- Modify `controller/MediaController.java`: add `GET /search` and `GET /facets` with validation.
- Create `config/MongoIndexConfig.java`: ensures the two indexes on `ApplicationReadyEvent`.
- Tests (`media-service/src/test/java/com/sparkle/mediaservice/...`):
  - `service/MediaQueriesTests.java`
  - `service/MediaServiceSearchTests.java`
  - `controller/MediaControllerSearchTests.java`
  - `config/MongoIndexConfigTests.java`

**Cluster checks:**
- Modify `charts/media-service/templates/tests/test-connection.yaml`: the Helm test calls `/api/media/search?size=1`.
- Modify `borg-cloud/05-media/media-test.sh`: checks for search, facets, 400, the indexes, parity with the old client rules, and latency.

**RecordPool** (`record-pool/`):
- Modify `services/catalogApi.ts`: add `searchTracks` and `fetchFacets`, and remove `fetchTracks`.
- Create `hooks/useTrackSearch.ts`: paging, debounce and cancellation.
- Modify `app/(tabs)/RecordPoolApp.tsx`: use the hook and facets, and remove the in-browser filtering.

**Docs:**
- Modify `docs/borg-cloud-runbook.md` (only the RecordPool/media-service rows, committed without the user's uncommitted hunks).
- Modify the spec's `Status` line.

---

### Task 1: `MediaQueries.criteria`: filters as a Mongo Criteria

**Files:**
- Create: `media-service/src/main/java/com/sparkle/mediaservice/service/MediaQueries.java`
- Test: `media-service/src/test/java/com/sparkle/mediaservice/service/MediaQueriesTests.java`

**Interfaces:**
- Produces: `public static Criteria MediaQueries.criteria(String q, String genre, String version)`. Null or blank arguments mean no filter. It returns an empty `new Criteria()` when there are no filters.

- [ ] **Step 1: Write the failing test**

```java
package com.sparkle.mediaservice.service;

import org.bson.Document;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.*;

class MediaQueriesTests {

    private static Document doc(String q, String genre, String version) {
        return MediaQueries.criteria(q, genre, version).getCriteriaObject();
    }

    /** The regex that the criteria applies to one field inside an $or */
    private static Pattern regexOn(Document or, String field) {
        return (Pattern) or.get(field);
    }

    @Test
    void noFiltersMatchesEverything() {
        assertEquals(new Document(), doc(null, null, null));
        assertEquals(new Document(), doc("", " ", ""));
    }

    @Test
    void qIsCaseInsensitiveSubstringOnTitleOrArtist() {
        Document d = doc("Nirvana", null, null);
        @SuppressWarnings("unchecked")
        List<Document> or = (List<Document>) d.get("$or");
        assertEquals(2, or.size());
        Pattern title = regexOn(or.get(0), "title");
        Pattern artist = regexOn(or.get(1), "artist");
        for (Pattern p : List.of(title, artist)) {
            assertTrue((p.flags() & Pattern.CASE_INSENSITIVE) != 0);
            assertTrue(p.matcher("SMELLS LIKE NIRVANA SPIRIT").find());
            assertFalse(p.matcher("Nirv").find());
        }
    }

    @Test
    void qMetacharactersMatchLiterally() {
        for (String q : List.of("a.b", "(", "*", "\\", "[x", "a+b")) {
            @SuppressWarnings("unchecked")
            Pattern p = regexOn(((List<Document>) doc(q, null, null).get("$or")).get(0), "title");
            assertTrue(p.matcher("xx" + q + "yy").find(), q);
        }
        @SuppressWarnings("unchecked")
        Pattern dot = regexOn(((List<Document>) doc("a.b", null, null).get("$or")).get(0), "title");
        assertFalse(dot.matcher("axb").find(), "'.' must not be a wildcard");
    }

    @Test
    void genreAndVersionMatchExactly() {
        assertEquals(new Document("genre", "HOUSE"), doc(null, "HOUSE", null));
        assertEquals(new Document("remix", "Clean"), doc(null, null, "Clean"));
    }

    @Test
    void filtersCombineWithAnd() {
        Document d = doc("love", "HOUSE", "Clean");
        @SuppressWarnings("unchecked")
        List<Document> and = (List<Document>) d.get("$and");
        assertEquals(3, and.size());
        assertTrue(and.get(0).containsKey("$or"));
        assertEquals(new Document("genre", "HOUSE"), and.get(1));
        assertEquals(new Document("remix", "Clean"), and.get(2));
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd media-service && ./mvnw -q test -Dtest=MediaQueriesTests`
Expected: a compilation error, `cannot find symbol ... MediaQueries`

- [ ] **Step 3: Write the minimal implementation**

```java
package com.sparkle.mediaservice.service;

import org.springframework.data.mongodb.core.query.Criteria;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/** Catalog search filters (GET /api/media/search) as a MongoDB Criteria. */
public final class MediaQueries {

    private MediaQueries() {
    }

    /**
     * q: case-insensitive substring of title OR artist, matched literally. genre, version: exact match on
     * genre and remix. A null or blank argument is no filter; no filters is an empty Criteria.
     */
    public static Criteria criteria(String q, String genre, String version) {
        List<Criteria> filters = new ArrayList<>();
        if (q != null && !q.isBlank()) {
            Pattern literal = Pattern.compile(Pattern.quote(q), Pattern.CASE_INSENSITIVE);
            filters.add(new Criteria().orOperator(
                    Criteria.where("title").regex(literal),
                    Criteria.where("artist").regex(literal)));
        }
        if (genre != null && !genre.isBlank())
            filters.add(Criteria.where("genre").is(genre));
        if (version != null && !version.isBlank())
            filters.add(Criteria.where("remix").is(version));

        if (filters.isEmpty())
            return new Criteria();
        if (filters.size() == 1)
            return filters.get(0);
        return new Criteria().andOperator(filters);
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd media-service && ./mvnw -q test -Dtest=MediaQueriesTests && grep -o 'tests="[0-9]*" errors="[0-9]*" skipped="[0-9]*" failures="[0-9]*"' target/surefire-reports/TEST-*MediaQueriesTests.xml`
Expected: `tests="5" errors="0" skipped="0" failures="0"`

- [ ] **Step 5: Commit**

```bash
git add media-service/src/main/java/com/sparkle/mediaservice/service/MediaQueries.java media-service/src/test/java/com/sparkle/mediaservice/service/MediaQueriesTests.java
git commit -m "media-service: MediaQueries, catalog search filters as a Mongo Criteria (#16)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `MediaService.search` and `facets`, with the `MediaPage` and `MediaFacets` DTOs

**Files:**
- Create: `media-service/src/main/java/com/sparkle/mediaservice/dto/MediaPage.java`
- Create: `media-service/src/main/java/com/sparkle/mediaservice/dto/MediaFacets.java`
- Modify: `media-service/src/main/java/com/sparkle/mediaservice/service/MediaService.java` (add a field and two methods; keep everything else)
- Test: `media-service/src/test/java/com/sparkle/mediaservice/service/MediaServiceSearchTests.java`

**Interfaces:**
- Consumes: `MediaQueries.criteria(String, String, String)` (Task 1)
- Produces:
  - `MediaPage` (Lombok `@Data @Builder @AllArgsConstructor @NoArgsConstructor`): `List<MediaResponse> items; int page; int size; long total`
  - `MediaFacets` (same Lombok annotations): `List<String> genres; List<String> versions`
  - `public MediaPage MediaService.search(String q, String genre, String version, int page, int size)`: assumes the caller validated `page` and `size`
  - `public MediaFacets MediaService.facets()`
  - `MediaService` gets the constructor-injected `private final MongoTemplate mongoTemplate` (after `mediaRepository`, via `@RequiredArgsConstructor`)

- [ ] **Step 1: Write the failing test**

```java
package com.sparkle.mediaservice.service;

import com.sparkle.mediaservice.dto.MediaFacets;
import com.sparkle.mediaservice.dto.MediaPage;
import com.sparkle.mediaservice.model.Media;
import com.sparkle.mediaservice.repository.MediaRepository;
import org.bson.Document;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Query;

import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class MediaServiceSearchTests {

    private MongoTemplate mongoTemplate;
    private MediaService service;

    @BeforeEach
    void setUp() {
        mongoTemplate = mock(MongoTemplate.class);
        service = new MediaService(mock(MediaRepository.class), mongoTemplate);
    }

    @Test
    void searchPagesNewestFirstAndCountsAllMatches() {
        Media m = Media.builder().id("abc").songId(402391).title("HIGHLIFE").artist("KARMA").isVideo(true).build();
        when(mongoTemplate.find(any(Query.class), eq(Media.class))).thenReturn(List.of(m));
        when(mongoTemplate.count(any(Query.class), eq(Media.class))).thenReturn(123L);

        MediaPage result = service.search("karma", "HOUSE", null, 2, 50);

        ArgumentCaptor<Query> find = ArgumentCaptor.forClass(Query.class);
        verify(mongoTemplate).find(find.capture(), eq(Media.class));
        Query q = find.getValue();
        assertEquals(100, q.getSkip());
        assertEquals(50, q.getLimit());
        assertEquals(new Document("_id", -1), q.getSortObject());
        // java.util.regex.Pattern has no equals(), so compare the rendered documents
        assertEquals(MediaQueries.criteria("karma", "HOUSE", null).getCriteriaObject().toString(), q.getQueryObject().toString());

        ArgumentCaptor<Query> count = ArgumentCaptor.forClass(Query.class);
        verify(mongoTemplate).count(count.capture(), eq(Media.class));
        assertEquals(q.getQueryObject().toString(), count.getValue().getQueryObject().toString());

        assertEquals(2, result.getPage());
        assertEquals(50, result.getSize());
        assertEquals(123L, result.getTotal());
        assertEquals(1, result.getItems().size());
        assertEquals("abc", result.getItems().get(0).getId());
        assertEquals(402391, result.getItems().get(0).getSong_id());
        assertEquals(Boolean.TRUE, result.getItems().get(0).getIs_video());
    }

    @Test
    void facetsAreDistinctNonEmptyAndSorted() {
        when(mongoTemplate.findDistinct(any(Query.class), eq("genre"), eq(Media.class), eq(String.class)))
                .thenReturn(Arrays.asList("TRAP", null, "", "AFRO BEATS", "HOUSE"));
        when(mongoTemplate.findDistinct(any(Query.class), eq("remix"), eq(Media.class), eq(String.class)))
                .thenReturn(Arrays.asList("Dirty", " ", "Clean"));

        MediaFacets facets = service.facets();

        assertEquals(List.of("AFRO BEATS", "HOUSE", "TRAP"), facets.getGenres());
        assertEquals(List.of("Clean", "Dirty"), facets.getVersions());
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd media-service && ./mvnw -q test -Dtest=MediaServiceSearchTests`
Expected: a compilation error, `cannot find symbol` for `MediaPage`, `MediaFacets` and the `MediaService(MediaRepository, MongoTemplate)` constructor

- [ ] **Step 3: Write the DTOs**

`media-service/src/main/java/com/sparkle/mediaservice/dto/MediaPage.java`:

```java
package com.sparkle.mediaservice.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/** One page of GET /api/media/search. total counts every match, not just this page. */
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class MediaPage {
    private List<MediaResponse> items;
    private int page;
    private int size;
    private long total;
}
```

`media-service/src/main/java/com/sparkle/mediaservice/dto/MediaFacets.java`:

```java
package com.sparkle.mediaservice.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/** GET /api/media/facets: the distinct genre and version (remix) values, for filter dropdowns. */
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class MediaFacets {
    private List<String> genres;
    private List<String> versions;
}
```

- [ ] **Step 4: Add the service methods**

In `MediaService.java`, add these imports:

```java
import com.sparkle.mediaservice.dto.MediaFacets;
import com.sparkle.mediaservice.dto.MediaPage;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Query;
```

Add the field below `private final MediaRepository mediaRepository;`:

```java
    private final MongoTemplate mongoTemplate;
```

Add these methods after `getMediaByTitle`:

```java
    /** One page of the catalog, newest first. page and size are validated by the caller. */
    public MediaPage search(String q, String genre, String version, int page, int size) {
        Query query = new Query(MediaQueries.criteria(q, genre, version));
        long total = mongoTemplate.count(query, Media.class);
        query.with(Sort.by(Sort.Direction.DESC, "_id")).skip((long) page * size).limit(size);
        List<MediaResponse> items = mongoTemplate.find(query, Media.class).stream().map(this::mapToMediaResponse).toList();
        return MediaPage.builder().items(items).page(page).size(size).total(total).build();
    }

    public MediaFacets facets() {
        return MediaFacets.builder().genres(distinct("genre")).versions(distinct("remix")).build();
    }

    private List<String> distinct(String field) {
        return mongoTemplate.findDistinct(new Query(), field, Media.class, String.class).stream()
                .filter(v -> v != null && !v.isBlank())
                .sorted()
                .toList();
    }
```

Note: `count` runs before `with/skip/limit` so it counts every match. `Query.with/skip/limit` mutate the same query, which is why the test compares the criteria of both captured queries rather than their skip values. `Pattern` has no `equals()`, so the test compares `toString()` of the documents.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd media-service && ./mvnw -q test -Dtest='MediaServiceSearchTests,MediaQueriesTests,MediaControllerUrlTests,CdnUrlsTests' && for f in target/surefire-reports/TEST-*{MediaServiceSearch,MediaQueries,MediaControllerUrl,CdnUrls}Tests.xml; do grep -o 'tests="[0-9]*" errors="[0-9]*" skipped="[0-9]*" failures="[0-9]*"' $f; done`
Expected: 4 lines, all `errors="0"` and `failures="0"` (2, 5, 5 and 6 tests)

- [ ] **Step 6: Commit**

```bash
git add media-service/src/main/java/com/sparkle/mediaservice/dto/MediaPage.java media-service/src/main/java/com/sparkle/mediaservice/dto/MediaFacets.java media-service/src/main/java/com/sparkle/mediaservice/service/MediaService.java media-service/src/test/java/com/sparkle/mediaservice/service/MediaServiceSearchTests.java
git commit -m "media-service: MediaService.search (paged, newest first) and facets (#16)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `GET /api/media/search` and `GET /api/media/facets` endpoints

**Files:**
- Modify: `media-service/src/main/java/com/sparkle/mediaservice/controller/MediaController.java` (add two handlers after `getAllMedia`; the class already imports `ResponseStatusException` and `org.springframework.web.bind.annotation.*`)
- Test: `media-service/src/test/java/com/sparkle/mediaservice/controller/MediaControllerSearchTests.java`

**Interfaces:**
- Consumes: `MediaService.search(String, String, String, int, int)`, `MediaService.facets()`, `MediaPage`, `MediaFacets` (Task 2)
- Produces: the HTTP endpoints in Global Constraints. They are the contract for Tasks 5 and 6.

- [ ] **Step 1: Write the failing test**

```java
package com.sparkle.mediaservice.controller;

import com.sparkle.mediaservice.dto.MediaFacets;
import com.sparkle.mediaservice.dto.MediaPage;
import com.sparkle.mediaservice.dto.MediaResponse;
import com.sparkle.mediaservice.service.MediaService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** GET /api/media/search and /facets (no Spring context or MongoDB needed). */
class MediaControllerSearchTests {

    private MediaService mediaService;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mediaService = mock(MediaService.class);
        when(mediaService.search(any(), any(), any(), anyInt(), anyInt())).thenAnswer(inv -> MediaPage.builder()
                .items(List.of(MediaResponse.builder().id("abc").title("HIGHLIFE").build()))
                .page(inv.getArgument(3)).size(inv.getArgument(4)).total(40147).build());
        mvc = MockMvcBuilders.standaloneSetup(new MediaController(mediaService)).build();
    }

    @Test
    void searchDefaultsToFirstPageOf50() throws Exception {
        mvc.perform(get("/api/media/search"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].title").value("HIGHLIFE"))
                .andExpect(jsonPath("$.page").value(0))
                .andExpect(jsonPath("$.size").value(50))
                .andExpect(jsonPath("$.total").value(40147));
        verify(mediaService).search(null, null, null, 0, 50);
    }

    @Test
    void searchPassesFiltersAndPaging() throws Exception {
        mvc.perform(get("/api/media/search").param("q", "karma").param("genre", "AFRO BEATS")
                        .param("version", "Clean").param("page", "3").param("size", "200"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.page").value(3))
                .andExpect(jsonPath("$.size").value(200));
        verify(mediaService).search("karma", "AFRO BEATS", "Clean", 3, 200);
    }

    @Test
    void searchWithNoMatchesIsAnEmptyPage() throws Exception {
        when(mediaService.search(eq("zzzzqqq"), any(), any(), anyInt(), anyInt()))
                .thenReturn(MediaPage.builder().items(List.of()).page(0).size(50).total(0).build());
        mvc.perform(get("/api/media/search").param("q", "zzzzqqq"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items").isEmpty())
                .andExpect(jsonPath("$.total").value(0));
    }

    @Test
    void searchRejectsBadPaging() throws Exception {
        for (String[] p : new String[][]{{"size", "0"}, {"size", "201"}, {"page", "-1"}, {"size", "abc"}, {"page", "x"}}) {
            mvc.perform(get("/api/media/search").param(p[0], p[1])).andExpect(status().isBadRequest());
        }
        verify(mediaService, never()).search(any(), any(), any(), anyInt(), anyInt());
    }

    @Test
    void facetsReturnsGenresAndVersions() throws Exception {
        when(mediaService.facets()).thenReturn(MediaFacets.builder()
                .genres(List.of("AFRO BEATS", "HOUSE")).versions(List.of("Clean")).build());
        mvc.perform(get("/api/media/facets"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.genres[0]").value("AFRO BEATS"))
                .andExpect(jsonPath("$.genres[1]").value("HOUSE"))
                .andExpect(jsonPath("$.versions[0]").value("Clean"));
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd media-service && ./mvnw -q test -Dtest=MediaControllerSearchTests 2>&1 | grep -E "Tests run:|expected" | head`
Expected: `Tests run: 5, Failures: 5`. `/search` and `/facets` currently match `GET /{title}`, which returns 200 with an empty list, so the JSON path assertions and the 400 checks fail.

- [ ] **Step 3: Write the minimal implementation**

In `MediaController.java`, add these imports:

```java
import com.sparkle.mediaservice.dto.MediaFacets;
import com.sparkle.mediaservice.dto.MediaPage;
```

Add these handlers directly after `getAllMedia()`, before `@GetMapping(value = "/{title}")`:

```java
    public static final int MAX_PAGE_SIZE = 200;

    /** One page of the catalog, newest first. q: title or artist substring; genre, version: exact. */
    @GetMapping(value = "/search")
    @RolesAllowed({"user"})
    @ResponseStatus(HttpStatus.OK)
    public MediaPage searchMedia(@RequestParam(required = false) String q,
                                 @RequestParam(required = false) String genre,
                                 @RequestParam(required = false) String version,
                                 @RequestParam(defaultValue = "0") int page,
                                 @RequestParam(defaultValue = "50") int size) {
        if (page < 0)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "page must be >= 0");
        if (size < 1 || size > MAX_PAGE_SIZE)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "size must be 1.." + MAX_PAGE_SIZE);
        log.info("searchMedia: q={} genre={} version={} page={} size={}", q, genre, version, page, size);
        return mediaService.search(q, genre, version, page, size);
    }

    /** Distinct genres and versions, for filter dropdowns. */
    @GetMapping(value = "/facets")
    @RolesAllowed({"user"})
    @ResponseStatus(HttpStatus.OK)
    public MediaFacets getFacets() {
        return mediaService.facets();
    }
```

A non-numeric `page` or `size` fails Spring's type conversion (`MethodArgumentTypeMismatchException`), which the default handler turns into 400. The test checks this.

- [ ] **Step 4: Run all the media-service unit tests to verify they pass**

Run: `cd media-service && ./mvnw -q test -Dtest='MediaControllerSearchTests,MediaServiceSearchTests,MediaQueriesTests,MediaControllerUrlTests,CdnUrlsTests' && for f in target/surefire-reports/TEST-*{MediaControllerSearch,MediaServiceSearch,MediaQueries,MediaControllerUrl,CdnUrls}Tests.xml; do grep -o 'tests="[0-9]*" errors="[0-9]*" skipped="[0-9]*" failures="[0-9]*"' $f; done`
Expected: 5 lines, all `errors="0"` and `failures="0"`

- [ ] **Step 5: Commit**

```bash
git add media-service/src/main/java/com/sparkle/mediaservice/controller/MediaController.java media-service/src/test/java/com/sparkle/mediaservice/controller/MediaControllerSearchTests.java
git commit -m "media-service: GET /api/media/search (paged) and /api/media/facets (#16)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `MongoIndexConfig`: ensure the filter indexes at startup

**Files:**
- Create: `media-service/src/main/java/com/sparkle/mediaservice/config/MongoIndexConfig.java` (the `config/` package directory exists and is empty)
- Test: `media-service/src/test/java/com/sparkle/mediaservice/config/MongoIndexConfigTests.java`

**Interfaces:**
- Consumes: `MongoTemplate`, `Media` (`@Document("media")`)
- Produces: `public void MongoIndexConfig.ensureIndexes()`, called on `ApplicationReadyEvent`. The index names are `genre_1__id_-1` and `remix_1__id_-1`.

- [ ] **Step 1: Write the failing test**

```java
package com.sparkle.mediaservice.config;

import com.sparkle.mediaservice.model.Media;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.index.IndexDefinition;
import org.springframework.data.mongodb.core.index.IndexOperations;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.*;

class MongoIndexConfigTests {

    @Test
    void ensuresGenreAndRemixIndexesSortedNewestFirst() {
        MongoTemplate mongoTemplate = mock(MongoTemplate.class);
        IndexOperations ops = mock(IndexOperations.class);
        when(mongoTemplate.indexOps(Media.class)).thenReturn(ops);

        new MongoIndexConfig(mongoTemplate).ensureIndexes();

        ArgumentCaptor<IndexDefinition> defs = ArgumentCaptor.forClass(IndexDefinition.class);
        verify(ops, times(2)).ensureIndex(defs.capture());
        List<IndexDefinition> all = defs.getAllValues();
        assertEquals(new Document("genre", 1).append("_id", -1), all.get(0).getIndexKeys());
        assertEquals("genre_1__id_-1", all.get(0).getIndexOptions().get("name"));
        assertEquals(new Document("remix", 1).append("_id", -1), all.get(1).getIndexKeys());
        assertEquals("remix_1__id_-1", all.get(1).getIndexOptions().get("name"));
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd media-service && ./mvnw -q test -Dtest=MongoIndexConfigTests 2>&1 | grep -E "ERROR.*cannot find symbol" | head -2`
Expected: `cannot find symbol ... MongoIndexConfig`

- [ ] **Step 3: Write the minimal implementation**

```java
package com.sparkle.mediaservice.config;

import com.sparkle.mediaservice.model.Media;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.event.EventListener;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.index.Index;
import org.springframework.data.mongodb.core.index.IndexOperations;

/**
 * Indexes for GET /api/media/search: each filter, then newest first. Created explicitly because Boot 2.7 has
 * spring.data.mongodb.auto-index-creation off. ensureIndex is a no-op when the index already exists.
 */
@Configuration
@RequiredArgsConstructor
@Slf4j
public class MongoIndexConfig {

    private final MongoTemplate mongoTemplate;

    @EventListener(ApplicationReadyEvent.class)
    public void ensureIndexes() {
        IndexOperations ops = mongoTemplate.indexOps(Media.class);
        for (String field : new String[]{"genre", "remix"}) {
            String name = ops.ensureIndex(new Index().on(field, Sort.Direction.ASC).on("_id", Sort.Direction.DESC)
                    .named(field + "_1__id_-1"));
            log.info("Mongo index {} ensured", name);
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd media-service && ./mvnw -q test -Dtest=MongoIndexConfigTests && grep -o 'tests="[0-9]*" errors="[0-9]*" skipped="[0-9]*" failures="[0-9]*"' target/surefire-reports/TEST-*MongoIndexConfigTests.xml`
Expected: `tests="1" errors="0" skipped="0" failures="0"`

- [ ] **Step 5: Run the whole media-service suite and record the result**

Run: `cd media-service && ./mvnw test 2>&1 | grep -E "Tests run:.*Fail" | tail -1; for f in target/surefire-reports/TEST-*.xml; do echo "$(basename $f .xml): $(grep -m1 -o 'tests="[0-9]*" errors="[0-9]*" skipped="[0-9]*" failures="[0-9]*"' $f)"; done`
Expected:
- Every new class has `errors="0" failures="0"`.
- `AccountServiceTests` and `MediaServiceApplicationTests` have `errors="1"` each, with "Could not find a valid Docker environment". That was already the case before this work, and the spec leaves it out of scope. Report it by name.

- [ ] **Step 6: Commit**

```bash
git add media-service/src/main/java/com/sparkle/mediaservice/config/MongoIndexConfig.java media-service/src/test/java/com/sparkle/mediaservice/config/MongoIndexConfigTests.java
git commit -m "media-service: ensure the genre and remix search indexes at startup (#16)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Cluster checks, deploy media-service, verify against real MongoDB

**Files:**
- Modify: `charts/media-service/templates/tests/test-connection.yaml` (line 15)
- Modify: `borg-cloud/05-media/media-test.sh` (insert a section after the first `GET /api/media` check, before the POST)

**Interfaces:**
- Consumes: the HTTP contract (Task 3) and the index names (Task 4). The script's existing helpers are `ok`, `bad`, `$body` and `$VIP_ADDRESS`. `mongo_primary`, `mongo_eval <pod> <uri> <js>` and `mongo_app_uri` come from `03-databases/lib.sh`.
- Produces: `make media-test` covering search, facets, 400, the indexes, parity and latency.

- [ ] **Step 1: Point the Helm test at a one-item page**

In `charts/media-service/templates/tests/test-connection.yaml`, replace:

```yaml
      args: ["-fsS", "http://{{ include "media-service.serviceName" . }}:{{ .Values.service.port }}/api/media"]
```

with:

```yaml
      # One item, not the whole catalog
      args: ["-fsS", "http://{{ include "media-service.serviceName" . }}:{{ .Values.service.port }}/api/media/search?size=1"]
```

Run: `helm lint charts/media-service -f charts/media-service/values-borg.yaml | tail -1 && helm template t charts/media-service -f charts/media-service/values-borg.yaml | grep -n 'search?size=1'`
Expected: `1 chart(s) linted, 0 chart(s) failed`, and one matching line

- [ ] **Step 2: Add the search checks to `media-test.sh`**

After the block ending `bad "GET http://$VIP_ADDRESS/api/media -> $code"` / `fi`, insert:

```bash
# ---- GET /api/media/search and /facets (#16) ----
# The full list in $body is the reference: the old client-side rules, applied with jq
api="http://$VIP_ADDRESS/api/media"
all_total=$(jq length "$body" 2>/dev/null || echo -1)
search() { curl -s -m 10 -G "$api/search" "$@"; }
# expected <q> <genre> <version>: matches under the old client-side rules (substring of title+artist, lower-cased)
expected() {
    jq --arg q "$1" --arg g "$2" --arg v "$3" '[.[] | select(
        (((.title // "") + "\n" + (.artist // "")) | ascii_downcase | contains($q | ascii_downcase))
        and ($g == "" or .genre == $g) and ($v == "" or .remix == $v))] | length' "$body"
}

page=$(search --data-urlencode size=5)
if [ "$(jq '.items | length' <<<"$page")" = 5 ] && [ "$(jq .total <<<"$page")" = "$all_total" ] && [ "$(jq .page <<<"$page")" = 0 ]; then
    ok "GET /api/media/search?size=5 -> 5 items, total $all_total (= full list)"
else
    bad "GET /api/media/search?size=5 -> $(head -c 200 <<<"$page")"
fi

newest=$(jq -r '.items[0].id' <<<"$page" 2>/dev/null || true)   # || true: set -e, and page may not be JSON
if [ "$newest" = "$(jq -r 'max_by(.id) | .id' "$body")" ]; then ok "search is newest first (_id descending)"; else bad "search's first item $newest is not the newest _id"; fi

for bad_params in "size=0" "size=201" "page=-1" "size=abc"; do
    code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' "$api/search?$bad_params" || true)
    if [ "$code" = 400 ]; then ok "GET /api/media/search?$bad_params -> 400"; else bad "GET /api/media/search?$bad_params -> $code (expected 400)"; fi
done

facets=$(curl -s -m 10 "$api/facets" || true)
genre=$(jq -r '.genres[0] // empty' <<<"$facets" 2>/dev/null || true)
version=$(jq -r '.versions[0] // empty' <<<"$facets" 2>/dev/null || true)
if [ -n "$genre" ] && [ -n "$version" ] && [ "$(jq '.genres | . == (sort | unique)' <<<"$facets")" = true ]; then
    ok "GET /api/media/facets -> $(jq '.genres | length' <<<"$facets") genres, $(jq '.versions | length' <<<"$facets") versions (sorted, distinct)"
else
    bad "GET /api/media/facets -> $(head -c 200 <<<"$facets")"
fi

# Parity with the old client-side filtering: q, regex metacharacters taken literally, genre, version, combined
top_genre=$(jq -r '[.[].genre | select(. != null and . != "")] | group_by(.) | max_by(length) | .[0]' "$body")
while IFS='|' read -r q g v; do
    want=$(expected "$q" "$g" "$v")
    got=$(search --data-urlencode "q=$q" --data-urlencode "genre=$g" --data-urlencode "version=$v" --data-urlencode size=1 | jq .total 2>/dev/null || echo error)
    if [ "$got" = "$want" ]; then ok "search q='$q' genre='$g' version='$v' -> total $got (= client-side rules)"; else bad "search q='$q' genre='$g' version='$v' -> $got, client-side rules give $want"; fi
done <<EOF
nirvana||
LOVE||
a.b||
(||
zzzzqqq||
|$top_genre|
||$version
love|$top_genre|
EOF

p=$(mongo_primary 2>/dev/null || true)
indexes=$( [ -n "$p" ] && mongo_eval "$p" "$(mongo_app_uri)" 'db.media.getIndexes().map(i => i.name).join(",")' 2>/dev/null || true)
if grep -q 'genre_1__id_-1' <<<"$indexes" && grep -q 'remix_1__id_-1' <<<"$indexes"; then
    ok "indexes genre_1__id_-1 and remix_1__id_-1 exist"
else
    bad "search indexes missing (have: $indexes)"
fi

# Latency: best of 3, first page, no filter
ms=$(for i in 1 2 3; do curl -s -m 10 -o /dev/null -w '%{time_total}\n' "$api/search?page=0&size=50"; done | sort -n | head -1 | awk '{printf "%d", $1 * 1000}')
if [ "$ms" -lt 100 ]; then ok "GET /api/media/search?page=0&size=50 in ${ms} ms (< 100)"; else bad "GET /api/media/search?page=0&size=50 took ${ms} ms (>= 100)"; fi
```

Update the header comment of `media-test.sh`: after `# HTTP checks against media-service through HAProxy on the VIP.`, add a line: `# Covers the full list, paged search and facets (with parity against the old client-side filtering), the search indexes and latency.`

Run: `bash -n borg-cloud/05-media/media-test.sh && echo syntax-ok`
Expected: `syntax-ok`

- [ ] **Step 3: Run it against the currently deployed media-service to verify it fails**

Run: `cd borg-cloud && make media-test 2>&1 | grep -E "FAIL|PASS|>>>" | head -30`
Expected:
- FAIL for `search?size=5`, the 400 checks, facets, every parity line and the indexes.
- The deployed image has no `/search`, so `/search` is answered by `GET /{title}` with `[]`.
- Ends with `>>> media-test: FAILED`.

- [ ] **Step 4: Commit, then deploy media-service from a clean worktree**

```bash
git add charts/media-service/templates/tests/test-connection.yaml borg-cloud/05-media/media-test.sh
git commit -m "media-test: check paged search, facets, indexes and parity with client-side filtering (#16)

The media-service helm test fetches one search result instead of the
whole catalog.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
W=/tmp/claude-1000/-home-cfrank-git-media-stream/86137798-5b58-4cf7-84f4-b2937a08b43c/scratchpad/wt-search
git worktree add -q --detach "$W" HEAD
(cd "$W/borg-cloud" && make deploy-media 2>&1 | tail -3)
```

Expected: `>>> Deployed localhost:5050/media3:<HEAD short sha>` (no `-dirty` suffix)

- [ ] **Step 5: Run the cluster checks to verify they pass**

Run: `cd "$W/borg-cloud" && make media-test 2>&1 | grep -E "FAIL|PASS|>>>" && helm test media-service -n media --timeout 2m | grep -E "Phase|STATUS"`
Expected:
- Every line is PASS and the run ends with `>>> media-test: all checks passed`.
- `helm test` shows `Phase: Succeeded`.
- If the latency check fails, report the measured ms. Don't loosen the threshold.

If the index check fails with an authorization error in the media-service log (`kubectl -n media logs deploy/media-service | grep -i index`), stop and report it. The `app` user's role would lack `createIndex`, which is a database permission decision for the user.

---

### Task 6: RecordPool loads pages from `/search`

**Files:**
- Modify: `record-pool/services/catalogApi.ts` (replace `fetchTracks`; add `searchTracks`, `fetchFacets` and their types)
- Create: `record-pool/hooks/useTrackSearch.ts`
- Modify: `record-pool/app/(tabs)/RecordPoolApp.tsx`
- Test: `/tmp/claude-1000/-home-cfrank-git-media-stream/86137798-5b58-4cf7-84f4-b2937a08b43c/scratchpad/perf/search.mjs` (headless Chrome. puppeteer-core and `measure.mjs` are already installed in that directory. record-pool has no JS test runner, and the spec's tests for this layer are browser checks.)

**Interfaces:**
- Consumes: `GET /api/media/search` and `GET /api/media/facets` (Task 3, deployed in Task 5)
- Produces:
  - `searchTracks(params: TrackQuery, signal?: AbortSignal): Promise<TrackPage>`, where `TrackQuery = { q?: string; genre?: string; version?: string; page: number; size: number }` and `TrackPage = { tracks: Track[]; page: number; size: number; total: number }`
  - `fetchFacets(signal?: AbortSignal): Promise<Facets>`, where `Facets = { genres: string[]; versions: string[] }`
  - `useTrackSearch(filters: { q: string; genre: string; version: string }, pageSize?: number)` returns `{ tracks: Track[]; total: number; loading: boolean; error: string | null; loadMore: () => void }`

- [ ] **Step 1: Write the failing browser check**

Create `/tmp/claude-1000/-home-cfrank-git-media-stream/86137798-5b58-4cf7-84f4-b2937a08b43c/scratchpad/perf/search.mjs`:

```js
import puppeteer from 'puppeteer-core';
const base = 'http://192.168.56.120';
const results = [];
const check = (name, pass, detail = '') => results.push(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);

const browser = await puppeteer.launch({ executablePath: '/usr/bin/google-chrome', headless: true, protocolTimeout: 120000 });
const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 900 });
const api = [];
page.on('response', async (r) => {
  const u = new URL(r.url());
  if (!u.pathname.startsWith('/api/media')) return;
  let bytes = 0; try { bytes = (await r.buffer()).length; } catch {}
  api.push({ path: u.pathname, search: u.searchParams, bytes });
});
// testIDs from RecordPoolApp.tsx: React Native Web renders them as data-testid
const rowTitles = () => page.evaluate(() => [...document.querySelectorAll('[data-testid="track-title"]')].map((e) => e.innerText));
const rowIds = () => page.evaluate(() => [...document.querySelectorAll('[data-testid^="track-row-"]')].map((e) => e.dataset.testid));
const settle = (ms = 1500) => new Promise((r) => setTimeout(r, ms));

// 1. First load: one page, not the whole catalog
await page.goto(`${base}/RecordPoolApp`, { waitUntil: 'domcontentloaded' });
await page.waitForFunction(() => !document.body.innerText.includes('Loading tracks'), { timeout: 90000 }).catch(() => {});
await settle();
const firstBytes = api.reduce((n, r) => n + r.bytes, 0);
check('first load does not fetch the full list (GET /api/media)', !api.some((r) => r.path === '/api/media'));
check('first load transfers < 200 KB of API data', firstBytes < 200_000, `${Math.round(firstBytes / 1024)} KB`);
check('first load requests /search page 0', api.some((r) => r.path === '/api/media/search' && r.search.get('page') === '0'));
check('dropdowns come from /facets', api.some((r) => r.path === '/api/media/facets'));
const first = await rowTitles();
check('rows are shown', first.length > 0, `${first.length} rows`);

// 2. Scrolling to the end loads page 1, with no duplicate rows
for (let i = 0; i < 3; i++) {
  await page.evaluate(() => { const s = document.querySelector('[data-testid="track-list"]'); s.scrollTop = s.scrollHeight; });
  await settle(800);
}
await settle(1500);
check('scrolling to the end requests page 1', api.some((r) => r.path === '/api/media/search' && r.search.get('page') === '1'));
const afterScroll = await rowTitles();
check('more rows after scrolling', afterScroll.length > first.length, `${first.length} -> ${afterScroll.length}`);
const ids = await rowIds();
check('no duplicate rows after scrolling', new Set(ids).size === ids.length, `${ids.length} rows, ${new Set(ids).size} distinct`);

// 3. Search: same tracks as the server's own answer for q=nirvana
const want = await (await fetch(`${base}/api/media/search?q=nirvana&size=200`)).json();
await page.type('input[placeholder^="Search"]', 'nirvana');
await settle(2000);
const got = await rowTitles();
check('search sends q=nirvana to the server', api.some((r) => r.search.get('q') === 'nirvana'));
check('search shows exactly the matching tracks', got.length === want.items.length && want.items.every((m) => got.includes(m.title)),
  `server ${want.items.length}, shown ${got.length}`);

// 4. A search with no matches shows "No Tracks Found"
await page.click('input[placeholder^="Search"]', { clickCount: 3 });
await page.type('input[placeholder^="Search"]', 'zzzzqqq');
await settle(2000);
check('no matches shows "No Tracks Found"', await page.evaluate(() => document.body.innerText.includes('No Tracks Found')));

// 5. Genre filter goes to the server
await page.click('input[placeholder^="Search"]', { clickCount: 3 });
await page.keyboard.press('Backspace');
const facets = await (await fetch(`${base}/api/media/facets`)).json();
await page.select('select', facets.genres[0]);
await settle(2000);
check(`genre filter sends genre=${facets.genres[0]}`, api.some((r) => r.search.get('genre') === facets.genres[0]));

console.log(results.join('\n'));
await browser.close();
process.exit(results.some((r) => r.startsWith('FAIL')) ? 1 : 0);
```

- [ ] **Step 2: Run it against the deployed RecordPool to verify it fails**

Run: `cd /tmp/claude-1000/-home-cfrank-git-media-stream/86137798-5b58-4cf7-84f4-b2937a08b43c/scratchpad/perf && timeout 240 node search.mjs`
Expected:
- FAIL for:
  - "does not fetch the full list"
  - "< 200 KB" (about 13,450 KB)
  - "requests /search page 0"
  - "dropdowns come from /facets"
  - "requests page 1"
  - "sends q=nirvana"
  - "genre filter sends genre="
- Exit code 1.

- [ ] **Step 3: Replace `fetchTracks` in `catalogApi.ts`**

Delete this block:

```ts
/** Every track in the catalog. media-service has no search or paging yet, so callers filter locally. */
export async function fetchTracks(signal?: AbortSignal): Promise<Track[]> {
    const response = await get('/api/media', signal);
    const body: MediaResponse[] = await response.json();
    return body.map(toTrack);
}
```

and put this in its place:

```ts
/** Search filters and the page to fetch. Empty q, genre or version means no filter. page counts from 0. */
export interface TrackQuery {
    q?: string;
    genre?: string;
    version?: string;
    page: number;
    size: number;
}

/** One page of results. total counts every match. */
export interface TrackPage {
    tracks: Track[];
    page: number;
    size: number;
    total: number;
}

/** The values for the genre and version dropdowns */
export interface Facets {
    genres: string[];
    versions: string[];
}

/** One page of the catalog, newest first (GET /api/media/search) */
export async function searchTracks(query: TrackQuery, signal?: AbortSignal): Promise<TrackPage> {
    const params = new URLSearchParams({ page: String(query.page), size: String(query.size) });
    if (query.q) params.set('q', query.q);
    if (query.genre) params.set('genre', query.genre);
    if (query.version) params.set('version', query.version);
    const response = await get(`/api/media/search?${params}`, signal);
    const body: { items: MediaResponse[]; page: number; size: number; total: number } = await response.json();
    return { tracks: body.items.map(toTrack), page: body.page, size: body.size, total: body.total };
}

/** Distinct genres and versions in the catalog (GET /api/media/facets) */
export async function fetchFacets(signal?: AbortSignal): Promise<Facets> {
    const response = await get('/api/media/facets', signal);
    return response.json();
}
```

- [ ] **Step 4: Create `record-pool/hooks/useTrackSearch.ts`**

```ts
import { useCallback, useEffect, useRef, useState } from 'react';

import { searchTracks, Track } from '@/services/catalogApi';

export interface TrackFilters {
    q: string;
    genre: string;
    version: string;
}

/** value, once it has stopped changing for delayMs */
function useDebouncedValue<T>(value: T, delayMs: number): T {
    const [debounced, setDebounced] = useState(value);
    useEffect(() => {
        const timer = setTimeout(() => setDebounced(value), delayMs);
        return () => clearTimeout(timer);
    }, [value, delayMs]);
    return debounced;
}

/**
 * The catalog, one server page at a time. Changing a filter (q is debounced 300 ms) starts again at page 0
 * and aborts the request in flight, so an older response never replaces a newer one. loadMore fetches the
 * next page; it does nothing while a page is loading or when every match is loaded. After a failed page,
 * calling loadMore again retries it.
 */
export function useTrackSearch(filters: TrackFilters, pageSize = 50) {
    const q = useDebouncedValue(filters.q.trim(), 300);
    const { genre, version } = filters;

    const [tracks, setTracks] = useState<Track[]>([]);
    const [total, setTotal] = useState(0);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    const controllerRef = useRef<AbortController | null>(null);
    const loadingRef = useRef(false); // set synchronously: onEndReached can fire twice before a re-render
    const nextPageRef = useRef(0);

    const load = useCallback(
        (page: number) => {
            controllerRef.current?.abort();
            const controller = new AbortController();
            controllerRef.current = controller;
            loadingRef.current = true;
            setLoading(true);
            setError(null);
            searchTracks({ q, genre, version, page, size: pageSize }, controller.signal)
                .then((result) => {
                    if (controller.signal.aborted) return;
                    setTracks((loaded) => (page === 0 ? result.tracks : [...loaded, ...result.tracks]));
                    setTotal(result.total);
                    nextPageRef.current = page + 1;
                })
                .catch((err) => {
                    if (!controller.signal.aborted) setError(err.message);
                })
                .finally(() => {
                    if (controllerRef.current !== controller) return;
                    loadingRef.current = false;
                    setLoading(false);
                });
        },
        [q, genre, version, pageSize]
    );

    // A filter changed (or first render): start again at page 0
    useEffect(() => {
        nextPageRef.current = 0;
        setTracks([]);
        setTotal(0);
        load(0);
        return () => controllerRef.current?.abort();
    }, [load]);

    const loadMore = useCallback(() => {
        if (loadingRef.current || nextPageRef.current === 0 || tracks.length >= total) return;
        load(nextPageRef.current);
    }, [load, tracks.length, total]);

    return { tracks, total, loading, error, loadMore };
}
```

- [ ] **Step 5: Switch `RecordPoolApp.tsx` to the hook and the facets**

1. Imports: change the React import to
   `import React, { useState, useEffect, useCallback, memo } from 'react';`
   and the catalog import to
   `import { fetchDownloadUrl, fetchFacets, fetchStreamUrl, Facets, Track } from '@/services/catalogApi';`
   and add `import { useTrackSearch } from '@/hooks/useTrackSearch';`.
2. Remove the `tracks` and `loading` `useState` lines, and add after the `selectedVersion` state:

```tsx
    const [facets, setFacets] = useState<Facets>({ genres: [], versions: [] });
    // Filtering and paging happen in media-service (GET /api/media/search)
    const { tracks, total, loading, error: searchError, loadMore } = useTrackSearch({
        q: searchTerm,
        genre: selectedGenre,
        version: selectedVersion,
    });
```

3. Replace the whole `// --- Catalog (media-service GET /api/media) ---` `useEffect`, plus `availableGenres`, `availableVersions`, `searchIndex`, `deferredSearchTerm` and `filteredTracks` (everything from `// --- Catalog` up to `// --- Audio Playback ---`), with:

```tsx
    // --- Filter dropdowns (media-service GET /api/media/facets) ---
    useEffect(() => {
        const controller = new AbortController();
        fetchFacets(controller.signal)
            .then(setFacets)
            .catch((err) => {
                if (!controller.signal.aborted) setError(`Failed to load filters: ${err.message}`);
            });
        return () => controller.abort();
    }, []);

    useEffect(() => {
        if (searchError) setError(`Failed to load tracks: ${searchError}`);
    }, [searchError]);

```

4. In the two `<select>`s, replace `availableGenres.map` with `facets.genres.map` and `availableVersions.map` with `facets.versions.map`.
5. Directly before `{/* Track List: ...` add the count:

```tsx
            <Text style={styles.trackCount}>
                {loading && tracks.length === 0 ? ' ' : `${total.toLocaleString()} tracks`}
            </Text>

```

6. In the `<FlatList>`, replace `data={loading ? [] : filteredTracks}` with `data={tracks}`, and add these props after `windowSize={11}`:

```tsx
                onEndReached={loadMore}
                onEndReachedThreshold={0.5}
                ListFooterComponent={
                    loading && tracks.length > 0 ? (
                        <View style={styles.noTracks}>
                            <Text style={styles.noTracksText}>Loading more...</Text>
                        </View>
                    ) : null
                }
```

In `ListEmptyComponent`, keep both branches: `loading` shows "Loading tracks...", otherwise "No Tracks Found". It already reads `loading`, which now comes from the hook.

7. Add a style entry after `trackList`:

```tsx
    trackCount: {
        fontSize: 14,
        color: '#d1d5db',
        marginBottom: 8,
        marginLeft: 10,
    },
```

8. `togglePlay` keeps `tracks.find(...)` and its `[audio, playingTrack, tracks]` dependencies. `tracks` now comes from the hook.
9. Test hooks for the browser check (React Native Web renders `testID` as `data-testid`):
   - In `TrackRow`, the outer `<View style={styles.trackItem}>` becomes `<View style={styles.trackItem} testID={`track-row-${track.id}`}>`.
   - The title `<Text style={styles.trackTitle}>` becomes `<Text style={styles.trackTitle} testID="track-title">`.
   - Add `testID="track-list"` to the `<FlatList>`.

- [ ] **Step 6: Type-check**

Run: `cd record-pool && npx tsc --noEmit -p . 2>&1 | grep -E "RecordPoolApp|catalogApi|useTrackSearch" | grep -v "TS2322" ; echo done`
Expected:
- Only the existing `RecordPoolApp.tsx(...): error TS2353 ... 'space' does not exist` line, then `done`.
- TS2322 is the file's existing style-typing error; there are 57 today.
- No errors in `catalogApi.ts` or `useTrackSearch.ts`.

- [ ] **Step 7: Commit, then deploy RecordPool from a clean worktree**

```bash
git add record-pool/services/catalogApi.ts record-pool/hooks/useTrackSearch.ts "record-pool/app/(tabs)/RecordPoolApp.tsx"
git commit -m "record-pool: load the catalog a page at a time from /api/media/search (#16)

Search, genre and version filtering run in media-service. The dropdowns
come from /api/media/facets. useTrackSearch loads the next page when the
list reaches its end, starts again at page 0 when a filter changes (the
search text is debounced 300 ms), and aborts the request in flight so an
older response can't replace a newer one. The first load transfers one
page instead of the whole 13.8 MB catalog.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
W=/tmp/claude-1000/-home-cfrank-git-media-stream/86137798-5b58-4cf7-84f4-b2937a08b43c/scratchpad/wt-search
git -C "$W" checkout -q --detach media-search-paging
(cd "$W/borg-cloud" && make deploy-record-pool 2>&1 | tail -2)
```

Expected: `>>> Deployed localhost:5050/record-pool:<HEAD short sha>`

- [ ] **Step 8: Run the browser check and the cluster checks to verify they pass**

Run: `cd /tmp/claude-1000/-home-cfrank-git-media-stream/86137798-5b58-4cf7-84f4-b2937a08b43c/scratchpad/perf && timeout 240 node search.mjs; echo "exit=$?"; timeout 250 node measure.mjs after-16; cd "$W/borg-cloud" && make record-pool-test 2>&1 | tail -1`
Expected:
- All `search.mjs` lines PASS and `exit=0`.
- `measure.mjs` prints `first_tracks_ms` (record it; it was 1547 before this change).
- `>>> record-pool-test: all checks passed`.

---

### Task 7: Docs, merge-ready state and issue close-out

**Files:**
- Modify: `docs/borg-cloud-runbook.md`. The user has uncommitted hunks in this file. Commit only this task's change, through the index, as described in Step 2.
- Modify: `docs/superpowers/specs/2026-09-26-media-search-paging-design.md` (the `Status` line)

- [ ] **Step 1: Update the runbook text** (apply the same edit to the working file and to the HEAD copy)

In the `## RecordPool web app` section, after the paragraph that starts `The API base URL is built into the bundle`, add:

```
The app loads the catalog a page at a time from `GET /api/media/search?q=&genre=&version=&page=&size=` (newest first, 50 per page, at most 200), and its genre and version dropdowns from `GET /api/media/facets`. `GET /api/media` still returns the whole catalog as one array. `make media-test` checks that search gives the same totals as the old client-side filtering.
```

- [ ] **Step 2: Commit only that hunk**

```bash
S=/tmp/claude-1000/-home-cfrank-git-media-stream/86137798-5b58-4cf7-84f4-b2937a08b43c/scratchpad
git show HEAD:docs/borg-cloud-runbook.md > $S/runbook-head.md
# apply the Step 1 paragraph insertion to $S/runbook-head.md and to docs/borg-cloud-runbook.md (same python replace on both)
git update-index --cacheinfo 100644,$(git hash-object -w $S/runbook-head.md),docs/borg-cloud-runbook.md
sed -i 's/^- \*\*Status:\*\* Design approved, awaiting spec review/- **Status:** Implemented/' docs/superpowers/specs/2026-09-26-media-search-paging-design.md
git add docs/superpowers/specs/2026-09-26-media-search-paging-design.md docs/superpowers/plans/2026-09-26-media-search-paging.md
git commit -m "docs: paged catalog search in the runbook; spec implemented (#16)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git diff --stat docs/borg-cloud-runbook.md   # expected: only the user's own 49 uncommitted lines remain
```

- [ ] **Step 3: Remove the worktree**

Run: `git worktree remove /tmp/claude-1000/-home-cfrank-git-media-stream/86137798-5b58-4cf7-84f4-b2937a08b43c/scratchpad/wt-search && git worktree list`
Expected: only the main checkout is listed

- [ ] **Step 4: Report, and close #16 after the user confirms the branch**

- Tick the checkboxes in #16's body, and post a comment with the commit list, the `media-test` and `search.mjs` results, and the before/after first-load size.
- Close #16. Closing is what the user asked for with "complete and close issue 16".
- Merging or pushing the branch needs the user's go-ahead. Ask them.
