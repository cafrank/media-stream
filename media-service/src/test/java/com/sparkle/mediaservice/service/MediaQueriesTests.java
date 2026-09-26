package com.sparkle.mediaservice.service;

import org.bson.Document;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.*;

class MediaQueriesTests {

    private static Document doc(String q, String genre, String version) {
        return MediaQueries.criteria(q, genre, version).getCriteriaObject();
    }

    /** The regex that the criteria applies to one field inside an $or */
    private static Pattern regexOn(Document or, String field) {
        return (Pattern) or.get(field);
    }

    @Test
    void noFiltersMatchesEverything() {
        assertEquals(new Document(), doc(null, null, null));
        assertEquals(new Document(), doc("", " ", ""));
    }

    @Test
    void qIsCaseInsensitiveSubstringOnTitleOrArtist() {
        Document d = doc("Nirvana", null, null);
        @SuppressWarnings("unchecked")
        List<Document> or = (List<Document>) d.get("$or");
        assertEquals(2, or.size());
        Pattern title = regexOn(or.get(0), "title");
        Pattern artist = regexOn(or.get(1), "artist");
        for (Pattern p : List.of(title, artist)) {
            assertTrue((p.flags() & Pattern.CASE_INSENSITIVE) != 0);
            assertTrue(p.matcher("SMELLS LIKE NIRVANA SPIRIT").find());
            assertFalse(p.matcher("Nirv").find());
        }
    }

    @Test
    void qMetacharactersMatchLiterally() {
        for (String q : List.of("a.b", "(", "*", "\\", "[x", "a+b")) {
            @SuppressWarnings("unchecked")
            Pattern p = regexOn(((List<Document>) doc(q, null, null).get("$or")).get(0), "title");
            assertTrue(p.matcher("xx" + q + "yy").find(), q);
        }
        @SuppressWarnings("unchecked")
        Pattern dot = regexOn(((List<Document>) doc("a.b", null, null).get("$or")).get(0), "title");
        assertFalse(dot.matcher("axb").find(), "'.' must not be a wildcard");
    }

    @Test
    void genreAndVersionMatchExactly() {
        assertEquals(new Document("genre", "HOUSE"), doc(null, "HOUSE", null));
        assertEquals(new Document("remix", "Clean"), doc(null, null, "Clean"));
    }

    @Test
    void filtersCombineWithAnd() {
        Document d = doc("love", "HOUSE", "Clean");
        @SuppressWarnings("unchecked")
        List<Document> and = (List<Document>) d.get("$and");
        assertEquals(3, and.size());
        assertTrue(and.get(0).containsKey("$or"));
        assertEquals(new Document("genre", "HOUSE"), and.get(1));
        assertEquals(new Document("remix", "Clean"), and.get(2));
    }
}
