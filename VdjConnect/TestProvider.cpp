#include "TestProvider.hpp"
//#include "JSON.hpp"
#include "Internet.hpp"

// including RapidJSON header files
#include "rapidjson/document.h"
#include "rapidjson/stringbuffer.h"
#include "rapidjson/writer.h"

//using std::cout;
using std::list;
using std::string;
using rapidjson::Document;
using rapidjson::Value;
using rapidjson::StringBuffer;
using rapidjson::Writer;
//using rapidjson::kTypeNames;

HRESULT VDJ_API TestProvider::OnGetPluginInfo(TVdjPluginInfo8* infos)
{
    myLog.info("TestProvider::OnGetPluginInfo");
    infos->PluginName = "TestProvider";
    return S_OK;
}

HRESULT VDJ_API TestProvider::OnSearch(const char* search, IVdjTracksList* tracksList)
{
    lastSearch = search;
    if (IsLogged() == S_FALSE)
        return S_FALSE;
    
    string key = search;
    std::transform(key.begin(), key.end(),key.begin(), ::toupper);
    string url = apiMediaBase + "/" +Internet::urlencode(key) ; //+ "?" + apiAuthParam();

    myLog.writeSuccess((char*)"TestProvider::OnSearch: %s", url.c_str());

    string json = Internet::downloadString(url, accessToken);
    
    Document DOM;
    if (DOM.Parse(json.c_str()).HasParseError())
        return S_FALSE;
    
    const Value& arr = DOM.GetArray();
    if(!arr.IsArray())
        return S_FALSE;

    myLog.writeError((char*)"Array of size: %d", arr.Size());
    int cnt = 0;
    for (auto& v : arr.GetArray()) {
        string id = std::to_string(v["song_id"].GetInt()) + (v["is_video"].GetBool() ? ".mp4" : ".mp3");
//        log.writeError("tracksList->add: Title: %s, Artist: %s, Remix: %s, Genre: %s, CoverUrl: %s, BPM: %d, Year: %d%\n",
//                       v["title"].GetString(), v["artist"].GetString(), v["remix"].GetString(),
//                       v["genre"].GetString(), v["coverUrl"].GetString(), v["bpm"].GetInt(), v["year"].GetInt());

//        string streamUrl = "https://www.my12inch.com/app/dl.jsp?file=";
//        streamUrl += v["file"].GetString();
//        myLog.writeSuccess("TestProvider::OnSearch: File: %s: %s", songId.c_str(), streamUrl.c_str());

        tracksList->add(id.c_str(), v["title"].GetString(), v["artist"].GetString(), "remix", v["genre"].GetString(), "label", "comment", "coverUrl", nullptr, 240, v["bpm"].GetInt(), 0, 2022, true, false);
        if (++cnt > 10000)
            break;
    }
    return S_OK;
}

HRESULT VDJ_API TestProvider::OnSearchCancel()
{
    myLog.info("TestProvider::OnSearchCancel");
    Internet::closeDownloads();
    return S_OK;
}

HRESULT VDJ_API TestProvider::GetStreamUrl(const char* uniqueId, IVdjString& url, IVdjString& errorMessage)
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

HRESULT VDJ_API TestProvider::GetContextMenu(const char* uniqueId, IVdjContextMenu* contextMenu)
{
    myLog.info("TestProvider::GetContextMenu");
    contextMenu->add("Open in TestProvider");
    return S_OK;
}

HRESULT VDJ_API TestProvider::OnContextMenu(const char* uniqueId, size_t menuIndex)
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
HRESULT VDJ_API TestProvider::IsLogged()
{
    // return S_OK if the user is logged in, S_FALSE if he's not, or E_NOTIMPL if you don't
    // need virtualdj to handle login  HRESULT VDJ_API TestProvider::OnLogin() { return E_NOTIMPL; }
    myLog.writeSuccess((char*)"TestProvider::IsLogged: %s", isLoggedIn ? "Yes" : "No");
    if (isLoggedIn) {
        myLog.writeSuccess((char*)"tokenExpire: %ld, Delta: %ld)", accessTokenExpire, accessTokenExpire -time(0));
        if (accessTokenExpire - 100 < time(0)) {            // Time to refresh
            string client = "client_id="+ kcClient +"&client_secret="+ kcSecret;
            oauth->refreshToken(refreshToken.c_str(), kcTokenUrl.c_str(), client.c_str());
        }
        isLoggedIn = accessTokenExpire >= time(0);
    }
    
    return (isLoggedIn && accessTokenExpire - 100 > time(0)) ? S_OK : S_FALSE;
}

// curl -X GET "http://keycloak:8180/realms/Services/.well-known/uma2-configuration" | jq
// See also:   https://stackoverflow.com/questions/45352880/keycloak-invalid-parameter-redirect-uri
HRESULT VDJ_API TestProvider::OnLogin()
{
    myLog.info("TestProvider::OnLogin");
    curl_global_init(CURL_GLOBAL_ALL);

    string url = kcBaseUrl + "/realms/"+ kcRealm +"/protocol/openid-connect/auth?client_id="+ kcClient +"&client_secret="+ kcSecret +"scope=openid&grant_type=urn:openid:params:grant-type:ciba&username=grhex&password=foo";
    myLog.writeError("TestProvider::OnLogin: %s", url.c_str());
    oauth->open(url.c_str());
    // Internet::openBrowser(url);
    return S_OK;
}

HRESULT VDJ_API TestProvider::OnLogout()
{
    myLog.info("TestProvider::OnLogout");
    Internet::openBrowser(kcLoguotUrl);
    curl_global_cleanup();
    isLoggedIn = false;
    return S_OK;
}

HRESULT VDJ_API TestProvider::OnOAuth(const char *access_token, size_t access_token_expire, const char* refresh_token, const char* code, const char* errorMessage)
{
    string XtokenUrl = kcBaseUrl +  "realms/"+ kcRealm +"/protocol/openid-connect/token?client_id="+ kcClient +"&client_secret="+ kcSecret +"&scope=openid&grant_type=password&username=grhex&password=foo";
    myLog.writeSuccess((char*)"TestProvider::OnOAuth(Access: %s, Expire: %d, Refresh: %s, Code: %s, Error: %s)",
                       access_token, access_token_expire, refresh_token, code, errorMessage);
    if (code)
    {
        myLog.writeSuccess((char*)"oauth->getToken(%s, %s)", code, kcTokenUrl.c_str());
        // getToken will POST code=, grant_type= and redirect_uri=. anything else should be added in tokenPost.
        string client = "client_id="+ kcClient +"&client_secret="+ kcSecret;
        oauth->getToken(code, kcTokenUrl.c_str(), client.c_str());
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

