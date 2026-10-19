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
			print [as-red "[FAIL]" name "=>" either string? :result [:result][mold/flat/part :result 80]]
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
set-env "SISKIN_TEST_VAR" "hello"
;; `do-args` normally sets it; needed by `host-windows?`
extend system 'real-platform system/platform

;;=============================================================================
group "Pre-build: `do` arguments"
;;=============================================================================

;; `none` args must be consumed, else the following command is swallowed
code: reduce ['do %a.reb none 'do %b.reb "x"]

--test-- "sh: do without args"           [has? out: siskin/form-sh-pre-build spec copy/deep code "a.reb"]
--test-- "sh: command after none args"   [has? out "b.reb"]
--test-- "sh: string args"               [has? out {["x"]}]

--test-- "msvc: do without args"         [has? out: msvc/form-pre-post-build copy/deep code base "a.reb"]
--test-- "msvc: command after none args" [has? out "b.reb"]
--test-- "msvc: string args"             [has? out {[\"x\"]}]

;;=============================================================================
group "Pre-build: dir tracking"
;;=============================================================================

siskin/emit-reset base
--test-- "emit-pushd relative"        [is? siskin/emit-pushd %a/ join base %a/]
--test-- "emit-pushd nested relative" [is? siskin/emit-pushd %b/ join base %a/b/]
--test-- "emit-popd to parent"        [is? siskin/emit-popd join base %a/]
--test-- "emit-popd to base"          [is? siskin/emit-popd base]
--test-- "emit-pushd absolute"        [is? siskin/emit-pushd %/x/ %/x/]
--test-- "emit-popd from absolute"    [is? siskin/emit-popd base]

--test-- "emit-reset sets the base" [
	siskin/emit-reset %/x/
	is? siskin/emit-popd %/x/
]

sh-cd: func [dir][ajoin ["cd " siskin/quote-sh-arg siskin/to-posix-file dir]]
--test-- "sh: pushd" [
	out: siskin/form-sh-pre-build spec [pushd %sub/ popd]
	has? out sh-cd join base %sub/
]
--test-- "sh: popd" [
	any [
		did find/last out sh-cd base
		ajoin ["got " mold/flat out]
	]
]
--test-- "sh: root with spaces is quoted" [
	out: siskin/form-sh-pre-build make map! reduce ['root join base %"a b/"] []
	has? out sh-cd join base %"a b/"
]
--test-- "sh: popd returns to spec/root, not what-dir" [
	out: siskin/form-sh-pre-build make map! reduce ['root join base %r/] [pushd %sub/ popd]
	all [
		true = has? out sh-cd join base %r/sub/
		true = any [
			did find/last out sh-cd join base %r/
			ajoin ["got " mold/flat out]
		]
	]
]
--test-- "msvc: cmd with dir" [
	out: msvc/form-pre-post-build [cmd %sub/ "echo x"] base
	has? out join "CD " msvc/to-windows-file join base %sub/
]
--test-- "msvc: cmd dir relative to the start dir" [
	out: msvc/form-pre-post-build [cmd %sub/ "echo x"] join base %r/
	has? out join "CD " msvc/to-windows-file join base %r/sub/
]

;;=============================================================================
group "Pre-build: command quoting"
;;=============================================================================

--test-- "sh: single quotes"         [is? siskin/quote-sh-arg {a'b $X `c`} {'a'\''b $X `c`'}]
--test-- "cmd: spaces"               [is? siskin/quote-cmd-arg {a b}       {"a b"}]
--test-- "cmd: embedded quotes"      [is? siskin/quote-cmd-arg {say "hi"}  {"say \"hi\""}]
--test-- "cmd: special out of quote" [is? siskin/quote-cmd-arg {a"&b"}     {"a\"^^&b\""}]
--test-- "cmd: percent"              [is? siskin/quote-cmd-arg {50%}       {"50%%"}]
--test-- "cmd: trailing backslash"   [is? siskin/quote-cmd-arg {c:\dir\}   {"c:\dir\\"}]

--test-- "r3 runner, sh" [
	has? siskin/form-do-cmd/as %x.r3 [a "b" %c] 'sh 'r3 {--do 'do/args %x.r3 [a "b" %c]'}
]
--test-- "Siskin runner, sh" [
	has? siskin/form-do-cmd/as %x.r3 [a "b" %c] 'sh 'Siskin {--script 'x.r3' --args '[a "b" %c]'}
]
--test-- "Siskin runner, no args" [
	has? siskin/form-do-cmd/as %x.r3 none 'sh 'Siskin {--args '[]'}
]
--test-- "r3 runner, cmd" [
	has? siskin/form-do-cmd/as %x.r3 [a "b" %c] 'cmd 'r3 {--do "do/args %%x.r3 [a \"b\" %%c]"}
]
--test-- "env expanded at generation" [
	has? siskin/form-do-cmd/as %x.r3 "$SISKIN_TEST_VAR" 'sh 'r3 {["hello"]}
]
--test-- "Siskin runner args round trip" [
	is? mold second siskin/take-script-args reduce [
		"--script" "/x.r3" "--args" mold/flat siskin/prep-do-args {c:\dir\spec.reb}
	] {["c:\dir\spec.reb"]}
]
--test-- "msvc: escaped for MSBuild/XML" [
	out: msvc/form-pre-post-build reduce ['do %a.reb "x &y"] base
	all [
		true = has? out "&amp;y"
		none? find out "%a.reb"   ;; must be %25%25a.reb
		true = has? out "%25%25a.reb"
	]
]

;;=============================================================================
group "Pre-build: script file"
;;=============================================================================

tmp-dir: make-dir %tmp-siskin-test/
;; NOTE: a failing `chmod` quits the whole run (eval-cmd), which also means a failure
--test-- "write-sh-pre-build: chmod follows the host, not --platform" [
	real: system/platform
	unprotect 'system/platform
	system/platform: either real = 'Windows ['Linux]['Windows]
	f: try [siskin/write-sh-pre-build spec tmp-dir]
	system/platform: real
	case [
		error? f [f]
		real = 'Windows [true]
		'else [
			out: copy ""
			call/wait/output ajoin ["test -x " siskin/quote-sh-arg siskin/to-posix-file f " && echo yes"] out
			any [did find out "yes" "script is not executable"]
		]
	]
]
try [delete f delete tmp-dir]

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

--test-- "prep-do-args none" [is? siskin/prep-do-args none none]
--test-- "prep-do-args keeps a string as one value" [
	is? mold siskin/prep-do-args {a "b c" 1 %f} {[{a "b c" 1 %f}]}
]
--test-- "prep-do-args expands env in a string" [
	is? mold siskin/prep-do-args {$SISKIN_TEST_VAR x} {["hello x"]}
]
--test-- "prep-do-args keeps a path string" [
	is? mold siskin/prep-do-args {c:\dir\spec.reb} {["c:\dir\spec.reb"]}
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

sa: func [args][mold siskin/take-script-args args]
--test-- "no --args"                    [is? sa ["--script" "/x.r3" "a"]         {[%/x.r3 ["a"]]}]
--test-- "molded block"                 [is? sa ["--script" "/x.r3" "--args" {[a "b c" %f]}] {[%/x.r3 [a "b c" %f]]}]
--test-- "molded string stays a string" [is? sa ["--script" "/x.r3" "--args" {"a %f"}]       {[%/x.r3 ["a %f"]]}]
--test-- "env in molded string"         [is? sa ["--script" "/x.r3" "--args" {"$SISKIN_TEST_VAR"}] {[%/x.r3 ["hello"]]}]
--test-- "env in molded block"          [is? sa ["--script" "/x.r3" "--args" {["$SISKIN_TEST_VAR"]}] {[%/x.r3 ["hello"]]}]
--test-- "unmolded legacy value"        [is? sa ["--script" "/x.r3" "--args" {a b c}]         {[%/x.r3 [a b c]]}]
--test-- "extra argv kept"              [is? sa ["--script" "/x.r3" "--args" {[a]} "%b"]      {[%/x.r3 [a "%b"]]}]
--test-- "relative script path"         [
	is? first siskin/take-script-args ["--script" "x.r3"] join system/options/path %x.r3
]

;;=============================================================================
group "eval-code"
;;=============================================================================

hits: 0
--test-- "do [code] evaluates only its own block" [
	siskin/eval-code make map! [] reduce [
		'do [set 'hits hits + 1]
		'do [set 'hits hits + 10]
	]
	is? hits 11
]

summary
