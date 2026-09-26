package com.sparkle.mediaservice.config;

import com.sparkle.mediaservice.model.Media;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.index.IndexDefinition;
import org.springframework.data.mongodb.core.index.IndexOperations;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.*;

class MongoIndexConfigTests {

    @Test
    void ensuresGenreAndRemixIndexesSortedNewestFirst() {
        MongoTemplate mongoTemplate = mock(MongoTemplate.class);
        IndexOperations ops = mock(IndexOperations.class);
        when(mongoTemplate.indexOps(Media.class)).thenReturn(ops);

        new MongoIndexConfig(mongoTemplate).ensureIndexes();

        ArgumentCaptor<IndexDefinition> defs = ArgumentCaptor.forClass(IndexDefinition.class);
        verify(ops, times(2)).ensureIndex(defs.capture());
        List<IndexDefinition> all = defs.getAllValues();
        assertEquals(new Document("genre", 1).append("_id", -1), all.get(0).getIndexKeys());
        assertEquals("genre_1__id_-1", all.get(0).getIndexOptions().get("name"));
        assertEquals(new Document("remix", 1).append("_id", -1), all.get(1).getIndexKeys());
        assertEquals("remix_1__id_-1", all.get(1).getIndexOptions().get("name"));
    }
}
