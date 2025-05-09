.SILENT:

compile:
	rm -f ./build/devbuild
	jai-linux ./build.jai - bake_font

run:
	rm -f ./build/devbuild
	jai-linux ./build.jai - bake_font && ./build/devbuild

profile:
	rm -f ./build/devbuild
	jai-linux ./build.jai -plug Iprof - bake_font && ./build/devbuild

profile-all:
	rm -f ./build/devbuild
	jai-linux ./build.jai -plug Iprof -modules - bake_font && ./build/devbuild

release:
	rm -f ./build/asterisk
	jai-linux ./build.jai - release bake_font