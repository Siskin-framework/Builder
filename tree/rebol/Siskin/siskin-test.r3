Rebol [
	title: "Siskin inner code test file"
	file:  %siskin-test.r3
]

import %prebol.reb
import %siskin-msvc.reb
import %siskin-xcode.reb
mmake:  import %siskin-make.reb
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

;; get-relative-path
assert [%../src/a.c  = siskin/get-relative-path %/p/src/a.c %/p/msvc/]
assert [%a.c         = siskin/get-relative-path %/p/a.c     %/p/]
assert [%../../x/y.c = siskin/get-relative-path %/x/y.c     %/p/q/]
assert [%../src/a.c  = siskin/get-relative-path %/p/src/a.c %/p/msvc]  ;; base without slash
;; to-posix-file
f: siskin/to-posix-file %/c/some/dir/file.c
assert [not find f #"\"]
assert [not find siskin/to-posix-file %"/c/a b/c.c" #"^""]  ;; no quoting
;; emitters still load and use it
assert [function? :siskin/get-relative-path]
foreach mod [msvc mmake xcode] [assert [not in system/modules/:mod 'get-relative-path]]


print "OK"