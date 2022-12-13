;;; -*- Mode:Lisp; Syntax:ANSI-Common-Lisp; Coding:utf-8; Package:Varray -*-
;;;; primal.lisp

(in-package #:varray)

"Definitions of virtual arrays derived solely from their input parameters and not based on other arrays."

(defclass vapri-integer-progression (varray-primal)
  ((%number :accessor vapip-number
            :initform 1
            :initarg :number
            :documentation "The number of values.")
   (%origin :accessor vapip-origin
            :initform 0
            :initarg :origin
            :documentation "The origin point - by default, the index origin.")
   (%offset :accessor vapip-offset
            :initform 0
            :initarg :offset
            :documentation "The offset - an amount added to or subtracted from each value.")
   (%factor :accessor vapip-factor
            :initform 1
            :initarg :factor
            :documentation "Factor of values.")
   (%repeat :accessor vapip-repeat
            :initform 1
            :initarg :repeat
            :documentation "Instances of each value."))
  (:metaclass va-class)
  (:documentation "Integer progression vector - a series of numeric values generated by [⍳ index]."))

(defmethod etype-of ((vvector vapri-integer-progression))
  (if (floatp (vapip-factor vvector))
      'double-float (list 'integer (min 0 (+ (vapip-offset vvector)
                                             (vapip-origin vvector)))
                          (max (vapip-offset vvector)
                               (+ (vapip-origin vvector)
                                  (+ (vapip-offset vvector)
                                     (* (vapip-factor vvector)
                                        (first (shape-of vvector)))))))))

(defmethod prototype-of ((vvector vapri-integer-progression))
  (declare (ignore vvector))
  0)

;; the shape of an IP vector is its number times its repetition
(defmethod shape-of ((vvector vapri-integer-progression))
  ;; TODO: it's still possible to create something like ⍳¯5, the error doesn't happen
  ;; until it's rendered - is there a better way to implement this check?
  (when (not (and (integerp (vapip-number vvector))
                  (or (zerop (vapip-number vvector))
                      (plusp (vapip-number vvector)))))
    (error "The argument to [⍳ index] must be an integer 0 or higher."))
  (get-promised (varray-shape vvector) (list (* (vapip-number vvector)
                                                (vapip-repeat vvector)))))

;; the IP vector's parameters are used to index its contents
(defmethod generator-of ((vvector vapri-integer-progression) &optional indexers params)
  (declare (ignore params indexers) (optimize (speed 3) (safety 0)))
  (let* ((origin (the (unsigned-byte 62) (vapip-origin vvector)))
         (offset (the (unsigned-byte 62) (vapip-offset vvector)))
         (factor (the real (vapip-factor vvector)))
         (repeat (the (unsigned-byte 62) (vapip-repeat vvector)))
         (indexer (funcall (if (or (and (integerp factor) (= 1 factor))
                                   (and (typep factor 'single-float) (= 1.0 factor))
                                   (and (typep factor 'double-float) (= 1.0d0 factor)))
                               (if (zerop offset)
                                   #'identity (lambda (fn)
                                                (lambda (item) (+ offset (funcall fn item)))))
                               (if (integerp factor)
                                   (lambda (fn) (lambda (item)
                                                  (declare (type (unsigned-byte 62) item))
                                                  (+ offset
                                                     (* (the (unsigned-byte 62) factor)
                                                        (the (unsigned-byte 62)
                                                             (funcall (the function fn) item))))))
                                   (lambda (fn) (lambda (item)
                                                  (declare (type (unsigned-byte 62) item)
                                                           (type function fn))
                                                  (+ offset (* (the float factor)
                                                               (funcall fn item)))))))
                           (if (= 1 repeat)
                               (if (zerop origin)
                                   #'identity
                                   (lambda (index)
                                     (declare (type (unsigned-byte 62) index))
                                     (the (unsigned-byte 64) (+ origin index))))
                               (lambda (index)
                                 (declare (type (unsigned-byte 62) index))
                                 (the (unsigned-byte 64)
                                      (+ origin (the (unsigned-byte 62)
                                                     (floor index repeat)))))))))
    (case (getf params :format)
      (:encoded (setf (getf params :format) :linear)
       (generator-of vvector nil params))
      (:linear indexer)
      (t indexer))))

(deftype fast-iota-sum-fixnum ()
  "The largest integer that can be supplied to fast-iota-sum without causing a fixnum overflow"
  '(integer 0 #.(isqrt (* 2 most-positive-fixnum))))

(declaim (ftype (function (fast-iota-sum-fixnum) fixnum) fast-iota-sum))
(defun fast-iota-sum (n)
  "Fast version of iota-sum for integers of type fast-iota-sum-fixnum"
  (declare (optimize (speed 3) (safety 0)))
  (if (oddp n)
      (* n (the fixnum (/ (1+ n) 2)))
    (let ((n/2 (the fixnum (/ n 2))))
      (+ (* n n/2) n/2))))

(defun iota-sum (n index-origin)
  "Fast implementation of +/⍳X."
  (cond ((< n 0)
	 (error "The argument to [⍳ index] must be a positive integer, i.e. ⍳9, or a vector, i.e. ⍳2 3."))
	((= n 0) 0)
	((= n 1) index-origin)
	((typep n 'fast-iota-sum-fixnum)
	 (if (= index-origin 1) (fast-iota-sum n)
	     (fast-iota-sum (1- n))))
	(t (* n (/ (+ n index-origin index-origin -1) 2)))))

(defmethod get-reduced ((vvector vapri-integer-progression) function)
  (let ((fn-meta (funcall function :get-metadata)))
    ;; (print (list :ff fn-meta))
    (case (getf fn-meta :lexical-reference)
      (#\+ (iota-sum (vapip-number vvector) (vapip-origin vvector)))
      ;; TODO: extend below to support any ⎕IO
      (#\× (sprfact (+ (vapip-number vvector) (- (vapip-origin vvector) 1))))
      (t (let* ((generator (generator-of vvector))
                (output (funcall generator 0)))
           (loop :for i :from 1 :below (vapip-number vvector)
                 :do (setf output (funcall function (funcall generator i) output)))
           output)))))
      
(defclass vapri-coordinate-vector (varray-primal)
  ((%reference :accessor vacov-reference
               :initform nil
               :initarg :reference
               :documentation "The array to which this coordinate vector belongs.")
   (%index :accessor vacov-index
           :initform 0
           :initarg :index
           :documentation "The row-major index of the referenced array this coordinate vector represents."))
  (:metaclass va-class)
  (:documentation "Coordinate vector - a vector of the integer coordinates corresponding to a given row-major index in an array."))

(defmethod etype-of ((vvector vapri-coordinate-vector))
  "The type of the coordinate vector."
  ;; if this refers to a [⍸ where] invocation, it is based on the shape of the argument to [⍸ where];
  ;; it cannot directly reference the argument because the [⍸ where] invocation" because the dimensional
  ;; factors are stored along with the [⍸ where] object
  (list 'integer 0 (reduce #'max (if (typep (vacov-reference vvector) 'vader-where)
                                     (shape-of (vader-base (vacov-reference vvector)))
                                     (shape-of (vacov-reference vvector))))))

(defmethod prototype-of ((vvector vapri-coordinate-vector))
  (declare (ignore vvector))
  0)

(defmethod shape-of ((vvector vapri-coordinate-vector))
  (get-promised (varray-shape vvector)
                (list (length (vads-dfactors (vacov-reference vvector))))))

(defmethod generator-of ((vvector vapri-coordinate-vector) &optional indexers params)
  (let* ((dfactors (vads-dfactors (vacov-reference vvector)))
         (output (make-array (length dfactors) :element-type (etype-of vvector)))
         (remaining (vacov-index vvector)))
    (loop :for f :across dfactors :for ix :from 0
          :do (multiple-value-bind (item remainder) (floor remaining f)
                (setf (aref output ix) (+ item (vads-io (vacov-reference vvector)))
                      remaining remainder)))
    (lambda (index) (aref output index))))

(defclass vapri-coordinate-identity (vad-subrendering varray-primal vad-with-io vad-with-dfactors)
  ((%shape :accessor vapci-shape
           :initform 1
           :initarg :number
           :documentation "The shape of the array."))
  (:metaclass va-class)
  (:documentation "Coordinate identity array - an array of coordinate vectors generated by [⍳ index]."))

(defmethod etype-of ((varray vapri-coordinate-identity))
  "Being a nested array, the type is always t."
  (declare (ignore varray))
  t)

(defmethod prototype-of ((varray vapri-coordinate-identity))
  "Prototype is an array of zeroes with length equal to the array's rank."
  (make-array (length (vapci-shape varray)) :element-type 'bit :initial-element 0))

(defmethod shape-of ((varray vapri-coordinate-identity))
  "Shape is explicit; dimensional factors are generated by this function if not set."
  (unless (vads-dfactors varray)
    (setf (vads-dfactors varray)
          (get-dimensional-factors (vapci-shape varray) t)))
  (get-promised (varray-shape varray)
                (vapci-shape varray)))

(defmethod generator-of ((varray vapri-coordinate-identity) &optional indexers params)
  "Each index returns a coordinate vector."
  (lambda (index) (make-instance 'vapri-coordinate-vector
                                 :reference varray :index index)))

(defclass vapri-axis-vector (vad-subrendering varray-primal vad-with-io vad-with-dfactors)
  ((%reference :accessor vaxv-reference
               :initform nil
               :initarg :reference
               :documentation "The array to which this axis vector belongs.")
   (%axis :accessor vaxv-axis
          :initform nil
          :initarg :axis
          :documentation "The axis along which the axis vector leads.")
   (%window :accessor vaxv-window
            :initform nil
            :initarg :window
            :documentation "The window of division along the axis.")
   (%index :accessor vaxv-index
           :initform nil
           :initarg :index
           :documentation "This axis vector's index within the reference array reduced along the axis."))
  (:metaclass va-class)
  (:documentation "A sub-vector along an axis of an array."))

(defmethod etype-of ((varray vapri-axis-vector))
  (etype-of (vaxv-reference varray)))

(defmethod shape-of ((varray vapri-axis-vector))
  (get-promised (varray-shape varray)
                (list (or (vaxv-window varray)
                          (nth (vaxv-axis varray) (shape-of (vaxv-reference varray)))))))

(defmethod generator-of ((varray vapri-axis-vector) &optional indexers params)
  (let* ((axis (vaxv-axis varray))
         (window (vaxv-window varray))
         (wsegment)
         (ref-index (vaxv-index varray))
         (ref-indexer (generator-of (vaxv-reference varray)))
         (irank (rank-of (vaxv-reference varray)))
         (idims (shape-of (vaxv-reference varray)))
         (rlen (nth axis idims))
         (increment (reduce #'* (nthcdr (1+ axis) idims))))
    (loop :for dim :in idims :for dx :from 0
          :when (and window (= dx axis))
            :do (setq wsegment (- dim (1- window))))
    (let ((delta (+ (if window (* rlen (floor ref-index wsegment))
                        (if (= 1 increment)
                            0 (* (floor ref-index increment)
                                 (- (* increment rlen) increment))))
                    (if (/= 1 increment) ref-index
                        (if window (if (>= 1 irank) ref-index
                                       (mod ref-index wsegment))
                            (* ref-index rlen))))))
      (lambda (index) (funcall ref-indexer (+ delta (* index increment)))))))
