package org.sparkle.auth.kc.repository;

import lombok.extern.slf4j.Slf4j;
import org.junit.jupiter.api.Test;
import org.sparkle.auth.kc.modle.UserAttr;
import org.sparkle.auth.kc.modle.UserMy12;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.Arrays;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@Testcontainers
//@AutoConfigureMockMvc
@Slf4j

class UserMy12RepositoryTest extends ContainersEnvironment {
    @Autowired
    private UserAttrRepository attrRepo;
    @Autowired
    private UserMy12Repository userRepo;

    @Test
    void contextLoads() {
    }


    @Test
    void smokeTestUserData() {
        attrRepo.getReferenceById(1L);
        userRepo.getReferenceById(1L);
    }

    @Test
    void savedUserHasUserData() {
        UserAttr attr = UserAttr.builder()
        //        .id(1L)
                .mkey("ACL")
                .mvalue("VID").build();
        UserMy12 user = UserMy12.builder()
        //        .id(1L)
                .login("cfrank")
                .email("cfrank@osafo.com")
                .firstName("Colin")
                .lastName ("Frank")
                .attrList(Arrays.asList(attr))
                .build();

        attr.setUser(user);             // To avoid: org.springframework.dao.DataIntegrityViolationException: not-null property references a null or transient value : org.sparkle.auth.kc.modle.UserAttr.user; nested exception is org.hibernate.PropertyValueException: not-null property references a null or transient value : org.sparkle.auth.kc.modle.UserAttr.user
        UserMy12 savedUser = userRepo.save(user);
        //UserMy12 savedUser = this.entityManager.persist(user);
        assertThat(savedUser.getEmail()).isNotNull();
        assertThat(savedUser.getLogin()).isEqualTo("cfrank");
    }

}