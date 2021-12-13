Rebol [
	Title:  "Siskin Builder - core"
	Type:    module
	Name:    siskin
	Version: 0.4.1
	Author: "Oldes"
	;Needs:  prebol
	exports: [
		windows?
		macOS?
		linux?
		posix?
	]
]
;? system
banner: next rejoin [{
^[[0;33m═╗
^[[0;33m ║^[[1;31m    .-.
^[[0;33m ║^[[1;31m   /'v'\   ^[[0;33mSISKIN-Framework Builder 0.4.1 Rebol } rebol/version {
^[[0;33m ║^[[1;31m  (/^[[0;31muOu^[[1;31m\)  ^[[0;33mhttps://github.com/Siskin-framework/Builder/
^[[0;33m ╚════^[[1;31m"^[[0;33m═^[[1;31m"^[[0;33m═══════════════════════════════════════════════════════════════════════^[[m}]

       import 'prebol
msvc:  import 'msvc
xcode: import 'xcode
 msvc/siskin:
xcode/siskin:  self

debug?: off

append system/options/log [siskin: 1]

commands-to-args: #(
	t      "-test"
	test   "-test"
	v      "-v"
	vv     "-vv"
	vvv    "-vvv"
	d      "-debug"
	debug  "-debug"
	r      "-run"
	run    "-run"
	msvc   "-msvc"
	xcode  "-xcode"
	u      "-update"
	update "-update"
	c      "-clean"
	clean  "-clean"
)
short-commands: #(
	"-t"   "-test"
	"-d"   "-debug"
	"-r"   "-run"
	"-u"   "-update"
	"-c"   "-clean"
	"-q"   "-quiet"
)

;- environment -

nest-context: object [
	root-dir: none
	template: make map! reduce/only [ ;@@ the reduce/only is required when the source is embedded in exe!
		name:       none
		compiler:   none
		arch:       none
		root:       none
		temp:       none
		sign:       none
		output:     none ;%bin/
		source:     %""
		objects:    none
		gits:       []
		files:      []
		clean:      []
		assembly:   []
		libraries:  []
		shared:     []
		frameworks: []
		defines:    []
		includes:   []
		resource:   none
		rflags:     ""   ; resource options
		cflags:     ""
		lflags:     ""
		stack-size: none
		cc:         none
		ccpp:       none
		pre-build:  []   ; native commands executed before building (in msvc PreBuildEvent)
		post-build: []   ; not used yet
		actions:    []
		eggs:       []
	]

	nest-root:    none
	nest-spec:    none
	rebuild?:     false ; if force compilation of all files (even if not modified)
	no-eval?:     false
	clang?:       false
	run-result?:  false
	update?:      false
	CI?:          false
	target-names: copy []
	interactive?: false

	force-compiler: none

	android-sdk:  none
	android-ndk:  none

	timestamp:    none
	result:       none
	out-file:     none

	defaults: make map! [
		output: %build/
		temp:   %tmp/
	]
	s: p: val: valid: none
]

dirs-stack: copy []
chars_alpha:   charset [#"a" - #"z" #"A" - #"Z"]
chars_numbers: charset [#"0" - #"9"]
chars-file:    charset [#"a" - #"z" #"A" - #"Z" #"0" - #"9" #"-" #"_" ] ;#"."

cpp-extensions: [%.cc %.cpp %.cxx %.c++]

do-args: closure/with [
	"Main Sisking input processor"
][
	system/options/quiet: false
	;? system/options

	;@@ this is temporary hack before finding a better way how to handle raw args!
	if "--script" = first system/options/args [
		; I've added this option to be able preprocess builds using Rebol scripts
		; without need to download Rebol as an additional utility (in GitHub actions)
		script: to-rebol-file take remove system/options/args
		if #"/" <> first script [ insert script system/options/path ]
		if "--args" = first system/options/args [take system/options/args] ;ignored
		;? script
		;? system/options/args
		print-debug ["Executing script:" as-red to-local-file script]
		print-debug ["..with arguments:" as-red form system/options/args]
		system/options/quiet: true
		try/except [ do/args script system/options/args ][
			print-error system/state/last-error
			quit/return 1 ;@@ TODO: choose which error number to use
		]
		quit
	]

	print banner

	either system/product = 'Siskin [
		; using prebuild Siskin utility
		args: system/options/args
	][
		; using Rebol with Siskin script needs special handling!
		if all [
			none? system/script/args
			block? system/options/args
		] [
			;@@ woraround for running nest file associated with Siskin utility on Windows
			try [system/options/args/1: mold to-rebol-file system/options/args/1]
			system/script/args: reform system/options/args
		]
		args: any [system/script/args system/options/args]
	]

	change-dir root-dir: system/options/path

	if debug? [?? args]
	if all [string? args empty? args][args: none]
	either all [args not empty? args][
		if string? args [
			try/except [args: load/all args][
				print-error ["Failed to parse args:" as-red args]
				exit
			]
		] 
		unless block? args [args: reduce [args]]
		project: to file! take args
		parts: split-path project
		unless any [
			'file = exists? nest: project
			'file = exists? nest: join project %.nest
			'file = exists? nest: join project %/.nest
			'file = exists? nest: rejoin [%./ project %/ parts/2 %.nest ]
			'file = exists? nest: rejoin [%./tree/ project %.nest]
			'file = exists? nest: rejoin [%./tree/ project %/ parts/2 %.nest]
			'file = exists? nest: rejoin [%./projects/ project %.nest]
			'file = exists? nest: rejoin [%./projects/ project %/ parts/2 %.nest]
		][
			print-error ["Nest not found:" as-red project]
			exit
		]

		;?? nest
		try/except [ do-nest nest args ][ print-error none ]
	][
		; Script may be evaluated from inside Siskin utility or as a Rebol script! 
		print ajoin [
			" ^[[33mUsage: ^[[1;32m"
			second split-path system/options/boot
			either system/product = 'Siskin [""][" siskin.r3 "]
			" ^[[1;33mnest-name ^[[0;33m[commands]^[[m"
		] 
		exit
	]
] :nest-context

do-strip: closure/with [spec [map!] file [file!]][
	;-- strip resulted binary
	any [
		all [file? spec/strip       exists? strip: spec/strip]
		all [spec/compiler = 'clang exists? strip: locate-tool 'llvm-strip none]
		strip: locate-tool 'strip none
	]
	either exists? strip [
		print-info ["Stripping binary from:" as-yellow size? file as-cyan "bytes"]
		eval-cmd/no-quit/v [to-local-file strip file either macOS? [""]["-s "]]
	][
		print-error "STRIP command not found!"
	]
] :nest-context

do-upx: closure/with [file [file!]][
	upx: locate-tool 'upx none
	unless any [
		exists? upx
		exists? expand-env copy upx
	][
		print-error "UPX command not found!"
		unless windows? [exit]
		try/except [
			print-info "Downloading UPX"
			bin: read https://github.com/upx/upx/releases/download/v3.96/upx-3.96-win32.zip
			if #{00AD82F88046686070C93993A47BE46D32684407} <> checksum bin 'sha1 [
				print-error "UPX binary checksum failed!"
				exit
			]
			exe: codecs/zip/decode/only bin [%upx-3.96-win32/upx.exe]
			upx: write root-dir/upx.exe exe/2/2
			add-env-path root-dir
		] [	print-error system/state/last-error exit ]
	]

	either any [
		exists? upx
		exists? expand-env copy upx
	][
		set-env "UPX" none ; upx tool is using it for some unknown reason and don't like our use
		eval-cmd/no-quit/vv [upx file]
	][
		print-error ["UPX command not found! (" mold upx ")"]
	]
] :nest-context

do-rebol2: closure/with [code [string! file!]][
	add-env-path root-dir
	rebol2: any [
		get-env "REBOL2"
		locate-tool 'rebol2 none
	]
	if 'file <> exists? rebol2 [
		print-error "REBOL2 not found!"
		switch system/platform [
			windows [
				url: http://www.rebol.com/downloads/v278/rebol-view-278-3-1.exe
				crc: #{1DEF65DDE53AB24C122DA6C76646A36D7D910790}
			]
			linux [
				url: http://www.rebol.com/downloads/v278/rebol-view-278-4-3.tar.gz
				crc: #{F078EF80744DF217AAB5CD60E75B5A5D2690F396}
			]
			macos
			Macintosh [
				url: http://www.rebol.com/downloads/v278/rebol-view-278-2-5.tar.gz
				crc: #{E45DEFC8155D157090588F85B521A40FA7A30E48}
			]
		]
		unless url [
			print-error ["REBOL2 not available for" system/platform "platform!"]
			exit
		]
		try/except [
			print-info "Downloading REBOL2"
			bin: read/binary url
			if crc <> checksum bin 'sha1 [
				print-error "REBOL2 binary checksum failed!"
				exit
			]
			either Windows? [
				rebol2: write root-dir/rebol2.exe bin
			][
				; file is *.tar.gz
				tar: decode 'tar decompress bin 'gzip
				rebol2: write root-dir/rebol2 tar/6/1
				eval-cmd/v ["chmod +x" root-dir/rebol2]
			]
			add-env "REBOL2" to-local-file rebol2
		] [	print-error system/state/last-error exit ]
	]
	;It looks that Rebol2 does not support output redirection, so use temp file...
	eval-cmd/log/v [rebol2 "-csw" trim/lines code] %log.txt

] :nest-context

add-pre-build: func[dest cmd [block!]][
	cmd: new-line/all reduce cmd false
	append dest/pre-build new-line cmd true
]
add-action: func[
	dest
	name [set-word!]
	spec [block!]
	code [block!]
	/local title
][
	parse spec [
		opt set title string!
		;TODO: args
	]
	append/only append dest/actions name compose/only [
		title: (title)
		code: (preprocess code)
	]
]

parse-nest: closure/with [
	nest [file! block!]
	dest [map! block! none!]
][
	;if file? nest [print-info ["Parsing nest:" as-green nest]]

	spec: preprocess nest

	case [
		block? dest [dest: to map! dest]
		none?  dest [dest: copy/deep template]
	]

	src-dir: any [dest/source %""]
	truthy: ['true  | 'on  | quote 1]
	falsy:  ['false | 'off | 'none | quote 0]

	reserved-words: [
		ar arch assembly cc cflags clean compiler define defines file files
		flags git github include includes lflags libraries library libs
		name needs optimize out-dir output shared source stack-size strip
		eggs temp temp-dir tools upx framework frameworks info
	]

	get-spec-block-value: func[spec [map!] what /local block][
		unless block: spec/:what [block: spec/:what: copy []]
		unless block? block [
			print-error [
				"Unexpected type of:" as-red form what
				as-purple "Expected block, but have got:" as-red type? block
			]
			return none
		]
		block
	]

	add-files: func[spec [map!] what [word!] files /local block file][
		files: either block? files [preprocess files][to block! files]
		unless block: get-spec-block-value spec what [exit]
		forall files [
			file: files/1
			switch/default type?/word file [
				file! [
					if file <> #"/" [file: join src-dir file]
					append block clean-path file
				]
				get-word! [
					add-files spec what any [
						select dest file
						select nest-spec file
					]
				]
			][
				print-warn ["Unexpected file input:" as-red mold file]
			]
		]
	]
	add-to: func[spec [map!] what [word!] values /local block][
		values: either block? values [preprocess values][to block! values]
		unless block: get-spec-block-value spec what [exit]
		forall values [
			switch/default type?/word values/1 [
				word! string! ref! [
					append block values/1
				]
				get-word! [
					add-to spec what any [
						select dest values/1
						select nest-spec values/1
					]
				]
			][
				print-warn ["Unexpected `add-to` input:" as-red mold values/1]
			]
		]
	]

	opt-get-word: [opt [p: get-word! (
		change/only p select dest first p
	) :p]]

	logic: [
		       set val: logic!
		| truthy ( val: true  )
		| falsy  ( val: false )
	]

	parse copy spec [any [
		;x: (probe first x)
		  quote name:       set val:  any-string!      ( dest/name: to string! val )
		| quote tools:      set val:  any-string!      ( tools: expand-env val ) ; stored in nest-context!
		| quote git:        set val: [url! | block!]   ( append dest/gits val )
		| quote github:     set val: [path! | file! | ref!] (
			if ref? val [val: join %Siskin-framework/ val]
			append dest/gits either CI? [
				join https://github.com/ [val %.git]
			][	to url! rejoin [git@github.com #":" val %.git] ]
		) opt [set val: [refinement!] (append dest/gits val)] ;optional branch
		| quote eggs: [opt 'only (clear dest/eggs) ] set val: block! (
			append dest/eggs preprocess val
		)
		| quote stack-size: set val:  integer!            ( dest/stack-size: val )
		| quote arch:       set val:  word!               ( dest/arch:       val )
		| quote root:       set val:  file!               ( dest/root: clean-path val )
		| quote sign:      [set val: string! | logic]     ( dest/sign:       val )
		|[quote temp-dir: | quote temp:  ] set val: file! ( dest/temp:       val )
		|[quote out-dir:  | quote output:] set val: file! ( dest/output:     val )
		|[quote compiler: | quote cc:    ] [
			  set val: any-string! ( dest/cc: expand-env to-rebol-file val )
			| falsy                ( dest/compiler: none)
			| set val: word!       ( dest/compiler: val)
		]
		| quote ar: set val: any-string! ( dest/ar: expand-env to-rebol-file val )
		| quote strip: [
			  set val: any-string! ( dest/strip: to file! val )
			| logic                ( dest/strip: val )
		]
		| quote upx: [
			  set val: any-string! ( dest/upx: to file! val )
			| logic                ( dest/upx: val )
		]
		| quote source: set val: any-string! ( 
			src-dir: to file! val
			if not empty? src-dir [
				src-dir: dirize expand-env copy src-dir
			]
			dest/source: src-dir
		)
		|[quote includes: | quote include:] set val: [any-string! | block!] (
			if none? dest/includes [ clear dest/includes ]
			if not block? val [val: reduce [val]]
			append dest/includes val
		)

		|[quote files: | quote file:][
			'none ( clear dest/files )
			|
			opt ['only (clear dest/files )]
			opt-get-word
			set val: [block! | file!] ( add-files dest 'files val )
		]
		|[quote needs: | 'needs] set val: [word! | block!] ( unless prep-needs/required val dest/arch [return false] )
		|[quote clean: | 'clean] [
			'none ( clear dest/clean )
			|
			opt ['only (clear dest/clean )]
			opt-get-word
			set val: [block! | file!] ( add-files dest 'clean val )
		]
		| quote shared: set val: [file! | block!] ( append dest/shared val )
		| quote assembly: 
			opt ['only (clear dest/assembly)]
			[ set val: file!  (append dest/assembly join src-dir val)
			| set val: block! (foreach file val [append dest/assembly join src-dir val])
			]
		|[quote flags: | quote cflags: | quote flag:]
			opt ['only (
				clear dest/cflags
				clear dest/lflags
			)] set val: [block! | word! | string!] (
				val: either block? val [preprocess val][to block! val]
				forall val [ add-flag dest val/1 ]
			)
		|[quote lflags: | quote lflag:] any [
			['only | 'none]       (clear dest/lflags)
			| set val: any-string! (append-flag dest/lflags val)
			| p: block! :p into [
				some [
					set val: 1 skip (
						val: form val
						append-flag dest/lflags val
					)
				]
			]
		]
		|[quote rflags: | quote resource-options:] any [
			['only | 'none]       (clear dest/rflags)
			| set val: any-string! (append-flag dest/rflags val)
			| p: block! :p into [
				some [
					set val: 1 skip (
						val: form val
						append-flag dest/rflags val
					)
				]
			]
		]
		| quote flags: 'none ( clear dest/cflags clear dest/lflags )
		| quote optimize: set val [integer! | 'size | 'z | 's | 'fast] (
			add-flag dest join #"O" case [
				val = 'size [#"s"]
				true        [val ] 
			]
		)
		|[quote define:  | quote defines:][
			'none (clear dest/defines)
			|
			opt ['only (clear dest/defines  )]
			opt-get-word
			set val: [word! | string! | ref! | block!] (add-to dest 'defines val)
		]

		|[quote library: | quote libraries: | quote libs:] 
			opt ['only (clear dest/libraries)]
			set val: [file! | block!] (append dest/libraries val)

		|[quote framework: | quote frameworks:] 
			opt ['only (clear dest/frameworks)]
			set val: [word! | file! | block!] (append dest/frameworks val)

		|['set | 'set-env] set var: [any-string! | any-word!]set val: [string!] (add-env var val)

		| pos: set name: set-word! [
			'action set spec: block! set code: block!(
				add-action dest name spec code 
			)
			; any `key: value` quote stored and can be used by `get-word!`
			|
			opt-get-word
			set val: 1 skip (
				;quit
				if find reserved-words to word! name [
					print-error rejoin [
						"Invalid dialect use at: ^[[31m"
						next mold/flat/part pos 50
					]
					return false
				]
				if block? val [val: preprocess val]
				either all [val block? dest/:name] [
					append dest/:name val
				][	dest/(name): val]
			)
		]
		| set name: get-word! pos: (
			either val: dest/:name [
				if block? val [val: preprocess val]
				insert pos val
			][
				print-error rejoin ["Failed to process:" as-red mold name]
				return false
			]
		)
		|
		'info set val: string! (
			print-info val
		)
		|
		'pushd set val: file! (
			add-pre-build dest ['pushd val]
		)
		|
		'popd (
			add-pre-build dest ['popd]
		)
		|
		'python set val: file! (
			add-pre-build dest ['python val]
		)
		|
		'msbuild set val: file! set args: string! (
			add-pre-build dest ['msbuild val args]
		)
		|
		'cmd set dir [file! | none!] set val: string! (
			add-pre-build dest ['cmd dir val]
		)
		|
		'call set val: [file! | string!]  (
			add-pre-build dest ['call val]
		)
		|
		'Rebol2 set val: string! (
			add-pre-build dest ['Rebol2 val]
		)
		|
		'Rebol3 set val: string! (
			add-pre-build dest ['Rebol3 val]
		)
		|
		'Red set val: file! (
			add-pre-build dest ['Red val]
		)
		|
		'do [
			set val: file! set args [string! | block! | #[none]] (
				add-pre-build dest ['do val args]
			)
			|
			set val: block! (
				add-pre-build dest ['do val]
			)
		]
		|
		set val: word! (
			either find dest/actions val [
				add-pre-build dest ['action val]
			][
				print-error ["Unknown action: " mold val]
				return false
			]
		)
		|
		pos: 1 skip (
			print-error rejoin [
				"Invalid dialect use at: ^[[31m"
				next mold/flat/part pos 50
			]
			return false
		)
	]]

	dest/files: unique dest/files
	new-line/all dest/files true

	;add these flag even when not specified by user as these are needed
	unless dest/arch [
		dest/arch: any [
			select system/build 'target
			either find form system/build/os "-x64" ['x64]['x86] ;@@ deprecated!
		]
	]
;	switch dest/arch [
;		x86 [ add-flag dest 'm32 ]
;		x64 [ add-flag dest 'm64 ]  
;	]
;? dest
	dest
] :nest-context

print-eggs: closure/with [][
	i: 0
	print as-yellow "^/Found eggs:"
	clear target-names
	parse nest-spec/eggs [
		any [
			set name: string! set target: block! (
				i: i + 1
				append target-names name
				print rejoin ["  " as-green i ":^-" name]
			)
			| p: 1 skip (
				print-error ["Unknown target rule at:" mold p]
			) 
		]
	]
] :nest-context

parse-action: closure/with [
	nest [file! block!]
	dest [map! block! none!]
][
	if file? nest [print-info ["Parsing nest:" as-green nest]]
	spec: preprocess nest
] :nest-context

do-nest: closure/with [
	nest [file!]
	args [block!]
	/with parent [map!]
][
	CI?: ("true" = get-env "CI")
	print-info ["Processing nest:" as-green to-local-file clean-path nest]

	unless interactive?: empty? args [
		print-info ["With commands:" as-green mold args]
	]
	
	set [nest-root: nest:] split-path nest
	nest-root: pushd nest-root
	nest-spec: parse-nest nest none
	if none? nest-spec [exit]

	if parent [
		foreach [k v] parent [
			if any [none? v all [series? v empty? v]] [continue]
			;print ["extending:" mold k mold v]
			extend nest-spec k v
		]
		;not empty? parent/eggs] [
		;;@@ using so far just eggs
		;nest-spec/eggs: parent/eggs
	]

	if debug? [?? nest-spec]
	any[
		all [any-string? nest-spec/root 'dir = exists? nest-root: clean-path nest-spec/root]
		nest-root: clean-path first split-path nest
	]
	add-env "NEST_ROOT" nest-root
	pushd make-dir/deep nest-root

	clone-gits nest-spec/gits

	eggs: nest-spec/eggs
	if file? nest: nest-spec/nest [
		; nest has a link to another nest
		try/except [
			nest-spec/gits: none
			nest-spec/nest: none
			do-nest/with nest args nest-spec
		][ print-error none ]
		exit
	]
	unless block? eggs: nest-spec/eggs [ exit ]

	if debug? [??  eggs]

	forever [
		try/except [
			if any [none? args all [block? args empty? args]][
				unless none? args [print-eggs]
				args: ask as-green "^/Egg command: "
				unless args [ quit ] ; CTRL+C
				try/except [args: load args][
					print-error ["Invalid command:" as-red args]
					args: none
					continue
				]
				unless block? args [args: to block! args] ; in case that input was a single value
				forall args [
					if tmp: select commands-to-args args/1 [ change args tmp ]
				]
			]

			; make sure, that args are block even for a not interactive input
			; (may be string when running Builder as a pure Rebol script with just a single argument)
			unless block? args [args: reduce [args]]

			if empty? args [ continue ]

			forall args [
				; in case that args are from command line, expand short versions
				; or allow numeric and file input...
				if any [
					tmp: select short-commands args/1
					all [
						not error? try [tmp: load args/1]
						find #[typeset! [integer! file!]] type? :tmp
					]
				][
					change args tmp
				]
			]

			if debug? [?? args]

			no-eval?: false
			run-result?: false
			set-env "NEST_SPEC" none

			debug?: off
			system/options/log/siskin: 1

			parse args [
				any [
					(
						;-- reset states if there are more commands in one call
						;@@ TODO: may need more additions!
						rebuild?:    false
						clang?:      false
						run-result?: false
						update?:     false
					)
					any [
					  "-test"   (no-eval?: true) ;-- like normal build command, but there are no evaluations
					| "-clean"  (rebuild?: true) ;@@ TODO: could be better used to delete all cache files
					| "-v"      (system/options/log/siskin: 1)
					| "-vv"     (system/options/log/siskin: 2)
					| "-vvv"    (system/options/log/siskin: 3)
					| "-vvvv"   (system/options/log/siskin: 4)
					| "-debug"  (system/options/log/siskin: 4 debug?: on)
					| "-quiet"  (system/options/log/siskin: 0 debug?: off)
					| "-run"    (run-result?: on)
					| "-msvc"   (force-compiler: @msvc)
					| "-xcode"  (force-compiler: @xcode)
					| "-update" (update?: on)
					| ['q | 'quit] (interactive?: false)
					]
					copy ids: any [integer! | file! | string!]
					(
						forall ids [
							build-target ids/1
							if all [
								run-result?
								not no-eval?
								object? result
								file? result/name
							][
								print [as-green "^/Executing:" to-local-file result/name]
								pushd first split-path result/name
								eval-cmd/no-quit/v to-local-file result/name
								popd
							] 
						]
					)
					|
					p: 1 skip (print-error ["Unklnown arg:" as-red mold first p])
				]
			]
			args: none
		] :on-error-warn
		
		unless interactive? [break]
	]
	popd
] :nest-context


get-spec: closure/with [
	command [integer! file! string!]
][
	n: 1
	foreach [name spec] nest-spec/eggs [
	;?? name ?? spec
		if any [
			command = n
			command = name
			command = select spec 'name
		][
			print [as-green "^/Building:" as-red name]
			return parse-nest spec copy/deep nest-spec
		]
		++ n
	]
	none
] :nest-context

update-gits: function/with [
	spec [map!]
][
	;@@TODO: make sure not to update gits multiple time in one command batch
	foreach git spec/gits [
		print [as-green "Updating GIT:" git]
		attempt [
			pushd get-git-dir git
			eval-cmd/vv {git pull}
			popd
		]
	]
] :nest-context

build-target: closure/with [
	command [block! integer! file! string!]
][
	timestamp: now/time/precise
	try/except [
		unless spec: get-spec command [
			print-error ["Command not handled:" as-red mold command]
			print-failed
			exit
		]
		if update? [update-gits spec]

		;@@ temporary using strings because of https://github.com/Oldes/Rebol-issues/issues/2466
		;@@ use ref! once build with fixed Rebol version!!!
		if force-compiler [
		switch to string! force-compiler [
			"msvc"  [build-msvc  spec  exit]
			"xcode" [build-xcode spec  exit]
		]]

		try/except [build spec][
			print-failed
			exit
		]
	] :on-error-quit
] :nest-context

build-msvc: function/with [
	"Build using Microsoft's Visual Studio project"
	spec [map!]
][
	try/except [
		spec/eggs: none
		bat: msvc/make-project spec
		eval-cmd/v ["CALL " bat]
		;? spec
		file: rejoin [
			any [spec/root what-dir]
			either spec/arch = 'x64 [%msvc/Release-x64/][%msvc/Release-Win32/]
			spec/name
		]
		finalize-build spec file
	] :on-error-quit
] :nest-context

build-xcode: function/with [
	"Build using Apple's XCode project"
	spec [map!]
][
	try/except [
		spec/eggs: none
		spec/compiler: 'xcode
		? spec
		xcodeproj: xcode/make-project spec
		
		if debug? [
			; to get info about xcodeproj:
			eval-cmd/v ["xcodebuild -list -project " xcodeproj]
			; to see settings:
			eval-cmd/v ["xcodebuild -configuration Release -showBuildSettings -project " xcodeproj]
		]

		; to build xcodeproj:
		unless no-eval? [
			eval-cmd/v ["xcodebuild -configuration Release -project " xcodeproj " build" either debug? [""][" -quiet"]]
			finalize-build spec spec/output
		]
	] :on-error-quit
] :nest-context

build: function/with [
	"Build using given specification"
	spec [map!]
][
	foreach [k v] defaults [
		unless spec/:k [
			print-debug ["Using default" k "as" as-red v]
			spec/:k: v
		]
	]

	out-file: any [spec/exe-file spec/name spec/target]
	if out-file [out-file: to file! out-file]

	spec/defines: copy new-line/all sort unique spec/defines true
	foreach def spec/defines [
		;?? def
		if any-string? def [expand-env def]
		;?? def
	]

	spec/includes: copy new-line/all sort unique spec/includes true
	foreach inc spec/includes [ expand-env inc ]

	if block? spec/libraries [
		spec/libraries: new-line/all sort unique spec/libraries true
	]

	while [not tail? spec/files][
		parts: split-path spec/files/1
		spec/files: either find parts/2 #"*" [
			;?? parts
			remove spec/files
			wc: wildcard parts/1 parts/2
			foreach f wc [
				append spec/files join parts/1 second split-path f
			]
			skip spec/files length? wc
		][	next spec/files ]
	]
	new-line/all spec/files: head spec/files true

	;- check existence of all files (optionaly adding extensions)
	foreach file spec/files [
		unless exists? file [
			source: get-file-with-extensions file [%.c %.cpp %.cc %.m]
			either source [
				change file source
			][
				print-error ["Source file not found: " to-local-file file]
				;quit
			]
		]
	]
	foreach file spec/clean [
		unless exists? file [
			source: get-file-with-extensions file [%.c %.cpp %.cc %.m]
			change file source
		]
	]

	spec/clean: new-line/all sort intersect spec/files spec/clean true

	;src-dir: to-rebol-file preprocess-dirs any [spec/source %""]

	switch spec/arch [
		x86 x86-win32 [ add-flag spec 'm32 ]
		x64           [ add-flag spec 'm64 ]  
	]

	probe-spec spec [
		name
		files
		clean
		libraries
		shared
		defines
		includes
		stack-size
		cflags
		lflags
		libs
		compiler
	]

	;- prepare libs & flags
	cflags: spec/cflags
	lflags: spec/lflags

	; stack size
	if all [
		spec/stack-size
		none? find lflags "-shared" ; don't use stack-size setting when making a shared library
	][
		case [
			windows? [
				;This does not work on Linux!
				append lflags rejoin either find form spec/compiler "gcc" [
					["-Wl,--stack="                 spec/stack-size  ]
				][	["-Wl,-stack:0x" skip to-binary spec/stack-size 4]]
			]
			Linux? [
				;This does not work with Apple's clang!
				append lflags join "-Wl,-z,stack-size=" spec/stack-size
			]
			macOS? [
				append lflags join "-Wl,-stack_size -Wl,0x" skip to-binary spec/stack-size 4
			]
		]
		append lflags #" "
	]

	; static libraries
	if block? spec/libraries [
		libs: copy ""
		foreach lib spec/libraries [
			;lib: preprocess-dirs lib
			clear-extension lib %.lib
			append libs rejoin either find "/\" last lib [
				["-L" to-local-file lib #" "]
			][	["-l" to-local-file lib #" "]]
		]
	]

	; dynamic libraries
	dylib-fix: copy []
	shared: copy ""
	if block? spec/shared [
		; include output directory for shared libraries lookup
		append shared ajoin ["-L" to-local-file clean-path spec/output #" "]
		foreach file spec/shared [
			;file: preprocess-dirs file
			switch system/platform [
				Windows   [
					add-extension file either clang? [%.lib][%.dll]
				]
				macOS
				Macintosh [
					add-extension file %.dylib
					if all [
						find file #"/"
						rel-path? file
					][
						append dylib-fix file
					]
				]
				Linux     [
					parse file [remove "lib" to end]
					replace file %.so "" ;@@ TODO: use safer method!
					append shared ajoin ["-l" file #" "]
					continue
				]
			]
			append append shared to-local-file join spec/output file #" "
		]
	]

	; defines
	defines: make string! 1000
	foreach def spec/defines [
		append append defines " -D" def
	]
	;append cflags defines
	;append lflags defines ;- defines may be needed in linker phase when processing assembly code!

	; frameworks
	foreach frm spec/frameworks [
		append append lflags " -framework " frm
	]
	; includes
	includes: make string! 1000
	foreach inc spec/includes [
		append append includes " -I" to-local-file inc
	]

	append cflags #" "
	append lflags #" "

	spec/libraries: libs
	spec/shared: shared

	if none? spec/arch [
		; try to detect architecture using c flags
		p1: find/last cflags "-m32 "
		p2: find/last cflags "-m64 "
		spec/arch: any [
			all [p1 any [none? p2 (index? p1) > (index? p2)] 'x32]
			all [p2 any [none? p1 (index? p1) < (index? p2)] 'x64]
		]
	]

	;- prepare a directory to hold object files                                 
	;? spec/objects
	if none? spec/objects [
		spec/objects: dirize either out-file [
			 rejoin [
				dirize any [spec/temp %tmp/]
				spec/compiler #"-" spec/arch #"/"
				normalize-file-name out-file
			]
		][
			any [spec/objects spec/temp  %tmp/]
		]
	]

	probe-spec spec [
		objects
		libraries
		shared
		cflags
		lflags
		arch
	]

	add-env "DEFINES" trim defines
	add-env "INCLUDES" trim includes
	add-env "NEST_SPEC" to-local-file clean-path spec/objects/spec.reb

	make-dir/deep spec/objects
	save spec/objects/spec.reb spec

	;- preprocession phase..
	unless empty? spec/pre-build [
		print-info "Evaluate pre-build scripts.."
		eval-code spec spec/pre-build
	]

	unless spec/compiler [
		unless finalize-build/no-fail spec out-file [
			print-info "No compiler to use."
		]
		exit
	]
	if all [empty? spec/files empty? spec/assembly] [
		print-info "No files to compile."
		exit
	]

	any [
		all [spec/cc any [
			exists? cc: spec/cc
			exists? cc: add-extension copy spec/cc %.exe
			exists? cc: add-extension copy spec/cc %.cmd
		]]
		cc: locate-tool spec/compiler spec/arch
	]

	if debug? [?? spec/cc ?? cc]
	unless cc [
		print-error ["Compiler not defined or found:" as-red mold spec/compiler]
		exit
	]
	
	if debug? [try [eval-cmd/vv/no-quit [cc "--version"]]]

	cc-dir: first split-path cc
	any [
		all [spec/ar any [
			exists? ar: spec/ar
			exists? ar: add-extension copy spec/ar %.exe
		]]
		all [spec/compiler = 'clang
			exists? ar: locate-tool 'llvm-ar spec/arch
		]
		exists? ar: locate-tool 'ar spec/arch

		ar: cc
	]
	if debug? [?? ar]

	;- remove objects of files which must be always compiled                    
	unless empty? spec/clean [
		print-info "Cleaning..."
		foreach file spec/clean [
			file: expand-env copy file
			target: rejoin [spec/objects force-relative-file file %.o]

			if debug? [?? target]
			if exists? target [
				;print [as-green "Removing object:" as-yellow to-local-file target]
				unless no-eval? [attempt [delete target]]
			]
		]
	]
	; delete also temporary object list file (collected during compilation)
	print-info "Preparing objects dir..."
	either exists? spec/objects/objects.txt [
		;probe spec/objects/objects.txt
		unless no-eval? [delete spec/objects/objects.txt]
	][	make-dir/deep spec/objects ]

	;-- prepare output file name and delete it if already exists          
	print-info "Preparing output file name..."
	out-file: clean-path rejoin [spec/output out-file]
	if none? suffix? out-file [
		switch system/platform [
			Windows [
				either find spec/lflags "-shared" [
					add-extension out-file %.dll
				][	add-extension out-file %.exe]
			]
			macOS
			Macintosh [
				if find spec/lflags "-shared" [
					add-extension out-file %.dylib
				]
			]
			Linux [
				if find spec/lflags "-shared" [
					add-extension out-file %.so
				]
			]
		]
	]

	add-env "_" undirize spec/objects
	;tmp-env: either windows? ["%_%"]["${_}"]
	tmp-env: either windows? ["$_\"]["$_/"]
	;?? tmp-env

	unless ccpp [
		any [
			all [spec/ccpp any[
				exists? ccpp: expand-env copy spec/ccpp
				exists? ccpp: expand-env rejoin [spec/tools spec/ccpp]
			]]
			all [
				tmp: find/last copy cc "gcc"
				exists? ccpp: head replace tmp "gcc" "g++"
			]
			ccpp: cc
		]
	]
	add-env "CC" cc
	add-env "CCPP" ccpp

	if debug? [?? out-file]
	either exists? out-file [
		delete out-file
	][
		; make sure to create target directory if needed
		make-dir/deep first split-path out-file
	]

	;-- compile each file                                                       

	n: length? spec/files
	i: 0

	if n > 0 [print [lf as-yellow "Compiling" as-green n as-yellow either n = 1 ["file:"]["files:"]]]
	foreach file spec/files [
		i: i + 1
		;file: expand-env copy file
		;?? file
		source-info: query source: file
		unless source-info [
			print-error ["Source file not found: " to-local-file file]
			print-failed
			exit
		]

		suffix: suffix? source
		;-- not sure if its needed, but why not
		;source-type: switch/default suffix [
		;	%.m   [ "-x objective-c "]
		;	%.cc  [ "-x objective-c "]
		;	%.c   [ "-x c "]
		;	%.cpp [ "-x c++"]
		;][	"" ]
		source-type: ""

		compile: "$CC"
		if cpp?: find cpp-extensions suffix [
			needs-cpp-linker?: true
			compile: "$CCPP"
		]

		target: rejoin [spec/objects force-relative-file file %.o]
		target-short: rejoin [tmp-env force-relative-file file %.o]

		p: to integer! round 100 * i / n
		prin rejoin [" [" pad/left p 4 "% ] "]

		either any [
			rebuild?
			none? target-info: query target
			target-info/date < source-info/date
		][
			make-dir/deep first split-path target

			print [as-green "Building object:" as-yellow mold target-short]

			eval-cmd/vvv [
				compile
				;source-type
				to-local-file source
				"-c" cflags "$DEFINES $INCLUDES"
				"-o" to-local-file target-short ;-- using environment variable to hold temp location
			]
		][
			print ["^[[32mFile up to date^[[0m:" to-local-file target-short]
		]
		store-object spec/objects/objects.txt target
	]

	foreach file spec/assembly [
		either any [
			all [source: query file source/type = 'file source: file]
			source: get-file-with-extensions    file [%.S %.s %.sx]
		][
			store-object spec/objects/objects.txt to-local-file source
		][
			print-error ["Assembly file not found: " mold file]
		]
	]

	;- compile resource file if needed
	if file? spec/resource [
		target: rejoin [spec/objects second split-path spec/resource]
		windres: locate-tool 'windres none
		eval-cmd/vvv rejoin [
			to-local-file windres #" "
			;" -v "
			any [spec/rflags ""] #" "
			to-local-file spec/resource
			" -O coff -o " target
		]
		store-object spec/objects/objects.txt target
	]

	archive-only?: find spec/lflags "-archive-only"

	;- linking ...
	if exists? spec/objects/objects.txt [
		if not archive-only? [
			print as-green "^/Linking binary:^/"
			;append-flag lflags "-dynamiclib"
			;probe get-env "CC"
			eval-cmd/v [
				"$CC"
				;"-v"
				"-o" out-file
				join "@" to-local-file spec/objects/objects.txt
				lflags "$DEFINES"
				libs
				shared
			]
		]

		if any [
			archive-only?
			find lflags "-shared"
		][
			print as-green "^/Making archive:^/"

			tmp: split-path out-file
			either windows? [
				replace-extension tmp/2 %.lib
			][
				replace-extension tmp/2 %.a
				unless find/part tmp/2 %lib 3 [insert tmp/2 %lib]
			]
			archive: join tmp/1 tmp/2

			unless ar [
				print-error ["AR tool not found!^/Compilation failed!"]
				exit
			]

			either macOS? [
				;print-error "FIXME: AR utility on macOS does not support input from @ file"
				;print-error "Archive file not created."
				tmp: rejoin [
					to-local-file ar
					" qc " to-local-file archive
					#" " replace/all read/string spec/objects/objects.txt LF #" "
				]
				eval-cmd/v tmp
			][
				eval-cmd/v rejoin [to-local-file ar " rcu " to-local-file archive #" " join "@" to-local-file spec/objects/objects.txt ]
			]
			if spec/compiler = 'gcc [
				ranlib: locate-tool 'ranlib spec/arch
				eval-cmd [to-local-file ranlib to-local-file archive]
			]
		]
	]

	finalize-build spec either archive-only? [archive][out-file]
] :nest-context

probe-spec: func[spec [map!] values [block!] /local val][
	foreach key values [
		val: spec/:key
		unless any [
			none? val
			all [series? val empty? val]
		][
			if block? val [new-line val true]
			print-debug format [$0.32 9 ": " $33 ] reduce [key mold val]
		]
	]
]

preprocess: func [
	spec [block! file!]
][
	spec: either block? spec [ copy spec ][ load spec ]
	process-source/only spec 0
	spec
]

finalize-build: closure/with [spec [map!] file [file! none!] /no-fail][
	either any [
		'file = exists? out-file: file
		'file = exists? out-file: join file %.exe
		'file = exists? out-file: join file %.dll
	][
		if all [macOS? spec/sign <> false][
			if any [
				; 1. sign is environment variable...
				all [
					string? spec/sign
					#"$" = first spec/sign
					sign: get-env next spec/sign
				]
				; 2. sign is user defined string
				string? sign: spec/sign
				; 3. try hardcoded environment variable
				sign: get-env "SISKIN_SIGN_IDENTITY"
			][
				unless valid-sign-identity? sign [
					print-error "Sign identity defined but not found as a valid one!"
					sign: none
				]
			]
		]

		if spec/strip [
			either all [macOS? spec/sign <> false not sign][
				print-error "Not using requested STRIP as it would invalidate a signature!"
				print-error "There is no available sign identity to re-sign!"
			][
				try/except [do-strip spec out-file][print-error system/state/last-error]
			]
		]
		if spec/upx [
			try/except [do-upx out-file][print-error system/state/last-error]
		]
		if all [sign macOS?][
			eval-cmd/v rejoin [{codesign --sign "} sign {" -f -o runtime } out-file]
		]
		

		
		if all [macOS? system/options/log/siskin > 0] [
			eval-cmd/v ["file" out-file]
			eval-cmd/v ["otool -L" out-file]
		]
		print-ready
		return true
	][	unless no-fail [print-failed]]
	false
] :nest-context

clone-gits: function [
	gits [block! url!]
][
	unless block? gits [gits: reduce [gits]]
	if empty? gits [exit]
	found-git?: false
	forall gits [
		git: first gits
		branch: either refinement? second gits [first gits: next gits][none]
		print-info ["Using git:" as-yellow git]
		dir: dirize to file! first split (second split-path git) #"."
		unless exists? dir [
			unless found-git? [
				locate-tool 'git none
				found-git?: true
			]
			cmd: ["git clone" git "--depth 1 --quiet"]
			if branch [append cmd ["--branch" branch]]
			res: either find/match git https:// [
				eval-cmd/v cmd
			][	eval-cmd/no-pipe/v cmd ] ; using no-pipe as it may require user input

			if res = 0 [
				print-info "Project cloned successfuly."
			]
		]
	]
]

;convert-scripts: func[
;	action-code
;	/local dir result
;][
;	result: copy []
;	parse action-code [any[
;		'in-dir set dir file! (
;			make-dir/deep dir
;			in-dir dir [
;
;			]
;
;		)
;	]]
;]

eval-code: function/with [
	spec [map!]
	code [block!]
	/local arg1 arg2 p args tmp err act
][
	if debug? [
		probe what-dir
		prin "eval-code -> " ?? code
	]
	parse code [any[
		'action set arg1 word! (
			act: select spec/actions arg1
			either act [
				print ["Evaluating action:" as-green arg1]
				if act/title [ print as-yellow act/title ]
				eval-code spec act/code
			][
				print ["** Action not found!:" as-red arg1]
			]

		)
		|
		'needs set arg1 [word! | block!] ( prep-needs arg1 spec/arch )
		|
		'in-dir set arg1 file! set arg2 block! (
			;?? arg1 ?? arg2
			make-dir/deep arg1
			pushd arg1
			attempt [eval-code spec arg2]
			popd
		)
		|
		'cmake set arg1 file! set arg2 [string! | #[none]] (
			eval-cmd/v ['cmake arg1 arg2]
		)
		|
		'do [
			set arg1 file! set arg2 [block! | string! | none! | #[none]] (
				case [
					string? arg2 [ expand-env arg2 ]
					block?  arg2 [ forall arg2 [if string? arg2/1 [ expand-env arg2/1]] ]
				]
				try/except [eval-cmd/v [system/options/boot '--script arg1 arg2]] :on-error-warn
				;try/except [do/args arg1 arg2] :on-error-quit
			)
			| set arg1 block! (
				try/except [
					fn: function/with [spec] code :nest-context
					fn spec code
				] :on-error-warn
			)
		]
		|
		'Rebol2 set val string! (do-rebol2 val)
;		| 'Red set val file! (
;			eval-cmd/v [
;				to-local-file any [ expand-env %$RED_CLI  %red ] #" " 
;				to-local-file val
;			]
;		)
;		| 'python set val file! (
;			eval-cmd/v [to-local-file any [config/python %python] #" " to-local-file val]
;		)
;		| 'msbuild set val file! set args string! (
;			eval-cmd/v rejoin [
;				#"^"" to-local-file expand-env %$MSBUILD #"^""
;				#" " to-local-file val
;				#" " args
;			]
;		)
		| 'call set val [file!]  (
			if rel-path? val [insert val what-dir]
			eval-cmd/v join " CALL " to-local-file val
		)
		| 'cmd set dir [file! | none!] set val string! (
			print ["cmd." mold dir]
			if dir [
				if not exists? dir [make-dir/deep dir]
				pushd dir
			]
			foreach line split val lf [
				line: trim/head/tail line
				unless empty? line [
					eval-cmd/v line
				]
			]
			if dir [popd]
		)
		| 'pushd set val file! (pushd val)
		| 'popd (popd)
		|
		p:
		1 skip (
			print [as-red "??? " mold first p]
		)
	]]
] :nest-context

windows?: does [system/platform = 'Windows]
macOS?:   does [to logic! find [macOS Macintosh] system/platform]
linux?:   does [system/platform = 'Linux]
posix?:   does [to logic! find [linux macos macintosh] system/platform]

print-error: func[err][ sys/log/error 'SISKIN any [err system/state/last-error] ]
print-info:  func[msg][ sys/log/info  'SISKIN msg ]
print-debug: func[msg][ sys/log/debug 'SISKIN msg ]
print-more:  func[msg][ sys/log/more  'SISKIN msg ]
print-warn:  func[msg][ sys/log/info  'SISKIN as-purple form either block? msg [reduce msg][msg]]


print-bird: does [
	prin {
^[[1;31m           .-.
^[[1;31m          /'v'\ 
^[[1;31m         (/^[[0;31muOu^[[1;31m\)}
]
print-ready: closure/with [][
	result: query out-file
	print-bird
	prin {^/^[[0;32m═[^[[1mSISKIN^[[0;32m]══^[[1;31m"^[[0;32m═^[[1;31m"^[[0;32m═>  ^[[1mBuild READY}
	prin {^/^[[0;32m │}
	prin {^/^[[0;32m └──────[ FILE ]: ^[[1;37m} prin to-local-file result/name
	prin {^/^[[0;32m        [ SIZE ]: ^[[1;37m} prin               result/size
	prin {^/^[[0;32m        [ DATE ]: ^[[1;37m} prin               result/date
	prin {^/^[[0;32m        [ TIME ]: ^[[1;37m} prin now/time/precise - timestamp
	prin "^/^/"
	result
] :nest-context

print-failed: func[][
	print-bird
	print {^/^[[0;31m═[^[[1mSISKIN^[[0;31m]══^[[1;31m"^[[0;31m═^[[1;31m"^[[0;31m═>  ^[[1mBuild failed (output not found!)}
	none
]


force-relative-file: func[file][
	either abs-path? file [next file][file]
]

pad: func[
	str n
	/left "Pad the string on left side" 
	/with c [char!] "Pad with char" 
][
	unless string? str [str: form str] 
	head insert/dup 
	any [all [left str] tail str] 
	any [c #" "] (n - length? str)
]

env-chars: charset [#"A" - #"Z" #"a" - #"z" #"_" #"0" - #"9"]
expand-env: function [
	"Expands possible posix-like system environmental variables (for example $PATH)"
	value [any-string!] "Input value (modified)"
][
	parse value [any [
		to #"$" [
			s: 1 skip [
				  #"{" copy var: to #"}" 1 skip 
				|      copy var: some env-chars
			] e: (
				;?? var
				if env: get-env var [
					if file? value [env: to-rebol-file env]
					change/part s env e 
				]
			) :e
			| 1 skip
		]
	]]
	value
]

as-env: func[val][
	ajoin either windows? [
		[#"%" val #"%"]
	][	["${" val #"}"]]
]

on-error-quit: func[err][
	print-error err
	;popd
	quit/return either error? err [err/code][1]
]
on-error-throw: func[err][
	print-error err
	do err
]
on-error-warn: func[err [error!]][
	print err
	wait 0:0:2
	;ask "Continue?^[[0m"
]

attempt: func[code [block!] /local err][
	try/except code :on-error-throw
]

pushd: function [
	target [file!]
	/quiet
][
	dir: what-dir
	if dir <> target [
		attempt [target: change-dir target]	
		unless quiet [print-info ["Changed directory to:" as-green to-local-file target]]
	]
	append dirs-stack dir
	target
]
popd: function [
	/quiet
][
	try/except [
		dir: take/last dirs-stack
		if dir <> what-dir [
			change-dir dir
			unless quiet [print-info ["Changed directory to:" as-green to-local-file what-dir]]
		]
	] :on-error-warn
]

delete: function/with [
	"Delete file if exists (ignored on test run)"
	file [file!]
][
	if exists? file [
		print-info ["Deleting:" as-green to-local-file file]
		unless no-eval? [
			try/except [lib/delete file] :on-error-throw
		]
	]
] :nest-context

normalize-file-name: func[
	name [any-word! any-string! any-path!]
	/local p
][
	name: form name
	parse name [
		some [end | some chars-file | p: (p: change p #"-") :p]
	]
	to file! name
]

escaped-space: either Windows? ["^ "]["\ "]

to-local-file: func[
	file
	/no-escape "Don't escape spaces"
][
	file: lib/to-local-file file
	unless no-escape [
		replace/all file #" " escaped-space
	]
	file
]

append-flag: func[flags [string!] flag [string!]][
	flag: append trim/tail flag #" "
	unless find "-`" flag/1 [insert flag #"-"]
	unless find flags flag [append flags flag]
	flags
]

add-flag: func[dest [map!] flag [any-word! any-string!] /local pos][
	flag: any [
		select [
			NSL "-nostdlib"
		] flag
		;or...
		(
			flag: form flag
			unless find "-`" flag/1 [insert flag #"-"]
			flag
		)
	]
	either find [
		"-mconsole"
		"-mwindows"
		"-static"        ;-- On systems that support dynamic linking, this overrides -pie and prevents linking with the shared libraries.
		"-shared"        ;-- Produce a shared object which can then be linked with other objects to form an executable.
		"-nostdlib"
		"-nodefaultlibs"
		"-nostartfiles"
		"-pie"           ;-- Produce a dynamically linked position independent executable on commands that support it
		"-no-pie"        ;-- Don’t produce a dynamically linked position independent executable.
		"-static-pie"    ;-- Produce a static position independent executable on commands that support it.
		"-pthread"       ;-- Link with the POSIX threads library.
		"-rdynamic"      ;-- Pass the flag -export-dynamic to the ELF linker, on commands that support it.
		"-strip-all"
		"-s"             ;-- Remove all symbol table and relocation information from the executable.
		;@@ TODO: add more once needed!

		"-archive-only"
	] flag [
		switch flag [
			"-mconsole" [if pos: find dest/lflags "-mwindows " [remove/part pos 10]]
			"-mwindows" [if pos: find dest/lflags "-mconsole " [remove/part pos 10]]
		]
		;linker only flags
		append-flag dest/lflags flag
	][
		append-flag dest/cflags flag
		append-flag dest/lflags flag
	]
]

eval-cmd: function/with [
	cmd /no-pipe /no-quit /log log-file [file!]
	/v    "print info"
	/vv   "print more"
	/vvv  "print debug"
	/force "evaluate even when no-eval is used"
][
	if block? cmd [
		attempt [cmd: reduce cmd]
		local: copy ""
		;?? cmd
		parse cmd [any [
			set val [word!] (append append local val #" ")
			|
			set val file! (
				val: to-local-file val
				append append local val #" "
			)
			|
			set val string! (
				append append local expand-env copy val #" "
			)
			|
			none! ; skip
			| set val 1 skip (append append local :val #" ")
		]]
		cmd: local
		;?? cmd
	]
	case [
		vvv [print-more  ["EVAL:^[[0;33m" cmd]]
		vv  [print-debug ["EVAL:^[[0;33m" cmd]] 
		v   [print-info  ["EVAL:^[[0;33m" cmd]]
	]

	cmd: expand-env copy cmd

	; there may be case, where evaluation is needed even when no-eval? is true
	; for example when just making xcode project without actually trying to build it
	if all [no-eval? not force] [exit]

	if log [
		if exists? log-file [try [lib/delete log-file]]
		append cmd rejoin [" > " to-local-file log-file]
		no-pipe: true
	]

	;clear err

	either no-pipe [
		res: call/wait/shell cmd
		if all [file? log-file exists? log-file] [
			either res <> 0 [
				print-error read/string log-file
			][	print read/string log-file ]
			delete log-file
		]
		if res <> 0 [
			if CI? [quit/return 1]
			ask as-purple "^/Press enter to continue."
		]
	][
		res: call/wait/shell cmd
		if all [res <> 0 not no-quit][ quit/return 1 ]
	]
	res
] :nest-context

store-object: func[list [file!] file [file! string!]][
	write/append list rejoin [
		;using *nix type of path even on Windows + escaped spaces
		replace/all replace/all to-local-file/no-escape file #"\" #"/" #" " "\ "
		newline
	]
]

lib-extension: any [select [Windows %.dll Macintosh %.dylib] system/platform %.so]
exe-extension: either windows? [%.exe][%""]

has-extension?: func[file ext][ to logic! find/match/last file ext ]

add-extension: func[
	file [any-string!]
	ext  [any-string!]
	/local f
][
	unless find/match/last file ext [
		append file ext
	]
]
clear-extension: func[file ext /local s][
	if s: suffix? file [ clear find/last file s	]
	file
]
replace-extension: func[file ext][
	clear-extension file ext
	add-extension file ext
	file
]

get-file-with-extensions: func[
	file [file!]
	ext  [block!]
	/in dir [file!]
	/local result
][
	;?? file
	unless dir [dir: %""]
	if exists? result: rejoin [dir file][
		return result
	]
	forall ext [
		if exists? result: rejoin [dir file ext/1][
			return result
		]
	]
	none
]

prep-needs: func[
	needs [word! block! file!]
	arch  [word! none!]
	/required
	/local tool
][
	unless block? needs [needs: reduce [needs]]
	forall needs [
		;prin ["Needs:" as-green pad needs/1 12]
		either tool: apply :locate-tool [needs/1 arch required] [
			;print ["using:" as-green to-local-file tool]
		][
			;print as-red " not found!"
			if required [
				print-error ["Tool not found" as-red needs/1]
				return false
			]
		]
	]
	true
]

to-abs-dir: func[
	"Convert path to Rebol file and apply clean-path/dir on it."
	path [file! string!]
][
	clean-path/dir to-rebol-file path
]

abs-path?: func[path][#"/" =  first path]
rel-path?: func[path][#"/" <> first path]

env-paths: none 
env-paths-init: does [
	unless env-paths [
		env-paths: split get-env "PATH" either windows? [#";"][#":"]
		forall env-paths [
			change env-paths to-abs-dir env-paths/1
		]
		new-line/all env-paths true
	]
]

locate-tool: function/with [
	tool [word! any-string!]
	arch
	/required "Return NONE if not located"
][
	print-debug ["Locating tool:" as-green tool any [arch ""]]
	tool-file: to file! tool

	switch/default tool [
		clang
		clang-cl [
			clang?: true
			add-env-path tools: %$LLVM/bin/
		]
		gcc   [
			if windows? [
				switch arch [
					x86 [ add-env-path tools: %$MINGW32/bin/ ]
					x64 [ add-env-path tools: %$MINGW64/bin/ ]
				]
				;i686-w64-mingw32-gcc.exe
			]
		]
		tcc [
			any [
				type: exists? tools: expand-env %$TCC
				type: exists? tools: expand-env %$TCC_HOME
			]
			if type = 'file [
				tools: first split-path tools
				return tools
			]
		]
		emcc [
			any [
				type: exists? tools: expand-env %$EMSCRIPTEN
				type: exists? tools: expand-env %$TCC_HOME
			]
		]
		android-sdk [
			if any [
				exists? android-sdk: expand-env %$ANDROID_SDK
				exists? android-sdk: expand-env %$ANDROID_HOME
				exists? android-sdk: expand-env %$ANDROID_SDK_ROOT
				exists? android-sdk: expand-env %$HOME/Android/Sdk
				exists? android-sdk: expand-env %$HOME/Library/Android/sdk
				        android-sdk: none
			][
				add-env "ANDROID_SDK" android-sdk: dirize android-sdk
				if build-tools: last wildcard join android-sdk %/build-tools/ "*/" [
					add-env "BUILD_TOOLS" build-tools
				]
				return  android-sdk
			]
		]
		android-ndk [
			if any [
				all [exists? android-ndk: expand-env %$NDK              exists? dirize android-ndk/toolchains]
				all [exists? android-ndk: expand-env %$ANDROID_NDK      exists? dirize android-ndk/toolchains]
				all [exists? android-ndk: expand-env %$ANDROID_NDK_HOME exists? dirize android-ndk/toolchains]
				             android-ndk: none
			][
				switch system/platform [
					windows [ add-env "OS_NAME" "windows-x86_64" ]
					linux   [ add-env "OS_NAME" "linux-x86_64"   ]
					macos   [ add-env "OS_NAME" "darwin-x86_64"  ]
				]
				add-env "ANDROID_NDK" android-ndk
				add-env         "NDK" android-ndk ; it seems to be used quite a lot in tutorials
				add-env "NDK_TOOLCHAIN" join android-ndk %toolchains/llvm/prebuilt/$OS_NAME/
				return  android-ndk
			]
		]
		msbuild [
			if all [
				tmp: first msvc/vswhere
				tmp: select tmp 'installationPath
			][
				;eval-cmd/vvv rejoin [{"} tmp {\VC\Auxiliary\Build\vcvarsall.bat" } any [arch 'x64]]
				add-env-path tmp: join to-rebol-file tmp %\MSBuild\Current\Bin\
				return tmp
			]

		]
	][	;else..
		; make sure that we know env-paths
		env-paths-init
	]
	;?? tool ?? tools
	; searching in tools, root and PATH directories...
	foreach dir join reduce [tools root-dir] env-paths [
		unless file? dir [continue]
		if any [
			'file = exists? tool-exe:               dir/:tool-file
			'file = exists? tool-exe: add-extension dir/:tool-file %.exe
			'file = exists? tool-exe: add-extension dir/:tool-file %.cmd
			'file = exists? tool-exe: add-extension dir/:tool-file %.bat
		][
			try [add-env uppercase form to word! tool tool-exe]
			return tool-exe
		]
	]
	either required [none][tool-file]
] :nest-context

add-env-path: func[
	path [file! string!]
][
	;print-info ["add-env-path:" mold path]
	env-paths-init	
	if all [
		exists? path: to-abs-dir expand-env path
		not find env-paths path
	][	
		; adding in front of other paths so it's most likely to be used!
		insert env-paths path
		print-info ["Adding PATH:" as-green path]
		set-env "PATH" rejoin [to-local-file path #";" get-env "PATH"]
	]
]

add-env: func [
	key [any-string! any-word!]
	value [string! file! none!]
][
	if file? value [value: to-local-file value]
	if value [value: expand-env copy value]
	if value <> get-env key [
		;print ["set.." mold key mold value]
		set-env key value
		print-info [
			"Environment:"
			as-green ajoin ["${" key #"}"]
			as-cyan "is"
			as-green mold value
		]
	]
]

valid-sign-identity?: function[sign][
	out: make string! 1000
	all [
		0 = try [call/shell/wait/output {security find-identity -v -p codesigning} out]
		find out sign
		print-info "Sign identity is valid."
		true
	]
]
