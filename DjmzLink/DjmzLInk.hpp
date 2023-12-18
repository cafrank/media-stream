#pragma once

#include <list>
#include <string>
#include <cstring>
#include "vdjOnlineSource.h"
#include "Log.hpp"

// https://www.virtualdj.com/wiki/Plugins_SDKv8_Example7.html

using std::list;
using std::string;

class DjmzLink : public IVdjPluginOnlineSource
{
private:
    bool isLoggedIn = false;
    
    // FIXME: Config files
    string kcBaseUrl   = "https://key.lxci.net:8443";           // keycloak server
//  string kcBaseUrl   = "https://key.lxci.net";                // keycloak server
    string kcLoguotUrl = kcBaseUrl + "/realms/Services/protocol/openid-connect/logout";
    string kcTokenUrl  = kcBaseUrl + "/realms/Services/protocol/openid-connect/token";

//  string apiMediaBase = "http://api.djmz.com/api/media";   // API Gateway with keycloak
    string apiMediaBase = "http://api.djmz.com:8080/api/media";   // API Gateway with keycloak
//  string apiMediaBase = "http://localhost:8084/api/media";   // Direct API. No auth
    string accessToken;
    string refreshToken;
    size_t accessTokenExpire;
    string apiAuthParam()
    {
        string url = "client_id=product-app&scope=openid" +
            (accessToken.length() ? "&access_token="+ accessToken : "");
        return url;
    }

public:
	HRESULT VDJ_API OnGetPluginInfo(TVdjPluginInfo8* infos) override;
	HRESULT VDJ_API OnSearch(const char* search, IVdjTracksList* tracksList) override;
	HRESULT VDJ_API OnSearchCancel() override;
	HRESULT VDJ_API GetStreamUrl(const char* uniqueId, IVdjString& url, IVdjString& errorMessage) override;
	HRESULT VDJ_API GetContextMenu(const char* uniqueId, IVdjContextMenu* contextMenu) override;
	HRESULT VDJ_API OnContextMenu(const char* uniqueId, size_t menuIndex) override;

    HRESULT VDJ_API IsLogged() override;
    HRESULT VDJ_API OnLogin() override;
    HRESULT VDJ_API OnLogout() override;
    HRESULT VDJ_API OnOAuth(const char *access_token, size_t access_token_expire, const char* refresh_token, const char* code, const char* errorMessage) override;

    // if you have subfolders, list them here
    HRESULT VDJ_API GetFolderList(IVdjSubfoldersList* subfoldersList)  override
    {
        myLog.writeSuccess((char*)"TestProvider::GetFolderList()");

        //virtual void VDJ_API add(const char* folderUniqueId, const char* folderName = 0) = 0;
        subfoldersList->add("AUDIO",   "New Audio");
        subfoldersList->add("VIDEO",   "New Video");
        subfoldersList->add("VJTOOLS", "VJ Tools");
//        subfoldersList->add("INTROS",  "New Intros");
//        subfoldersList->add("OLD_AUDIO", "OldSchool Audio");
//        subfoldersList->add("OLD_VIDEO", "Oldschool Video");
        return S_OK;
    }
    
// and this function will be called when the user browses a subfolder
    HRESULT VDJ_API GetFolder(const char* folderUniqueId, IVdjTracksList* tracksList)  override
    {
        myLog.writeSuccess((char*)"TestProvider::GetFolder(%s)\n", folderUniqueId);
        OnSearch("HALO", tracksList);
        return S_OK;
    }
};
