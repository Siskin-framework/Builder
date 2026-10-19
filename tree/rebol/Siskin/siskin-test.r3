Rebol [
	title:   "Siskin inner code test file"
	file:    %siskin-test.r3
	Purpose: {
		Tests Siskin's internal functions and the project emitters
		without building anything.

		Usage:
			r3 siskin-test.r3

		Exits with 1 if any test failed, so it can gate CI.
	}
]

import %prebol.reb
import %siskin-msvc.reb
import %siskin-xcode.reb
import %siskin-make.reb
siskin: import %siskin.reb

;;=============================================================================
;; Minimal self-contained harness
;;=============================================================================

test-count: 0
fail-count: 0
failed: copy []

group: func ["Starts a named group of tests" name [string!]][
	print ajoin [lf as-yellow "== " as-yellow name]
]

;; NOTE: plain `func` with explicit locals - `function` would collect the
;; counter set-words as locals and the totals would never move.
;;
;; A test block must EVALUATE to true; anything else counts as a failure and
;; is printed as the detail, so a check can hand back a string saying what
;; went wrong. Never use `return` inside one.
--test--: func [
	"Passes when the code block evaluates to true"
	name [string!]
	code [block!]
	/local result
][
	test-count: test-count + 1
	result: try code
	case [
		error? :result [
			fail-count: fail-count + 1
			append failed name
			print [as-red "[FAIL]" name]
			print [as-red "      " mold/flat :result]
		]
		:result = true [
			print [as-green "[ ok ]" name]
		]
		true [
			fail-count: fail-count + 1
			append failed name
			print [as-red "[FAIL]" name "=>" mold/flat/part :result 80]
		]
	]
	:result
]

;; Compares a result with what it should be and hands back the actual value
;; when they differ, so the failure line shows it.
is?: func ["Compares a value with the expected one" value expected][
	any [value == expected  ajoin ["got " mold/flat value]]
]

;; Checks that the text contains the part and hands back both when it does not.
has?: func ["Checks that a string contains a part" text [string!] part [string!]][
	any [
		did find text part
		ajoin ["missing " mold part " in " mold/flat text]
	]
]

summary: does [
	print ajoin [lf as-yellow "-----------------------------------------------------------------------------"]
	print [
		"tests:" test-count
		as-green ajoin ["passed: " test-count - fail-count]
		either fail-count > 0 [as-red ajoin ["failed: " fail-count]][ajoin ["failed: " fail-count]]
	]
	if fail-count > 0 [
		print as-red ajoin ["^/Failed tests:^/  " mold/flat failed]
	]
	print ""
	quit/return either fail-count > 0 [1][0]
]

base: what-dir
spec: make map! reduce ['root base]
msvc: system/modules/msvc

;;=============================================================================
group "Pre-build: `do` arguments"
;;=============================================================================

;; `none` args must be consumed, else the following command is swallowed
code: reduce ['do %a.reb none 'do %b.reb "x"]

--test-- "sh: do without args"           [has? out: siskin/form-sh-pre-build spec copy/deep code "a.reb"]
--test-- "sh: command after none args"   [has? out "b.reb"]
--test-- "sh: string args"               [has? out {--args "x"}]

--test-- "msvc: do without args"         [has? out: msvc/form-pre-post-build copy/deep code "a.reb"]
--test-- "msvc: command after none args" [has? out "b.reb"]
--test-- "msvc: string args"             [has? out {--args "x"}]

;;=============================================================================
group "Pre-build: dir tracking"
;;=============================================================================

clear siskin/emit-dirs
--test-- "emit-pushd relative"        [is? siskin/emit-pushd %a/ join base %a/]
--test-- "emit-pushd nested relative" [is? siskin/emit-pushd %b/ join base %a/b/]
--test-- "emit-popd to parent"        [is? siskin/emit-popd join base %a/]
--test-- "emit-popd to base"          [is? siskin/emit-popd base]
--test-- "emit-pushd absolute"        [is? siskin/emit-pushd %/x/ %/x/]
--test-- "emit-popd from absolute"    [is? siskin/emit-popd base]

--test-- "sh: pushd" [
	out: siskin/form-sh-pre-build spec [pushd %sub/ popd]
	has? out join "cd " siskin/to-posix-file join base %sub/
]
--test-- "sh: popd" [
	any [
		did find/last out join "cd " siskin/to-posix-file base
		ajoin ["got " mold/flat out]
	]
]
--test-- "msvc: cmd with dir" [
	out: msvc/form-pre-post-build [cmd %sub/ "echo x"]
	has? out join "CD " msvc/to-windows-file join base %sub/
]

;;=============================================================================
group "Pre-build: sh escaping"
;;=============================================================================

--test-- "escape-sh-args quotes and backslashes" [
	is? siskin/escape-sh-args {a "b" c\d} { --args "a \"b\" c\\d"}
]
--test-- "escape-sh-args none" [is? siskin/escape-sh-args none ""]

;;=============================================================================
group "Shared helpers"
;;=============================================================================

--test-- "get-relative-path to sibling dir"    [is? siskin/get-relative-path %/p/src/a.c %/p/msvc/ %../src/a.c]
--test-- "get-relative-path in same dir"       [is? siskin/get-relative-path %/p/a.c     %/p/      %a.c]
--test-- "get-relative-path two levels up"     [is? siskin/get-relative-path %/x/y.c     %/p/q/    %../../x/y.c]
--test-- "get-relative-path base without slash"[is? siskin/get-relative-path %/p/src/a.c %/p/msvc  %../src/a.c]

--test-- "to-posix-file has no backslashes" [
	f: siskin/to-posix-file %/c/some/dir/file.c
	any [not find f #"\"  ajoin ["got " mold f]]
]
--test-- "to-posix-file does not quote" [
	f: siskin/to-posix-file %"/c/a b/c.c"
	any [not find f #"^""  ajoin ["got " mold f]]
]

foreach mod [msvc mmake xcode] [
	--test-- ajoin [mod ": no own get-relative-path"] compose [
		none? in system/modules/(mod) 'get-relative-path
	]
]
foreach mod [mmake xcode] [
	--test-- ajoin [mod ": no own pre-build emitter"] compose [
		all [
			none? in system/modules/(mod) 'form-pre-post-build
			none? in system/modules/(mod) 'escaped-args
		]
	]
]

;;=============================================================================
group "do arguments"
;;=============================================================================

set-env "SISKIN_TEST_VAR" "hello"
--test-- "prep-do-args none" [is? siskin/prep-do-args none none]
--test-- "prep-do-args loads a string" [
	is? mold siskin/prep-do-args {a "b c" 1 %f} {[a "b c" 1 %f]}
]
--test-- "prep-do-args expands env in a string" [
	is? mold siskin/prep-do-args {"$SISKIN_TEST_VAR" x} {["hello" x]}
]
--test-- "prep-do-args rejects invalid syntax" [
	error? try [siskin/prep-do-args {"unclosed}]
]
--test-- "prep-do-args expands env in block strings" [
	is? mold siskin/prep-do-args ["$SISKIN_TEST_VAR" x %f] {["hello" x %f]}
]
--test-- "prep-do-args keeps the input untouched" [
	s: "$SISKIN_TEST_VAR"
	siskin/prep-do-args reduce [s]
	siskin/prep-do-args s
	is? s "$SISKIN_TEST_VAR"
]

summary
