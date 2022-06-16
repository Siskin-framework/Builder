Rebol []

slang: %hlsl5 ;%glsl300es

make-dir/deep join %tmp/ slang

foreach file read dir: %sokol-samples/sapp/ [
	attempt [
		if %.glsl = suffix? file [
			out: rejoin [%tmp/ slang #"/" file %.h] 
			cmd: rejoin [
				{sokol-tools-bin\bin\win32\sokol-shdc.exe}
				{ --input }  to-local-file dir/:file
				{ --output } to-local-file out
				{ --slang "} slang {"}
			]
			print cmd
			call/wait/console cmd
		]
	]
]
wait 4