package com.sparkle.mediaservice.service;

import org.springframework.data.mongodb.core.query.Criteria;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/** Catalog search filters (GET /api/media/search) as a MongoDB Criteria. */
public final class MediaQueries {

    private MediaQueries() {
    }

    /**
     * q: case-insensitive substring of title OR artist, matched literally. genre, version: exact match on
     * genre and remix. A null or blank argument is no filter; no filters is an empty Criteria.
     */
    public static Criteria criteria(String q, String genre, String version) {
        List<Criteria> filters = new ArrayList<>();
        if (q != null && !q.isBlank()) {
            Pattern literal = Pattern.compile(Pattern.quote(q), Pattern.CASE_INSENSITIVE);
            filters.add(new Criteria().orOperator(
                    Criteria.where("title").regex(literal),
                    Criteria.where("artist").regex(literal)));
        }
        if (genre != null && !genre.isBlank())
            filters.add(Criteria.where("genre").is(genre));
        if (version != null && !version.isBlank())
            filters.add(Criteria.where("remix").is(version));

        if (filters.isEmpty())
            return new Criteria();
        if (filters.size() == 1)
            return filters.get(0);
        return new Criteria().andOperator(filters);
    }
}
