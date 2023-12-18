package org.sparkle.auth.kc.modle;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.keycloak.credential.CredentialInput;
import org.keycloak.credential.CredentialModel;
import org.keycloak.models.*;

import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import java.util.*;
import java.util.stream.Stream;

@Slf4j
@AllArgsConstructor
@NoArgsConstructor
@Data
@Builder
public class MyUserModel implements UserModel {

    public static String FEDERATION_LINK = "federation.link";
    public static String SA_CLIENT_LINK = "service.account.client.link";

    private String id;
    private String userName;
    private String email;
    private String firstName;       // Keep these for the Builder Pattern
    private String lastName;
    private String serviceAccountLink;
    private boolean isEnabled = true;
    private boolean isEmailVerified = true;
    private Map<String, List<String>> attributes = new HashMap();
    //Map<> realmRolaMapping = new HashMap();
    private Map<ClientModel, List<RoleModel>> clientRoleMapping = new HashMap();

    private SubjectCredentialManager myCredMgr = new SubjectCredentialManager() {

        @Override
        public boolean isValid(List<CredentialInput> list) {
            log.info("SubjectCredentialManager.isValid() ====== "+list+" ======");
            return true;
        }

        @Override
        public boolean isValid(CredentialInput... inputs) {
            log.info("SubjectCredentialManager.isValid() ======   ======");
            return SubjectCredentialManager.super.isValid(inputs);
        }

        @Override
        public boolean updateCredential(CredentialInput credentialInput) {
            log.info("SubjectCredentialManager.updateCredential() ====== "+credentialInput+" ======");
            return false;
        }

        @Override
        public void updateStoredCredential(CredentialModel credentialModel) {
            log.info("SubjectCredentialManager.updateStoredCredential() ====== "+credentialModel+" ======");
        }

        @Override
        public CredentialModel createStoredCredential(CredentialModel credentialModel) {
            log.info("SubjectCredentialManager.createStoredCredential("+credentialModel+"): NULL ======");
            return null;
        }

        @Override
        public boolean removeStoredCredentialById(String s) {
            log.info("SubjectCredentialManager.removeStoredCredentialById("+s+"): FALSE ======");
            return false;
        }

        @Override
        public CredentialModel getStoredCredentialById(String s) {
            log.info("SubjectCredentialManager.getStoredCredentialById("+s+"): NULL ======");
            return null;
        }

        @Override
        public Stream<CredentialModel> getStoredCredentialsStream() {
            // org.keycloak.models.SubjectCredentialManager.getStoredCredentialsStream
            log.info("SubjectCredentialManager.getStoredCredentialsStream(): EMPTY ======");
            return Stream.empty();
        }

        @Override
        public Stream<CredentialModel> getStoredCredentialsByTypeStream(String s) {
            log.info("SubjectCredentialManager.getStoredCredentialsByTypeStream("+s+"): EMPTY ======");
            return Stream.empty();
        }

        @Override
        public CredentialModel getStoredCredentialByNameAndType(String s, String s1) {
            log.info("SubjectCredentialManager.getStoredCredentialByNameAndType("+s+"): NULL ======");
            return null;
        }

        @Override
        public boolean moveStoredCredentialTo(String s, String s1) {
            log.info("SubjectCredentialManager.getStoredCredentialByNameAndType("+s+"): NULL ======");
            return false;
        }

        @Override
        public void updateCredentialLabel(String s, String s1) {

        }

        @Override
        public void disableCredentialType(String s) {

        }

        @Override
        public Stream<String> getDisableableCredentialTypesStream() {
            log.info("SubjectCredentialManager.getDisableableCredentialTypesStream(): EMPTY ======");
            return Stream.empty();
        }

        @Override
        public boolean isConfiguredFor(String s) {
            return false;
        }

        @Override
        public boolean isConfiguredLocally(String s) {
            return false;
        }

        @Override
        public Stream<String> getConfiguredUserStorageCredentialTypesStream() {
            log.info("SubjectCredentialManager.getConfiguredUserStorageCredentialTypesStream(): EMPTY ======");
            return Stream.empty();
        }

        @Override
        public CredentialModel createCredentialThroughProvider(CredentialModel credentialModel) {
            return null;
        }
    };

    public String toString() {
        return "{ id: "+ getId() + ", username: " + getUsername() +"}";
    }

    public MyUserModel(String id, String username, String email, String firstName, String lastName) {
        this.id = id;
        userName = username;
        this.setEmail (email);
        this.setFirstName(firstName);
        this.setLastName (lastName);
    }

    @Override
    public String getId() {
        // log.info("getId(f:"+ id +":"+ userName +")");
        return id;
    }

    @Override
    public String getUsername() {
        // log.info("getUsername("+ userName +")");
        attributes.get(UserModel.USERNAME);
        return userName;
    }

    @Override
    public void setUsername(String s) {
        userName = s;
        attributes.put(UserModel.USERNAME, Arrays.asList(s));
        log.info("setUsername("+ userName +")");
    }

    @Override
    public Long getCreatedTimestamp() {
        return null;
    }

    @Override
    public void setCreatedTimestamp(Long aLong) {
        log.info("setCreatedTimestamp("+ userName +")");
    }

    @Override
    public boolean isEnabled() {
        // log.info("isEnabled(): "+ isEnabled);
        attributes.get(UserModel.ENABLED);
        return isEnabled;
    }

    @Override
    public void setEnabled(boolean b) {
        attributes.put(UserModel.ENABLED, Arrays.asList(toString()));
        isEnabled = b;
    }

    @Override
    public void setSingleAttribute(String s, String s1) {
        attributes.put(s, Arrays.asList(s1));
        log.info("setSingleAttribute("+ s +","+ s1 +")");
    }

    @Override
    public void setAttribute(String s, List<String> list) {
        attributes.put(s, list);
        log.info("setAttribute(): "+ s);
    }

    @Override
    public void removeAttribute(String s) {
        attributes.remove(s);
    }

    @Override
    public String getFirstAttribute(String s) {
        log.info("getFirstAttribute("+ s +"): "
                + (attributes.containsKey(s) ? attributes.get(s).get(0) : "NULL"));
        return attributes.containsKey(s) ? attributes.get(s).get(0) : null;
    }

    @Override
    public Stream<String> getAttributeStream(String s) {
        log.info("getAttributeStream("+ s +"): EMPTY");
        return attributes.containsKey(s) ? attributes.get(s).stream() : Stream.empty();

    }

    @Override
    public Map<String, List<String>> getAttributes() {
        return attributes;
    }

    @Override
    public Stream<String> getRequiredActionsStream() {
        // log.info("getRequiredActionsStream()");
        return getAttributeStream("required.actions");
    }

    @Override
    public void addRequiredAction(String s) {
        log.info("addRequiredAction()");
        if (attributes.containsKey("addRequiredAction()"))
            attributes.get("required.actions").add(s);
        else
            attributes.put("required.actions", Arrays.asList(s));
    }

    @Override
    public void removeRequiredAction(String s) {
        if (attributes.containsKey("addRequiredAction()"))
            attributes.get("required.actions").remove(s);
        log.info("getRequiredActions()");
    }

    @Override
    public String getFirstName() {
        return getFirstAttribute(UserModel.FIRST_NAME);
        // return firstName;
    }

    @Override
    public void setFirstName(String s) {
        firstName = s;
        setSingleAttribute(UserModel.FIRST_NAME, s);
    }

    @Override
    public String getLastName() {
        return lastName;
    }

    @Override
    public void setLastName(String s) {
        lastName = s;
        setSingleAttribute(UserModel.LAST_NAME, s);
    }

    @Override
    public String getEmail() {
        return email;
    }

    @Override
    public void setEmail(String s) {
        log.info("setEmail()");
        email = s;
        setSingleAttribute(UserModel.EMAIL, s);
    }

    @Override
    public boolean isEmailVerified() {
        return isEmailVerified;
    }

    @Override
    public void setEmailVerified(boolean b) {
        isEmailVerified = b;
        setSingleAttribute(UserModel.EMAIL_VERIFIED, ""+b);
    }

    @Override
    public Stream<GroupModel> getGroupsStream() {
        log.info("getGroupsStream(): EMPTY");
        return Stream.empty();
    }

    @Override
    public void joinGroup(GroupModel groupModel) {
        log.info("getRequiredActions()");
    }

    @Override
    public void leaveGroup(GroupModel groupModel) {
        log.info("getRequiredActions()");
    }

    @Override
    public boolean isMemberOf(GroupModel groupModel) {
        log.info("getRequiredActions()");
        return false;
    }

    @Override
    public String getFederationLink() {
        log.info("getRequiredActions()");
        return null;
    }

    @Override
    public void setFederationLink(String s) {
        log.info("getRequiredActions()");
        setSingleAttribute(MyUserModel.FEDERATION_LINK, s);

    }

    @Override
    public String getServiceAccountClientLink() {
        log.info("getServiceAccountClientLink(): "+ serviceAccountLink);
        return serviceAccountLink;
    }

    @Override
    public void setServiceAccountClientLink(String s) {
        serviceAccountLink = s;
        setSingleAttribute(MyUserModel.SA_CLIENT_LINK, s);
    }

    @Override
    public SubjectCredentialManager credentialManager() {
        log.info("credentialManager()");
        return myCredMgr;
    }


    @Override
    public Stream<RoleModel> getRealmRoleMappingsStream() {
        log.info("getRealmRoleMappingsStream(): EMPTY");
        return Stream.empty();
    }

    @Override
    public Stream<RoleModel> getClientRoleMappingsStream(ClientModel clientModel) {
        log.info("getClientRoleMappingsStream()");
        return clientRoleMapping.containsKey(clientModel) ? clientRoleMapping.get(clientModel).stream(): Stream.empty();
    }

    @Override
    public boolean hasRole(RoleModel roleModel) {
        log.info("hasRole()");
        return false;
    }

    @Override
    public void grantRole(RoleModel roleModel) {
        log.info("grantRole() ====== "+ roleModel +" ======");
    }

    @Override
    public Stream<RoleModel> getRoleMappingsStream() {
        log.info("getRoleMappingsStream() ====== EMPTY ======");
        return Stream.empty();
    }

    @Override
    public void deleteRoleMapping(RoleModel roleModel) {
        log.info("deleteRoleMapping() ====== "+ roleModel +" ======");
    }
}
