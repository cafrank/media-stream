package org.sparkle.auth.kc.provider;

import lombok.extern.slf4j.Slf4j;
import org.keycloak.component.ComponentModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.storage.UserStorageProviderFactory;

@Slf4j
public class FakeUserStorageProviderFactory
        implements UserStorageProviderFactory<FakeUserStorageProvider> {
    @Override
    public String getId() {
        return "Fake";
    }

    @Override
    public FakeUserStorageProvider create(KeycloakSession ksession, ComponentModel model) {
        log.info("Creating FakeUserStorageProvider...");
        return new FakeUserStorageProvider(ksession,model);
    }

//    @Override
//    public FakeUserStorageProvider create(KeycloakSession ksession, ComponentModel model) {
//        log.info("Creating FakeUserStorageProvider...");
//        return new FakeUserStorageProvider(ksession,model);
//    }
}