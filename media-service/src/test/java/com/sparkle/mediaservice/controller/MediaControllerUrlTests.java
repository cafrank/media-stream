package com.sparkle.mediaservice.controller;

import com.sparkle.mediaservice.dto.MediaResponse;
import com.sparkle.mediaservice.service.CdnSigner;
import com.sparkle.mediaservice.service.MediaService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.hamcrest.Matchers.*;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Signed stream and download URLs (no Spring context or MongoDB needed). */
class MediaControllerUrlTests {

    private MockMvc mvc;
    private MediaService mediaService;

    @BeforeEach
    void setUp() {
        mediaService = mock(MediaService.class);
        when(mediaService.getMediaById("video"))
                .thenReturn(MediaResponse.builder().id("video").song_id(402391).is_video(true).build());
        when(mediaService.getMediaById("unpublished"))
                .thenReturn(MediaResponse.builder().id("unpublished").is_video(true).build());
        mvc = MockMvcBuilders.standaloneSetup(new MediaController(mediaService, new CdnSigner("testkey", "q83vEjRWeJCrze8SNFZ4kA=="))).build();
    }

    @Test
    void downloadReturnsSignedUrlWithDownloadFlag() throws Exception {
        mvc.perform(post("/api/media/video/download"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.url", startsWith("https://www.my12inch.com/prev/gen3/402391.mp4?download=1&Expires=")))
                .andExpect(jsonPath("$.url", containsString("&Signature=")))
                .andExpect(jsonPath("$.expiresAt", matchesPattern("\\d{4}-\\d{2}-\\d{2}T.*Z")));
    }

    @Test
    void downloadOfUnknownTrackIs404() throws Exception {
        mvc.perform(post("/api/media/missing/download")).andExpect(status().isNotFound());
    }

    @Test
    void downloadOfTrackWithoutSongIdIs404() throws Exception {
        mvc.perform(post("/api/media/unpublished/download")).andExpect(status().isNotFound());
    }

    @Test
    void streamUrlPointsAtTheSongIdFile() throws Exception {
        mvc.perform(get("/api/media/video/stream"))
                .andExpect(status().isOk())
                .andExpect(content().string(startsWith("https://www.my12inch.com/prev/gen3/402391.mp4?Expires=")));
    }

    @Test
    void streamOfUnknownTrackIs404() throws Exception {
        mvc.perform(get("/api/media/missing/stream")).andExpect(status().isNotFound());
    }

    @Test
    void urlsAreSignedWithTheConfiguredKeyName() throws Exception {
        mvc.perform(get("/api/media/video/stream"))
                .andExpect(content().string(containsString("&KeyName=testkey&Signature=")))
                .andExpect(content().string(not(containsString("mykey2"))));
        mvc.perform(post("/api/media/video/download"))
                .andExpect(jsonPath("$.url", containsString("&KeyName=testkey&Signature=")));
    }

    @Test
    void streamUrlLastsFourHoursWhenTheLengthIsUnknown() throws Exception {
        long before = System.currentTimeMillis() / 1000;
        String url = mvc.perform(get("/api/media/video/stream")).andReturn().getResponse().getContentAsString();
        long expires = Long.parseLong(url.replaceAll(".*[?&]Expires=(\\d+).*", "$1"));
        org.junit.jupiter.api.Assertions.assertTrue(expires >= before + 4 * 3600 && expires <= before + 4 * 3600 + 5, url);
    }

    @Test
    void withoutASigningKeyStreamAndDownloadAre503() throws Exception {
        MockMvc unconfigured = MockMvcBuilders.standaloneSetup(new MediaController(mediaService, new CdnSigner("", ""))).build();
        unconfigured.perform(get("/api/media/video/stream")).andExpect(status().isServiceUnavailable());
        unconfigured.perform(post("/api/media/video/download")).andExpect(status().isServiceUnavailable());
    }
}
