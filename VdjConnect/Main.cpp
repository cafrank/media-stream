//
//  Main.cpp
//  VdjConnect
//
//  Created by DJMZ FRANK on 10/26/22.
//

//  #include <iostream>
#include "TestProvider.hpp"

HRESULT VDJ_API DllGetClassObject(const GUID &rclsid,const GUID &riid,void** ppObject)
{
    myLog.writeSuccess("DllGetClassObject(%08x) called...\n", rclsid.Data1);  // Ths logs to /tmp/vdj.log

    if (memcmp(&rclsid,&CLSID_VdjPlugin8,sizeof(GUID))==0 && memcmp(&riid,&IID_IVdjPluginOnlineSource,sizeof(GUID))==0) {
        *ppObject=new TestProvider();
    } else {
        myLog.writeSuccess("DllGetClassObject(): CLASS_E_CLASSNOTAVAILABLE...");
        return CLASS_E_CLASSNOTAVAILABLE;
    }
    return NO_ERROR;
}
