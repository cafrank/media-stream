package com.sparkle.mediaservice.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/** A short-lived signed CDN URL (POST /api/media/{id}/download). */
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class SignedUrlResponse {
    private String url;
    /** ISO-8601, UTC */
    private String expiresAt;
}
