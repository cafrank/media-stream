package org.sparkle.auth.kc.provider;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.DeserializationContext;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.KeyDeserializer;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.module.SimpleModule;
import lombok.extern.slf4j.Slf4j;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClientBuilder;
import org.keycloak.component.ComponentModel;
import org.keycloak.credential.CredentialInput;
import org.keycloak.credential.CredentialInputValidator;
import org.keycloak.models.*;
import org.keycloak.storage.UserStorageProvider;
import org.keycloak.storage.user.UserLookupProvider;
import org.keycloak.storage.user.UserQueryProvider;
import org.keycloak.storage.user.UserBulkUpdateProvider;
import org.keycloak.storage.user.UserRegistrationProvider;
import org.sparkle.auth.kc.modle.MyUserModel;
import org.sparkle.auth.kc.modle.UserMy12;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.*;
import java.util.stream.Stream;

@Slf4j
public class ApiUserStorageProvider implements UserStorageProvider,
        UserLookupProvider,
        CredentialInputValidator,
        UserBulkUpdateProvider,
        UserRegistrationProvider,
        UserQueryProvider {


    private final String adapterBaseUrl = "http://adapter-svc:8085";
    private final KeycloakSession ksession;
    private final ComponentModel model;

    // ... private members omitted

    public ApiUserStorageProvider(KeycloakSession ksession, ComponentModel model) {
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

    @Override
    public void grantToAllUsers(RealmModel realmModel, RoleModel roleModel) {
        log.info(" ***************** grantToAllUsers(" + realmModel.getDisplayName() + ", " + roleModel.getName());
    }

    @Override
    public UserModel addUser(RealmModel realmModel, String s) {
        log.info(" ***************** addUser(" + realmModel.getDisplayName() + ", " + s);
        return null;
    }

    @Override
    public boolean removeUser(RealmModel realmModel, UserModel userModel) {
        log.info(" ***************** removeUser(" + realmModel.getDisplayName() + ", " + userModel.getUsername());
        return false;
    }

    // https://stackoverflow.com/questions/6371092/can-not-find-a-map-key-deserializer-for-type-simple-type-class
    class ClientModelKeyDeserializer extends KeyDeserializer {
        @Override
        public Object deserializeKey(final String key, final DeserializationContext ctxt) throws IOException, JsonProcessingException {
            log.info("ClientModelKeyDeserializer.deserializeKey: " + key);
            return null; // replace null with your logic
        }
    }

    private UserModel toUserModel(UserMy12 x) {
        //SubjectCredentialManager credMge = new SubjectCredentialManager();

        return MyUserModel.builder()
                .id("f:" + model.getId() + ":" + x.getId())
                .userName(x.getLogin())
                .firstName(x.getFirstName())
                .lastName(x.getLastName())
                //    .myCredMgr(credMge)         // FIXME: Better to pass it here than create one per instance
                .build();
    }

    private UserModel apiGetUser(String url) {
        String str = httpGet(url);
        log.info(str);
        log.info("JSON Length: " + str.length());

        ObjectMapper objectMapper = new ObjectMapper();
        objectMapper.configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
        SimpleModule simpleModule = new SimpleModule();
        simpleModule.addKeyDeserializer(ClientModel.class, new ClientModelKeyDeserializer());
        objectMapper.registerModule(simpleModule);
        try {
            MyUserModel user = objectMapper.readValue(str, MyUserModel.class);
            user.setId("f:" + model.getId() + ":" + user.getId());
            return user;
        } catch (JsonProcessingException e) {
            e.printStackTrace();
            throw new RuntimeException(e);
        }
    }

    public Stream<UserModel> apiGetUserStream(String url, Integer firstResult, Integer maxResults) {
        String str = httpGet(url);
        log.info(str);
        log.info("JSON Length: " + str.length());

        ObjectMapper objectMapper = new ObjectMapper();
        objectMapper.configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
        objectMapper.configure(DeserializationFeature.USE_JAVA_ARRAY_FOR_JSON_ARRAY, true);
        // https://stackoverflow.com/questions/6371092/can-not-find-a-map-key-deserializer-for-type-simple-type-class
        SimpleModule simpleModule = new SimpleModule();
        simpleModule.addKeyDeserializer(ClientModel.class, new ClientModelKeyDeserializer());
        objectMapper.registerModule(simpleModule);
        try {
//            MyUserModel[] list = objectMapper.readValue(str, MyUserModel[].class);		// This works too.
//            return Arrays.stream(list)
            List<MyUserModel> list = objectMapper.readValue(str, new TypeReference<List<MyUserModel>>() {
            });    // Sweet!
            return list.stream()
                    .map(i -> {
                        i.setId("f:" + model.getId() + ":" + i.getId());
                        return i;
                    })
                    .map(i -> (UserModel) i);
        } catch (JsonProcessingException e) {
            e.printStackTrace();
            throw new RuntimeException(e);
        }
    }

    public Stream<UserModel> searchForUserStream(RealmModel realm, String foo, Integer firstResult, Integer maxResults) {
        log.info("searchForUserStream(" + foo + ", " + firstResult + ", " + maxResults + ")");
        return foo.isBlank() ?
                apiGetUserStream(adapterBaseUrl +"/api/auth/user/", firstResult, maxResults) :
                apiGetUserStream(adapterBaseUrl +"/api/auth/user/like/" + foo, firstResult, maxResults);
    }

    @Override
    public Stream<UserModel> searchForUserStream(RealmModel realmModel, Map<String, String> map, Integer integer, Integer integer1) {
        log.info("searchForUserStream(" + map + ")");
        return null;
    }

    @Override
    public UserModel getUserByUsername(RealmModel realm, String foo) {
        log.info("getUserByUsername(" + foo + ")");
        return apiGetUser(adapterBaseUrl+"/api/auth/user/name/" + foo);
    }

    @Override
    public UserModel getUserByEmail(RealmModel realmModel, String s) {
        log.info("getUserByEmail(" + s + ")");
        return null;
    }

    public UserModel getUserById(RealmModel realm, String foo) {
        log.info("getUserById(" + foo + ")");
        String[] arr = foo.split(":");
        if (!model.getId().equals(arr[1])) {
            log.error("Wrong model identifier getUserByEmail: " + arr[1]);
            return null;
        }
        return apiGetUser(adapterBaseUrl +"/api/auth/user/id/" + arr[2]);
    }

    @Override
    public boolean supportsCredentialType(String s) {
        log.info("supportsCredentialType(" + s + "): TRUE");
        return true;
    }

    @Override
    public boolean isConfiguredFor(RealmModel realmModel, UserModel userModel, String s) {
        log.info("isConfiguredFor(RealmModel realmModel, UserModel userModel, " + s + "): Not down with OTP");
        return !"otp".equals(s);
    }

    private String httpPostJson(String url, String json) {
        log.info("httpPostJson requestBody: " + json);
        HttpRequest request = HttpRequest.newBuilder(URI.create(url))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(json))
                .build();
        final List<String> rc = new ArrayList();
        HttpClient.newHttpClient()
                .sendAsync(request, HttpResponse.BodyHandlers.ofString())
                .thenApply(HttpResponse::body)
                .thenAccept(s -> rc.add(s))
                .join();
        return rc.isEmpty() ? "" : rc.get(0);
    }

    private int httpHead(String url) throws IOException {
        log.info("httpHead: "+ url);
        try (CloseableHttpClient client = HttpClientBuilder.create().build()) {
            CloseableHttpResponse response = client.execute(new HttpGet(url));
            return response.getStatusLine().getStatusCode();
        }
    }

    private String httpGet(String url) {
        log.info("httpGet: "+ url);
        HttpRequest request = HttpRequest.newBuilder(URI.create(url))
         //       .header("Content-Type", "application/json")
                .GET()
                .build();
        final List<String> rc = new ArrayList();
        HttpClient.newHttpClient()
                .sendAsync(request, HttpResponse.BodyHandlers.ofString())
                .thenApply(HttpResponse::body)
                .exceptionally(e -> e.getMessage())
                .thenAccept(s -> rc.add(s))
                .join();
        return rc.isEmpty() ? "" : rc.get(0);

//        try (CloseableHttpClient client = HttpClientBuilder.create().build()) {
//            HttpResponse httpResp = client.execute(new HttpGet(url));
//            if (httpResp.getStatusLine().getStatusCode() != HttpStatus.SC_OK)
//                return "";
//            HttpEntity entity = httpResp.getEntity();
//            return EntityUtils.toString(entity, "UTF-8");
//        } catch (ClientProtocolException e) {
//            throw new RuntimeException(e);
//        } catch (IOException e) {
//            throw new RuntimeException(e);
//        }
    }

    @Override
    public boolean isValid(RealmModel realmModel, UserModel userModel, CredentialInput credentialInput) {
        log.info("isValid( realmModel, "+userModel+", "+credentialInput+"): TRUE");
        final Map<String, String> map = Map.of(
                "username", userModel.getUsername(),
                "password", credentialInput.getChallengeResponse(),
                "type", credentialInput.getType());

        ObjectMapper objectMapper = new ObjectMapper();
        try {
            String requestBody = objectMapper
                    .writerWithDefaultPrettyPrinter()
                    .writeValueAsString(map);
            return Boolean.valueOf(httpPostJson(adapterBaseUrl +"/api/auth/isValid", requestBody));
        } catch (JsonProcessingException e) {
            throw new RuntimeException(e);
        }
    }

    @Override
    public int getUsersCount(RealmModel realmModel) {
        log.info("getUsersCount");
        return Integer.parseInt(httpGet(adapterBaseUrl +"/api/auth/count"));
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
