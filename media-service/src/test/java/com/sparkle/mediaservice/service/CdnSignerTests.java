package com.sparkle.mediaservice.service;

import com.sparkle.mediaservice.dto.MediaResponse;
import org.junit.jupiter.api.Test;

import java.util.Base64;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.*;

class CdnSignerTests {

    private static final String KEY_B64 = "q83vEjRWeJCrze8SNFZ4kA==";
    private static final Date NOW = new Date(1_800_000_000_000L);

    private static CdnSigner signer() {
        return new CdnSigner("testkey", KEY_B64);
    }

    @Test
    void unconfiguredWithoutKeyOrKeyName() {
        assertFalse(new CdnSigner("", KEY_B64).isConfigured());
        assertFalse(new CdnSigner("testkey", " ").isConfigured());
        assertTrue(signer().isConfigured());
    }

    @Test
    void signsWithTheConfiguredKeyAndKeyName() throws Exception {
        Date expires = new Date(NOW.getTime() + 60_000);
        String url = signer().sign("https://www.my12inch.com/prev/gen3/402391.mp4", true, expires);

        assertTrue(url.contains("?download=1&Expires=1800000060&KeyName=testkey&Signature="), url);
        byte[] key = Base64.getUrlDecoder().decode(KEY_B64);
        assertEquals(expires.getTime() / 1000, GcsSignUrl.checkUrlSignature(url, key, "testkey").getTime() / 1000);
    }

    @Test
    void streamUrlsLastTheTrackPlusTwoHours() {
        MediaResponse media = MediaResponse.builder().length(300).build();
        assertEquals(NOW.getTime() + (300 + 2 * 3600) * 1000L, signer().streamExpiry(media, NOW).getTime());
    }

    @Test
    void streamUrlsLastFourHoursWhenTheLengthIsUnknown() {
        assertEquals(NOW.getTime() + 4 * 3600 * 1000L, signer().streamExpiry(MediaResponse.builder().build(), NOW).getTime());
    }

    @Test
    void downloadUrlsLastTenMinutes() {
        assertEquals(NOW.getTime() + 600 * 1000L, signer().downloadExpiry(NOW).getTime());
    }
}
