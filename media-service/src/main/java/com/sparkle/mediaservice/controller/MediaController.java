package com.sparkle.mediaservice.controller;

import com.sparkle.mediaservice.dto.MediaRequest;
import com.sparkle.mediaservice.dto.MediaFacets;
import com.sparkle.mediaservice.dto.MediaPage;
import com.sparkle.mediaservice.dto.MediaResponse;
import com.sparkle.mediaservice.dto.SignedUrlResponse;
import com.sparkle.mediaservice.service.CdnSigner;
import com.sparkle.mediaservice.service.CdnUrls;
import com.sparkle.mediaservice.service.MediaService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import javax.annotation.security.RolesAllowed;
import java.util.Date;
import java.util.List;

@Slf4j
@RestController
@CrossOrigin(origins = "http://localhost:3000")
@RequestMapping("/api/media")
@RequiredArgsConstructor
public class MediaController {

    private final MediaService mediaService;
    private final CdnSigner cdnSigner;

    @DeleteMapping
    @RolesAllowed({"user"})                     // FIXME: Test authorization failure
    @ResponseStatus(HttpStatus.CREATED)
    public void deleteAllMedia(@RequestBody MediaRequest mediaRequest) {
        mediaService.deleteAllMedia();
    }

    @PostMapping
    @RolesAllowed({"user"})                     // FIXME: Test authorization failure
    @ResponseStatus(HttpStatus.CREATED)
    public void createMedia(@RequestBody MediaRequest mediaRequest) {
        mediaService.createMedia(mediaRequest);
    }

    // https://stackoverflow.com/questions/24006291/postgresql-return-result-set-as-json-array
    // postgres=# SELECT json_build_object('title', json_agg(t.title), 'artist',  json_agg(t.artist)) FROM t vms_songs WHERE song_id BETWEEN 1000 AND 1020;
    // SELECT array_to_json(array_agg(row_to_json(t))) FROM (SELECT title, artist FROM vms_songs WHERE song_id BETWEEN 100000 AND 100002) t;
    // SELECT array_to_json(array_agg(t)) FROM (SELECT title, artist, genre, remix, comment, bpm, year, '' as coverUrl FROM vms_songs WHERE song_id BETWEEN 0 AND 100000) t;
    // psql -t -c 'SELECT array_to_json(array_agg(t)) FROM (SELECT title, artist, genre, equalizer AS remix, label, comments AS comment, bpm, year, comments as coverUrl, vms_repo_path AS file FROM vms_songs WHERE song_id BETWEEN 0 AND 100000) t;' > /tmp/000k-100k.json
    // curl -X POST -H "Content-Type: application/json" -d @<(cat data.json) http://localhost:8084/api/media/bulk
    @PostMapping(value = "/bulk")
    //@RolesAllowed({"user"})                     // FIXME: Test authorization failure
    @ResponseStatus(HttpStatus.CREATED)
    public void createBulkMedia(@RequestBody MediaRequest[] mediaRequestList) {
        for (MediaRequest mediaRequest: mediaRequestList)
            mediaService.createMedia(mediaRequest);
    }

    @GetMapping
    @RolesAllowed({"user"})
    @ResponseStatus(HttpStatus.OK)
    public List<MediaResponse> getAllMedia() {
        log.info("getAllMedia");
        return mediaService.getAllMedia();
    }

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

    @GetMapping(value = "/{title}")
    //@RolesAllowed({"user"})
    @ResponseStatus(HttpStatus.OK)
    public List<MediaResponse> getMediaByTitle(@PathVariable final String title) {
        log.info("getMediaByTitle: "+ title);
        return mediaService.getMediaByTitle(title);
    }

    /** Signed URL of the track's file for playback (returned as text). Lasts the track plus 2 h (seeks re-request it). */
    @GetMapping(value = "/{id}/stream")
    @RolesAllowed({"user"})
    @ResponseStatus(HttpStatus.OK)
    public String getStreamUrlById(@PathVariable final String id) {
        MediaResponse media = findPublished(id);
        String url = cdnSigner.sign(fileUrl(media), false, cdnSigner.streamExpiry(media, new Date()));
        log.info("stream: id={}", id);
        return url;
    }

    /**
     * Signed URL that downloads the track's file (10 min): it carries download=1, for which the CDN origin answers
     * with Content-Disposition: attachment. No entitlement or quota check yet (there are no accounts).
     */
    @PostMapping(value = "/{id}/download")
    @RolesAllowed({"user"})
    @ResponseStatus(HttpStatus.OK)
    public SignedUrlResponse getDownloadUrlById(@PathVariable final String id) {
        MediaResponse media = findPublished(id);
        Date expires = cdnSigner.downloadExpiry(new Date());
        String url = cdnSigner.sign(fileUrl(media), true, expires);
        log.info("download: id={}", id);
        return SignedUrlResponse.builder().url(url).expiresAt(expires.toInstant().toString()).build();
    }

    /** The track, or 404; 503 when no signing key is configured (the CDN origin would refuse the URL) */
    private MediaResponse findPublished(String id) {
        if (!cdnSigner.isConfigured())
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "URL signing is not configured");
        MediaResponse media = mediaService.getMediaById(id);
        if (media == null)
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No media " + id);
        return media;
    }

    private static String fileUrl(MediaResponse media) {
        return CdnUrls.fileUrl(media)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Media " + media.getId() + " has no song_id, so no file"));
    }
}
