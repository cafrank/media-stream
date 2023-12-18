package com.sparkle.mediaservice.repository;

import com.sparkle.mediaservice.model.Media;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.List;

public interface MediaRepository extends MongoRepository<Media, String> {

    //public Media findById(String song);
    public List<Media> findByTitleLike(String song);
    public List<Media> findByArtistLike(String song);
    public List<Media> findByTitleOrArtistLike(String title, String artist);

}
