package com.sparkle.mediaservice.service;

import com.sparkle.mediaservice.dto.MediaFacets;
import com.sparkle.mediaservice.dto.MediaPage;
import com.sparkle.mediaservice.model.Media;
import com.sparkle.mediaservice.repository.MediaRepository;
import org.bson.Document;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Query;

import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class MediaServiceSearchTests {

    private MongoTemplate mongoTemplate;
    private MediaService service;

    @BeforeEach
    void setUp() {
        mongoTemplate = mock(MongoTemplate.class);
        service = new MediaService(mock(MediaRepository.class), mongoTemplate);
    }

    @Test
    void searchPagesNewestFirstAndCountsAllMatches() {
        Media m = Media.builder().id("abc").songId(402391).title("HIGHLIFE").artist("KARMA").isVideo(true).length(300).build();
        when(mongoTemplate.find(any(Query.class), eq(Media.class))).thenReturn(List.of(m));
        when(mongoTemplate.count(any(Query.class), eq(Media.class))).thenReturn(123L);

        MediaPage result = service.search("karma", "HOUSE", null, 2, 50);

        ArgumentCaptor<Query> find = ArgumentCaptor.forClass(Query.class);
        verify(mongoTemplate).find(find.capture(), eq(Media.class));
        Query q = find.getValue();
        assertEquals(100, q.getSkip());
        assertEquals(50, q.getLimit());
        assertEquals(new Document("_id", -1), q.getSortObject());
        // java.util.regex.Pattern has no equals(), so compare the rendered documents
        assertEquals(MediaQueries.criteria("karma", "HOUSE", null).getCriteriaObject().toString(), q.getQueryObject().toString());

        ArgumentCaptor<Query> count = ArgumentCaptor.forClass(Query.class);
        verify(mongoTemplate).count(count.capture(), eq(Media.class));
        assertEquals(q.getQueryObject().toString(), count.getValue().getQueryObject().toString());

        assertEquals(2, result.getPage());
        assertEquals(50, result.getSize());
        assertEquals(123L, result.getTotal());
        assertEquals(1, result.getItems().size());
        assertEquals("abc", result.getItems().get(0).getId());
        assertEquals(402391, result.getItems().get(0).getSong_id());
        assertEquals(Boolean.TRUE, result.getItems().get(0).getIs_video());
        assertEquals(300, result.getItems().get(0).getLength());
    }

    @Test
    void facetsAreDistinctNonEmptyAndSorted() {
        when(mongoTemplate.findDistinct(any(Query.class), eq("genre"), eq(Media.class), eq(String.class)))
                .thenReturn(Arrays.asList("TRAP", null, "", "AFRO BEATS", "HOUSE"));
        when(mongoTemplate.findDistinct(any(Query.class), eq("remix"), eq(Media.class), eq(String.class)))
                .thenReturn(Arrays.asList("Dirty", " ", "Clean"));

        MediaFacets facets = service.facets();

        assertEquals(List.of("AFRO BEATS", "HOUSE", "TRAP"), facets.getGenres());
        assertEquals(List.of("Clean", "Dirty"), facets.getVersions());
    }
}
