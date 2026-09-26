package com.sparkle.mediaservice.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/** GET /api/media/facets: the distinct genre and version (remix) values, for filter dropdowns. */
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class MediaFacets {
    private List<String> genres;
    private List<String> versions;
}
