package com.sparkle.authservice.controller;

import com.sparkle.authservice.dto.CredentialInput;
import com.sparkle.authservice.dto.UserResponse;
import com.sparkle.authservice.service.AuthService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;

import javax.annotation.security.RolesAllowed;
import java.util.List;

@RestController
@RequestMapping("/api/auth")
@Slf4j
@RequiredArgsConstructor
public class AuthController {
        private final AuthService authService;

        @GetMapping(path = "/user")
        @ResponseStatus(HttpStatus.OK)
        public List<UserResponse> getAllUsers() {
                log.info("getAllUsers");
                return authService.getAllUsers();
        }

        @GetMapping(path = "/user/{userName}")
        @ResponseStatus(HttpStatus.OK)
        public List<UserResponse> getUsersByNameLike(@PathVariable("userName")  String userName) {
                List<UserResponse> rc = authService.getUsersLike(userName);
                log.info("getUsersByNameLike("+userName+"): "+ rc);
                return rc;
        }

        @Deprecated
        @GetMapping(path = "/user/like/{userName}")
        @ResponseStatus(HttpStatus.OK)
        public List<UserResponse> getUsersByNameLikeX(@PathVariable("userName")  String userName) {
                List<UserResponse> rc = authService.getUsersLike(userName);
                log.info("getUsersByNameLikeX("+userName+"): "+ rc);
                return rc;
        }

        @GetMapping(path = "/user/id/{id}")
        @ResponseStatus(HttpStatus.OK)
        public UserResponse getUser(@PathVariable("id")  String id) {
                log.info("getUser("+id+"): 4L");
                return authService.getUser(id);
        }

        @GetMapping(path = "/user/name/{userName}")
        @ResponseStatus(HttpStatus.OK)
        public UserResponse getUserByName(@PathVariable("userName")  String userName) {
                log.info("getUserByName("+userName+"): 4L");
                return authService.getUserByName(userName);
        }

        @GetMapping(path = "/count")
        @ResponseStatus(HttpStatus.OK)
        public Long getUserCount() {
                log.info("getUserCount(): "+ authService.getUserCount());
                return authService.getUserCount();
        }

        //@PostMapping(path = "/isValid", consumes = {MediaType.APPLICATION_FORM_URLENCODED_VALUE})
        @PostMapping(path = "/isValid", consumes = {"application/json", MediaType.MULTIPART_FORM_DATA_VALUE})
        @RolesAllowed({"user"})                     // FIXME: Test authorization failure
        @ResponseStatus(HttpStatus.OK)
        public boolean isUserValid(@RequestBody CredentialInput credentialInput) {
                log.info("isValid(."+credentialInput.username+"): "+ authService.isValid(credentialInput));
                return authService.isValid(credentialInput);
        }
}
