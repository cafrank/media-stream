package com.sparkle.mediaservice.controller;

import com.sparkle.mediaservice.dto.AccountRequest;
import com.sparkle.mediaservice.dto.AccountResponse;
import com.sparkle.mediaservice.service.AccountService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Slf4j
@RestController
@CrossOrigin(origins = "http://localhost:3000")
@RequestMapping("/")
@RequiredArgsConstructor
public class RootController {

    @GetMapping
    @ResponseStatus(HttpStatus.OK)
    public String getRoot() {
        log.info("getRoot");
        return "OK";
    }

    @GetMapping(value = "version")
    @ResponseStatus(HttpStatus.OK)
    public String getError() {
        return "2";
    }
}
