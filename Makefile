.PHONY=build install 

build: 
	swift build -c release

install: build
	cp -f ./.build/release/acwmctl ~/bin/acwmctl 
