package com.sparkle.mediaservice.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/** One page of GET /api/media/search. total counts every match, not just this page. */
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class MediaPage {
    private List<MediaResponse> items;
    private int page;
    private int size;
    private long total;
}
