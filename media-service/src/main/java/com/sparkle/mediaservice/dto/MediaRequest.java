package com.sparkle.mediaservice.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;

@Data           // == @Getter + @Setter
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class MediaRequest {
    private Integer song_id;
    private String title;
    private String artist;
    private String genre;
    private String remix;
    private String label;
    private String file;
    private Integer bpm;
    private Integer key;
    private Integer year;
    private Boolean is_video;
    private Boolean is_karaoke;
    private Integer length;
    private String comment;
    private String cover_url;
    private BigDecimal price;
}
