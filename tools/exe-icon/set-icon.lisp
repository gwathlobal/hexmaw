;;;; Give a Windows executable an icon, by writing a PE file directly.
;;;;
;;;; From Malgorod's tools/exe-icon. Loaded by tools/exe-icon/iconed-runtime.lisp on
;;;; Windows (tools/build-dist), which runs SET-EXE-ICON on a copy of the
;;;; SBCL runtime and then builds the game with that copy, so the icon is in
;;;; hexmaw.exe before the core is appended to it. Two things the obvious
;;;; routes cannot do decide the shape of this file:
;;;;
;;;; - The icon cannot go into hexmaw.exe after the save. SAVE-LISP-AND-DIE
;;;;   writes the runtime and appends the core behind it, and the runtime finds
;;;;   its core by an offset in a trailer at the end of the file; anything that
;;;;   grows the PE image moves the core out from under that offset, and the
;;;;   Windows resource API discards data past the image outright.
;;;;
;;;; - Nor can the Windows resource API (BeginUpdateResource, and rcedit and
;;;;   Resource Hacker, which are built on it) put it into the runtime.
;;;;   EndUpdateResource can only grow .rsrc in place when it is the last
;;;;   section, and sbcl.exe's .rsrc - a manifest and nothing else - is
;;;;   followed by .reloc, MinGW's debug sections and a COFF symbol table.
;;;;   It refuses with ERROR_CANT_MOVE_SECTION.
;;;;
;;;; So this leaves every existing section where it is and adds one more at the
;;;; end of the file, holding the whole resource tree - whatever the runtime
;;;; already had, the manifest above all, plus the icon - and points the
;;;; resource data directory at it. The old .rsrc stays in the file, unread.
;;;; It needs nothing from Windows, so it runs and is checked anywhere:
;;;; `7z l` on the result lists the resources the way Explorer will find them.

(defpackage #:hexmaw-exe-icon
  (:use #:cl)
  (:export #:set-exe-icon))

(in-package #:hexmaw-exe-icon)

(defconstant +rt-icon+ 3)
(defconstant +rt-group-icon+ 14)
;; The id the icon group goes in as. Explorer takes the first group in the
;; directory, and with no named groups that is the lowest id. (The game window's
;; own icon is set at launch from data/icon/hexmaw-64.png instead.)
(defconstant +group-id+ 1)
(defconstant +lang-neutral+ 0)
(defconstant +resource-directory-index+ 2)

;;; Octets

(defun read-octets (path)
  (with-open-file (in path :element-type '(unsigned-byte 8))
    (let ((v (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence v in)
      v)))

(defun write-octets (octets path)
  (with-open-file (out path :element-type '(unsigned-byte 8)
                            :direction :output :if-exists :supersede)
    (write-sequence octets out)))

(defun u (v i n)
  (loop for k below n sum (ash (aref v (+ i k)) (* 8 k))))

(defun (setf u) (value v i n)
  (dotimes (k n value)
    (setf (aref v (+ i k)) (ldb (byte 8 (* 8 k)) value))))

(defun u16 (v i) (u v i 2))
(defun u32 (v i) (u v i 4))
(defun (setf u16) (value v i) (setf (u v i 2) value))
(defun (setf u32) (value v i) (setf (u v i 4) value))

(defun align (n to)
  (* to (ceiling n to)))

(defun subseq-octets (v start length)
  (subseq v start (+ start length)))

;;; The PE headers, as offsets into the file

(defstruct (pe (:constructor %make-pe))
  octets coff opt sections section-count section-alignment file-alignment
  data-directories)

(defun parse-pe (octets)
  (unless (and (> (length octets) #x40) (= (u16 octets 0) #x5A4D))
    (error "Not an executable: no MZ header."))
  (let* ((pe-offset (u32 octets #x3C))
         (coff (+ pe-offset 4))
         (opt (+ coff 20))
         (magic (u16 octets opt)))
    (unless (= (u32 octets pe-offset) #x00004550)
      (error "Not a PE executable: no PE signature."))
    (%make-pe :octets octets
              :coff coff
              :opt opt
              :sections (+ opt (u16 octets (+ coff 16)))
              :section-count (u16 octets (+ coff 2))
              :section-alignment (u32 octets (+ opt 32))
              :file-alignment (u32 octets (+ opt 36))
              :data-directories (+ opt (ecase magic
                                         (#x10B 96)     ; PE32
                                         (#x20B 112)))))) ; PE32+

(defun section-header (pe i)
  (+ (pe-sections pe) (* 40 i)))

(defun rva-to-offset (pe rva)
  (let ((v (pe-octets pe)))
    (dotimes (i (pe-section-count pe) (error "RVA #x~X is in no section." rva))
      (let* ((h (section-header pe i))
             (va (u32 v (+ h 12)))
             (size (max (u32 v (+ h 8)) (u32 v (+ h 16)))))
        (when (<= va rva (1- (+ va size)))
          (return (+ (u32 v (+ h 20)) (- rva va))))))))

(defun data-directory (pe index)
  (let ((d (+ (pe-data-directories pe) (* 8 index))))
    (values (u32 (pe-octets pe) d) (u32 (pe-octets pe) (+ d 4)))))

;;; The resource tree: a flat list of entries, each one resource

(defstruct res type name lang codepage data)

(defun read-resource-string (v offset)
  (let ((n (u16 v offset)))
    (map 'string (lambda (i) (code-char (u16 v (+ offset 2 (* 2 i)))))
         (loop for i below n collect i))))

(defun read-resources (pe)
  "Every resource PE already holds, as RES structs."
  (multiple-value-bind (rva size) (data-directory pe +resource-directory-index+)
    (when (zerop size)
      (return-from read-resources nil))
    (let ((v (pe-octets pe))
          (base (rva-to-offset pe rva))
          (out '()))
      (labels ((entries (dir)
                 (loop with n = (+ (u16 v (+ dir 12)) (u16 v (+ dir 14)))
                       for i below n
                       for e = (+ dir 16 (* 8 i))
                       for name = (u32 v e)
                       collect (cons (if (logbitp 31 name)
                                         (read-resource-string v (+ base (ldb (byte 31 0) name)))
                                         name)
                                     (u32 v (+ e 4)))))
               (subdir (child)
                 (unless (logbitp 31 child)
                   (error "Malformed resource directory: a leaf where a directory belongs."))
                 (+ base (ldb (byte 31 0) child))))
        (loop for (type . c1) in (entries base)
              do (loop for (name . c2) in (entries (subdir c1))
                       do (loop for (lang . leaf) in (entries (subdir c2))
                                for d = (+ base leaf)
                                do (push (make-res :type type :name name :lang lang
                                                   :codepage (u32 v (+ d 8))
                                                   :data (subseq-octets
                                                          v (rva-to-offset pe (u32 v d))
                                                          (u32 v (+ d 4))))
                                         out)))))
      (nreverse out))))

(defun key< (a b)
  "Resource directory order: named entries first, by name, then ids ascending."
  (cond ((and (stringp a) (stringp b)) (string< a b))
        ((stringp a) t)
        ((stringp b) nil)
        (t (< a b))))

(defun group-by (key list)
  (let ((groups '()))
    (dolist (x list)
      (let ((g (assoc (funcall key x) groups :test #'equal)))
        (if g (push x (cdr g)) (push (list (funcall key x) x) groups))))
    (sort (mapcar (lambda (g) (cons (car g) (reverse (cdr g)))) groups)
          #'key< :key #'car)))

(defun build-resource-section (resources section-rva)
  "The octets of a resource section at SECTION-RVA holding RESOURCES:
directories, then data entries, then names, then the data, in that order."
  (let* ((tree (mapcar (lambda (types)
                         (cons (car types)
                               (mapcar (lambda (names)
                                         (cons (car names)
                                               (sort (copy-list (cdr names)) #'key<
                                                     :key #'res-lang)))
                                       (group-by #'res-name (cdr types)))))
                       (group-by #'res-type resources)))
         (dir-size (lambda (n) (+ 16 (* 8 n))))
         (dirs-size (+ (funcall dir-size (length tree))
                       (loop for (nil . names) in tree
                             sum (+ (funcall dir-size (length names))
                                    (loop for (nil . langs) in names
                                          sum (funcall dir-size (length langs)))))))
         (entries-offset dirs-size)
         (strings-offset (+ entries-offset (* 16 (length resources))))
         (strings (remove-duplicates
                   (remove-if-not #'stringp
                                  (loop for r in resources collect (res-type r) collect (res-name r)))
                   :test #'string=))
         (string-offsets (let ((at strings-offset))
                           (loop for s in strings
                                 collect (cons s at)
                                 do (incf at (+ 2 (* 2 (length s)))))))
         (data-offset (align (loop with at = strings-offset
                                   for s in strings do (incf at (+ 2 (* 2 (length s))))
                                   finally (return at))
                             8))
         (data-offsets (let ((at data-offset))
                         (loop for r in resources
                               collect (cons r at)
                               do (setf at (align (+ at (length (res-data r))) 8)))))
         (total (loop for (r . at) in data-offsets
                      maximize (+ at (length (res-data r))) into m
                      finally (return (max m data-offset))))
         (v (make-array total :element-type '(unsigned-byte 8) :initial-element 0))
         (next-dir 0)
         (next-entry entries-offset))
    (labels ((name-field (key)
               (if (stringp key)
                   (logior (ash 1 31) (cdr (assoc key string-offsets :test #'string=)))
                   key))
             (write-dir (children write-child)
               ;; CHILDREN is ((key . whatever) ...) in directory order.
               (let ((at next-dir)
                     (named (count-if #'stringp children :key #'car)))
                 (incf next-dir (funcall dir-size (length children)))
                 (setf (u16 v (+ at 12)) named
                       (u16 v (+ at 14)) (- (length children) named))
                 (loop for child in children
                       for e = (+ at 16) then (+ e 8)
                       do (setf (u32 v e) (name-field (car child))
                                (u32 v (+ e 4)) (funcall write-child child)))
                 at))
             (write-leaf (r)
               (let ((at next-entry))
                 (incf next-entry 16)
                 (setf (u32 v at) (+ section-rva (cdr (assoc r data-offsets)))
                       (u32 v (+ at 4)) (length (res-data r))
                       (u32 v (+ at 8)) (res-codepage r))
                 at)))
      ;; Each directory takes its own space from NEXT-DIR before it writes any
      ;; of its children: it needs their offsets for its entries, and they
      ;; must not land on top of it.
      (write-dir tree
                 (lambda (type)
                   (logior (ash 1 31)
                           (write-dir (cdr type)
                                      (lambda (name)
                                        (logior (ash 1 31)
                                                (write-dir (mapcar (lambda (r) (cons (res-lang r) r))
                                                                   (cdr name))
                                                           (lambda (lang) (write-leaf (cdr lang))))))))))
      (loop for (s . at) in string-offsets
            do (setf (u16 v at) (length s))
               (loop for ch across s
                     for i from (+ at 2) by 2
                     do (setf (u16 v i) (char-code ch))))
      (loop for (r . at) in data-offsets
            do (replace v (res-data r) :start1 at)))
    v))

;;; The icon

(defun icon-resources (ico)
  "An .ico file's images as RT_ICON resources numbered from 1, and the
RT_GROUP_ICON directory that names them."
  (let ((v (read-octets ico)))
    (unless (and (= (u16 v 0) 0) (= (u16 v 2) 1))
      (error "~A is not an .ico file." ico))
    (let* ((n (u16 v 4))
           (group (make-array (+ 6 (* 14 n)) :element-type '(unsigned-byte 8) :initial-element 0))
           (icons '()))
      (setf (u16 group 2) 1
            (u16 group 4) n)
      (dotimes (i n)
        (let ((e (+ 6 (* 16 i)))
              (g (+ 6 (* 14 i)))
              (id (1+ i)))
          ;; The first twelve bytes of an entry are the same in both
          ;; directories; the group has the resource id where the file has
          ;; the image's offset.
          (replace group v :start1 g :start2 e :end2 (+ e 12))
          ;; Pillow writes 0 planes for a PNG image; Windows' own tools write
          ;; 1, and the size matching that picks an image reads it.
          (when (zerop (u16 group (+ g 4)))
            (setf (u16 group (+ g 4)) 1))
          (setf (u16 group (+ g 12)) id)
          (push (make-res :type +rt-icon+ :name id :lang +lang-neutral+ :codepage 0
                          :data (subseq-octets v (u32 v (+ e 12)) (u32 v (+ e 8))))
                icons)))
      (cons (make-res :type +rt-group-icon+ :name +group-id+ :lang +lang-neutral+
                      :codepage 0 :data group)
            (nreverse icons)))))

;;; The patch

(defun set-exe-icon (exe ico)
  "Rewrite EXE in place so that ICO is its icon, keeping every other resource
it has. Returns EXE."
  (let* ((pe (parse-pe (read-octets exe)))
         (v (pe-octets pe))
         (n (pe-section-count pe))
         (new-header (section-header pe n))
         (first-raw (loop for i below n
                          for p = (u32 v (+ (section-header pe i) 20))
                          when (plusp p) minimize p))
         (size-of-headers (u32 v (+ (pe-opt pe) 60))))
    ;; The new header goes into the slack between the section table and the
    ;; first section's data, which must be there and must be empty.
    (unless (and (<= (+ new-header 40) (min first-raw size-of-headers))
                 (every #'zerop (subseq-octets v new-header 40)))
      (error "~A has no room for another section header." exe))
    (let* ((resources (append (remove-if (lambda (r) (member (res-type r) (list +rt-icon+ +rt-group-icon+)))
                                         (read-resources pe))
                              (icon-resources ico)))
           (rva (align (loop for i below n
                             for h = (section-header pe i)
                             maximize (+ (u32 v (+ h 12)) (max (u32 v (+ h 8)) (u32 v (+ h 16)))))
                       (pe-section-alignment pe)))
           (section (build-resource-section resources rva))
           (raw-size (align (length section) (pe-file-alignment pe)))
           ;; At the end of the file, after the COFF symbol table: the loader
           ;; finds a section by its header, not by where it sits.
           (raw (align (length v) (pe-file-alignment pe)))
           (out (make-array (+ raw raw-size) :element-type '(unsigned-byte 8) :initial-element 0)))
      (replace out v)
      (replace out section :start1 raw)
      (replace out (map 'vector #'char-code ".rsrc2") :start1 new-header)
      (setf (u32 out (+ new-header 8)) (length section)
            (u32 out (+ new-header 12)) rva
            (u32 out (+ new-header 16)) raw-size
            (u32 out (+ new-header 20)) raw
            ;; initialized data, readable: what a linker gives .rsrc
            (u32 out (+ new-header 36)) #x40000040)
      (setf (u16 out (+ (pe-coff pe) 2)) (1+ n)
            ;; SizeOfImage
            (u32 out (+ (pe-opt pe) 56)) (align (+ rva (length section)) (pe-section-alignment pe))
            ;; CheckSum. Not checked for an executable, and SAVE-LISP-AND-DIE
            ;; appending the core would make any value here wrong anyway.
            (u32 out (+ (pe-opt pe) 64)) 0)
      (let ((d (+ (pe-data-directories pe) (* 8 +resource-directory-index+))))
        (setf (u32 out d) rva
              (u32 out (+ d 4)) (length section)))
      (write-octets out exe)
      exe)))
