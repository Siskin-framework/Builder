Rebol [
	title: "Prepare a new Rebol extension project"
	needs: [thru-cache]
]

ext-name1: ask "Name of the extension: "
ext-name2: lowercase copy ext-name1
ext-root:  join %Rebol- ext-name1

;; Check if there is already a project with this name.
if exists? ext-root [
	print as-purple rejoin ["*** There is already a project with name:" as-yellow ext-root]
	wait-for-key
	quit
]
;; Make the root directory
make-dir ext-root

;; As we will work with binary data later, prepare the names as binary as well.
name1: to binary! ext-name1
name2: to binary! ext-name2

;; Try to download all template files as a ZIP archive.
try/with [
	template: load https://github.com/Oldes/Rebol-C-Extension-Template/archive/refs/heads/master.zip
][
	print as-purple "*** Failed to download a template sources!"
	wait-for-key
	quit
]

;; For each file in the archive, replace all template names in both its path and content.
foreach [path data] template [
	path: find/tail path #"/"
	if empty? path [continue]
	probe path
	replace/all/case path %template ext-name2
	replace/all/case path %Template ext-name1
	either dir? path [
		make-dir/deep ext-root/:path
	][
		bin: second data
		if find [%.md %.r3 %.c %.h %.yml %.nest] suffix? path [
			replace/all bin #{74656D706C617465} name2
			replace/all bin #{54656D706C617465} name1
		]
		write ext-root/:path :bin
	]
]