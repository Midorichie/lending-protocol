;; Title: Oracle Interface
;; Version: 0.1.1

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INVALID-PRICE (err u1001))
(define-constant ERR-STALE-PRICE (err u1002))
(define-constant ERR-INVALID-ADDRESS (err u1003))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant PRICE-VALIDITY-PERIOD u150) ;; ~25 minutes in blocks

;; Data vars
(define-data-var current-price uint u0)
(define-data-var last-update uint u0)
(define-data-var oracle-address principal CONTRACT-OWNER)

;; Public functions
(define-public (update-price (new-price uint))
    (begin
        (asserts! (is-eq tx-sender (var-get oracle-address)) ERR-NOT-AUTHORIZED)
        (asserts! (> new-price u0) ERR-INVALID-PRICE)
        (var-set current-price new-price)
        (var-set last-update block-height)
        (ok true)
    )
)

(define-public (set-oracle-address (new-oracle principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        ;; Validate the new oracle address is not null or zero address
        (asserts! (not (is-eq new-oracle 'SP000000000000000000002Q6VF78)) ERR-INVALID-ADDRESS)
        (var-set oracle-address new-oracle)
        (ok true)
    )
)

;; Read only functions
(define-read-only (get-price)
    (let
        (
            (price (var-get current-price))
            (last-update-block (var-get last-update))
        )
        (asserts! (> price u0) ERR-INVALID-PRICE)
        (asserts! (< (- block-height last-update-block) PRICE-VALIDITY-PERIOD) ERR-STALE-PRICE)
        (ok price)
    )
)

(define-read-only (get-last-update)
    (ok (var-get last-update))
)
