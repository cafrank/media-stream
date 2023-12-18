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
@RequestMapping("/api/account")
@RequiredArgsConstructor
public class AccountController {

    private final AccountService accountService;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public void create(@RequestBody AccountRequest accountRequest) {
        accountService.create(accountRequest);
    }

    @GetMapping
    @ResponseStatus(HttpStatus.OK)
    public List<AccountResponse> getAll() {
        log.info("getAllAccounts");
        return accountService.getAll();
    }
}
