Rebol [
	Title:  "Siskin Builder - Visual Studio project generator"
	name: msvc
	type: module
]

siskin: none

;-- variables:
PLATFORM:   
PLATFORM-X:
PROJECT-TYPE-GUID:
PROJECT-GUID:
PROJECT-NAME:
SUBSYSTEM:
LIBRARY-PATH:
INCLUDE-PATH:
ADDITIONAL-DEPENDENCIES:
CONFIGURATION-TYPE:
PROJECT-FILES:
PROJECT-DEFINES:
PRE-BUILD-EVENT:
POST-BUILD-EVENT:
RESOURCE-ITEM:
MSVC-PATH:
TOOLSET-VERSION:
STACK-SIZE:
none


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

to-windows-file: either system/platform = 'windows [
	:to-local-file
][
	func[path [file! string!]][
		path: to-local-file path
		replace/all path #"/" #"\"
		if #"\" = path/1 [
			insert next remove path #":"
		]
		path
	]
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


make-guid: func[/from name /local id] [
	id: enbase (checksum/with to-binary form any [name now/precise] 'md5 "Siskin") 16
	insert at id 9 "-"
	insert at id 14 "-"
	insert at id 19 "-"
	insert at id 24 "-"
	id
]
prepare-dir: func[dir [file! string!]][
	clean-path siskin/prepare-dir 'MSVC dir
]
write-file: func[file [file! block!] data][
	if block? file [file: rejoin file]
	try/except [
		write file data
		sys/log/more 'SISKIN ["MSVC Generated:^[[33m" to-local-file file]
	][	sys/log/error 'SISKIN system/state/last-error ]
	file
]

escaped-args: func[args [block! string! none!]][
	if none?  args [return ""]
	args: either block? args [reform args][copy args]
	; not nice and optimal, but I have no time now...
	replace/all args #"^^" "^^^^"
	replace/all args #"^"" {^^"}
	replace/all args #"^/" "^^^/"
	replace/all args #"^M" ""
	ajoin [{ --args "} args {"}]
]

form-pre-post-build: func[
	code [block!]
	/local val args tmp siskin result
][
	result: make string! 1024
	append result "^/^-  <Command>cd .."
	siskin: system/modules/siskin
	parse code [any[
		'do [
			set val file! set args [block! | string! | none] (
				;?? args
				if string? args [siskin/expand-env args]
				append result rejoin [
					crlf to-local-file system/options/boot ;to-local-file siskin/expand-env %$REBOL3
					" --script " to-local-file val
					escaped-args args
				]
			)
		]
		|
		'Rebol2 set val string! (
			if none? siskin/config/Rebol2 [ siskin/config/Rebol2: %rebol2]
			;if #"/" <> config/Rebol2/1 [insert config/Rebol2 root-dir]
			replace/all val "#[LIB]" siskin/lib-extension
			replace/all val "#[EXE]" siskin/exe-extension
			append result rejoin [
				"^-  <Command>"
				to-local-file config/Rebol2 "-csw" trim/lines val
				"^-  </Command>^/"
			]
		)
		| 'python set val file! (
			append result rejoin [
				"^-  <Command>"
				to-local-file any [config/python %python] #" " to-local-file val
				"^-  </Command>^/"
			]
		)
		| 'call set val [file!]  (
			if #"/" <> first val [insert val what-dir]
			append result rejoin [
				"^-  <Command>"
				"CALL " to-local-file val
				"^-  </Command>^/"
			]
		)
		| 'cmd set dir [file! | none!] set val string! (
			append result "^-  <Command>"
			if dir [
				append result rejoin ["CD " to-windows-file pushd dir " & "]
			]
			foreach line split val lf [
				line: trim/head/tail line
				unless empty? line [
					append result rejoin [line " & "]
				]
			]
			if dir [
				append result rejoin ["CD " to-windows-file popd]
			]
			append result "^-  </Command>^/"
		)
		| 'pushd set val file! (
			append result rejoin [
				"CD " to-windows-file pushd dir
			]
		)
		| 'popd (
			append result rejoin [
				"^/CD" to-windows-file popd
			]
		)
		|
		copy val 2 skip (
			siskin/print-warn ["!!! Ignoring setting: " mold/flat val]
			;ask "Press enter to continue."
		)
	]]
	append result "^/^-  </Command>^/^-"
	result
]

vswhere: function[][
	vswhere: siskin/locate-tool 'vswhere none
	;?? vswhere
	versions: copy []
	if exists? vswhere [
		output: make string! 1000
		try/except [
			call/wait/shell/output to-local-file vswhere output
			;probe output
			append output "^M^/"
			parse output [
				thru "^M^/^M^/"
				any [copy ver: thru "^M^/^M^/" (append versions construct ver)]
			]
			;probe construct output
		][
			siskin/print-error ["Failed to call:" as-red vswhere]
			siskin/print-error system/state/last-error
		]
	]
	forall versions [
		either all [
			p: select versions/1 'installationPath
			v: select versions/1 'installationVersion
		][ siskin/print-more ["MSVC available:^[[0;32m" pad v 16 "at" p]
		][ remove versions/1 ]
	]
	; use the latest version if possible..
	try [sort/compare versions func[a b][a/installationVersion > b/installationVersion]]
	versions
]

make-project: func[
	spec   [map!]
	;dir    [file! string!]
	/guid
		id [string!] "Visual studio project type GUID"
	/local
		name tmp output dir dir-vs dir-bin defines includes rel-file
		filters items ver lib-paths
][
	unless siskin [siskin: system/modules/siskin]
	output: make string! 30000

	; check for available VS versions
	ver: vswhere
	MSVC-PATH: any [
		all [object? first ver select ver/1 'installationPath]
		"c:\Program Files\Microsoft Visual Studio\2022\Community"
		"c:\Program Files (x86)\Microsoft Visual Studio\2017\Community"
	]

	if not exists? to-rebol-file MSVC-PATH [
		siskin/print-error "MSVC path not found!"
		quit/return 2
	]
	siskin/print-info ["MSVC path:" as-green MSVC-PATH]

	TOOLSET-VERSION: any [
		all [find MSVC-PATH "\2019\" "v142"]
		all [find MSVC-PATH "\2017\" "v141"]
		all [find MSVC-PATH "\2015\" "v140"]
		"$(DefaultPlatformToolset)"
	]
	siskin/print-info ["MSVC platform toolset:" as-green TOOLSET-VERSION]

	dir-bin: prepare-dir any [spec/out-dir %.]
	dir-vs:  prepare-dir %msvc

	if name: spec/name [
		set [dir name] split-path name
		if all [dir-bin dir <> %./][append dir-bin dir]
	]

	STACK-SIZE: any [spec/stack-size ""]
	
	try [
		; this part is a little bit hackish!
		; it's for being able to use specification done for not MSVC compiler
		replace name tmp: join "-" spec/compiler "-vs"
		if block? spec/shared [
			foreach file spec/shared [
				if file? file [
					replace file tmp "-vs"
					replace file %.dll %.lib ; not much safe, but good for now
				]
			]
		]
		spec/compiler: 'cl
		spec/name: name
	]
	siskin/add-env "NEST_SPEC" save dir-vs/(join name %.reb) spec 

	;-- compose .sln file                                                       

	PROJECT-GUID: make-guid/from name
	PROJECT-NAME: name
	PROJECT-TYPE-GUID: any [id make-guid/from "Siskin Visual Studio Project"]
	PLATFORM:   either spec/arch = 'x64 ["x64"]["Win32"]
	PLATFORM-X: either spec/arch = 'x64 ["x64"]["x86"]
	SUBSYSTEM:  either find spec/lflags "-mwindows" ["Windows"]["Console"]

	reword/escape/into sln self [#"#" #"#"] output
	write-file [dir-vs name %.sln] output

	;-- collect ADDITIONAL-DEPENDENCIES                                         
	lib-paths: copy [] 
	clear output
	foreach lib join spec/libraries spec/shared [
		either dir? lib [
			append lib-paths lib
		][
		lib: split-path lib
			append lib-paths lib/1
			if lib/2 [
				unless parse lib/2 [thru ".lib" end][
					append lib/2 ".lib"
				]
				append append output lib/2
				either parse lib/2 [thru ".lib" end][";"][".lib;"]
			]
		]
	]
	ADDITIONAL-DEPENDENCIES: copy output
	LIBRARY-PATH: copy ""
	foreach path unique lib-paths [
		if #"/" <> first path [insert path %../] 
		append append LIBRARY-PATH to-local-file path #";"
	]

	;-- collect RESOURCE-ITEM                                                   
	RESOURCE-ITEM: either file? spec/resource [
		if #"/" <> first spec/resource [ insert spec/resource spec/root ]
		rejoin [
		{  <ItemGroup>^/}
		{    <ResourceCompile Include="}
		to-windows-file get-relative-path spec/resource dir-vs {" />^/}
		{  </ItemGroup>}
		]
	][""]

	;-- collect PROJECT-FILES                                                   
	clear output
	filters: copy [] ; used later
	items:   copy []
	foreach file join spec/files spec/assembly [
		;file: siskin/get-file-with-extensions file [%.c %.cpp %.cc %.m %.S %.s %.sx]
		rel-file: get-relative-path file dir-vs
		dir: first split-path rel-file
		parse dir [remove any %../]    ; get directory name without .. (used in gui as names of folders)
		take/last dir                  ; undirize
		append filters dir             ; remember current name
		repend items [rel-file dir]    ; and store link between file and this dir name
		;include all directories in the path..
		while [not find [%./ %../] dir: first split-path dir][
			if #"/" = last dir [take/last dir]
			append filters dir
		]
		
		if file
		append output rejoin [
			{    <ClCompile Include="} to-windows-file rel-file {" />^/}
		] 
	]
	PROJECT-FILES: copy output

	;-- collect PROJECT-DEFINES                                                 
	clear output
	foreach def any [spec/defines []] [
		append output rejoin [def #";"]
	]
	replace/all output {\"} {"} ;@@ temp solution!!! 
	PROJECT-DEFINES: copy output

	;-- collect INCLUDE-PATH                                                    
	clear output
	foreach inc spec/includes [
		inc: clean-path/only inc
		if #"/" <> first inc [ insert inc %../ ]
		append append output to-local-file inc #";"
	]
	INCLUDE-PATH: copy output

	;-- collect CONFIGURATION-TYPE                                              
	CONFIGURATION-TYPE: either any [
		find spec/lflags "-shared "
	][
		either find spec/lflags "-archive-only " ["StaticLibrary"]["DynamicLibrary"]
	][
		"Application"
	]

	;-- and...
	PRE-BUILD-EVENT: form-pre-post-build spec/pre-build
	;@@ TODO: post actions..
	POST-BUILD-EVENT: copy "" ;form-pre-post-build spec/post-build

;	siskin/print-info [as-green "MSVC Name:  " as-yellow name]
;	siskin/print-info [as-green "MSVC Bin:   " as-yellow dir-bin]
;	siskin/print-info [as-green "MSVC Libs:  " as-yellow AdditionalDependencies]

	clear output
	reword/escape/into vcxproj self [#"#" #"#"] output
	write-file [dir-vs name %.vcxproj] output

	filters: unique filters
	new-line/all filters true
	;probe sort filters

	vcxproj.filters: {<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup>}

	foreach filter filters [ ;first one is always %./ which we don't need
		filter: to-windows-file filter
		append vcxproj.filters rejoin [{
	<Filter Include="} filter {">
	  <UniqueIdentifier>^{} make-guid/from filter {^}</UniqueIdentifier>
	</Filter>}]
	]

	append vcxproj.filters {^/  </ItemGroup>^/  <ItemGroup>}
	foreach [item dir] items [
		;print [mold item mold dir]
		append vcxproj.filters rejoin [{^/    <ClCompile Include="} to-windows-file item {">}]
		if all [dir <> %. find filters dir] [
			append vcxproj.filters rejoin [{<Filter>} to-windows-file dir {</Filter>}]
		]
		append vcxproj.filters {</ClCompile>}
	]

	append vcxproj.filters {^/  </ItemGroup>^/</Project>}


	write-file [dir-vs name %.vcxproj.filters] vcxproj.filters


	clear output
	reword/escape/into build-vs-release self [#"#" #"#"] output
	output: write-file [dir-vs %build- name %-release.bat] output

	siskin/print-info {^[[1;35mMSVC Done^[[m}
	output
]

sln: {Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio 15
VisualStudioVersion = 15.0.26730.12
MinimumVisualStudioVersion = 10.0.40219.1
Project("{#PROJECT-TYPE-GUID#}") = "#PROJECT-NAME#", "#PROJECT-NAME#.vcxproj", "{#PROJECT-GUID#}"
EndProject
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Release|#PLATFORM-X# = Release|#PLATFORM-X#
		Debug|#PLATFORM-X# = Debug|#PLATFORM-X#
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution
		{#PROJECT-GUID#}.Release|#PLATFORM-X#.ActiveCfg = Release|#PLATFORM#
		{#PROJECT-GUID#}.Release|#PLATFORM-X#.Build.0 = Release|#PLATFORM#
		{#PROJECT-GUID#}.Debug|#PLATFORM-X#.ActiveCfg = Debug|#PLATFORM#
		{#PROJECT-GUID#}.Debug|#PLATFORM-X#.Build.0 = Debug|#PLATFORM#
	EndGlobalSection
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
EndGlobal
}

vcxproj: {<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup Label="ProjectConfigurations">
	<ProjectConfiguration Include="Debug|#PLATFORM#">
	  <Configuration>Debug</Configuration>
	  <Platform>#PLATFORM#</Platform>
	</ProjectConfiguration>
	<ProjectConfiguration Include="Release|#PLATFORM#">
	  <Configuration>Release</Configuration>
	  <Platform>#PLATFORM#</Platform>
	</ProjectConfiguration>
  </ItemGroup>
  <PropertyGroup Label="Globals">
	<VCProjectVersion>15.0</VCProjectVersion>
	<ProjectGuid>{#PROJECT-GUID#}</ProjectGuid>
	<ProjectName>#PROJECT-NAME#</ProjectName>
	<IntDir>$(Configuration)-$(Platform)\tmp\$(ProjectName).dir\</IntDir>
    <OutDir>$(SolutionDir)$(Configuration)-$(Platform)\</OutDir>
  </PropertyGroup>
  <Import Project="$(VCTargetsPath)\Microsoft.Cpp.Default.props" />

  <PropertyGroup Condition="'$(WindowsTargetPlatformVersion)'==''">
    <!-- Latest Target Version property -->
    <LatestTargetPlatformVersion>$([Microsoft.Build.Utilities.ToolLocationHelper]::GetLatestSDKTargetPlatformVersion('Windows', '10.0'))</LatestTargetPlatformVersion>
    <WindowsTargetPlatformVersion Condition="'$(WindowsTargetPlatformVersion)' == ''">$(LatestTargetPlatformVersion)</WindowsTargetPlatformVersion>
    <TargetPlatformVersion>$(WindowsTargetPlatformVersion)</TargetPlatformVersion>
  </PropertyGroup>

  <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='Debug|#PLATFORM#'" Label="Configuration">
	<ConfigurationType>#CONFIGURATION-TYPE#</ConfigurationType>
	<UseDebugLibraries>true</UseDebugLibraries>
	<PlatformToolset>#TOOLSET-VERSION#</PlatformToolset>
	<CharacterSet>Unicode</CharacterSet>
  </PropertyGroup>
  <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='Release|#PLATFORM#'" Label="Configuration">
	<ConfigurationType>#CONFIGURATION-TYPE#</ConfigurationType>
	<UseDebugLibraries>false</UseDebugLibraries>
	<PlatformToolset>#TOOLSET-VERSION#</PlatformToolset>
	<WholeProgramOptimization>false</WholeProgramOptimization>
	<CharacterSet>Unicode</CharacterSet>
  </PropertyGroup>

  <Import Project="$(VCTargetsPath)\Microsoft.Cpp.props" />
  <ImportGroup Label="ExtensionSettings">
  </ImportGroup>
  <ImportGroup Label="Shared">
  </ImportGroup>
  <ImportGroup Label="PropertySheets" Condition="'$(Configuration)|$(Platform)'=='Debug|#PLATFORM#'">
	<Import Project="$(UserRootDir)\Microsoft.Cpp.$(Platform).user.props" Condition="exists('$(UserRootDir)\Microsoft.Cpp.$(Platform).user.props')" Label="LocalAppDataPlatform" />
  </ImportGroup>
  <ImportGroup Label="PropertySheets" Condition="'$(Configuration)|$(Platform)'=='Release|#PLATFORM#'">
	<Import Project="$(UserRootDir)\Microsoft.Cpp.$(Platform).user.props" Condition="exists('$(UserRootDir)\Microsoft.Cpp.$(Platform).user.props')" Label="LocalAppDataPlatform" />
  </ImportGroup>
  <PropertyGroup Label="UserMacros" />
  <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='Debug|#PLATFORM#'">
	<IncludePath>#INCLUDE-PATH#$(IncludePath)</IncludePath>
	<LibraryPath>#LIBRARY-PATH#$(LibraryPath);$(SolutionDir)$(Configuration)-$(Platform)\</LibraryPath>
	<SourcePath>$(SourcePath)</SourcePath>
  </PropertyGroup>
  <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='Release|#PLATFORM#'">
	<IncludePath>#INCLUDE-PATH#;$(IncludePath)</IncludePath>
	<LibraryPath>#LIBRARY-PATH#$(LibraryPath);$(SolutionDir)$(Configuration)-$(Platform)\</LibraryPath>
	<SourcePath>$(SourcePath)</SourcePath>
  </PropertyGroup>

  <ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='Debug|#PLATFORM#'">
	<ClCompile>
	  <WarningLevel>Level3</WarningLevel>
	  <Optimization>Disabled</Optimization>
	  <SDLCheck>true</SDLCheck>
      <MultiProcessorCompilation>true</MultiProcessorCompilation>
	  <PreprocessorDefinitions>#PROJECT-DEFINES#%(PreprocessorDefinitions)</PreprocessorDefinitions>
	</ClCompile>
	<Link>
	  <AdditionalDependencies>#ADDITIONAL-DEPENDENCIES#%(AdditionalDependencies)</AdditionalDependencies>
	  <SubSystem>#SUBSYSTEM#</SubSystem>
	  <StackReserveSize>#STACK-SIZE#</StackReserveSize>
	</Link>
	<PreBuildEvent>#PRE-BUILD-EVENT#</PreBuildEvent>
	<PostBuildEvent>#POST-BUILD-EVENT#</PostBuildEvent>
  </ItemDefinitionGroup>

  <ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='Release|#PLATFORM#'">
	<ClCompile>
	  <WarningLevel>Level3</WarningLevel>
	  <Optimization>Full</Optimization>
	  <FunctionLevelLinking>true</FunctionLevelLinking>
	  <IntrinsicFunctions>false</IntrinsicFunctions>
	  <SDLCheck>true</SDLCheck>
      <MultiProcessorCompilation>true</MultiProcessorCompilation>
      <DebugInformationFormat>None</DebugInformationFormat>
	  <PreprocessorDefinitions>#PROJECT-DEFINES#%(PreprocessorDefinitions)</PreprocessorDefinitions>
      <WholeProgramOptimization>false</WholeProgramOptimization>
	</ClCompile>
	<Link>
	  <EnableCOMDATFolding>true</EnableCOMDATFolding>
	  <OptimizeReferences>true</OptimizeReferences>
	  <AdditionalDependencies>#ADDITIONAL-DEPENDENCIES#%(AdditionalDependencies)</AdditionalDependencies>
	  <SubSystem>#SUBSYSTEM#</SubSystem>
	  <StackReserveSize>#STACK-SIZE#</StackReserveSize>
	</Link>
	<PreBuildEvent>#PRE-BUILD-EVENT#</PreBuildEvent>
	<PostBuildEvent>#POST-BUILD-EVENT#</PostBuildEvent>
  </ItemDefinitionGroup>
  <ItemGroup>
#PROJECT-FILES#
  </ItemGroup>
#RESOURCE-ITEM#
  <Import Project="$(VCTargetsPath)\Microsoft.Cpp.targets" />
  <ImportGroup Label="ExtensionTargets">
  </ImportGroup>
</Project>}

vcxproj.filters: {<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup>
	<Filter Include="Source Files">
	  <UniqueIdentifier>{4FC737F1-C7A5-4376-A066-2A32D752A2FF}</UniqueIdentifier>
	  <Extensions>cpp;c;cc;cxx;def;odl;idl;hpj;bat;asm;asmx</Extensions>
	</Filter>
	<Filter Include="Header Files">
	  <UniqueIdentifier>{93995380-89BD-4b04-88EB-625FBE52EBFB}</UniqueIdentifier>
	  <Extensions>h;hh;hpp;hxx;hm;inl;inc;xsd</Extensions>
	</Filter>
	<Filter Include="Resource Files">
	  <UniqueIdentifier>{67DA6AB6-F800-4c08-8B7A-83BB121AAD01}</UniqueIdentifier>
	  <Extensions>rc;ico;cur;bmp;dlg;rc2;rct;bin;rgs;gif;jpg;jpeg;jpe;resx;tiff;tif;png;wav;mfcribbon-ms</Extensions>
	</Filter>
  </ItemGroup>
</Project>}

build-vs-release: {@echo off
call "#MSVC-PATH#\VC\Auxiliary\Build\vcvarsall.bat" #PLATFORM-X#
cd %~dp0
msbuild "#PROJECT-NAME#.sln" /p:Configuration=Release /p:Platform="#PLATFORM-X#"
cd %~dp0
}

;vs/make-project "Siskin-SDL" %Projects/Siskin-SDL/