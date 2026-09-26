package com.sparkle.mediaservice.controller;

import com.sparkle.mediaservice.dto.MediaFacets;
import com.sparkle.mediaservice.dto.MediaPage;
import com.sparkle.mediaservice.dto.MediaResponse;
import com.sparkle.mediaservice.service.CdnSigner;
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
        mvc = MockMvcBuilders.standaloneSetup(new MediaController(mediaService, new CdnSigner("", ""))).build();
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
