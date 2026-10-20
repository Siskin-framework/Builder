Rebol [
	Title:  "Siskin Builder - makefile project generator"
	name: mmake
	type: module
	note: "Work in progress!"
]

siskin: none

;-- variables:
Compiler:
CPP-Compiler:
LINKER:
Root-dir:
Objs-dir:
Source-dir:
File-build-targets:
OBJS:
LIBS:
INCLUDES:
DEFINES:
FRAMEWORKS:
CFLAGS:
CXXFLAGS:
LFLAGS:
PRODUCT:
PREP:
CLEAN:
PRE-BUILD:
; -----------
none

valid-archs: make map! [
	x86:    i386 
	i386:   i386
	x64:    x86_64
	x86_64: x86_64
	arm64:  arm64
	arm64e: arm64e ;used on the A12 chipset - on Mac M1's and iPhones models (XS/XS Max/XR)
	armv8:  arm64e
]

write-file: func[file [file! block!] data][
	if block? file [file: rejoin file]
	try/with [
		write file data
		sys/log/more 'SISKIN ["Make Generated:^[[33m" to-local-file file]
	][	sys/log/error 'SISKIN system/state/last-error ]
	file
]

quoted: func[str][
	if find str #" " [
		str: append insert copy str #"^"" #"^""
	]
	str
]

make-escape: func [
	"Escapes a string for a makefile recipe line"
	str [string!]
][
	replace/all copy str #"$" "$$"
]

make-path: func [
	"Escapes a path for makefile targets, prerequisites and recipes"
	path [file! string!]
][
	path: make-escape siskin/to-posix-file path
	replace/all path #"#" "\#"
	replace/all path #" " "\ "
	path
]

form-include: func [
	"Forms an include flag for a makefile recipe"
	dir [file!]
][
	make-escape siskin/quote-sh-arg join "-I" siskin/to-posix-file dir
]

form-define: func ["Forms a define flag for a makefile" def][
	make-escape siskin/quote-sh-arg join "-D" def
]

make-project: func[
	spec   [map!]
	;dir    [file! string!]
	/guid
		id [string!] "Visual studio project type GUID"
	/local
		output dir-bin dir-out rel-file name obj tmp file cpp? needs-cpp?
][
	unless siskin [siskin: system/modules/siskin]
	output: make string! 30000

	mkdir: func[dir][
		clean-path siskin/prepare-dir 'MAKE dir
	]

	dir-bin: mkdir any [spec/out-dir %.]


	if name: spec/name [
		set [dir name] split-path name
		if all [dir-bin dir <> %./][append dir-bin dir]
	]

	dir-out: mkdir %make/


	unless spec/root [
		spec/root: to file! get-env "NEST_ROOT"
	]

	siskin/add-env "NEST_SPEC" save dir-out/(join name %.reb) spec 

	PRODUCT: copy name

	;-- compose .pbxproj file
	if siskin/debug? [?? spec]

 	Compiler: spec/compiler
	CPP-Compiler: either spec/ccpp [siskin/to-posix-file spec/ccpp][form Compiler]
	unless any [spec/ccpp find CPP-Compiler "++"] [
		case [
			tmp: find/last CPP-Compiler "gcc"   [change/part tmp "g++" 3]
			tmp: find/last CPP-Compiler "clang" [insert skip tmp 5 "++"]
		]
	]
	Root-dir:   undirize spec/root
	Objs-dir:     dirize any [spec/objects spec/temp "."]
	Source-dir: undirize join spec/root any [spec/source ""]
	if #"/" <> first Objs-dir [insert Objs-dir join Root-dir #"/"]
	append Objs-dir rejoin [
		spec/compiler #"-" spec/arch #"/" spec/name
	]
	Root-dir:   make-path Root-dir
	Objs-dir:   make-path Objs-dir
	Source-dir: make-path Source-dir

	OBJS:       clear ""
	LIBS:       clear ""
	PREP:       clear ""
	INCLUDES:   clear ""
	DEFINES:    clear ""
	FRAMEWORKS: clear ""
	CFLAGS:     clear ""
	CXXFLAGS:   clear ""
	LFLAGS:     clear ""
	CLEAN:      clear ""
	File-build-targets: clear ""

	foreach dir spec/includes [
		if #"/" <> first dir [
			dir: join spec/root dir
		]
		rel-file: siskin/get-relative-path dir dir-out
		append INCLUDES join " \^/^-" form-include rel-file
	]

	;-- collect definitions
	foreach def any [spec/defines []] [
		append DEFINES join " \^/^-" form-define def
	]

	;-- collect libraries
	foreach lib any [spec/libraries []] [
		append LIBS join " \^/^--l" lib
	]

	;-- collect frameworks
	foreach file sort spec/frameworks [
		file: to file! file
		append FRAMEWORKS join " \^/^--framework " file
	]

	append CFLAGS spec/cflags
	append CXXFLAGS spec/cppflags
	append LFLAGS spec/lflags

	foreach file sort spec/shared [
		siskin/replace-extension file %.dylib
	]

	foreach file sort spec/frameworks [
		file: append to file! file %.framework
	]

	append OBJS #"\"

	tmp: copy []
	needs-cpp?: false

	foreach file sort spec/files [
		rel-file: skip siskin/get-relative-path file dir-out 3
		if cpp?: find siskin/cpp-extensions suffix? file [needs-cpp?: true]
;		file: find/tail file spec/root
;		set [d n] split-path file
		either find/match file spec/root [
			file: join "$R/" make-path skip file length? spec/root
		][
			file: make-path file
		]

		obj: siskin/replace-extension copy file %.o
		replace obj "$R/" "$O/"
		append OBJS ajoin ["^/^-" obj " \"]

		append tmp first split-path obj

		append File-build-targets rejoin [
			"^/^/" obj ": " file
			"^/^-" either cpp? ["$(CXX) "]["$(CC) "] file
			either cpp? [" $(CXXFLAGS)"][" $(CFLAGS)"] " -o " obj
		]
	]
	LINKER: either needs-cpp? ["$(CXX)"]["$(CC)"]

	foreach dir sort unique tmp [
		append PREP join "^/^-mkdir -p " dir
		append CLEAN rejoin ["^/^-$(RM) " dir %*.o]
	]

	;-- stack-size
	; stack size
	if all [
		spec/stack-size
		none? find LFLAGS "-shared" ; don't use stack-size setting when making a shared library
	][
		case [
			siskin/windows? [
				;This does not work on Linux!
				append LFLAGS rejoin either find form spec/compiler "gcc" [
					["-Wl,--stack="                 spec/stack-size  ]
				][	["-Wl,-stack:0x" skip to-binary spec/stack-size 4]]
			]
			siskin/Linux? [
				;This does not work with Apple's clang!
				append LFLAGS join "-Wl,-z,stack-size=" spec/stack-size
			]
			siskin/macOS? [
				append LFLAGS join "-Wl,-stack_size -Wl,0x" skip to-binary spec/stack-size 4
			]
		]
		append LFLAGS #" "
	]

;	unless find spec/cflags "-arch " [
;		
;	]


	;-- and...

;	spec/output: join %make/build/Release/ product


	PRE-BUILD: make-escape siskin/quote-sh-arg siskin/to-posix-file
		siskin/write-sh-pre-build spec dir-out
	;@@ TODO: post actions..
	;POST-BUILD-EVENT: copy "" ;siskin/form-sh-pre-build spec/post-build

	file: join dir-out [spec/name %.mk]

	reword/escape/into makefile self [#"<" #">"] output
	write-file file output

	siskin/print-info ajoin [{Make project generated: } as-yellow mold file]
	file
]

makefile: next {
# Siskin Builder generated makefile #
#####################################

PRODUCT= <PRODUCT>

# For the build toolchain:
CC=	   $(TOOLS)<Compiler>
CXX=   $(TOOLS)<CPP-Compiler>
NM=	   $(TOOLS)nm
STRIP= $(TOOLS)strip

# CP allows different copy progs:
CP= cp
# LS allows different ls progs:
LS= ls -l
# RM allows different RM progs:
RM= @-rm -rf
# UP - some systems do not use ../
UP= ..
# CD - some systems do not use ./
CD= ./

# Paths used by make:
R= <Root-dir>
O= <Objs-dir>
S= <Source-dir>

USE_FLAGS=

INCLUDES=<INCLUDES>

DEFINES=<DEFINES>

FRAMEWORKS=<FRAMEWORKS>

LIBS=<LIBS>

CFLAGS= -c $(INCLUDES) $(DEFINES) <CFLAGS> $(USE_FLAGS)
CXXFLAGS= $(CFLAGS) <CXXFLAGS>
LFLAGS= $(LIBS) $(FRAMEWORKS) <LFLAGS> $(USE_FLAGS)



### Build targets:
.PHONY: default prebuild
default: $(PRODUCT);

prebuild:
	sh <PRE-BUILD>

clean: <CLEAN>

all:
	$(MAKE) $(PROJECT_NAME)

prep: <PREP>


### Post build actions

strip:
	$(STRIP) $(PRODUCT)

OBJS = <OBJS>

# pre-build runs before any object is compiled, without forcing a rebuild
$(OBJS): | prebuild

### Main build target:

$(PRODUCT):	prep $(OBJS) $(RES)
	<LINKER> -o $(PRODUCT) $(OBJS) $(LFLAGS)

### File build targets: <File-build-targets>

}