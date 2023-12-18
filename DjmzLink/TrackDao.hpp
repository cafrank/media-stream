#pragma once
#include <list>
#include <string>
#include <cstring>
#include <iostream>
#include "Log.hpp"

// including JSON header files: https://www.youtube.com/watch?v=GYauneigGTs
#include <json\json.h>
#include <iostream>
#include <memory>

using std::cout;
using std::list;
using std::string;


class TrackDao
{
public:
    string uniqueId;
    string title;
    string artist;
    string remix;
    string genre;
    string label;
    string comment;
    string coverUrl;
    int    bpm;
    int    length;
    //list<JSON> children;
    //Document DOM;

    TrackDao();
    // static TrackDao& fromString(string url);
    static TrackDao& fromString(string str)
    {
        Json::Reader reader;
        Json::Value root;
        reader.parse(str, root);

        const Json::Value array = root;
        int size = array.size();

        // cout << "FromString: " << str << "\n";
        TrackDao* x = new TrackDao();
        x->bpm = root["bpm"].asInt();
        x->length = root["length"].asInt();
        x->title = root["title"].asString();
        x->artist = root["artist"].asString();
        x->remix = root["remix"].asString();
        x->label = root["label"].asString();
        x->comment = root["comment"].asString();
        x->coverUrl = root["coverUrl"].asString();
        x->uniqueId = root["uniqueId"].asString();
        return *x;
    }
    bool   hasParam(string);
    string getParam(string);

};


