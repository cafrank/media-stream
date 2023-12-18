package org.sparkle.auth.kc.provider;

import lombok.extern.slf4j.Slf4j;
import org.keycloak.component.ComponentModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.storage.UserStorageProviderFactory;

@Slf4j
public class My12UserStorageProviderFactory
        implements UserStorageProviderFactory<My12UserStorageProvider> {
    @Override
    public String getId() {
        return "JpaMy12";
    }

    @Override
    public My12UserStorageProvider create(KeycloakSession ksession, ComponentModel model) {
        log.info("Creating JpaMy12 UserStorageProvider...");
        return new My12UserStorageProvider(ksession,model);
    }

//    @Override
//    public FakeUserStorageProvider create(KeycloakSession ksession, ComponentModel model) {
//        log.info("Creating FakeUserStorageProvider...");
//        return new FakeUserStorageProvider(ksession,model);
//    }
}