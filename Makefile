.PHONY:
.SILENT:

compile:
	rm -f ./build/devbuild
	jai-linux ./first.jai

run: compile
	./build/devbuild

release:
	rm -f ./build/asterisk
	jai-linux ./first.jai - release