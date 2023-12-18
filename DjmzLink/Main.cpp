//
//  Main.cpp
//  VdjConnect
//
//  Created by DJMZ FRANK on 10/26/22.
//

//  #include <iostream>
#include "DjmzLink.hpp"


	VDJ_EXPORT HRESULT VDJ_API DllGetClassObject(const GUID& rclsid, const GUID& riid, void** ppObject)
	{
	    myLog.writeSuccess((char*) "DllGetClassObject(%08x) called...", rclsid.Data1);  // Ths logs to /tmp/vdj.log
	    // MessageBox(0, "Hello World from DLL!\n", "Hi", MB_ICONINFORMATION);

	    if (memcmp(&rclsid,&CLSID_VdjPlugin8,sizeof(GUID))==0 && memcmp(&riid,&IID_IVdjPluginOnlineSource,sizeof(GUID))==0)
		*ppObject=new DjmzLink();
	    else
		return CLASS_E_CLASSNOTAVAILABLE;
	    return NO_ERROR;
	}
extern "C" {
}

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved)
{
	// MessageBox(0, "Hello World from DLL!...\n", "Hi", MB_ICONINFORMATION);

	switch (fdwReason)
	{
	case DLL_PROCESS_ATTACH:
	{
		break;
	}
	case DLL_PROCESS_DETACH:
	{
		break;
	}
	case DLL_THREAD_ATTACH:
	{
		break;
	}
	case DLL_THREAD_DETACH:
	{
		break;
	}
	}

	/* Return TRUE on success, FALSE on failure */
	return TRUE;
}
