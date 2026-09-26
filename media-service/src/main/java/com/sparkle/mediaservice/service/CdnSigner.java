package com.sparkle.mediaservice.service;

import com.sparkle.mediaservice.dto.MediaResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;
import java.util.Date;

/**
 * Signs CDN file URLs with the key the origin checks (www.my12inch.com, mod_lua signed_urls.lua, #17).
 * The key comes from the environment (SIGNING_KEY_NAME, SIGNING_KEY: base64url, from a Secret), never from
 * the source. Without it, isConfigured() is false and callers refuse to hand out URLs.
 */
@Component
@Slf4j
public class CdnSigner {

    /** A stream URL is requested again for every seek and buffer refill, so it lasts the whole track */
    static final long STREAM_MARGIN_SECONDS = 2 * 3600;
    static final long STREAM_UNKNOWN_LENGTH_SECONDS = 4 * 3600;
    static final long DOWNLOAD_SECONDS = 600;

    private final String keyName;
    private final byte[] key;

    public CdnSigner(@Value("${SIGNING_KEY_NAME:}") String keyName, @Value("${SIGNING_KEY:}") String keyBase64Url) {
        this.keyName = keyName == null ? "" : keyName.trim();
        byte[] decoded = new byte[0];
        if (keyBase64Url != null && !keyBase64Url.isBlank()) {
            try {
                decoded = Base64.getUrlDecoder().decode(keyBase64Url.trim());
            } catch (IllegalArgumentException e) {
                log.error("SIGNING_KEY is not base64url; stream and download URLs are disabled");
            }
        }
        this.key = decoded;
        if (!isConfigured())
            log.warn("SIGNING_KEY_NAME/SIGNING_KEY not set; /stream and /download answer 503");
    }

    public boolean isConfigured() {
        return !keyName.isEmpty() && key.length > 0;
    }

    public String sign(String fileUrl, boolean download, Date expires) {
        try {
            return CdnUrls.signedUrl(fileUrl, download, key, keyName, expires);
        } catch (InvalidKeyException | NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    public Date streamExpiry(MediaResponse media, Date now) {
        long seconds = media.getLength() != null ? media.getLength() + STREAM_MARGIN_SECONDS : STREAM_UNKNOWN_LENGTH_SECONDS;
        return new Date(now.getTime() + seconds * 1000);
    }

    public Date downloadExpiry(Date now) {
        return new Date(now.getTime() + DOWNLOAD_SECONDS * 1000);
    }
}
