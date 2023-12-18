package org.sparkle.auth.kc.provider;

import dasniko.testcontainers.keycloak.KeycloakContainer;
import org.junit.jupiter.api.Test;
import org.keycloak.admin.client.Keycloak;
import org.keycloak.admin.client.KeycloakBuilder;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.io.File;
import java.util.Arrays;
import java.util.Map;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.junit.jupiter.api.Assertions.*;

// https://www.youtube.com/watch?v=FEbIW23RoXk&t=313s

@Testcontainers
class FakeUserStorageProviderTest {

//  /realms/Services/.well-known/openid-configuration
//  /realms/Services/protocol/openid-connect/token

    static File[] fileArray = {
            new File("target/org.sparkle-auth.jar"),
    };
    @Container
    KeycloakContainer KEYCLOAK = new KeycloakContainer()
            .withRealmImportFile("realm.json")
            //.withRealmImportFile("test-realm.json")
            .withProviderLibsFrom(Arrays.asList(fileArray));

    @Test
    void getOpenIdToken() throws InterruptedException {
        assertTrue(KEYCLOAK.isRunning());

        String authServerUrl = KEYCLOAK.getAuthServerUrl();
        System.out.println(authServerUrl + "/realms/Services/protocol/openid-connect/token");
        Thread.sleep(500);

        // This needs a full setup user with a role, not the admin user.
        String accessToken = given()
                .contentType("application/x-www-form-urlencoded")
                .formParams(Map.of(
                        "username", "foo",
                        "password", "bar",
                        "grant_type", "password",
                        "client_id", "product-app" //, "client_secret", "secret"
                ))
                .post(authServerUrl + "/realms/Services/protocol/openid-connect/token")
                .then().assertThat().statusCode(200)
                .extract().path("access_token");

        System.out.println("=====================================================================================");
        System.out.println(accessToken);
        System.out.println("=====================================================================================");

//        given().header("Authorization", accessToken)
//                .when()
//                .get(authServerUrl + "/users/me")   // ???
//                .then()
//                .body("username", equalTo("foo"))
//                .body("lastname", equalTo("Frank"))
//                .body("firstname", equalTo("Colin"))
//                .body("email", equalTo("cfrank@osafo.com"));
    }

    /*
    @Test
    void close() {
    }

    @Test
    void searchForUserStream() {
    }

    @Test
    void testSearchForUserStream() {
    }

    @Test
    void testSearchForUserStream1() {
    }

    @Test
    void getUserByUsername() {
    }

    @Test
    void getUserByEmail() {
    }

    @Test
    void supportsCredentialType() {
    }

    @Test
    void isConfiguredFor() {
    }

    @Test
    void isValid() {
    }

    @Test
    void getUsersCount() {
    }

    @Test
    void getUsersStream() {
    }

    @Test
    void getGroupMembersStream() {
    }

    @Test
    void testGetGroupMembersStream() {
    }

    @Test
    void searchForUserByUserAttributeStream() {
    }
    */
}