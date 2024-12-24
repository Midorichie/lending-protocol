;; Title: Bitcoin Lending Protocol
;; Version: 0.2.3
;; Description: A lending protocol enabling Bitcoin-collateralized loans on Stacks

(use-trait ft-trait .sip-010-trait.sip-010-trait)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INVALID-LOAN (err u1001))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u1002))
(define-constant ERR-LOAN-NOT-FOUND (err u1003))
(define-constant ERR-ALREADY-DEFAULTED (err u1004))
(define-constant ERR-NOT-DEFAULTED (err u1005))
(define-constant ERR-WRONG-COLLATERAL (err u1006))
(define-constant ERR-ZERO-AMOUNT (err u1007))
(define-constant ERR-NO-ACTIVE-LOAN (err u1008))
(define-constant ERR-TRANSFER-FAILED (err u1009))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant COLLATERAL-RATIO u150) ;; 150%
(define-constant LIQUIDATION-RATIO u120) ;; 120%
(define-constant INTEREST-RATE u500) ;; 5% APR in basis points
(define-constant SECONDS-PER-YEAR u31536000)
(define-constant MINIMUM-COLLATERAL u1000000) ;; Minimum collateral in uSTX

;; Data vars
(define-data-var total-loans uint u0)
(define-data-var total-collateral uint u0)
(define-data-var last-price-update uint u0)
(define-data-var btc-price uint u0)
(define-data-var protocol-paused bool false)

;; Principal data maps
(define-map loans 
    principal 
    {
        collateral: uint,
        borrowed: uint,
        timestamp: uint,
        interest-rate: uint,
        last-payment: uint,
        status: (string-ascii 20)
    }
)

(define-map user-positions
    principal
    {
        total-borrowed: uint,
        total-collateral: uint,
        loan-count: uint,
        last-action: uint
    }
)

;; Administrative functions
(define-public (pause-protocol)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (var-set protocol-paused true))
    )
)

(define-public (resume-protocol)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (var-set protocol-paused false))
    )
)

(define-public (initialize-protocol (initial-price uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (> initial-price u0) ERR-ZERO-AMOUNT)
        (var-set btc-price initial-price)
        (var-set last-price-update block-height)
        (ok true)
    )
)

;; Core lending functions
(define-public (provide-collateral (amount uint))
    (let
        (
            (sender tx-sender)
            (position (default-to 
                { 
                    total-borrowed: u0, 
                    total-collateral: u0, 
                    loan-count: u0,
                    last-action: u0
                }
                (map-get? user-positions sender)
            ))
        )
        (begin
            ;; Check protocol conditions
            (asserts! (not (var-get protocol-paused)) ERR-NOT-AUTHORIZED)
            (asserts! (>= amount MINIMUM-COLLATERAL) ERR-INSUFFICIENT-COLLATERAL)
            
            ;; Handle the transfer first
            (try! (stx-transfer? amount sender (as-contract tx-sender)))
            
            ;; Update user position
            (map-set user-positions sender
                (merge position 
                    { 
                        total-collateral: (+ (get total-collateral position) amount),
                        last-action: block-height
                    }
                )
            )
            
            ;; Update protocol stats
            (var-set total-collateral (+ (var-get total-collateral) amount))
            
            (ok true)
        )
    )
)

(define-public (take-loan (borrow-amount uint))
    (let
        (
            (sender tx-sender)
            (required-collateral (calculate-required-collateral borrow-amount))
            (position (default-to 
                { 
                    total-borrowed: u0, 
                    total-collateral: u0, 
                    loan-count: u0,
                    last-action: u0
                }
                (map-get? user-positions sender)
            ))
        )
        (begin
            (asserts! (not (var-get protocol-paused)) ERR-NOT-AUTHORIZED)
            (asserts! (> borrow-amount u0) ERR-ZERO-AMOUNT)
            (asserts! (>= (get total-collateral position) required-collateral) ERR-INSUFFICIENT-COLLATERAL)
            
            ;; Transfer the borrowed amount
            (try! (as-contract (stx-transfer? borrow-amount (as-contract tx-sender) sender)))
            
            ;; Create the loan
            (map-set loans sender
                {
                    collateral: required-collateral,
                    borrowed: borrow-amount,
                    timestamp: block-height,
                    interest-rate: INTEREST-RATE,
                    last-payment: block-height,
                    status: "active"
                }
            )
            
            ;; Update user position
            (map-set user-positions sender
                (merge position 
                    {
                        total-borrowed: (+ (get total-borrowed position) borrow-amount),
                        loan-count: (+ (get loan-count position) u1),
                        last-action: block-height
                    }
                )
            )
            
            ;; Update protocol stats
            (var-set total-loans (+ (var-get total-loans) u1))
            
            (ok true)
        )
    )
)

(define-public (repay-loan (payment uint))
    (let
        (
            (sender tx-sender)
            (loan (unwrap! (map-get? loans sender) ERR-LOAN-NOT-FOUND))
            (position (unwrap! (map-get? user-positions sender) ERR-LOAN-NOT-FOUND))
        )
        (begin
            (asserts! (not (var-get protocol-paused)) ERR-NOT-AUTHORIZED)
            (asserts! (> payment u0) ERR-ZERO-AMOUNT)
            (asserts! (is-eq (get status loan) "active") ERR-INVALID-LOAN)
            
            (let
                (
                    (interest-owed (calculate-interest loan))
                    (total-owed (+ (get borrowed loan) interest-owed))
                )
                ;; Handle the payment transfer
                (try! (stx-transfer? payment sender (as-contract tx-sender)))
                
                ;; Process the payment
                (if (>= payment total-owed)
                    (close-loan sender loan position)
                    (update-loan-payment sender loan payment)
                )
            )
        )
    )
)

;; Read only functions
(define-read-only (get-loan-data (borrower principal))
    (map-get? loans borrower)
)

(define-read-only (get-user-position (user principal))
    (map-get? user-positions user)
)

(define-read-only (get-protocol-stats)
    (ok {
        total-loans: (var-get total-loans),
        total-collateral: (var-get total-collateral),
        btc-price: (var-get btc-price),
        last-price-update: (var-get last-price-update),
        is-paused: (var-get protocol-paused)
    })
)

(define-read-only (calculate-required-collateral (borrow-amount uint))
    (let
        (
            (btc-current-price (var-get btc-price))
        )
        (/
            (* borrow-amount COLLATERAL-RATIO)
            u100
        )
    )
)

(define-read-only (calculate-liquidation-price (loan-amount uint) (collateral-amount uint))
    (/
        (* loan-amount LIQUIDATION-RATIO)
        (* collateral-amount u100)
    )
)

;; Private functions
(define-private (calculate-interest (loan {collateral: uint, borrowed: uint, timestamp: uint, interest-rate: uint, last-payment: uint, status: (string-ascii 20)}))
    (let
        (
            (time-elapsed (- block-height (get last-payment loan)))
            (interest-rate (get interest-rate loan))
            (borrowed (get borrowed loan))
        )
        (/
            (* (* borrowed interest-rate) time-elapsed)
            (* u10000 SECONDS-PER-YEAR))
    )
)

(define-private (close-loan (borrower principal) (loan {collateral: uint, borrowed: uint, timestamp: uint, interest-rate: uint, last-payment: uint, status: (string-ascii 20)}) (position {total-borrowed: uint, total-collateral: uint, loan-count: uint, last-action: uint}))
    (let
        (
            (collateral-amount (get collateral loan))
            (borrowed-amount (get borrowed loan))
        )
        (begin
            ;; Delete the loan first
            (map-delete loans borrower)
            
            ;; Update user position
            (map-set user-positions borrower
                (merge position 
                    {
                        total-borrowed: (- (get total-borrowed position) borrowed-amount),
                        total-collateral: (- (get total-collateral position) collateral-amount),
                        loan-count: (- (get loan-count position) u1),
                        last-action: block-height
                    }
                )
            )
            
            ;; Update protocol stats
            (var-set total-loans (- (var-get total-loans) u1))
            (var-set total-collateral (- (var-get total-collateral) collateral-amount))
            
            ;; Return collateral to borrower
            (as-contract (stx-transfer? collateral-amount (as-contract tx-sender) borrower))
        )
    )
)

(define-private (update-loan-payment (borrower principal) (loan {collateral: uint, borrowed: uint, timestamp: uint, interest-rate: uint, last-payment: uint, status: (string-ascii 20)}) (payment uint))
    (begin
        (map-set loans borrower
            (merge loan 
                {
                    borrowed: (- (get borrowed loan) payment),
                    last-payment: block-height
                }
            )
        )
        (ok true)
    )
)
