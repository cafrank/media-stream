package com.sparkle.mediaservice.config;

import com.sparkle.mediaservice.model.Media;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.event.EventListener;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.index.Index;
import org.springframework.data.mongodb.core.index.IndexOperations;

/**
 * Indexes for GET /api/media/search: each filter, then newest first. Created explicitly because Boot 2.7 has
 * spring.data.mongodb.auto-index-creation off. ensureIndex is a no-op when the index already exists.
 */
@Configuration
@RequiredArgsConstructor
@Slf4j
public class MongoIndexConfig {

    private final MongoTemplate mongoTemplate;

    @EventListener(ApplicationReadyEvent.class)
    public void ensureIndexes() {
        IndexOperations ops = mongoTemplate.indexOps(Media.class);
        for (String field : new String[]{"genre", "remix"}) {
            String name = ops.ensureIndex(new Index().on(field, Sort.Direction.ASC).on("_id", Sort.Direction.DESC)
                    .named(field + "_1__id_-1"));
            log.info("Mongo index {} ensured", name);
        }
    }
}
