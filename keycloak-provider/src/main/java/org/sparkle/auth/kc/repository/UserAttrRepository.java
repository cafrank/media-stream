package org.sparkle.auth.kc.repository;

import org.sparkle.auth.kc.modle.UserAttr;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserAttrRepository extends JpaRepository<UserAttr, Long> {
}