package com.sparkle.mediaservice.service;

import com.sparkle.mediaservice.dto.MediaResponse;
import org.junit.jupiter.api.Test;

import java.util.Base64;
import java.util.Date;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;

class CdnUrlsTests {

    private static final byte[] KEY = Base64.getUrlDecoder().decode("dvCuEDg4jJsTXIQgt6CkbA==");
    private static final String KEY_NAME = "test-key";

    @Test
    void videoTrackMapsToSongIdMp4() {
        MediaResponse media = MediaResponse.builder().id("abc").song_id(402391).is_video(true).build();
        assertEquals(Optional.of("https://www.my12inch.com/prev/gen3/402391.mp4"), CdnUrls.fileUrl(media));
    }

    @Test
    void audioTrackMapsToSongIdMp3() {
        MediaResponse media = MediaResponse.builder().id("abc").song_id(1001).is_video(false).build();
        assertEquals(Optional.of("https://www.my12inch.com/prev/gen3/1001.mp3"), CdnUrls.fileUrl(media));
    }

    @Test
    void unknownIsVideoMeansAudio() {
        MediaResponse media = MediaResponse.builder().id("abc").song_id(1001).build();
        assertEquals(Optional.of("https://www.my12inch.com/prev/gen3/1001.mp3"), CdnUrls.fileUrl(media));
    }

    @Test
    void trackWithoutSongIdHasNoFile() {
        MediaResponse media = MediaResponse.builder().id("abc").is_video(true).build();
        assertEquals(Optional.empty(), CdnUrls.fileUrl(media));
    }

    @Test
    void downloadUrlSignsTheDownloadFlag() throws Exception {
        Date expires = new Date(1_800_000_000_000L);
        String url = CdnUrls.signedUrl("https://www.my12inch.com/prev/gen3/402391.mp4", true, KEY, KEY_NAME, expires);

        assertTrue(url.startsWith("https://www.my12inch.com/prev/gen3/402391.mp4?download=1&Expires=1800000000&KeyName=test-key&Signature="), url);
        assertEquals(expires, GcsSignUrl.checkUrlSignature(url, KEY, KEY_NAME));
        // Stripping the flag from a signed download URL (or adding it to a stream URL) breaks the signature
        assertNull(GcsSignUrl.checkUrlSignature(url.replace("download=1&", ""), KEY, KEY_NAME));
    }

    @Test
    void streamUrlHasNoDownloadFlag() throws Exception {
        Date expires = new Date(1_800_000_000_000L);
        String url = CdnUrls.signedUrl("https://www.my12inch.com/prev/gen3/402391.mp4", false, KEY, KEY_NAME, expires);

        assertTrue(url.startsWith("https://www.my12inch.com/prev/gen3/402391.mp4?Expires=1800000000&KeyName=test-key&Signature="), url);
        assertEquals(expires, GcsSignUrl.checkUrlSignature(url, KEY, KEY_NAME));
    }
}
