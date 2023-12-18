//
//  Log.hpp
//  VdjConnect
//
//  Created by DJMZ FRANK on 10/26/22.
//

#ifndef Log_hpp
#define Log_hpp

#include <stdio.h>
#include <fstream>

// using namespace std;
using std::string;
using std::ofstream;

class Log
{
public:
        // Constructor / Destructor
        Log();
        ~Log();

        // Class functions
        void writeNewline();
        void info(const string &text);
        void writeError(char * text,...);
        void writeSuccess(char * text,...);

private:
        ofstream logfile;
};

static Log myLog;

#endif /* Log_hpp */
