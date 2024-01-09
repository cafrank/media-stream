#include <string>
#include <cstring>
#include <CoreFoundation/CFBundle.h>
#include <ApplicationServices/ApplicationServices.h>
#include <curl/curl.h>
#include <cctype>
#include <iomanip>
#include <sstream>
#include "Log.hpp"

using std::string;
using std::ostringstream;
using std::hex;
using std::uppercase;
using std::nouppercase;
using std::setw;
// using namespace std;

class Internet 
{
public:
    static string downloadString(string url, string accessToken = 0);
    static void   closeDownloads();
    static string urlencode(const string &value);
    static void   openBrowser(const string &url_str);
    // Log log;
};

string Internet::urlencode(const string &value)
{
    ostringstream escaped;
    escaped.fill('0');
    escaped << hex;

    for (string::const_iterator i = value.begin(), n = value.end(); i != n; ++i) {
        string::value_type c = (*i);

        // Keep alphanumeric and other accepted characters intact
        if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
            escaped << c;
            continue;
        }

        // Any other characters are percent-encoded
        escaped << uppercase;
        escaped << '%' << setw(2) << int((unsigned char) c);
        escaped << nouppercase;
    }

    return escaped.str();
}

void Internet::closeDownloads()
{

}

size_t writeFunction(void *ptr, size_t size, size_t nmemb, std::string* data) {
    data->append((char*) ptr, size * nmemb);
    return size * nmemb;
}


// https://curl.se/libcurl/c/simple.html
// https://gist.github.com/whoshuu/2dc858b8730079602044
string Internet::downloadString(string url, string accessToken)
{
    CURL *curl;
    CURLcode res;
    string str;
    // Log log;

    curl = curl_easy_init();
    if(curl) {
        // myLog.info("Internet::downloadString");

        curl_easy_setopt(curl, CURLOPT_URL, url.c_str());

        /* example.com is redirected, so we tell libcurl to follow redirection */
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
        curl_easy_setopt(curl, CURLOPT_UNRESTRICTED_AUTH, 1L);
        curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 6L);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeFunction);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &str);
//        curl_easy_setopt(curl, CURLOPT_COOKIEFILE, "/tmp/cookies.txt");
//        curl_easy_setopt(curl, CURLOPT_COOKIEJAR,  "/tmp/cookies.txt");
        curl_easy_setopt(curl, CURLOPT_TCP_KEEPALIVE, 1L);
        curl_easy_setopt(curl, CURLOPT_VERBOSE, 1L);

        if(accessToken.length() > 0)
        {
            myLog.writeSuccess((char*)"Internet::downloadString(%s, %s)", url.c_str(), accessToken.c_str());
//            curl_easy_setopt(curl, CURLOPT_XOAUTH2_BEARER, authHeader.c_str());
            string authHeader = "Authorization: Bearer "+ accessToken;
            struct curl_slist* headers = NULL;
            headers = curl_slist_append(headers, "Content-Type: application/json");
            headers = curl_slist_append(headers, "Accept: application/json");
            headers = curl_slist_append(headers, authHeader.c_str());
            curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        }


        /* Perform the request, res will get the return code */
        res = curl_easy_perform(curl);

        /* Check for errors */
        if(res != CURLE_OK) {
            myLog.writeError((char*)"curl_easy_perform() failed: %s", curl_easy_strerror(res));
        } else {
            long response_code, redirects;
            char *location;
            res = curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
            if((res == CURLE_OK) && ((response_code / 100) != 3)) {
                curl_easy_getinfo(curl, CURLINFO_REDIRECT_COUNT, &redirects);
                myLog.writeSuccess((char*)"Not a redirect.  Code: %ld, %ld", response_code, redirects);
                
                /* extract all known cookies */
                struct curl_slist *cookies = NULL;
                res = curl_easy_getinfo(curl, CURLINFO_COOKIELIST, &cookies);
                if(!res && cookies) {
                  /* a linked list of cookies in cookie file format */
                  struct curl_slist *each = cookies;
                  while(each) {
                      myLog.writeSuccess((char*)"    %s", each->data);
                    each = each->next;
                  }
                  /* we must free these cookies when we are done */
                  curl_slist_free_all(cookies);
                }

            }
            else {
              res = curl_easy_getinfo(curl, CURLINFO_REDIRECT_URL, &location);
       
              if((res == CURLE_OK) && location) {
                /* This is the new absolute URL that you could redirect to, even if
                 * the Location: response header may have been a relative URL. */
                  myLog.writeSuccess((char*)"Redirected to: %s", location);
                  // Manual: return Internet::downloadString(location, accessToken.c_str());
              }
            }
        }
        /* always cleanup */
        curl_easy_cleanup(curl);
    }
    
    // log.info(str);
    return str;
}

// https://stackoverflow.com/questions/4177744/c-os-x-open-default-browser
void Internet::openBrowser(const string &url_str)
{
    CFURLRef url = CFURLCreateWithBytes (
        NULL,                        // allocator
        (UInt8*)url_str.c_str(),     // URLBytes
        url_str.length(),            // length
        kCFStringEncodingASCII,      // encoding
        NULL                         // baseURL
      );
    LSOpenCFURLRef(url,0);
    CFRelease(url);
}
