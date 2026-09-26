package com.sparkle.mediaservice.controller;

import com.sparkle.mediaservice.dto.MediaResponse;
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

    @BeforeEach
    void setUp() {
        MediaService mediaService = mock(MediaService.class);
        when(mediaService.getMediaById("video"))
                .thenReturn(MediaResponse.builder().id("video").song_id(402391).is_video(true).build());
        when(mediaService.getMediaById("unpublished"))
                .thenReturn(MediaResponse.builder().id("unpublished").is_video(true).build());
        mvc = MockMvcBuilders.standaloneSetup(new MediaController(mediaService)).build();
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
}
