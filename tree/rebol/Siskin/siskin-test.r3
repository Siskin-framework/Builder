Rebol [
	title: "Siskin inner code test file"
	file:  %siskin-test.r3
]

import %prebol.reb
import %siskin-msvc.reb
import %siskin-xcode.reb
import %siskin-make.reb
siskin: import %siskin.reb

base: what-dir
spec: make map! reduce ['root base]
;; `do` with none/string args
out: siskin/form-sh-pre-build spec reduce ['do %a.reb none 'do %b.reb "x"]
assert [find out "a.reb"]
assert [find out "b.reb"]
assert [find out {--args "x"}]
;; pushd/popd
out: siskin/form-sh-pre-build spec [pushd %sub/ popd]
assert [find out join "cd " siskin/to-posix-file join base %sub/]
assert [find/last out join "cd " siskin/to-posix-file base]
;; escaping
assert [{ --args "a \"b\" c\\d"} = siskin/escape-sh-args {a "b" c\d}]
assert [""  = siskin/escape-sh-args none]

print "OK"