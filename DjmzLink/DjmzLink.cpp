#include "DjmzLink.hpp"
#include "TrackDao.hpp"
#include "Internet.hpp"
#include <string>
#include <algorithm>

//#define _GLIBCXX_USE_CXX11_ABI 0
#include <stdlib.h>

using std::list;
using std::string;

HRESULT VDJ_API DjmzLink::OnGetPluginInfo(TVdjPluginInfo8* infos)
{
    myLog.info("TestProvider::OnGetPluginInfo");
    infos->PluginName = "TestProvider";
    return S_OK;
}

HRESULT VDJ_API DjmzLink::OnSearch(const char* search, IVdjTracksList* tracksList)
{
    if (IsLogged() == S_FALSE)
        return S_FALSE;
    
    string key = search;
    std::transform(key.begin(), key.end(), key.begin(), ::toupper);
    string url = apiMediaBase + "/" +Internet::urlencode(key) ; //+ "?" + apiAuthParam();

    myLog.writeSuccess((char*)"TestProvider::OnSearch: %s", url.c_str());

    // string streamUrl = "https://www.my12inch.com/app/dl.jsp?file=";

    string jstring = Internet::downloadString(url, accessToken);

    Json::Reader reader;
    Json::Value root;
    reader.parse(jstring, root);

    const Json::Value array = root;
    int size = array.size();

    myLog.writeSuccess((char*)"DjmzLink::OnSearch: %d", size);

    for (Json::Value trk : array)
    {
        myLog.writeSuccess((char*)"ID: %s, Title: %s, Artist: %s, Genre: %s", 
            trk["song_id"].asString().c_str(),
            trk["title"].asString().c_str(),
            trk["artist"].asString().c_str(),
            trk["genre"].asString().c_str()
            );

        //string id = std::to_string(trk["song_id"].asString()) + (trk["is_video"].asBool() ? ".mp4" : ".mp3");
        string id = trk["song_id"].asString() + (trk["is_video"].asBool() ? ".mp4" : ".mp3");

        tracksList->add(id.c_str(),
            trk["title"].asString().c_str(),
            trk["artist"].asString().c_str(),
            trk["remix"].asString().c_str(),
            trk["genre"].asString().c_str(),
            "label", "comment", "coverUrl", nullptr, 240,
            trk["bpm"].asInt(),
            0, 2022, true, false);
    }
    return S_OK;
}

HRESULT VDJ_API DjmzLink::OnSearchCancel()
{
    myLog.info("TestProvider::OnSearchCancel");
    Internet::closeDownloads();
    return S_OK;
}

HRESULT VDJ_API DjmzLink::GetStreamUrl(const char* uniqueId, IVdjString& url, IVdjString& errorMessage)
{
    OnSearchCancel();
    myLog.writeSuccess((char*)"TestProvider::GetStreamUrl: ID: %s", uniqueId);
    string qry  = apiMediaBase +"/"+ Internet::urlencode(uniqueId) + "/stream";

    string path = Internet::downloadString(qry, accessToken);
    myLog.writeSuccess((char*)"   StreamUrl(%s): %s", uniqueId, path.c_str());
    url =  path.c_str();
    return S_OK;

//  string path = "https://www.my12inch.com/app/dl.jsp?file="+ Internet::downloadString(qry);
//  url = "https://www.my12inch.com/a.mp4";
//    string path = "https://www.my12inch.com/prev/gen3/"+ Internet::urlencode(uniqueId);

    // Generate AWS Cloudfront signed URL
    // https://www.youtube.com/watch?v=JIW_pV3zau8 TS: 10:30

//    string url = "https://api.testprovider.com/getStreamUrl?id=" + Internet::urlencode(uniqueId);
//    string html = Internet::downloadString(url);
//    JSON json = JSON::fromString(html);
//    if (json.hasParam("url"))
//    {
//        url = json.getParam("url").c_str();
//        return S_OK;
//    }
//    else
//    {
//        errorMessage = json.getParam("error").c_str();
//        return S_FALSE;
//    }
}

HRESULT VDJ_API DjmzLink::GetContextMenu(const char* uniqueId, IVdjContextMenu* contextMenu)
{
    myLog.info("TestProvider::GetContextMenu");
    contextMenu->add("Open in TestProvider");
    return S_OK;
}

HRESULT VDJ_API DjmzLink::OnContextMenu(const char* uniqueId, size_t menuIndex)
{
    myLog.info("TestProvider::OnContextMenu");
    if (menuIndex==0)
    {
        string url = "https://www.y12inch.com/" + Internet::urlencode(uniqueId);
        Internet::openBrowser(url);
    }
    return S_OK;
}

// implement this to handle login your users in and out
HRESULT VDJ_API DjmzLink::IsLogged()
{
    // return S_OK if the user is logged in, S_FALSE if he's not, or E_NOTIMPL if you don't
    // need virtualdj to handle login  HRESULT VDJ_API TestProvider::OnLogin() { return E_NOTIMPL; }
    myLog.writeSuccess((char*)"TestProvider::IsLogged: %s", isLoggedIn ? "Yes" : "No");
    if (isLoggedIn) {
        myLog.writeSuccess((char*)"tokenExpire: %ld, Delta: %ld)", accessTokenExpire, accessTokenExpire -time(0));
        if (accessTokenExpire - 100 < time(0)) {            // Time to refresh
            oauth->refreshToken(refreshToken.c_str(), kcTokenUrl.c_str(), "client_id=product-app");
        }
        isLoggedIn = accessTokenExpire >= time(0);
    }
    
    return (isLoggedIn && accessTokenExpire - 100 > time(0)) ? S_OK : S_FALSE;
}

// curl -X GET "http://keycloak:8180/realms/Services/.well-known/uma2-configuration" | jq
// See also:   https://stackoverflow.com/questions/45352880/keycloak-invalid-parameter-redirect-uri
HRESULT VDJ_API DjmzLink::OnLogin()
{
    myLog.info("TestProvider::OnLogin");
#if 1
    curl_global_init(CURL_GLOBAL_ALL);
#endif
    string url = kcBaseUrl + "/realms/Services/protocol/openid-connect/auth?client_id=product-app&client_secret=5c1H4o1jZ9Q0iPST0CBsBQ1mhJVwaRPK&scope=openid&grant_type=urn:openid:params:grant-type:ciba&username=grhex&password=foo";
    myLog.writeError((char*) "TestProvider::OnLogin: %s", url.c_str());
    oauth->open(url.c_str());
    // Internet::openBrowser(url);
    return S_OK;
}

HRESULT VDJ_API DjmzLink::OnLogout()
{
    myLog.info("TestProvider::OnLogout");
    Internet::openBrowser(kcLoguotUrl);
#if 1
    curl_global_cleanup();
#endif
    isLoggedIn = false;
    return S_OK;
}

HRESULT VDJ_API DjmzLink::OnOAuth(const char *access_token, size_t access_token_expire, const char* refresh_token, const char* code, const char* errorMessage)
{
    string XtokenUrl = kcBaseUrl +  "realms/Services/protocol/openid-connect/token?client_id=product-app&client_secret=5c1H4o1jZ9Q0iPST0CBsBQ1mhJVwaRPK&scope=openid&grant_type=password&username=grhex&password=foo";
    myLog.writeSuccess((char*)"TestProvider::OnOAuth(Access: %s, Expire: %d, Refresh: %s, Code: %s, Error: %s)",
                       access_token, access_token_expire, refresh_token, code, errorMessage);
    if (code)
    {
        myLog.writeSuccess((char*)"oauth->getToken(%s, %s)", code, kcTokenUrl.c_str());
        // getToken will POST code=, grant_type= and redirect_uri=. anything else should be added in tokenPost.
        oauth->getToken(code, kcTokenUrl.c_str(), "client_id=product-app");
    } else {
        if (access_token) {
            accessToken = access_token;
            isLoggedIn = true;
        }
        if (refresh_token) {
            refreshToken= refresh_token;
            accessTokenExpire = access_token_expire;
            myLog.writeSuccess((char*)"tokenExpire: %ld, Delta: %ld)", accessTokenExpire, accessTokenExpire -time(0));
        }
    }
    return S_OK;
}

#if 0
HRESULT VDJ_API DllGetClassObject(const GUID& rclsid, const GUID& riid, void** ppObject)
{
    myLog.writeSuccess((char*) "DllGetClassObject(%08x) called...", rclsid.Data1);  // Ths logs to /tmp/vdj.log
    MessageBox(0, "Hello World from DLL!\n", "Hi", MB_ICONINFORMATION);

    if (memcmp(&rclsid, &CLSID_VdjPlugin8, sizeof(GUID)) == 0 && memcmp(&riid, &IID_IVdjPluginOnlineSource, sizeof(GUID)) == 0)
        *ppObject = new DjmzLink();
    else
        return CLASS_E_CLASSNOTAVAILABLE;
    return NO_ERROR;
}
#endif
