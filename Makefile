.SILENT:

compile:
	rm -f ./build/devbuild
	jai-linux ./build.jai -natvis - bake_font

run:
	rm -f ./build/devbuild
	jai-linux ./build.jai -natvis - bake_font && ./build/devbuild

release:
	rm -f ./build/asterisk
	jai-linux ./build.jai - release bake_font