//
//  Log.cpp
//  VdjConnect
//
//  Created by DJMZ FRANK on 10/26/22.
//

#include "Log.hpp"
#include <ctime>
#include <stdarg.h>
#include <iostream>

//using std::cout;

const int BUFFER_SIZE = 4096;

using namespace std;

Log::Log()
{
    if (logfile.is_open())
        return;
    
    // Create a log file for output
    logfile.open ("c:/Users/User/my-log.txt", ios::out);

    // Grab the current system time
    time_t t = time(0);
    struct tm * now = localtime( & t );

    // TODO: Format the time correctly

    // Insert the time and date at the top
    logfile << "<---> Logfile Initialized on " << now->tm_mon + 1 << "-" <<
            now->tm_mday << "-" << now->tm_year + 1900 << " at " << now->tm_hour <<
            ":" << now->tm_min << ":" << now->tm_sec << endl;
}

// Destructor
Log::~Log()
{
    // Close the logfile
    logfile.close();
}

void Log::info(const string &text)
{
    logfile << "<-*-> " << text << endl;
}

void Log::writeError(char * text,...)
{
    // Grab the variables and insert them
    va_list ap;
    va_start(ap, text);
    char buff[BUFFER_SIZE];
    vsnprintf(buff, sizeof(buff), text, ap);

    // Output to the log
    logfile << "<-!-> " << buff << endl;
}

void Log::writeSuccess(char * text,...)
{
    // Grab the variables and insert them
    va_list ap;
    va_start(ap, text);
    char buff[BUFFER_SIZE];
    vsnprintf(buff, sizeof(buff), text, ap);

    // Output to the log
    logfile << "<---> " << buff << endl;
}

void Log::writeNewline()
{
    // Create a new line in the logfile
    logfile << endl;
}

int main()
{
    // Log log;
    cout << "Testing log!.  Try tail c:/Users/User/my-log.txt\n";
    myLog.info("main() Log: It works");
}