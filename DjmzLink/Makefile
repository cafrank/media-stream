
CC	= gcc
CXX	= g++
module	= MyPlugin8

CXXFLAGS = -IC:/lib/curl/include -Ic:/lib/jsoncpp/include
LDFLAGS  = -DCURL_STATICLIB -LC:/lib/curl/lib
LDLIBS	 = -lstdc++ -lcurl -lws2_32 -lwinmm

all: dll

clean:
	rm -f *.o *.dll *.a

install: dll
	cp  ${module}.dll  C:/Users/User/AppData/Local/VirtualDJ/Plugins64/OnlineSources
	#cp  cyg${module}.dll  /c/Users/User/Documents/VirtualDJ/Plugins64/OnlineSources/

#${module}.o:

dll2: ${module}.o
	gcc -shared -o ${module}.dll $<

dll: ${module}.o Log.o
	g++ $(LDFLAGS) ${LDLIBS} -shared $< Log.o \
		-o ${module}.dll \
	    -Wl,--out-implib=lib${module}.dll.a \
	    -Wl,--export-all-symbols \
	    -Wl,--enable-auto-import \
	    -Wl,--whole-archive ${old_libs} \
	    -Wl,--no-whole-archive ${dependency_libs} 


