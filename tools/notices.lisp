;;;; Writes THIRD-PARTY-NOTICES.txt, or checks it (tools/notices). Loaded after boot.lisp,
;;;; with the game loaded, so it can also see which systems the image really holds.
;;;;
;;;; The file is notices/head.txt (SBCL, the native libraries, the fonts, the LGPL libraries:
;;;; written by hand), then every Lisp library the game depends on, one entry per release in
;;;; the pinned dists, then each licence text once. The libraries come from walking the
;;;; dependency tree in the .asd files, every (:feature ...) branch included, so one file
;;;; covers the Linux, Windows and macOS builds alike.

(defpackage #:hexmaw-notices
  (:use #:cl)
  (:export #:main))

(in-package #:hexmaw-notices)

(defvar *root* (uiop:pathname-parent-directory-pathname (uiop:pathname-directory-pathname *load-truename*)))

(defparameter *copyleft-allowed* '("text.editing" "utilities.print-items" "flexichain")
  "Releases under a copyleft licence the build may ship, with the obligations notices/head.txt
describes. Anything else copyleft fails the check.")

(defparameter *copyleft-markers*
  '("GPL" "GNU GENERAL PUBLIC LICENSE" "GNU LESSER GENERAL PUBLIC" "GNU LIBRARY GENERAL PUBLIC"
    "MOZILLA PUBLIC LICENSE" "EUROPEAN UNION PUBLIC" "CREATIVE COMMONS")
  "Text that marks a licence as copyleft or otherwise not plainly permissive.")

(defvar *override-problems* () "What is wrong with notices/overrides.lisp, as strings.")

(defun dep-name (dependency)
  (cond ((stringp dependency) dependency)
        ((symbolp dependency) (string-downcase dependency))
        ((and (consp dependency) (eq (car dependency) :feature)) (dep-name (third dependency)))
        ((and (consp dependency) (member (car dependency) '(:version :require))) (dep-name (second dependency)))))

(defun find-or-install (name)
  (or (asdf:find-system name NIL)
      (let ((system (ql-dist:find-system name)))
        (when system
          (ql-dist:ensure-installed system)
          (asdf:find-system name NIL)))))

(defun dependency-systems (root)
  "Every system ROOT depends on, by name, whatever the platform."
  (let ((seen (make-hash-table :test 'equal))
        (systems ()))
    (labels ((walk (name)
               (let ((name (string-downcase name)))
                 (unless (gethash name seen)
                   (setf (gethash name seen) T)
                   (let ((system (handler-bind ((warning #'muffle-warning))
                                   (ignore-errors (find-or-install name)))))
                     (when system
                       (push system systems)
                       (dolist (d (append (asdf:system-depends-on system)
                                          (asdf:system-defsystem-depends-on system)))
                         (let ((n (dep-name d))) (when n (walk n))))))))))
      (walk root))
    systems))

(defun release-directory (system)
  "The release folder SYSTEM's source is in, under a dist's software/, or NIL for a system
from elsewhere (this project, SBCL's contribs)."
  (let* ((dir (asdf:system-source-directory system))
         (parts (and dir (pathname-directory dir)))
         (at (position "software" parts :test #'equal)))
    (when (and at (< (1+ at) (length parts)))
      (make-pathname :directory (subseq parts 0 (+ at 2)) :name NIL :type NIL :defaults dir))))

(defun folder-name (directory)
  (car (last (pathname-directory directory))))

(defun project-name (release)
  "The release folder's name without its version: alloy-f4a8fc3d... is alloy,
flexichain-20201220-git is flexichain. A version in dots, as zpng-1.2.2, stays."
  (let ((name (if (uiop:string-suffix-p release "-git") (subseq release 0 (- (length release) 4)) release)))
    (let* ((dash (position #\- name :from-end T))
           (tail (and dash (subseq name (1+ dash)))))
      (if (and tail (<= 6 (length tail)) (every (lambda (c) (digit-char-p c 16)) tail))
          (subseq name 0 dash)
          name))))

(defun licence-files (directory)
  (sort (remove-if-not (lambda (file)
                         (let ((name (string-upcase (pathname-name file))))
                           (or (uiop:string-prefix-p "LICEN" name)
                               (uiop:string-prefix-p "COPYING" name)
                               (uiop:string-prefix-p "COPYRIGHT" name)
                               (uiop:string-prefix-p "UNLICENSE" name))))
                       (uiop:directory-files directory))
        #'string< :key #'file-namestring))

(defun read-text (file)
  (string-right-trim '(#\Space #\Newline #\Return #\Tab)
                     (remove #\Return (uiop:read-file-string file :external-format :utf-8))))

(defun normalise (text)
  (with-output-to-string (out)
    (let ((space NIL))
      (loop for c across text
            do (if (member c '(#\Space #\Newline #\Tab #\Return))
                   (setf space T)
                   (progn (when space (write-char #\Space out) (setf space NIL))
                          (write-char c out)))))))

(defstruct release name project systems licences texts)

(defun overrides ()
  (with-open-file (in (merge-pathnames "notices/overrides.lisp" *root*) :external-format :utf-8)
    (let ((*read-eval* NIL)) (read in))))

(defun apply-override (release entry)
  "Give RELEASE, which has no licence file, the copyright and licence text ENTRY names."
  (destructuring-bind (&key copyright text licence) (rest entry)
    (when licence (push licence (release-licences release)))
    (setf (release-texts release)
          (list (if text
                    (format NIL "~a~2%~a" copyright (read-text (merge-pathnames (format NIL "notices/~a.txt" text) *root*)))
                    copyright)))))

(defun releases ()
  "The releases the game depends on, by project name."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (system (dependency-systems "hexmaw"))
      (let ((dir (release-directory system)))
        (when dir
          (let ((release (or (gethash (folder-name dir) table)
                             (setf (gethash (folder-name dir) table)
                                   (make-release :name (folder-name dir)
                                                 :project (project-name (folder-name dir))
                                                 :texts (mapcar #'read-text (licence-files dir)))))))
            (pushnew (asdf:component-name system) (release-systems release) :test #'string=)
            (let ((licence (asdf:system-license system)))
              (when licence (pushnew licence (release-licences release) :test #'string=)))))))
    (let ((overrides (overrides)))
      (sort (loop for r being the hash-values of table
                  for entry = (assoc (release-project r) overrides :test #'string=)
                  do (cond ((and entry (release-texts r))
                            (push (format NIL "~a has a licence file now: take it out of notices/overrides.lisp"
                                          (release-name r))
                                  *override-problems*))
                           (entry (apply-override r entry)))
                     (setf (release-systems r) (sort (release-systems r) #'string<)
                           (release-licences r) (sort (release-licences r) #'string<))
                  collect r)
            #'string< :key #'release-project))))


(defun copyleft-p (release)
  (flet ((marked (text) (some (lambda (m) (search m (string-upcase text))) *copyleft-markers*)))
    (or (some #'marked (release-licences release))
        (some (lambda (text) (marked (subseq text 0 (min 400 (length text))))) (release-texts release)))))

(defun problems (releases)
  (append
   *override-problems*
   (loop for r in releases
         when (null (release-texts r))
           collect (format NIL "~a (~{~a~^, ~}): no licence file; give it an entry in notices/overrides.lisp"
                           (release-name r) (release-licences r))
         when (and (copyleft-p r) (not (member (release-project r) *copyleft-allowed* :test #'string=)))
           collect (format NIL "~a: copyleft (~{~a~^, ~}), and not in *COPYLEFT-ALLOWED*"
                           (release-name r) (release-licences r)))
   ;; Whatever this image loaded must be in the file, on whichever platform it runs.
   (let ((listed (make-hash-table :test 'equal)))
     (dolist (r releases) (setf (gethash (release-name r) listed) T))
     (loop for name in (asdf:already-loaded-systems)
           for system = (asdf:find-system name NIL)
           for dir = (and system (release-directory system))
           when (and dir (not (gethash (folder-name dir) listed)))
             collect (format NIL "~a is loaded (from ~a) but not listed" name (folder-name dir))))))

(defun notices-text (releases)
  (let ((texts ()))                     ; (normalised label text users), in order of first use
    (dolist (r releases)
      (dolist (text (release-texts r))
        (let ((entry (find (normalise text) texts :key #'first :test #'string=)))
          (if entry
              (push (release-project r) (fourth entry))
              (setf texts (append texts (list (list (normalise text) (1+ (length texts)) text
                                                    (list (release-project r))))))))))
    (flet ((labels-of (r)
             (loop for text in (release-texts r)
                   collect (second (find (normalise text) texts :key #'first :test #'string=)))))
      (with-output-to-string (out)
        (write-string (read-text (merge-pathnames "notices/head.txt" *root*)) out)
        (format out "~2%==========================================================================~%")
        (format out "LISP LIBRARIES~2%")
        (format out "~a~%" (read-text (merge-pathnames "notices/libraries.txt" *root*)))
        (dolist (r releases)
          (format out "~%~a~%  release ~a~%  systems: ~{~a~^, ~}~%  licence: ~:[(not stated in its .asd)~;~:*~{~a~^; ~}~]~%  licence text: ~{[~d]~^, ~}~%"
                  (release-project r) (release-name r) (release-systems r)
                  (remove "?" (release-licences r) :test #'string=) (labels-of r)))
        (format out "~%==========================================================================~%")
        (format out "LISP LIBRARIES: LICENCE TEXTS~%")
        (dolist (entry texts)
          (destructuring-bind (normal label text users) entry
            (declare (ignore normal))
            (format out "~%--------------------------------------------------------------------------~%")
            (format out "[~d] ~{~a~^, ~}~2%~a~%" label (reverse users) text)))
        ;; The native libraries' own texts, as upstream ships them (head.txt says whose is whose).
        (format out "~%==========================================================================~%")
        (format out "NATIVE LIBRARIES: LICENCE TEXTS~%")
        (dolist (file (sort (uiop:directory-files (merge-pathnames "notices/native/" *root*))
                            #'string< :key #'file-namestring))
          (format out "~%--------------------------------------------------------------------------~%")
          (format out "~a~2%~a~%" (file-namestring file) (read-text file)))))))

(defun main (&key check)
  (let* ((releases (releases))
         (problems (problems releases))
         (text (notices-text releases))
         (file (merge-pathnames "THIRD-PARTY-NOTICES.txt" *root*)))
    (dolist (p problems) (format *error-output* "~&notices: ~a~%" p))
    (cond (check
           (let ((old (and (probe-file file) (uiop:read-file-string file :external-format :utf-8))))
             (unless (equal old text)
               (format *error-output* "~&notices: THIRD-PARTY-NOTICES.txt is out of date: run tools/notices and commit it~%")
               (push "out of date" problems)))
           (format T "~&notices: ~d releases~:[, all in order~;, ~:*~d problem~:p~]~%"
                   (length releases) (and problems (length problems))))
          (T
           (with-open-file (out file :direction :output :if-exists :supersede :external-format :utf-8)
             (write-string text out))
           (format T "~&notices: wrote ~a, ~d releases~%" (file-namestring file) (length releases))))
    (uiop:quit (if problems 1 0))))
