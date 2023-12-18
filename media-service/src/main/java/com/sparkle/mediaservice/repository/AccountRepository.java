package com.sparkle.mediaservice.repository;

import com.sparkle.mediaservice.model.Account;
import org.springframework.data.mongodb.repository.MongoRepository;

public interface AccountRepository extends MongoRepository<Account, String> {
}
