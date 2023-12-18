package com.sparkle.mediaservice.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import java.math.BigDecimal;

@Document(value = "media")
@AllArgsConstructor
@NoArgsConstructor
@Builder
@Data
public class Media {
    @Id
    private String id;
    private Integer songId;
    private String title;
    private String artist;
    private String genre;
    private String remix;
    private String label;
    private String file;
    private Integer bpm;
    private Integer key;
    private Integer year;
    private Boolean isVideo;
    private Boolean isKaraoke;
    private Integer length;
    private String comment;
    private String coverUrl;
    private BigDecimal price;
}
