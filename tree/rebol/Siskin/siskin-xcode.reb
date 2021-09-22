Rebol [
	Title:  "Siskin Builder - xcode project generator"
	name: xcode
	type: module
]

siskin: none

;-- variables:
PROJECT-UUID:
PROJECT-NAME:
PROJECT-VERSION:
PRODUCT:
TARGET-UUID:
LIBRARY-PATH:
INCLUDE-PATH:
ADDITIONAL-DEPENDENCIES:
CONFIGURATION-TYPE:
PROJECT-FILES:
PROJECT-DEFINES:
PRE-BUILD:
PRE-BUILD-SCRIPT:
POST-BUILD-EVENT:
RESOURCE-ITEM:
TOOLSET-VERSION:
STACK-SIZE:
SECTION-PBXBuildFile:
SECTION-PBXFileReference:
SECTION-PBXGroup-Sources-Children:
SECTION-PBXGroup-Headers-Children:
SECTION-PBXGroup-Frameworks-Children:
SECTION-PBXSourcesBuildPhase-Files:
SECTION-PBXFrameworksBuildPhase-Files:
SECTION-PBXCopyFilesBuildPhase-EmbedLib-Files:
HEADER_SEARCH_PATHS:
GCC_PREPROCESSOR_DEFINITIONS:
GCC_OPTIMIZATION_LEVEL:
OTHER_LDFLAGS:
WARNING_CFLAGS:
MACH_O_TYPE:
ARCH:
GCC_WARN_64_TO_32_BIT_CONVERSION:
none

TAB2: "^-^-"
TAB4: "^-^-^-^-"

make-uuid: function[type [any-string!] name [any-string!]][
	uuid: make binary! 12
	ni: encode 'unixtime now
	tp: checksum join "SISKIN" type 'adler32
	nm: checksum join "SISKIN" name 'adler32
	binary/write uuid [UI32 :ni UI32 :tp UI32 :nm]
	sys/log/debug 'SISKIN ["UUID Generated:^[[33m" uuid mold type mold name]
	uuid
]
prepare-dir: func[dir [file! string!]][
	dir: dirize dir
	unless exists? dir [
		sys/log/more 'SISKIN ["Xcode made dir:^[[33m" to-local-file dir]
		if error? try [make-dir/deep dir][
			print ["Cannot make directory: " mold dir]
			halt
		]
	]
	dir
]
write-file: func[file [file! block!] data][
	if block? file [file: rejoin file]
	try/except [
		write file data
		sys/log/more 'SISKIN ["Xcode Generated:^[[33m" to-local-file file]
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

get-file-type: function[file][
	any [
		select/case filetypes suffix? file
		"file"
	]
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
			print ["!!! Ignoring setting: " mold val]
			ask "Press enter to continue."
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
		name tmp output dir dir-out dir-bin defines includes rel-file dir-name
		filters items ver lib-paths d n id_fileRef id_file dirs blk headers
		product-type
][
	unless siskin [siskin: system/modules/siskin]
	output: make string! 30000

	dir-bin: clean-path prepare-dir any [spec/out-dir %.]


	if name: spec/name [
		set [dir name] split-path name
		if all [dir-bin dir <> %./][append dir-bin dir]
	]

	dir-out: clean-path prepare-dir rejoin [%make/ name %.xcodeproj/]


	unless spec/root [
		spec/root: to file! get-env "NEST_ROOT"
	]

	STACK-SIZE: any [spec/stack-size ""]

	siskin/add-env "NEST_SPEC" save dir-out/(join name %.reb) spec 

	product: copy name

	;-- compose .pbxproj file
	if siskin/debug? [?? spec]

	PROJECT-UUID: make-uuid "project" name
	TARGET-UUID:  make-uuid "fileRef" name
	PROJECT-NAME: name
	PROJECT-VERSION: any [spec/version ""]
	SECTION-PBXBuildFile: clear ""
	SECTION-PBXFileReference: clear ""
	SECTION-PBXGroup-Sources-Children: clear ""
	SECTION-PBXGroup-Headers-Children: clear ""
	SECTION-PBXGroup-Frameworks-Children: clear ""
	SECTION-PBXSourcesBuildPhase-Files: clear ""
	SECTION-PBXFrameworksBuildPhase-Files: clear ""
	SECTION-PBXCopyFilesBuildPhase-EmbedLib-Files: clear ""

	ARCH: spec/arch
	case [
		ARCH = 'x86 [ARCH: 'i386]
		ARCH = 'x64 [ARCH: 'x86_64]
	]

	MACH_O_TYPE: any [
		all [
			find spec/lflags "-shared "
			product-type: "compiled.mach-o.dylib"
			siskin/replace-extension product %.dylib
			'mh_dylib
		]
		all [
			find spec/lflags "-archive-only "
			product-type: "compiled.mach-o.objfile"
			siskin/replace-extension product %.a
			unless find/match product "lib" [insert product "lib"]
			'staticlib
		]
		all [
			product-type: "compiled.mach-o.executable"
			'mh_execute
		]
	]

	HEADER_SEARCH_PATHS: clear ""
	OTHER_LDFLAGS: clear ""

	filters: copy [] ; used later
	items:   copy []
	dirs: #()
	foreach file join spec/files spec/assembly [
		;file: siskin/get-file-with-extensions file [%.c %.cpp %.cc %.m %.S %.s %.sx]
		rel-file: get-relative-path file dir-out
		set [dir name] split-path rel-file
		
		if none? blk: dirs/:dir [ blk: dirs/:dir: copy [] ]
		append blk name
		parse dir [any %../ dir-name: to end] ; get directory name without .. (used in gui as names of folders)

		take/last dir-name                    ; undirize
		append filters dir-name               ; remember current name
		repend items [rel-file dir-name]      ; and store link between file and this dir name

		;include all directories in the path..
		while [not find [%./ %../] dir-name: first split-path dir-name][
			if #"/" = last dir-name [take/last dir-name]
			append filters dir-name
		]
		
		;if file
		;append output rejoin [
		;	{    <ClCompile Include="} to-windows-file rel-file {" />^/}
		;] 
	]
	filters: sort unique filters
	items: unique items
	;? filters
	;? items
	

	foreach dir spec/includes [
		if #"/" <> first dir [
			dir: join spec/root dir
		]
		unless block? dirs/:dir [dirs/:dir: copy []]
		
		try/except [
			append dirs/:dir read dir
		][
			siskin/print-error ["Cannot read from:" as-red dir]
			continue
		]

		rel-file: skip get-relative-path dir dir-out 3
		append HEADER_SEARCH_PATHS rejoin [
			{^-^-^-^-^-"} rel-file {",^/}
		]
	]
	;? dirs

	headers: copy []
	foreach [dir files] dirs [
		if #"/" <> first dir [ dir: join dir-out dir ]

		try/except [tmp: read dir][
			siskin/print-error ["Cannot read from:" as-red dir]
			continue
		]
		foreach file tmp [
			if find [%.h %.inc %.hh %.h++ %.hp %.hpp] suffix? file [
				append headers dir/:file
			]
		]
	]
	;? headers

	append SECTION-PBXFileReference rejoin [
		TAB2 TARGET-UUID  " /* " product " */ = {isa = PBXFileReference; explicitFileType = ^""
		product-type "^"; includeInIndex = 0; path = " product "; sourceTree = BUILT_PRODUCTS_DIR; };^/"
	]

	foreach file sort spec/shared [
		siskin/replace-extension file %.dylib
		id_file:    make-uuid "file in Frameworks" file 
		id_fileRef: make-uuid "fileRef" file

		append SECTION-PBXFileReference rejoin [
			TAB2 id_fileRef  " /* " file " */ = {isa = PBXFileReference; lastKnownFileType = ^"compiled.mach-o.dylib^"; name = "
			file "; path = build/Release/" file "; sourceTree = ^"<group>^"; };^/"
		]

		append SECTION-PBXBuildFile rejoin [
			TAB2 id_file " /* " file " in Frameworks */ = {isa = PBXBuildFile; fileRef = "
			id_fileRef " /* " file " */; };^/"
		]

		append SECTION-PBXFrameworksBuildPhase-Files rejoin [
			TAB4 id_file " /* " file " in Frameworks */,^/"
		]

		append SECTION-PBXGroup-Frameworks-Children rejoin [
			TAB4 id_fileRef " /* " file " */,^/"
		]

		id_file:    make-uuid "file in Embed Libraries" file 
		append SECTION-PBXBuildFile rejoin [
			TAB2 id_file " /* " file " in Embed Libraries */ = {isa = PBXBuildFile; fileRef = "
			id_fileRef " /* " file " */; settings = {ATTRIBUTES = (CodeSignOnCopy, ); }; };^/"
		]

		append SECTION-PBXCopyFilesBuildPhase-EmbedLib-Files rejoin [
			TAB4 id_file " /* " file " in Embed Libraries */,^/"
		]

		
	]

	foreach file sort spec/frameworks [
		file: append to file! file %.framework
		id_file:    make-uuid "file" file 
		id_fileRef: make-uuid "fileRef" file
		append SECTION-PBXBuildFile rejoin [
			TAB2 id_file " /* " file " in Frameworks */ = {isa = PBXBuildFile; fileRef = "
			id_fileRef " /* " file " */; };^/"
		]
		append SECTION-PBXFileReference rejoin [
			TAB2 id_fileRef  " /* " file " */ = {"
			"isa = PBXFileReference; "
			"lastKnownFileType = wrapper.framework; "
			"name = ^"" file "^"; "
			"path = ^"System/Library/Frameworks/" file "^"; "
			"sourceTree = SDKROOT; };^/"
		]
		append SECTION-PBXFrameworksBuildPhase-Files rejoin [
			TAB4 id_file " /* " file " in Frameworks */,^/"
		]
		append SECTION-PBXGroup-Frameworks-Children rejoin [
			TAB4 id_fileRef " /* " file " */,^/"
		]
	]


	foreach file spec/files [
		rel-file: skip get-relative-path file dir-out 3
		file: find/tail file spec/root
		set [d n] split-path file
		id_file:    make-uuid "file" file 
		id_fileRef: make-uuid "fileRef" file
		append SECTION-PBXBuildFile rejoin [
			TAB2 id_file " /* " n " in Sources */ = {isa = PBXBuildFile; fileRef = "
			id_fileRef " /* " n " */; };^/"
		]

		append SECTION-PBXFileReference rejoin [
			TAB2 id_fileRef  " /* " n " */ = {"
			"isa = PBXFileReference; "
			"lastKnownFileType = " get-file-type n "; "
			"name = ^"" n "^"; "
			"path = ^"" rel-file "^"; "
			"sourceTree = ^"<group>^"; };^/"
		]

		append SECTION-PBXGroup-Sources-Children rejoin [
			TAB4 id_fileRef  " /* " n " */,^/"
		]

		append SECTION-PBXSourcesBuildPhase-Files rejoin [
			TAB4 id_file  " /* " n " in Sources */,^/"
		]
	]

	foreach file sort headers [
		rel-file: skip get-relative-path file dir-out 3
		file: find/tail file spec/root
		set [d n] split-path file
		id_file:    make-uuid "file" file 
		id_fileRef: make-uuid "fileRef" file

		append SECTION-PBXFileReference rejoin [
			TAB2 id_fileRef  " /* " n " */ = {"
			"isa = PBXFileReference; "
			"lastKnownFileType = " get-file-type n "; "
			"name = ^"" n "^"; "
			"path = ^"" rel-file "^"; "
			"sourceTree = ^"<group>^"; };^/"
		]

		append SECTION-PBXGroup-Headers-Children rejoin [
			TAB4 id_fileRef  " /* " n " */,^/"
		]
	]


	;-- collect GCC_PREPROCESSOR_DEFINITIONS
	GCC_PREPROCESSOR_DEFINITIONS: copy ""
	foreach def any [spec/defines []] [
		def: either any-string? def [copy def][to string! def]
		replace/all def #"\" {\\\} ;@@ temp solution!!! 
		append GCC_PREPROCESSOR_DEFINITIONS rejoin [
			{^-^-^-^-^-"} def {",^/}
		]
	]

	GCC_OPTIMIZATION_LEVEL: 2
	parse spec/cflags [
		["-O" | thru " -O"] copy GCC_OPTIMIZATION_LEVEL to #" "
	]
	
	

	;-- collect libraries
	OTHER_LDFLAGS: clear ""

	probe spec/lflags

	foreach lib any [spec/libraries []] [
		append OTHER_LDFLAGS rejoin [
			{^-^-^-^-^-"-l} lib {",^/}
		]
	]

	WARNING_CFLAGS: clear ""
	parse spec/cflags [
		any [
			to " -W" 1 skip copy tmp to #" " (
				append WARNING_CFLAGS rejoin [
					{^-^-^-^-^-"} tmp {",^/}
				]
			)
		]
	]

	;-- stack-size
	if all [
		spec/stack-size
		none? find spec/lflags "-shared" ; don't use stack-size setting when making a shared library
	][
		append OTHER_LDFLAGS rejoin [
			{^-^-^-^-^-"-Wl,-stack_size -Wl,0x} skip to-binary spec/stack-size 4 {",^/}
		]
	]

	;-- and...

	spec/output: join %make/build/Release/ product


	PRE-BUILD: form-pre-post-build spec any [spec/pre-build []]
	PRE-BUILD-SCRIPT: to-local-file join dir-out %pre-build.sh
	write-file [dir-out %pre-build.sh] PRE-BUILD
	siskin/eval-cmd/v/force ["chmod +x " PRE-BUILD-SCRIPT]
	;@@ TODO: post actions..
	;POST-BUILD-EVENT: copy "" ;form-pre-post-build spec/post-build

	GCC_WARN_64_TO_32_BIT_CONVERSION: either find spec/cflags @-Wno-shorten-64-to-32 [@NO][@YES]
	
	trim/tail SECTION-PBXBuildFile
	trim/tail SECTION-PBXGroup-Frameworks-Children
	trim/tail SECTION-PBXGroup-Sources-Children
	trim/tail SECTION-PBXFrameworksBuildPhase-Files
	trim/tail SECTION-PBXSourcesBuildPhase-Files
	trim/tail SECTION-PBXCopyFilesBuildPhase-EmbedLib-Files
	trim/head/tail HEADER_SEARCH_PATHS
	trim/head/tail GCC_PREPROCESSOR_DEFINITIONS
	trim/head/tail OTHER_LDFLAGS

	reword/escape/into project.pbxproj self [#"#" #"#"] output
	write-file [dir-out %project.pbxproj] output

	siskin/print-info {^[[1;32mXcode project generated.^[[m}

	dir-out ; returns the *.xcodeproj directory 
]

project.pbxproj: {// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 50;
	objects = {

/* Begin PBXBuildFile section */
#SECTION-PBXBuildFile#
/* End PBXBuildFile section */

/* Begin PBXCopyFilesBuildPhase section */
		40AFCA8426BD67990023CA1A /* CopyFiles */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = /usr/share/man/man1/;
			dstSubfolderSpec = 0;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 1;
		};
		40E23ADE26FB4A0C00E7BF3F /* Embed Libraries */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 10;
			files = (
#SECTION-PBXCopyFilesBuildPhase-EmbedLib-Files#
			);
			name = "Embed Libraries";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
#SECTION-PBXFileReference#
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		40AFCA8326BD67990023CA1A /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
#SECTION-PBXFrameworksBuildPhase-Files#
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		401BDAF826C44E8800F18C0F /* Frameworks */ = {
			isa = PBXGroup;
			children = (
#SECTION-PBXGroup-Frameworks-Children#
			);
			name = Frameworks;
			sourceTree = "<group>";
		};
		40AFCA7D26BD67990023CA1A = {
			isa = PBXGroup;
			children = (
				40AFCA8826BD67990023CA1A /* Sources */,
				40AFCA8826BD67990023CA1B /* Headers */,
				40AFCA8726BD67990023CA1A /* Products */,
				401BDAF826C44E8800F18C0F /* Frameworks */,
			);
			sourceTree = "<group>";
		};
		40AFCA8726BD67990023CA1A /* Products */ = {
			isa = PBXGroup;
			children = (
				#TARGET-UUID# /* #PRODUCT# */,
			);
			name = Products;
			sourceTree = "<group>";
		};
		40AFCA8826BD67990023CA1A /* Sources */ = {
			isa = PBXGroup;
			children = (
#SECTION-PBXGroup-Sources-Children#
			);
			name = "Sources";
			path = "../src/";
			sourceTree = "<group>";
		};
		40AFCA8826BD67990023CA1B /* Headers */ = {
			isa = PBXGroup;
			children = (
#SECTION-PBXGroup-Headers-Children#
			);
			name = "Headers";
			path = "../src/";
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		#PROJECT-UUID# /* #PROJECT-NAME# */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 40AFCA8D26BD67990023CA1A /* Build configuration list for PBXNativeTarget "#PROJECT-NAME#" */;
			buildPhases = (
				400196FC26E7F4B300D82EC0 /* ShellScript */,
				40AFCA8226BD67990023CA1A /* Sources */,
				40AFCA8326BD67990023CA1A /* Frameworks */,
				40AFCA8426BD67990023CA1A /* CopyFiles */,
				40E23AE226FB4D1F00E7BF3F /* Embed Libraries */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = #PRODUCT#;
			productName = #PRODUCT#;
			productReference = #TARGET-UUID# /* #PRODUCT# */;
			productType = "com.apple.product-type.tool";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		40AFCA7E26BD67990023CA1A /* Project object */ = {
			isa = PBXProject;
			attributes = {
				LastUpgradeCheck = 1250;
				TargetAttributes = {
					#PROJECT-UUID# = {
						CreatedOnToolsVersion = 12.5.1;
					};
				};
			};
			buildConfigurationList = 40AFCA8126BD67990023CA1A /* Build configuration list for PBXProject "#PROJECT-NAME#" */;
			compatibilityVersion = "Xcode 9.3";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = 40AFCA7D26BD67990023CA1A;
			productRefGroup = 40AFCA8726BD67990023CA1A /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				#PROJECT-UUID# /* #PROJECT-NAME# */,
			);
		};
/* End PBXProject section */

/* Begin PBXShellScriptBuildPhase section */
		400196FC26E7F4B300D82EC0 /* ShellScript */ = {
			isa = PBXShellScriptBuildPhase;
			alwaysOutOfDate = 1;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
			);
			outputFileListPaths = (
			);
			outputPaths = (
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "#PRE-BUILD-SCRIPT#";
			showEnvVarsInLog = 0;
		};
/* End PBXShellScriptBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		40AFCA8226BD67990023CA1A /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
#SECTION-PBXSourcesBuildPhase-Files#
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		40AFCA8B26BD67990023CA1A /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++14";
				CLANG_CXX_LIBRARY = "libc++";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = NO;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = #GCC_WARN_64_TO_32_BIT_CONVERSION#;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				MACOSX_DEPLOYMENT_TARGET = 10.7;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
			};
			name = Debug;
		};
		40AFCA8C26BD67990023CA1A /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++14";
				CLANG_CXX_LIBRARY = "libc++";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = NO;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				MACOSX_DEPLOYMENT_TARGET = 10.7;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = macosx;
			};
			name = Release;
		};
		40AFCA8E26BD67990023CA1A /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CLANG_ENABLE_MODULES = NO;
				CODE_SIGN_STYLE = Manual;
				CURRENT_PROJECT_VERSION = "#PROJECT-VERSION#";
				DEVELOPMENT_TEAM = "";
				ENABLE_HARDENED_RUNTIME = YES;
				GCC_PREPROCESSOR_DEFINITIONS = (
					#GCC_PREPROCESSOR_DEFINITIONS#
				);
				HEADER_SEARCH_PATHS = (
					#HEADER_SEARCH_PATHS#
				);
				OTHER_LDFLAGS = (
					#OTHER_LDFLAGS#
				);
				PRODUCT_NAME = "$(TARGET_NAME)";
				MACH_O_TYPE = "#MACH_O_TYPE#";
			};
			name = Debug;
		};
		40AFCA8F26BD67990023CA1A /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_NAME = "$(TARGET_NAME)";
				ARCHS = (
					#ARCH#,
				);
				ONLY_ACTIVE_ARCH = YES;
				CLANG_ENABLE_MODULES = NO;
				CODE_SIGN_STYLE = Manual;
				CURRENT_PROJECT_VERSION = "#PROJECT-VERSION#";
				DEVELOPMENT_TEAM = "";
				ENABLE_HARDENED_RUNTIME = YES;
				GCC_OPTIMIZATION_LEVEL = #GCC_OPTIMIZATION_LEVEL#;
				GCC_PREPROCESSOR_DEFINITIONS = (
					#GCC_PREPROCESSOR_DEFINITIONS#
				);
				HEADER_SEARCH_PATHS = (
					#HEADER_SEARCH_PATHS#
				);
				OTHER_LDFLAGS = (
					#OTHER_LDFLAGS#
				);
				WARNING_CFLAGS = (
					#WARNING_CFLAGS#
				);
				MACH_O_TYPE = "#MACH_O_TYPE#";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		40AFCA8126BD67990023CA1A /* Build configuration list for PBXProject "#PROJECT-NAME#" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				40AFCA8B26BD67990023CA1A /* Debug */,
				40AFCA8C26BD67990023CA1A /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		40AFCA8D26BD67990023CA1A /* Build configuration list for PBXNativeTarget "#PROJECT-NAME#" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				40AFCA8E26BD67990023CA1A /* Debug */,
				40AFCA8F26BD67990023CA1A /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = 40AFCA7E26BD67990023CA1A /* Project object */;
}
}

;- SOURCE: https://github.com/tuist/XcodeProj/blob/f54ce91a2df8ce0d565db72d21faa5de3e151cec/Sources/XcodeProj/Project/Xcode.swift#L70-L337
filetypes: #(
	%.1 "text.man"
	%.C "sourcecode.cpp.cpp"
	%.H "sourcecode.cpp.h"
	%.M "sourcecode.cpp.objcpp"
	%.a "archive.ar"
	%.ada "sourcecode.ada"
	%.adb "sourcecode.ada"
	%.ads "sourcecode.ada"
	%.aiff "audio.aiff"
	%.air "compiled.air"
	%.apinotes "text.apinotes"
	%.apns "text"
	%.app "wrapper.application"
	%.appex "wrapper.app-extension"
	%.applescript "sourcecode.applescript"
	%.archivingdescription "text.xml.ibArchivingDescription"
	%.asdictionary "archive.asdictionary"
	%.asm "sourcecode.asm.asm"
	%.atlas "folder.skatlas"
	%.au "audio.au"
	%.avi "video.avi"
	%.bin "archive.macbinary"
	%.bmp "image.bmp"
	%.bundle "wrapper.cfbundle"
	%.c "sourcecode.c.c"
	%.c++ "sourcecode.cpp.cpp"
	%.cc "sourcecode.cpp.cpp"
	%.cdda "audio.aiff"
	%.cl "sourcecode.opencl"
	%.class "compiled.javaclass"
	%.classdescription "text.plist.ibClassDescription"
	%.classdescriptions "text.plist.ibClassDescription"
	%.clp "sourcecode.clips"
	%.cp "sourcecode.cpp.cpp"
	%.cpp "sourcecode.cpp.cpp"
	%.csh "text.script.csh"
	%.css "text.css"
	%.ctrl "sourcecode.glsl"
	%.cxx "sourcecode.cpp.cpp"
	%.d "sourcecode.dtrace"
	%.dSYM "wrapper.dsym"
	%.dae "text.xml.dae"
	%.defs "sourcecode.mig"
	%.dext "wrapper.driver-extension"
	%.dict "text.plist"
	%.dsym "wrapper.dsym"
	%.dtd "text.xml"
	%.dylan "sourcecode.dylan"
	%.dylib "compiled.mach-o.dylib"
	%.ear "archive.ear"
	%.entitlements "text.plist.entitlements"
	%.eval "sourcecode.glsl"
	%.exp "sourcecode.exports"
	%.f "sourcecode.fortran"
	%.f77 "sourcecode.fortran.f77"
	%.f90 "sourcecode.fortran.f90"
	%.f95 "sourcecode.fortran.f90"
	%.for "sourcecode.fortran"
	%.frag "sourcecode.glsl"
	%.fragment "sourcecode.glsl"
	%.framework "wrapper.framework"
	%.fs "sourcecode.glsl"
	%.fsh "sourcecode.glsl"
	%.geom "sourcecode.glsl"
	%.geometry "sourcecode.glsl"
	%.gif "image.gif"
	%.gmk "sourcecode.make"
	%.gpx "text.xml"
	%.gs "sourcecode.glsl"
	%.gsh "sourcecode.glsl"
	%.gz "archive.gzip"
	%.h "sourcecode.c.h"
	%.h++ "sourcecode.cpp.h"
	%.hh "sourcecode.cpp.h"
	%.hp "sourcecode.cpp.h"
	%.hpp "sourcecode.cpp.h"
	%.hqx "archive.binhex"
	%.htm "text.html"
	%.html "text.html"
	%.htmld "wrapper.htmld"
	%.hxx "sourcecode.cpp.h"
	%.i "sourcecode.c.c.preprocessed"
	%.icns "image.icns"
	%.ico "image.ico"
	%.iconset "folder.iconset"
	%.ii "sourcecode.cpp.cpp.preprocessed"
	%.iig "sourcecode.iig"
	%.imagecatalog "folder.imagecatalog"
	%.inc "sourcecode.pascal"
	%.instrdst "com.apple.instruments.instrdst"
	%.instrpkg "com.apple.instruments.package-definition"
	%.intentdefinition "file.intentdefinition"
	%.ipp "sourcecode.cpp.h"
	%.jam "sourcecode.jam"
	%.jar "archive.jar"
	%.java "sourcecode.java"
	%.javascript "sourcecode.javascript"
	%.jpeg "image.jpeg"
	%.jpg "image.jpeg"
	%.js "sourcecode.javascript"
	%.jscript "sourcecode.javascript"
	%.json "text.json"
	%.jsp "text.html.other"
	%.kext "wrapper.kernel-extension"
	%.l "sourcecode.lex"
	%.lid "sourcecode.dylan"
	%.ll "sourcecode.asm.llvm"
	%.llx "sourcecode.asm.llvm"
	%.lm "sourcecode.lex"
	%.lmm "sourcecode.lex"
	%.lp "sourcecode.lex"
	%.lpp "sourcecode.lex"
	%.lxx "sourcecode.lex"
	%.m "sourcecode.c.objc"
	%.mak "sourcecode.make"
	%.make "sourcecode.make"
	%.map "sourcecode.module-map"
	%.markdown "net.daringfireball.markdown"
	%.md "net.daringfireball.markdown"
	%.mdimporter "wrapper.spotlight-importer"
	%.mdown "net.daringfireball.markdown"
	%.metal "sourcecode.metal"
	%.metallib "archive.metal-library"
	%.mi "sourcecode.c.objc.preprocessed"
	%.mid "audio.midi"
	%.midi "audio.midi"
	%.mig "sourcecode.mig"
	%.mii "sourcecode.cpp.objcpp.preprocessed"
	%.mlkitmodel "file.mlmodel"
	%.mlmodel "file.mlmodel"
	%.mm "sourcecode.cpp.objcpp"
	%.modulemap "sourcecode.module-map"
	%.moov "video.quicktime"
	%.mov "video.quicktime"
	%.mp3 "audio.mp3"
	%.mpeg "video.mpeg"
	%.mpg "video.mpeg"
	%.mpkg "wrapper.installer-mpkg"
	%.nasm "sourcecode.nasm"
	%.nib "wrapper.nib"
	%.nib~ "wrapper.nib"
	%.nqc "sourcecode.nqc"
	%.o "compiled.mach-o.objfile"
	%.octest "wrapper.cfbundle"
	%.p "sourcecode.pascal"
	%.pas "sourcecode.pascal"
	%.pbfilespec "text.plist.pbfilespec"
	%.pblangspec "text.plist.pblangspec"
	%.pbxproj "text.pbxproject"
	%.pch "sourcecode.c.h"
	%.pch++ "sourcecode.cpp.h"
	%.pct "image.pict"
	%.pdf "image.pdf"
	%.perl "text.script.perl"
	%.php "text.script.php"
	%.php3 "text.script.php"
	%.php4 "text.script.php"
	%.phtml "text.script.php"
	%.pict "image.pict"
	%.pkg "wrapper.installer-pkg"
	%.pl "text.script.perl"
	%.playground "file.playground"
	%.plist "text.plist"
	%.pluginkit "wrapper.app-extension"
	%.pm "text.script.perl"
	%.png "image.png"
	%.pp "sourcecode.pascal"
	%.ppob "archive.ppob"
	%.proto "sourcecode.protobuf"
	%.py "text.script.python"
	%.qtz "video.quartz-composer"
	%.r "sourcecode.rez"
	%.rb "text.script.ruby"
	%.rbw "text.script.ruby"
	%.rcproject "file.rcproject"
	%.rcx "compiled.rcx"
	%.rez "sourcecode.rez"
	%.rhtml "text.html.other"
	%.rsrc "archive.rsrc"
	%.rtf "text.rtf"
	%.rtfd "wrapper.rtfd"
	%.s "sourcecode.asm"
	%.scnassets "wrapper.scnassets"
	%.scncache "wrapper.scncache"
	%.scnp "file.scp"
	%.scriptSuite "text.plist.scriptSuite"
	%.scriptTerminology "text.plist.scriptTerminology"
	%.sh "text.script.sh"
	%.shtml "text.html.other"
	%.sit "archive.stuffit"
	%.sks "file.sks"
	%.skybox "file.skybox"
	%.sqlite "file"
	%.storyboard "file.storyboard"
	%.storyboardc "wrapper.storyboardc"
	%.strings "text.plist.strings"
	%.stringsdict "text.plist.stringsdict"
	%.swift "sourcecode.swift"
	%.systemextension "wrapper.system-extension"
	%.tar "archive.tar"
	%.tbd "sourcecode.text-based-dylib-definition"
	%.tcc "sourcecode.cpp.cpp"
	%.text "net.daringfireball.markdown"
	%.tif "image.tiff"
	%.tiff "image.tiff"
	%.ttf "file"
	%.txt "text"
	%.uicatalog "file.uicatalog"
	%.usdz "file.usdz"
	%.vert "sourcecode.glsl"
	%.vertex "sourcecode.glsl"
	%.view "archive.rsrc"
	%.vs "sourcecode.glsl"
	%.vsh "sourcecode.glsl"
	%.war "archive.war"
	%.wav "audio.wav"
	%.worksheet "text.script.worksheet"
	%.xcassets "folder.assetcatalog"
	%.xcbuildrules "text.plist.xcbuildrules"
	%.xcclassmodel "wrapper.xcclassmodel"
	%.xcconfig "text.xcconfig"
	%.xcdatamodel "wrapper.xcdatamodel"
	%.xcdatamodeld "wrapper.xcdatamodeld"
	%.xcfilelist "text.xcfilelist"
	%.xcframework "wrapper.xcframework"
	%.xclangspec "text.plist.xclangspec"
	%.xcmappingmodel "wrapper.xcmappingmodel"
	%.xcode "wrapper.pb-project"
	%.xcodeproj "wrapper.pb-project"
	%.xconf "text.xml"
	%.xcplaygroundpage "file.xcplaygroundpage"
	%.xcspec "text.plist.xcspec"
	%.xcstickers "folder.stickers"
	%.xcsynspec "text.plist.xcsynspec"
	%.xctarget "wrapper.pb-target"
	%.xctest "wrapper.cfbundle"
	%.xctxtmacro "text.plist.xctxtmacro"
	%.xcworkspace "wrapper.workspace"
	%.xhtml "text.xml"
	%.xib "file.xib"
	%.xmap "text.xml"
	%.xml "text.xml"
	%.xpc "wrapper.xpc-service"
	%.xsl "text.xml"
	%.xslt "text.xml"
	%.xsp "text.xml"
	%.y "sourcecode.yacc"
	%.yaml "text.yaml"
	%.ym "sourcecode.yacc"
	%.yml "text.yaml"
	%.ymm "sourcecode.yacc"
	%.yp "sourcecode.yacc"
	%.ypp "sourcecode.yacc"
	%.yxx "sourcecode.yacc"
	%.zip "archive.zip"
)
