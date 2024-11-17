# This approach compiled  plugin that loaded up on an Inter MacBook Pro, but does not work here.
# It showed promise in vdj-link stub-projefct but runs into compiule issues
# on this full implementation

CXXFLAGS = -Wall -fPIC 

all: VdjConnect.dylib VdjConnect.bundle

clean:
	rm -f *.o MyPlugin8.dylib VdjConnect.bundle
	
VdjConnect.dylib: Main.o TestProvider.o
	g++ -dynamiclib -o libutils.dylib Main.o MyPlugin8.o
	#g++ -dynamiclib -o libutils.dylib utils.cpp

VdjConnect.bundle: Main.o TestProvider.o
	g++ -flat_namespace -bundle -undefined suppress -o VdjConnect.bundle Main.o TestProvider.o
	chmod +x VdjConnect.bundle

install: VdjConnect.dylib VdjConnect.bundle
	cp VdjConnect.bundle ~/Documents/VirtualDJ/Plugins64/OnlineSources/

uninstall: clean
	rm -f ~/Documents/VirtualDJ/Plugins64/OnlineSources/VdjConnect.bundle

app:
	mkdir -p VdjConnect.app/Contents/MacOS
	mkdir -p VdjConnect.app/Contents/Resoruces
	echo >>  VdjConnect.app/Contents/Info.plist
	echo >>  VdjConnect.app/ContentsResoruces/MyPlugin8.icns
	cc -flat_namespace -bundle -undefined suppress -o VdjConnect.bundle *.o
