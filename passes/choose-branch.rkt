#lang racket

(require "utils.rkt")

(provide choose-branch)

;; TODO: I'm very tired right now -- this does more than what it advertises --
;; it simplifies eq?s etc.

(define (choose-branch pgm)
  (match pgm
    [`(program ,e)
     `(program ,(choose-branch-expr e))]
    [_ (unsupported-form 'choose-branch pgm)]))

;; TODO: We can be much more aggressive here, by doing a simple form of
;; compile-time evaluation.
(define (choose-branch-expr e0)
  (match e0

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; Important cases

    [`(if ,e1 ,e2 ,e3)
     (match (choose-branch-expr e1)
       [#t (choose-branch-expr e2)]
       [#f (choose-branch-expr e3)]
       [e1 `(if ,e1 ,(choose-branch-expr e2) ,(choose-branch-expr e3))])]

    [`(eq? ,e1 ,e2)
     (let [(e1 (choose-branch-expr e1))
           (e2 (choose-branch-expr e2))]
       (cond [(and (or (fixnum? e1) (boolean? e1))
                   (or (fixnum? e2) (boolean? e2)))
              (equal? e1 e2)]

             [(and (symbol? e1) (symbol? e2) (equal? e1 e2))
              #t]

             [else `(eq? ,e1 ,e2)]))]

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; Simple cases

    [(or (? fixnum?) (? boolean?) (? symbol?) `(read))
     e0]

    [`(,(or '- 'not) ,e1)
     (list (car e0) (choose-branch-expr e1))]

    [`(+ ,e1 ,e2)
     (list '+ (choose-branch-expr e1) (choose-branch-expr e2))]

    [`(let ([,var ,e1]) ,body)
     `(let ([,var ,(choose-branch-expr e1)]) ,(choose-branch-expr body))]

    [_ (unsupported-form 'choose-branch-expr e0)]))