package org.sparkle.auth.kc.provider;

import lombok.extern.slf4j.Slf4j;
import org.keycloak.component.ComponentModel;
import org.keycloak.credential.CredentialInput;
import org.keycloak.credential.CredentialInputValidator;
import org.keycloak.models.*;
import org.keycloak.storage.UserStorageProvider;
import org.keycloak.storage.user.UserLookupProvider;
import org.keycloak.storage.user.UserQueryProvider;
import org.sparkle.auth.kc.modle.MyUserModel;
import org.sparkle.auth.kc.modle.UserMy12;
import org.sparkle.auth.kc.repository.UserMy12Repository;
import org.springframework.beans.factory.annotation.Autowired;

import java.util.Map;
import java.util.stream.Stream;

@Slf4j
public class My12UserStorageProvider implements UserStorageProvider,
        UserLookupProvider,
        CredentialInputValidator,
        UserQueryProvider {

    @Autowired
    private UserMy12Repository userRepo;

    private final KeycloakSession ksession;
    private final ComponentModel model;

    // ... private members omitted

    public My12UserStorageProvider(KeycloakSession ksession, ComponentModel model) {
        this.ksession = ksession;
        this.model = model;
    }

    @Override
    public void close() {
        log.info("close called...");
    }

    public Stream<UserModel> searchForUserStream(RealmModel realm, String foo) {
        return searchForUserStream(realm, foo, 0, 1000000);
    }

    public Stream<UserModel> searchForUserStream(RealmModel realm, String foo, Integer firstResult, Integer maxResults) {
        log.info("searchForUserStream("+ foo +")");
        return userRepo.findAll().stream().map(this::toUserModel);
    }

    private UserModel toUserModel(UserMy12 x) {
        //SubjectCredentialManager credMge = new SubjectCredentialManager();

        return MyUserModel.builder()
                .id("" + x.getId())
                .userName(x.getLogin())
                .firstName(x.getFirstName())
                .lastName(x.getLastName())
            //    .myCredMgr(credMge)         // FIXME: Better to pass it here than create one per instance
                .build();
    }

    @Override
    public Stream<UserModel> searchForUserStream(RealmModel realmModel, Map<String, String> map, Integer integer, Integer integer1) {
        return null;
    }

    public UserModel getUserByUsername(RealmModel realm, String foo) {
        log.info("getUserByUsername("+ foo +")");
        return new MyUserModel("f:"+model.getId() +":cfrank0", foo, "cfrank9@osafo.com", "Colin", "Frank");
    }

    @Override
    public UserModel getUserByEmail(RealmModel realmModel, String s) {
        return null;
    }

    public UserModel getUserById(RealmModel realm, String foo) {
        log.info("getUserById("+ foo +")");
        return new MyUserModel("f:"+model.getId() +":cfrank0", foo, "cfrank9@osafo.com", "Colin", "Frank");
    }

    @Override
    public boolean supportsCredentialType(String s) {
        log.info("supportsCredentialType("+s+"): TRUE");
        return true;
    }

    @Override
    public boolean isConfiguredFor(RealmModel realmModel, UserModel userModel, String s) {
        log.info("isConfiguredFor(RealmModel realmModel, UserModel userModel, "+s+"): Not down with OTP");
        return ! "otp".equals(s);
    }


    @Override
    public boolean isValid(RealmModel realmModel, UserModel userModel, CredentialInput credentialInput) {
        log.info("isValid( realmModel, userModel, "+credentialInput+"): TRUE");
        return true;
    }

    @Override
    public int getUsersCount(RealmModel realmModel) {
        log.info("getUserByEmail");
        return 5;
    }

    @Override
    public Stream<UserModel> getUsersStream(RealmModel realmModel) {
        log.info("getUsersStream ============ NULL ============");
        return searchForUserStream(realmModel, "foo");
    }

    @Override
    public Stream<UserModel> getGroupMembersStream(RealmModel realmModel, GroupModel groupModel) {
        log.info("Stream getGroupMembersStream ============ NULL ============");
        return Stream.empty();
    }

    @Override
    public Stream<UserModel> getGroupMembersStream(RealmModel realmModel, GroupModel groupModel, Integer integer, Integer integer1) {
        log.info("Stream getGroupMembersStream ============ NULL ============");
        return Stream.empty();
    }

    @Override
    public Stream<UserModel> searchForUserByUserAttributeStream(RealmModel realmModel, String s, String s1) {
        return null;
    }

    // ... implementation methods for each supported capability
}
