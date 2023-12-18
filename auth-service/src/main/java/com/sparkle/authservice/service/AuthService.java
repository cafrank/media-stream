package com.sparkle.authservice.service;

import com.sparkle.authservice.dto.CredentialInput;
import com.sparkle.authservice.dto.UserResponse;
import com.sparkle.authservice.model.User;
import com.sparkle.authservice.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.xml.bind.DatatypeConverter;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.List;
import java.util.Optional;
import java.util.stream.Stream;

@Slf4j
@Service
@RequiredArgsConstructor
//@Transactional(readonly = true)
public class AuthService {

    private final UserRepository userRepository;

    // TODO: Only store password hash
    public static String md5Hash(String str) throws NoSuchAlgorithmException {
        MessageDigest md = MessageDigest.getInstance("MD5");
        md.update(str.getBytes());
        byte[] digest = md.digest();
        return DatatypeConverter.printHexBinary(digest).toUpperCase();
    }

    @Transactional(readOnly = true)
    public boolean isValid(CredentialInput credentialInput) {
        Object i = userRepository.count();
        i = userRepository.findAll();
        log.info("Database records: "+ i);
        Optional<User> user = userRepository.findByUsername(credentialInput.username);
        return user.isPresent() ? user.get().getPassword().equals(credentialInput.password) : false;
    }
    public UserResponse getUser(String id) {
        Optional<User> rc = userRepository.findById(Long.parseLong(id));
        return rc.isPresent() ? userToUserResponse(rc.get()) : null;
    }

    public UserResponse getUserByName(String userName) {
        Optional<User> rc = userRepository.findByUsername(userName);
        return rc.isPresent() ? userToUserResponse(rc.get()) : null;
    }

    public List<UserResponse> getAllUsers() {
        return userStreamToUserResponse(userRepository.findAll().stream()).toList();
    }

    @Transactional(readOnly = true)
    public List<UserResponse> getUsersLike(String partialName) {
        return userStreamToUserResponse(userRepository.findByUsernameLike("%"+ partialName +"%").stream()).toList();
    }

    private Stream<UserResponse> userStreamToUserResponse(Stream<User> userStream) {
        return userStream.map(AuthService::userToUserResponse);
    }

    private static UserResponse userToUserResponse(User i) {
        return UserResponse.builder()
                .id(i.getId())
                .email(i.getEmail())
                .username(i.getUsername())
                .password(i.getPassword())
                .firstName(i.getFirstName())
                .lastName(i.getLastName())
                .build();
    }

    public Long getUserCount() {
        return userRepository.count();
    }
}
