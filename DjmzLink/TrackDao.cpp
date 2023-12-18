#include "TrackDao.hpp"

bool TrackDao::hasParam(string p)
{
    cout << "HasParam: " << p << "\n";
    return true;
}

string TrackDao::getParam(string p)
{
    return "dfsdf";
}

TrackDao::TrackDao()
{
}

#if 0
TrackDao& TrackDao::fromString(string str)
{
    Json::Reader reader;
    Json::Value root;
    reader.parse(str, root);

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
#endif