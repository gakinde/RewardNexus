;; RewardNexus: Algorithmic Token Redistribution System
;; This contract implements a sophisticated token redistribution mechanism that rewards active participants
;; based on their holdings, participation score, and time-weighted contributions. The system uses
;; algorithmic rules to fairly distribute rewards from a redistribution pool funded by transaction fees.

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-balance (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-not-registered (err u103))
(define-constant err-already-registered (err u104))
(define-constant err-zero-address (err u105))
(define-constant err-redistribution-locked (err u106))
(define-constant err-no-rewards (err u107))
(define-constant err-invalid-percentage (err u108))

;; Redistribution fee percentage (2% = 200 basis points)
(define-constant redistribution-fee-bps u200)
(define-constant basis-points u10000)

;; Minimum holding period for rewards (in blocks)
(define-constant min-holding-period u144) ;; ~24 hours

;; data maps and vars

;; Track user balances
(define-map balances principal uint)

;; Track user participation scores (0-10000)
(define-map participation-scores principal uint)

;; Track last activity block for each user
(define-map last-activity-block principal uint)

;; Track registration status
(define-map registered-users principal bool)

;; Track total tokens held by each user over time (for time-weighted calculations)
(define-map cumulative-holdings principal uint)

;; Track last claim block for rewards
(define-map last-claim-block principal uint)

;; Track redistribution pool
(define-data-var redistribution-pool uint u0)

;; Track total supply
(define-data-var total-supply uint u0)

;; Track total registered users
(define-data-var total-registered-users uint u0)

;; Track if redistribution is active
(define-data-var redistribution-active bool true)

;; Track total participation score (sum of all users)
(define-data-var total-participation-score uint u0)

;; private functions

;; Calculate redistribution fee from amount
(define-private (calculate-fee (amount uint))
    (/ (* amount redistribution-fee-bps) basis-points)
)

;; Calculate net amount after fee
(define-private (calculate-net-amount (amount uint))
    (- amount (calculate-fee amount))
)

;; Update participation score based on activity
(define-private (update-participation-score (user principal))
    (let
        (
            (current-score (default-to u0 (map-get? participation-scores user)))
            (last-block (default-to block-height (map-get? last-activity-block user)))
            (blocks-since-activity (- block-height last-block))
        )
        ;; Decay score if inactive, boost if active
        (if (> blocks-since-activity u1000)
            ;; Decay by 10% if inactive for ~1 week
            (let ((new-score (/ (* current-score u9) u10)))
                (map-set participation-scores user new-score)
                (var-set total-participation-score 
                    (+ (- (var-get total-participation-score) current-score) new-score))
                new-score
            )
            ;; Boost by 1% up to max 10000
            (let ((new-score (if (< current-score u10000)
                                (+ current-score (/ current-score u100))
                                u10000)))
                (map-set participation-scores user new-score)
                (var-set total-participation-score 
                    (+ (- (var-get total-participation-score) current-score) new-score))
                new-score
            )
        )
    )
)

;; Calculate user's share of redistribution pool
(define-private (calculate-redistribution-share (user principal))
    (let
        (
            (user-balance (default-to u0 (map-get? balances user)))
            (user-score (default-to u0 (map-get? participation-scores user)))
            (pool-amount (var-get redistribution-pool))
            (total-score (var-get total-participation-score))
            (supply (var-get total-supply))
        )
        (if (and (> user-balance u0) (> total-score u0) (> supply u0))
            ;; Weight: 60% based on holdings, 40% based on participation score
            (let
                (
                    (holding-weight (/ (* pool-amount u60 user-balance) (* u100 supply)))
                    (score-weight (/ (* pool-amount u40 user-score) (* u100 total-score)))
                )
                (+ holding-weight score-weight)
            )
            u0
        )
    )
)

;; Update cumulative holdings for time-weighted calculations
(define-private (update-cumulative-holdings (user principal))
    (let
        (
            (current-balance (default-to u0 (map-get? balances user)))
            (last-block (default-to block-height (map-get? last-activity-block user)))
            (blocks-held (- block-height last-block))
            (current-cumulative (default-to u0 (map-get? cumulative-holdings user)))
        )
        (map-set cumulative-holdings user 
            (+ current-cumulative (* current-balance blocks-held)))
    )
)

;; public functions

;; Register user in the redistribution system
(define-public (register-user)
    (let
        (
            (user tx-sender)
            (is-registered (default-to false (map-get? registered-users user)))
        )
        (asserts! (not is-registered) err-already-registered)
        (map-set registered-users user true)
        (map-set participation-scores user u5000) ;; Start with median score
        (map-set last-activity-block user block-height)
        (map-set last-claim-block user block-height)
        (var-set total-registered-users (+ (var-get total-registered-users) u1))
        (var-set total-participation-score (+ (var-get total-participation-score) u5000))
        (ok true)
    )
)

;; Mint tokens (owner only, for initial distribution)
(define-public (mint (amount uint) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (default-to false (map-get? registered-users recipient)) err-not-registered)
        
        (map-set balances recipient 
            (+ (default-to u0 (map-get? balances recipient)) amount))
        (var-set total-supply (+ (var-get total-supply) amount))
        (map-set last-activity-block recipient block-height)
        (ok true)
    )
)

;; Transfer tokens with redistribution fee
(define-public (transfer (amount uint) (sender principal) (recipient principal))
    (let
        (
            (sender-balance (default-to u0 (map-get? balances sender)))
            (fee (calculate-fee amount))
            (net-amount (calculate-net-amount amount))
        )
        (asserts! (is-eq tx-sender sender) err-owner-only)
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (>= sender-balance amount) err-insufficient-balance)
        (asserts! (default-to false (map-get? registered-users sender)) err-not-registered)
        (asserts! (default-to false (map-get? registered-users recipient)) err-not-registered)
        
        ;; Update cumulative holdings before transfer
        (update-cumulative-holdings sender)
        (update-cumulative-holdings recipient)
        
        ;; Update balances
        (map-set balances sender (- sender-balance amount))
        (map-set balances recipient 
            (+ (default-to u0 (map-get? balances recipient)) net-amount))
        
        ;; Add fee to redistribution pool
        (var-set redistribution-pool (+ (var-get redistribution-pool) fee))
        
        ;; Update participation scores
        (update-participation-score sender)
        (update-participation-score recipient)
        
        ;; Update activity blocks
        (map-set last-activity-block sender block-height)
        (map-set last-activity-block recipient block-height)
        
        (ok true)
    )
)

;; Toggle redistribution system (owner only)
(define-public (toggle-redistribution)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set redistribution-active (not (var-get redistribution-active)))
        (ok (var-get redistribution-active))
    )
)

;; Read-only functions

;; Get balance of user
(define-read-only (get-balance (user principal))
    (ok (default-to u0 (map-get? balances user)))
)

;; Get participation score
(define-read-only (get-participation-score (user principal))
    (ok (default-to u0 (map-get? participation-scores user)))
)

;; Get redistribution pool size
(define-read-only (get-redistribution-pool)
    (ok (var-get redistribution-pool))
)

;; Get pending rewards for user
(define-read-only (get-pending-rewards (user principal))
    (ok (calculate-redistribution-share user))
)

;; Get total supply
(define-read-only (get-total-supply)
    (ok (var-get total-supply))
)

;; Advanced algorithmic redistribution function with time-weighted rewards and dynamic scoring
;; This function implements a sophisticated multi-factor reward calculation system that considers:
;; 1. Time-weighted holdings (longer holding = higher rewards)
;; 2. Participation velocity (recent activity vs historical)
;; 3. Proportional pool distribution with decay factors
;; 4. Anti-gaming mechanisms through minimum thresholds
(define-public (execute-algorithmic-redistribution (beneficiaries (list 10 principal)))
    (let
        (
            (pool-amount (var-get redistribution-pool))
            (current-block block-height)
            (total-score (var-get total-participation-score))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (var-get redistribution-active) err-redistribution-locked)
        (asserts! (> pool-amount u0) err-no-rewards)
        
        ;; Process each beneficiary with algorithmic distribution
        (ok (map process-beneficiary-redistribution beneficiaries))
    )
)

;; Helper function for algorithmic redistribution processing
(define-private (process-beneficiary-redistribution (user principal))
    (let
        (
            (user-balance (default-to u0 (map-get? balances user)))
            (user-score (default-to u0 (map-get? participation-scores user)))
            (last-activity (default-to block-height (map-get? last-activity-block user)))
            (last-claim (default-to block-height (map-get? last-claim-block user)))
            (cumulative (default-to u0 (map-get? cumulative-holdings user)))
            (blocks-held (- block-height last-activity))
            (blocks-since-claim (- block-height last-claim))
        )
        ;; Calculate time-weighted multiplier (1.0x to 2.0x based on holding period)
        (let
            (
                (time-multiplier (if (>= blocks-held min-holding-period)
                                    (+ u10000 (/ (* blocks-held u10000) (* min-holding-period u10)))
                                    u10000))
                (capped-multiplier (if (> time-multiplier u20000) u20000 time-multiplier))
                
                ;; Calculate velocity score (recent activity bonus)
                (velocity-bonus (if (< blocks-since-claim (* min-holding-period u2))
                                   u1500  ;; 15% bonus for recent claims
                                   u0))
                
                ;; Calculate base reward share
                (base-share (calculate-redistribution-share user))
                
                ;; Apply multipliers: base * time-weight * (1 + velocity-bonus)
                (adjusted-share (/ (* base-share capped-multiplier (+ u10000 velocity-bonus))
                                  (* u10000 u10000)))
                
                ;; Apply minimum threshold (must have at least 0.1% of supply)
                (min-threshold (/ (var-get total-supply) u1000))
                (eligible (>= user-balance min-threshold))
            )
            (if (and eligible (> adjusted-share u0) (>= blocks-since-claim min-holding-period))
                (begin
                    ;; Distribute rewards
                    (map-set balances user (+ user-balance adjusted-share))
                    (var-set redistribution-pool (- (var-get redistribution-pool) adjusted-share))
                    (map-set last-claim-block user block-height)
                    
                    ;; Update participation score with bonus for successful claim
                    (let ((boosted-score (if (< user-score u10000)
                                            (+ user-score u100)
                                            u10000)))
                        (map-set participation-scores user boosted-score)
                        (var-set total-participation-score 
                            (+ (- (var-get total-participation-score) user-score) boosted-score))
                    )
                    
                    adjusted-share
                )
                u0
            )
        )
    )
)


