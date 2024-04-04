Rebol [
	Title:  "Siskin Builder - makefile project generator"
	name: mmake
	type: module
	note: "Work in progress!"
]

siskin: none

;-- variables:
Compiler:
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
LFLAGS:
PRODUCT:
PREP:
CLEAN:
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
	try/except [
		write file data
		sys/log/more 'SISKIN ["Make Generated:^[[33m" to-local-file file]
	][	sys/log/error 'SISKIN system/state/last-error ]
	file
]

get-relative-path: function[path base][
    path: split clean-path/only path #"/"
    base: split clean-path/only dirize base #"/"
    take/last base          ;-- remove the empty part
    while [all [path/1 path/1 = base/1]] [remove path remove base]
    insert/dup path ".." length? base
    file: to file! any [first path %""]
    while [not tail? path: next path][append append file #"/" path/1]
    file
]

to-posix-file: either system/platform = 'windows [
	func[path [file! string!]][
		path: to-local-file path
		replace/all path #"\" #"/" 
		path
	]
][
	:to-local-file
]

relativize-files: func[files [block!] dir /local tmp][
	unless any-string? dir [exit]
	forall files [
		tmp: get-relative-path files/1 dir
		append clear files/1 tmp	
	]
	files
]

quoted: func[str][
	if find str #" " [
		str: append insert copy str #"^"" #"^""
	]
	str
]

dirs-stack: copy []
pushd: function [
	target [file!]
][
	dir: what-dir
	append dirs-stack dir
	dir
]
popd: function [][
	dir: take/last dirs-stack
]

escaped-args: func[args [block! string! none!]][
	if none?  args [return ""]
	args: either block? args [reform args][copy args]
	; not nice and optimal, but I have no time now...
	replace/all args #"\" "\\"
	replace/all args #"^"" {\"}
	replace/all args #"^/" "\n"
	replace/all args #"^M" ""
	ajoin [{ --args "} args {"}]
]

form-pre-post-build: func[
	spec 
	code [block!]
	/local val args tmp siskin result
][
	result: make string! 1000
	siskin: system/modules/siskin
	append result rejoin [
		{#!/bin/sh^/}
		{echo Prebuilding...^/}
		{cd } to-posix-file spec/root
	]
	parse code [any[
		'do [
			set val file! set args [block! | string! | none] (
				;?? args
				if string? args [siskin/expand-env args]
				append result rejoin [
					lf to-posix-file system/options/boot ;to-local-file siskin/expand-env %$REBOL3
					" --script " to-posix-file val
					escaped-args args
				]
			)
		]
		| 'pushd set val file! (
			append append result "^/cd " to-posix-file pushd dir
		)
		| 'popd (
			append append result "^/cd " to-posix-file popd
		)
		|
		copy val 2 skip (
			siskin/print-warn ["!!! Ignoring setting: " mold/flat val]
			;ask "Press enter to continue."
		)
	]]
	result
]


make-project: func[
	spec   [map!]
	;dir    [file! string!]
	/guid
		id [string!] "Visual studio project type GUID"
	/local
		output dir-bin dir-out rel-file name obj tmp file
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
	Root-dir:   undirize spec/root
	Objs-dir:     dirize any [spec/objects spec/temp "."]
	Source-dir: undirize join spec/root any [spec/source ""]
? Objs-dir 
	if #"/" <> first Objs-dir [insert Objs-dir join Root-dir #"/"]
? Objs-dir 
	append Objs-dir rejoin [
		spec/compiler #"-" spec/arch #"/" spec/name
	]

	OBJS:       clear ""
	LIBS:       clear ""
	PREP:       clear ""
	INCLUDES:   clear ""
	DEFINES:    clear ""
	FRAMEWORKS: clear ""
	CFLAGS:     clear ""
	LFLAGS:     clear ""
	CLEAN:      clear ""
	File-build-targets: clear ""

	foreach dir spec/includes [
		if #"/" <> first dir [
			dir: join spec/root dir
		]
		rel-file: get-relative-path dir dir-out
		append INCLUDES join " \^/^--I" to-posix-file rel-file
	]

	;-- collect definitions
	foreach def any [spec/defines []] [
		def: either any-string? def [copy def][to string! def]
		append DEFINES join " \^/^--D" def
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
	append LFLAGS spec/lflags

	foreach file sort spec/shared [
		siskin/replace-extension file %.dylib
	]

	foreach file sort spec/frameworks [
		file: append to file! file %.framework
	]

	append OBJS #"\"

	tmp: copy []

	foreach file sort spec/files [
		rel-file: skip get-relative-path file dir-out 3
;		file: find/tail file spec/root
;		set [d n] split-path file
		parse file [ spec/root file: (file: join "$R/" file) ]

		obj: siskin/replace-extension copy file %.o
		replace obj "$R/" "$O/"
		append OBJS ajoin ["^/^-" obj " \"]

		append tmp first split-path obj

		append File-build-targets rejoin [
			"^/^/" obj ": " file
			"^/^-$(CC) " file " $(CFLAGS) -o " obj
		]
	]
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


;	PRE-BUILD: form-pre-post-build spec any [spec/pre-build []]
;	PRE-BUILD-SCRIPT: siskin/to-local-file join dir-out %pre-build.sh
;	write-file [dir-out %pre-build.sh] PRE-BUILD
;	siskin/eval-cmd/v/force [{chmod +x } PRE-BUILD-SCRIPT]
;	replace/all PRE-BUILD-SCRIPT #" " "\\ " ;@@ add proper escaping!!!
	;@@ TODO: post actions..
	;POST-BUILD-EVENT: copy "" ;form-pre-post-build spec/post-build

	file: join dir-out [spec/name %.mk]

	reword/escape/into makefile self [#"<" #">"] output
	write-file file output

	siskin/print-info ajoin [{Make project generated: } as-yellow mold file]

	probe file
]

makefile: next {
# Siskin Builder generated makefile #
#####################################

PRODUCT= <PRODUCT>

# For the build toolchain:
CC=	   $(TOOLS)<Compiler>
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
LFLAGS= $(LIBS) $(FRAMEWORKS) <LFLAGS> $(USE_FLAGS)



### Build targets:
.PHONY: default
default: $(PRODUCT);

clean: <CLEAN>

all:
	$(MAKE) $(PROJECT_NAME)

prep: <PREP>


### Post build actions

strip:
	$(STRIP) $(PRODUCT)

OBJS = <OBJS>

### Main build target:

$(PRODUCT):	prep $(OBJS) $(RES)
	$(CC) -o $(PRODUCT) $(OBJS) $(LFLAGS)

### File build targets: <File-build-targets>

}