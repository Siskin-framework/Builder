Rebol []

switch system/platform [
	windows [
		shdc-tool: %sokol-tools-bin\bin\win32\sokol-shdc.exe
		slang: %hlsl5
	]
	linux [
		shdc-tool: %sokol-tools-bin\bin\linux\sokol-shdc
		slang: %glsl330
	]
	macintosh
	macOS [
		shdc-tool: either system/build/arch = 'arm64 [
			%sokol-tools-bin\bin\osx_arm64\sokol-shdc
		][	%sokol-tools-bin\bin\osx\sokol-shdc]
		slang: %metal_macos
	]
]

make-dir/deep join %tmp/ slang

foreach file read dir: %sokol-samples/sapp/ [
	try/with [
		if %.glsl = suffix? file [
			out: rejoin [%tmp/ slang #"/" file %.h] 
			cmd: rejoin [
				to-local-file shdc-tool
				{ --input }  to-local-file dir/:file
				{ --output } to-local-file out
				{ --slang "} slang {"}
				{ --format sokol}
				;{ --bytecode}
			]
			print cmd
			call/wait/console/shell cmd
		]
	] :print
]

;wait 4