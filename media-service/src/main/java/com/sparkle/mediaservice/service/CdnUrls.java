package com.sparkle.mediaservice.service;

import com.sparkle.mediaservice.dto.MediaResponse;

import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.util.Date;
import java.util.Optional;

/**
 * Where a track's file lives on the CDN, and signed URLs to it.
 * Files are published as {@code /prev/gen3/<song_id>.mp4} (video) or {@code .mp3} (audio).
 */
public final class CdnUrls {

    public static final String BASE_URL = "https://www.my12inch.com/prev/gen3/";

    private CdnUrls() {
    }

    /** The unsigned file URL, or empty when the track has no song_id (it was never published). */
    public static Optional<String> fileUrl(MediaResponse media) {
        if (media.getSong_id() == null)
            return Optional.empty();
        String ext = Boolean.TRUE.equals(media.getIs_video()) ? "mp4" : "mp3";
        return Optional.of(BASE_URL + media.getSong_id() + "." + ext);
    }

    /**
     * Signs {@code fileUrl}. With {@code download}, {@code download=1} is part of the signed URL, so the
     * origin can answer with Content-Disposition: attachment and the flag can't be added to a stream URL.
     */
    public static String signedUrl(String fileUrl, boolean download, byte[] key, String keyName, Date expires)
            throws InvalidKeyException, NoSuchAlgorithmException {
        return GcsSignUrl.signUrl(download ? fileUrl + "?download=1" : fileUrl, key, keyName, expires);
    }
}
