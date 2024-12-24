;; Title: SIP-010 Trait Definition
;; Description: Local definition of the SIP-010 fungible token trait

(define-trait sip-010-trait
    (
        ;; Transfer from the caller to a new principal
        (transfer (uint principal principal (optional (buff 34))) (response bool uint))

        ;; Get the token balance of the specified principal
        (get-balance (principal) (response uint uint))

        ;; Get the current total supply
        (get-total-supply () (response uint uint))

        ;; Get the token decimals
        (get-decimals () (response uint uint))

        ;; Get the token URI
        (get-token-uri () (response (optional (string-utf8 256)) uint))

        ;; Get the token name
        (get-name () (response (string-ascii 32) uint))

        ;; Get the token symbol
        (get-symbol () (response (string-ascii 32) uint))
    )
)
