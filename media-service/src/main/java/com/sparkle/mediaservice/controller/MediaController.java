package com.sparkle.mediaservice.controller;

import com.sparkle.mediaservice.dto.MediaRequest;
import com.sparkle.mediaservice.dto.MediaResponse;
import com.sparkle.mediaservice.dto.SignedUrlResponse;
import com.sparkle.mediaservice.service.CdnUrls;
import com.sparkle.mediaservice.service.MediaService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import javax.annotation.security.RolesAllowed;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;
import java.util.Calendar;
import java.util.Date;
import java.util.List;

@Slf4j
@RestController
@CrossOrigin(origins = "http://localhost:3000")
@RequestMapping("/api/media")
@RequiredArgsConstructor
public class MediaController {

    private final MediaService mediaService;

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

    @GetMapping(value = "/{title}")
    //@RolesAllowed({"user"})
    @ResponseStatus(HttpStatus.OK)
    public List<MediaResponse> getMediaByTitle(@PathVariable final String title) {
        log.info("getMediaByTitle: "+ title);
        return mediaService.getMediaByTitle(title);
    }

    private static byte[] getKey() {
        return "-MFzY6rtSErABnLtV9hyqg==".getBytes();
    }

    public Date getMediaExpriation() {
        Calendar cal = Calendar.getInstance();
        cal.setTime(new Date());
        // cal.add(Calendar.DATE, 1);
        // cal.add(Calendar.MINUTE, 1);    // One minute to download
        cal.add(Calendar.MILLISECOND, 50000);    // Five seconds to download before the URL is invalid
        return cal.getTime();
    }

    /** Signed URL of the track's file for playback (returned as text). */
    @GetMapping(value = "/{id}/stream")
    @RolesAllowed({"user"})
    @ResponseStatus(HttpStatus.OK)
    public String getStreamUrlById(@PathVariable final String id) {
        log.info("getStreamUrlById: "+ id);
        String rc = signFileUrl(id, false, getMediaExpriation());
        log.info("Signed URL: "+ rc);
        return rc;
    }

    /**
     * Signed URL that downloads the track's file: it carries download=1, for which the CDN origin answers
     * with Content-Disposition: attachment. No entitlement or quota check yet (there are no accounts).
     */
    @PostMapping(value = "/{id}/download")
    @RolesAllowed({"user"})
    @ResponseStatus(HttpStatus.OK)
    public SignedUrlResponse getDownloadUrlById(@PathVariable final String id) {
        Date expires = getMediaExpriation();
        String url = signFileUrl(id, true, expires);
        log.info("download: id={} url={}", id, url);
        return SignedUrlResponse.builder().url(url).expiresAt(expires.toInstant().toString()).build();
    }

    private String signFileUrl(String id, boolean download, Date expires) {
        String keyName = "mykey2";
        byte[] key = Base64.getUrlDecoder().decode("dvCuEDg4jJsTXIQgt6CkbA==");

        MediaResponse media = mediaService.getMediaById(id);
        if (media == null)
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No media " + id);
        // String url = "https://media-cdn/prev/gen3/"+ id;
        // https://docs.bridgecrew.io/docs/bc_gcp_networking_3
        // openssl s_client -connect 104.26.3.5:443 -servername external.example.com
        String url = CdnUrls.fileUrl(media)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Media " + id + " has no song_id, so no file"));
        try {
            return CdnUrls.signedUrl(url, download, key, keyName, expires);
        } catch (InvalidKeyException | NoSuchAlgorithmException e) {
            throw new RuntimeException(e);
        }
    }
}
