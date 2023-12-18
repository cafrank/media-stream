package com.sparkle.authservice.repository;

import com.sparkle.authservice.model.User;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.stream.Stream;

public interface UserRepository extends JpaRepository<User, Long> {
    Optional<User> findByEmail(String email);
    Optional<User> findByUsername(String userName);
    Stream<User> findByUsernameIn(List<String> userName);
    List<User> findByUsernameLike(String userName);
}
