package com.sparkle.mediaservice.service;

import com.sparkle.mediaservice.dto.AccountRequest;
import com.sparkle.mediaservice.dto.AccountResponse;
import com.sparkle.mediaservice.model.Account;
import com.sparkle.mediaservice.repository.AccountRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@RequiredArgsConstructor
@Slf4j
public class AccountService {

    private final AccountRepository repo;


    public void create(AccountRequest accountRequest) {
        Account account =  Account.builder()
                .name(accountRequest.getName())
                .description(accountRequest.getDescription())
                .build();

        repo.save(account);
        log.info("Account {} is saved", account.getId());
    }

    public List<AccountResponse> getAll() {
        List<Account> products = repo.findAll();
        return products.stream().map(this::mapToResponse).toList();
    }

    private AccountResponse mapToResponse(Account account) {
        return AccountResponse.builder()
                .id(account.getId())
                .name(account.getName())
                .description(account.getDescription())
                .balance(account.getBalance())
                .build();
    }
}
