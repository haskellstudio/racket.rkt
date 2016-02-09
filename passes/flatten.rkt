#lang racket

(require "utils.rkt")

(provide flatten)

;; NOTE: Flatten doesn't completely flatten the program. Namely, it returns
;; programs with if-expressions, which have two program branches.

(define (flatten pgm)
  (match pgm
    [`(program ,e)
     (let-values ([(_ pgm e) (flatten-expr (hash) '() e)])
       ; (printf "collect-binds result: ~s~n" (collect-binds pgm))
       (let [(stats (reverse (cons `(return ,e) pgm)))]
         ; (printf "stats before remove-var-asgns: ~s~n" stats)
         ; (printf "stats after remove-var-asgns: ~s~n" (remove-var-asgns stats))
         `(program ,(set->list (collect-binds pgm)) ,@(remove-var-asgns stats))))]

    [_ (unsupported-form 'flatten pgm)]))

(define (collect-binds pgm)
  ; (printf "collect-binds: ~s~n" pgm)
  (match pgm
    [(list) (set)]

    [(cons `(assign ,x ,_) t)
     (set-add (collect-binds t) x)]

    [(cons `(if ,x ,pgm1 ,pgm2) t)
     (set-union (if (symbol? x) (set x) (set))
                (collect-binds pgm1)
                (collect-binds pgm2)
                (collect-binds t))]

    [_ (unsupported-form 'collect-binds pgm)]))

(define (arg? e) (or (fixnum? e) (symbol? e)))

(define (flatten-expr binds pgm expr)
  (match expr

    [(or (? fixnum?) (? boolean?))
     (values binds pgm expr)]

    [`(read)
     (let [(fresh (gensym "tmp"))]
       (values binds (cons `(assign ,fresh (read)) pgm) fresh))]

    [`(,(or '- 'not) ,e1)
     (let-values ([(binds pgm e1) (flatten-expr binds pgm e1)])
       (let [(fresh (gensym "tmp"))]
         (values binds (cons `(assign ,fresh (,(car expr) ,e1)) pgm) fresh)))]

    [`(,(or '+ 'eq?) ,e1 ,e2)
     (let-values ([(binds pgm e1) (flatten-expr binds pgm e1)])
       (let-values ([(binds pgm e2) (flatten-expr binds pgm e2)])
         (let [(fresh (gensym "tmp"))]
           (values binds (cons `(assign ,fresh (,(car expr) ,e1 ,e2)) pgm) fresh))))]

    [(? symbol?)
     (values binds pgm (hash-ref binds expr))]

    [`(let ([,var ,e1]) ,body)
     (let-values ([(binds pgm e1) (flatten-expr binds pgm e1)])
       (let [(fresh (gensym (string-append "tmp_" (symbol->string var) "_")))]
         (let-values ([(binds pgm body)
                       (flatten-expr (hash-set binds var fresh)
                                     (cons `(assign ,fresh ,e1) pgm)
                                     body)])
           (values binds pgm body))))]

    [`(if (eq? ,e1 ,e2) ,e3 ,e4)
     (let [(fresh (gensym "tmp-if"))]
       (let*-values [((binds pgm e1)  (flatten-expr binds pgm e1))
                     ((binds pgm e2)  (flatten-expr binds pgm e2))
                     ((_ pgm-t ret-t) (flatten-expr binds '() e3))
                     ((_ pgm-f ret-f) (flatten-expr binds '() e4))]
         (let* [(pgm-t (reverse (cons `(assign ,fresh ,ret-t) pgm-t)))
                (pgm-f (reverse (cons `(assign ,fresh ,ret-f) pgm-f)))]
           (values binds (cons `(if (eq? ,e1 ,e2) ,pgm-t ,pgm-f) pgm) fresh))))]

    [`(if ,e1 ,e2 ,e3)
     (let [(fresh (gensym "tmp-if"))]
       (let*-values ([(binds pgm e1) (flatten-expr binds pgm e1)]
                     [(_ pgm-t ret-t) (flatten-expr binds '() e2)]
                     [(_ pgm-f ret-f) (flatten-expr binds '() e3)])
         (let* [(pgm-t (reverse (cons `(assign ,fresh ,ret-t) pgm-t)))
                (pgm-f (reverse (cons `(assign ,fresh ,ret-f) pgm-f)))]
           (values binds (cons `(if (eq? ,e1 #t) ,pgm-t ,pgm-f) pgm) fresh))))]

    [_ (unsupported-form 'flatten-expr expr)]))

;; Remove statements in form (assign x y) where y is a variable.
;; Does this by renaming x with y in the statements that follow this statement.
;; Does not effect semantics - for simplification purposes only.
;; NOTE: Statements should be in order - e.g. don't pass the list returned by
;; flatten-expr, it needs to be reversed!
(define (remove-var-asgns stmts)
  (match stmts
    [(list) '()]

    [(cons `(assign ,x ,y) t)
     (if (symbol? y)
       (remove-var-asgns (rename-stmts x y t))
       (cons `(assign ,x ,y) (remove-var-asgns t)))]

    ;; FIXME: This is not quite right: Last statement of if branches are always
    ;; assignments to a variable. Disabling this for now.
    ; [(cons `(if ,e ,pgm-t ,pgm-f) t)
    ;  (cons `(if ,e ,(remove-var-asgns pgm-t) ,(remove-var-asgns pgm-f))
    ;        (remove-var-asgns t))]

    [(cons s t)
     (cons s (remove-var-asgns t))]))

;; Substitute y for x in stmts
(define (rename-stmts x y stmts)
  (match stmts
    [(list) '()]

    [(cons `(assign ,x1 ,y1) t)
     (cond [(eq? x1 x)
            (error 'rename-stmts "BUG: the variable seen in LHS: ~s in ~s~n" x stmts)]
           [else
            (cons `(assign ,x1 ,(rename-expr x y y1)) (rename-stmts x y t))])]

    [(cons `(return ,y1) t)
     (if (eq? y1 x)
       (cons `(return ,y) (rename-stmts x y t))
       (cons `(return ,y1) (rename-stmts x y t)))]

    [(cons `(if ,e1 ,pgm-t ,pgm-f) t)
     (cons `(if ,(rename-expr x y e1) ,(rename-stmts x y pgm-t) ,(rename-stmts x y pgm-f))
           (rename-stmts x y t))]

    [(cons unsupported _)
     (unsupported-form 'rename-stmts unsupported)]))

(define (rename-expr x y expr)
  (match expr
    [`(read) expr]

    [`(,(or '- 'not) ,e1)
     `(,(car expr) ,(rename-arg x y e1))]

    [`(,(or '+ 'eq?) ,e1 ,e2)
     `(,(car expr) ,(rename-arg x y e1) ,(rename-arg x y e2))]

    [(or (? fixnum?) (? boolean?) (? symbol?))
     (rename-arg x y expr)]

    [_ (unsupported-form 'rename-expr expr)]))

(define (rename-arg x y arg)
  (match arg
    [(or (? fixnum?) (? boolean?)) arg]
    [(? symbol?) (if (eq? arg x) y arg)]
    [_ (unsupported-form 'rename-arg arg)]))