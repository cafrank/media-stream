package org.sparkle.auth.kc.provider;

import lombok.extern.slf4j.Slf4j;
import org.keycloak.component.ComponentModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.storage.UserStorageProviderFactory;

@Slf4j
public class ApiUserStorageProviderFactory
        implements UserStorageProviderFactory<ApiUserStorageProvider> {
    @Override
    public String getId() {
        return "ApiMy12";
    }

    @Override
    public ApiUserStorageProvider create(KeycloakSession ksession, ComponentModel model) {
        log.info("Creating ApiMy12 UserStorageProvider...");
        return new ApiUserStorageProvider(ksession,model);
    }
}