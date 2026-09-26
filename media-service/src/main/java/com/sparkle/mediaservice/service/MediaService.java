package com.sparkle.mediaservice.service;

import com.sparkle.mediaservice.dto.MediaFacets;
import com.sparkle.mediaservice.dto.MediaPage;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Query;
import com.sparkle.mediaservice.dto.MediaRequest;
import com.sparkle.mediaservice.dto.MediaResponse;
import com.sparkle.mediaservice.model.Media;
import com.sparkle.mediaservice.repository.MediaRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;

@Service
@RequiredArgsConstructor
@Slf4j
public class MediaService {

    private final MediaRepository mediaRepository;
    private final MongoTemplate mongoTemplate;

    public void createMedia(MediaRequest mediaRequest) {
        Media media =  Media.builder()
                .songId(mediaRequest.getSong_id())
                .title(mediaRequest.getTitle())
                .artist(mediaRequest.getArtist())
                .genre(mediaRequest.getGenre())
                .remix(mediaRequest.getRemix())
                .label(mediaRequest.getLabel())
                .file (mediaRequest.getFile())
                .bpm  (mediaRequest.getBpm())
                .key  (mediaRequest.getKey())
                .year (mediaRequest.getYear())
                .price(mediaRequest.getPrice())
                .isVideo(mediaRequest.getIs_video())
                .isKaraoke(mediaRequest.getIs_karaoke())
                .comment  (mediaRequest.getArtist())
                .coverUrl (mediaRequest.getCover_url())
                .build();

        mediaRepository.save(media);
        log.info("Media {} is saved", media.getSongId());
    }

    public void deleteAllMedia() {
        mediaRepository.deleteAll();
    }

    public List<MediaResponse> getAllMedia() {
        List<Media> media = mediaRepository.findAll();
        return media.stream().map(this::mapToMediaResponse).toList();
    }

    public List<MediaResponse> getMediaByTitle(String title) {
        List<Media> media = mediaRepository.findByTitleOrArtistLike(title, title);
        return media.stream().map(this::mapToMediaResponse).toList();
    }

    /** One page of the catalog, newest first. page and size are validated by the caller. */
    public MediaPage search(String q, String genre, String version, int page, int size) {
        Query query = new Query(MediaQueries.criteria(q, genre, version));
        long total = mongoTemplate.count(query, Media.class);
        query.with(Sort.by(Sort.Direction.DESC, "_id")).skip((long) page * size).limit(size);
        List<MediaResponse> items = mongoTemplate.find(query, Media.class).stream().map(this::mapToMediaResponse).toList();
        return MediaPage.builder().items(items).page(page).size(size).total(total).build();
    }

    public MediaFacets facets() {
        return MediaFacets.builder().genres(distinct("genre")).versions(distinct("remix")).build();
    }

    private List<String> distinct(String field) {
        return mongoTemplate.findDistinct(new Query(), field, Media.class, String.class).stream()
                .filter(v -> v != null && !v.isBlank())
                .sorted()
                .toList();
    }

    public MediaResponse getMediaById(String id) {
        Optional<Media> media = mediaRepository.findById(id);
        return media.isPresent() ? mapToMediaResponse(media.get()) : null;
    }

    private MediaResponse mapToMediaResponse(Media media) {
        return MediaResponse.builder()
                .id(media.getId())
                .song_id(media.getSongId())
                .title(media.getTitle())
                .artist(media.getArtist())
                .genre(media.getGenre())
                .remix(media.getRemix())
                .label(media.getLabel())
                .file (media.getFile())
                .bpm  (media.getBpm())
                .key  (media.getKey())
                .year (media.getYear())
                .is_video(media.getIsVideo())
                .is_karaoke(media.getIsKaraoke())
                .comment(media.getArtist())
                .cover_url(media.getCoverUrl())
                .price(media.getPrice())
                .build();
    }
}
