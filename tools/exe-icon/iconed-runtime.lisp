;;;; A copy of the running SBCL runtime with Hexmaw's icon written into it, for
;;;; tools/build-dist on Windows. Deploy saves hexmaw.exe from the runtime it runs under
;;;; (SAVE-LISP-AND-DIE writes that runtime and appends the image), and the icon can't be
;;;; added afterwards (set-icon.lisp says why), so the build runs under this copy instead:
;;;;
;;;;   sbcl --non-interactive --no-userinit --load tools/exe-icon/iconed-runtime.lisp
;;;;
;;;; prints two lines, "runtime <path>" and "core <path>", the copy and the core to start
;;;; it with. Started with that core (and SBCL_HOME as it is), the copy is SBCL in every
;;;; respect but the icon. Delete it after the build.

(load (merge-pathnames "set-icon.lisp" *load-truename*))

(defun uiop-free-directory (native)
  "NATIVE, a folder's native name, as a directory pathname: no ASDF is loaded here."
  (let ((path (sb-ext:parse-native-namestring native)))
    (if (or (pathname-name path) (pathname-type path))
        (make-pathname :directory (append (or (pathname-directory path) (list :relative))
                                          (list (file-namestring path)))
                       :name NIL :type NIL :defaults path)
        path)))

(let* ((root (merge-pathnames "../../" (make-pathname :name NIL :type NIL :defaults *load-truename*)))
       (ico (merge-pathnames "data/icon/hexmaw.ico" root))
       (runtime (merge-pathnames (format NIL "hexmaw-runtime-~d.exe" (get-universal-time))
                                 (uiop-free-directory
                                  (or (sb-ext:posix-getenv "TEMP") (sb-ext:posix-getenv "TMP") ".")))))
  (with-open-file (in sb-ext:*runtime-pathname* :element-type '(unsigned-byte 8))
    (with-open-file (to runtime :element-type '(unsigned-byte 8) :direction :output :if-exists :supersede)
      (let ((buffer (make-array 65536 :element-type '(unsigned-byte 8))))
        (loop for n = (read-sequence buffer in) while (plusp n) do (write-sequence buffer to :end n)))))
  (hexmaw-exe-icon:set-exe-icon runtime ico)
  (format T "~&runtime ~a~%core ~a~%" (sb-ext:native-namestring runtime)
          (sb-ext:native-namestring sb-ext:*core-pathname*)))
