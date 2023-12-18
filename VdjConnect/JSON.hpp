#include <list>
#include <string>
#include <cstring>
#include <iostream>
#include "Log.hpp"
#include "jsmn.h"

// including RapidJSON header files
#include "rapidjson/document.h"
#include "rapidjson/stringbuffer.h"
#include "rapidjson/writer.h"

using std::cout;
using std::list;
using std::string;
using rapidjson::Document;
using rapidjson::Value;
using rapidjson::StringBuffer;
using rapidjson::Writer;

class JSON 
{
public:
    string uniqueId;
    string title;
    string artist;
    string remix;
    string label;
    string comment;
    string coverUrl;
    int    length;
    list<JSON> children;
    //Document DOM;

    JSON();
    static JSON& fromString(string url);
    bool   hasParam(string);
    string getParam(string);

};

JSON::JSON() 
{
}

JSON& JSON::fromString(string str)
{
    // cout << "FromString: " << str << "\n";
    JSON *x = new JSON();
    Log log;
    Document DOM;
    
    const char *json = str.c_str();
    if (DOM.Parse(json).HasParseError())
        return *x;

    // Stringifying the DOM
    StringBuffer buffer;
    Writer<StringBuffer> writer(buffer);
    DOM.Accept(writer);
    std::string completeJsonData = buffer.GetString();
    // log.logfile << "DOM: " << completeJsonData << std::endl;
    
    const Value& a = DOM.GetArray();
    if(a.IsArray()) {
        log.writeError("Array of size: %d\n", a.Size());
    }

    return *x;
}

bool JSON::hasParam(string p)
{
    cout << "HasParam: " << p << "\n";
    return TRUE;
}

string JSON::getParam(string p)
{
    return "dfsdf";
}
