;; DECENTRALIZED COLLATERAL LENDING PROTOCOL (DCLP)
;; Protocol Name: Decentralized Collateral Lending Protocol
;;
;; Description:
;; A trustless DeFi lending protocol that enables users to deposit STX tokens as collateral
;; and mint loans against their holdings. The protocol enforces over-collateralization
;; requirements and implements automatic liquidation mechanisms to maintain system stability.
;; Users retain full control of their collateral until liquidation conditions are triggered,
;; creating a secure and transparent lending environment.
;;
;; Key Features:
;; - Over-collateralized lending (minimum 150% collateral ratio)
;; - Automatic liquidation system (triggered at 130% ratio)
;; - Dynamic pricing through oracle integration
;; - Governance-controlled fee structure
;; - Real-time position health monitoring

;; ERROR CONSTANTS

(define-constant ERR-UNAUTHORIZED-ACCESS u1)
(define-constant ERR-INSUFFICIENT-COLLATERAL u2)
(define-constant ERR-INSUFFICIENT-PROTOCOL-LIQUIDITY u3)
(define-constant ERR-COLLATERAL-RATIO-TOO-LOW u4)
(define-constant ERR-POSITION-NOT-FOUND u5)
(define-constant ERR-POSITION-ALREADY-EXISTS u6)
(define-constant ERR-INVALID-AMOUNT u7)
(define-constant ERR-LIQUIDATION-CONDITIONS-NOT-MET u8)
(define-constant ERR-FEE-EXCEEDS-MAXIMUM u9)
(define-constant ERR-ZERO-AMOUNT-NOT-ALLOWED u10)

;; PROTOCOL CONFIGURATION CONSTANTS

(define-constant minimum-collateral-ratio u150)    ;; 150% minimum collateral coverage
(define-constant liquidation-threshold-ratio u130) ;; 130% liquidation trigger point
(define-constant maximum-uint-value u340282366920938463463374607431768211455)
(define-constant maximum-fee-percentage u10)       ;; 10% maximum protocol fee
(define-constant default-borrowing-fee-rate u1)    ;; 1% default borrowing fee

;; PROTOCOL STATE VARIABLES

(define-data-var protocol-owner principal tx-sender)
(define-data-var total-locked-collateral uint u0)
(define-data-var total-outstanding-debt uint u0)
(define-data-var active-positions-count uint u0)
(define-data-var protocol-fee-rate uint default-borrowing-fee-rate)

;; DATA STRUCTURES

;; User lending position tracking
(define-map user-lending-positions
  { user-address: principal }
  {
    collateral-amount: uint,
    debt-amount: uint,
    last-update-block: uint
  }
)

;; Price oracle data storage
(define-map asset-price-oracle
  { asset-symbol: (string-ascii 32) }
  { price-usd-cents: uint }
)

;; READ-ONLY FUNCTIONS - POSITION QUERIES

;; Get user's lending position details
(define-read-only (get-user-position (user-address principal))
  (map-get? user-lending-positions { user-address: user-address })
)

;; Get current STX price from oracle
(define-read-only (get-stx-price)
  (default-to u100 
    (get price-usd-cents 
      (map-get? asset-price-oracle { asset-symbol: "STX" })))
)

;; Calculate collateral ratio for a position
(define-read-only (calculate-collateral-ratio (user-address principal))
  (let (
    (user-position (get-user-position user-address))
  )
  (match user-position
    position-data
    (let (
      (collateral-value-usd (* (get collateral-amount position-data) (get-stx-price)))
      (debt-amount (get debt-amount position-data))
    )
    (if (is-eq debt-amount u0)
      u0
      (/ (* collateral-value-usd u100) debt-amount)))
    u0
  ))
)

;; Calculate maximum borrowing capacity for user
(define-read-only (get-borrowing-capacity (user-address principal))
  (let (
    (user-position (get-user-position user-address))
  )
  (match user-position
    position-data
    (let (
      (collateral-value-usd (* (get collateral-amount position-data) (get-stx-price)))
    )
    (/ (* collateral-value-usd u100) minimum-collateral-ratio))
    u0
  ))
)

;; Check if position is eligible for liquidation
(define-read-only (is-liquidation-eligible (user-address principal))
  (let (
    (current-ratio (calculate-collateral-ratio user-address))
  )
  (and 
    (> current-ratio u0)
    (< current-ratio liquidation-threshold-ratio)
  ))
)

;; Calculate position health factor (100% = at liquidation threshold)
(define-read-only (get-position-health-factor (user-address principal))
  (let (
    (current-ratio (calculate-collateral-ratio user-address))
  )
  (if (is-eq current-ratio u0)
    u0
    (/ (* current-ratio u100) liquidation-threshold-ratio)
  ))
)

;; POSITION MANAGEMENT FUNCTIONS

;; Create new lending position
(define-public (create-lending-position)
  (let (
    (caller tx-sender)
  )
  ;; Ensure user doesn't already have a position
  (asserts! (is-none (get-user-position caller)) 
            (err ERR-POSITION-ALREADY-EXISTS))
  
  ;; Initialize new position with zero balances
  (map-set user-lending-positions
    { user-address: caller }
    {
      collateral-amount: u0,
      debt-amount: u0,
      last-update-block: block-height
    }
  )
  
  ;; Update global position counter
  (var-set active-positions-count 
           (+ (var-get active-positions-count) u1))
  (ok true))
)

;; Add collateral to existing position
(define-public (deposit-collateral (stx-amount uint))
  (let (
    (caller tx-sender)
    (current-position (unwrap! (get-user-position caller) 
                               (err ERR-POSITION-NOT-FOUND)))
    (current-collateral (get collateral-amount current-position))
  )
  ;; Validate deposit amount
  (asserts! (> stx-amount u0) (err ERR-ZERO-AMOUNT-NOT-ALLOWED))
  
  ;; Check for potential overflow
  (asserts! (<= (+ current-collateral stx-amount) maximum-uint-value) 
            (err ERR-INVALID-AMOUNT))
  (asserts! (<= (+ (var-get total-locked-collateral) stx-amount) maximum-uint-value) 
            (err ERR-INVALID-AMOUNT))
  
  ;; Transfer STX to protocol contract
  (try! (stx-transfer? stx-amount caller (as-contract tx-sender)))
  
  ;; Update position record
  (map-set user-lending-positions
    { user-address: caller }
    {
      collateral-amount: (+ current-collateral stx-amount),
      debt-amount: (get debt-amount current-position),
      last-update-block: block-height
    }
  )
  
  ;; Update global collateral tracking
  (var-set total-locked-collateral 
           (+ (var-get total-locked-collateral) stx-amount))
  (ok true))
)

;; Withdraw excess collateral from position
(define-public (withdraw-collateral (stx-amount uint))
  (let (
    (caller tx-sender)
    (current-position (unwrap! (get-user-position caller) 
                               (err ERR-POSITION-NOT-FOUND)))
    (current-collateral (get collateral-amount current-position))
    (current-debt (get debt-amount current-position))
  )
    ;; Validate withdrawal amount
    (asserts! (> stx-amount u0) (err ERR-ZERO-AMOUNT-NOT-ALLOWED))
    (asserts! (<= stx-amount current-collateral) 
              (err ERR-INSUFFICIENT-COLLATERAL))
    
    ;; Calculate post-withdrawal position health
    (let (
      (remaining-collateral (- current-collateral stx-amount))
      (remaining-collateral-value (* remaining-collateral (get-stx-price)))
      (new-collateral-ratio (if (is-eq current-debt u0)
                               u0
                               (/ (* remaining-collateral-value u100) current-debt)))
    )
      ;; Ensure position remains adequately collateralized
      (asserts! (or (is-eq current-debt u0) 
                    (>= new-collateral-ratio minimum-collateral-ratio)) 
                (err ERR-COLLATERAL-RATIO-TOO-LOW))
      
      ;; Transfer STX back to user
      (try! (as-contract (stx-transfer? stx-amount 
                                       (as-contract tx-sender) 
                                       caller)))
      
      ;; Update position record
      (map-set user-lending-positions
        { user-address: caller }
        {
          collateral-amount: remaining-collateral,
          debt-amount: current-debt,
          last-update-block: block-height
        }
      )
      
      ;; Update global collateral tracking
      (var-set total-locked-collateral 
               (- (var-get total-locked-collateral) stx-amount))
      (ok true)
    ))
)

;; BORROWING AND REPAYMENT FUNCTIONS

;; Borrow against collateral
(define-public (borrow-against-collateral (loan-amount uint))
  (let (
    (caller tx-sender)
    (current-position (unwrap! (get-user-position caller) 
                               (err ERR-POSITION-NOT-FOUND)))
    (collateral-balance (get collateral-amount current-position))
    (existing-debt (get debt-amount current-position))
  )
  ;; Validate loan amount
  (asserts! (> loan-amount u0) (err ERR-ZERO-AMOUNT-NOT-ALLOWED))
  
  ;; Check for overflow
  (asserts! (<= (+ existing-debt loan-amount) maximum-uint-value) 
            (err ERR-INVALID-AMOUNT))
  
  ;; Verify borrowing capacity
  (let (
    (collateral-value-usd (* collateral-balance (get-stx-price)))
    (max-borrowing-capacity (/ (* collateral-value-usd u100) minimum-collateral-ratio))
    (total-debt-after-loan (+ existing-debt loan-amount))
  )
    ;; Ensure loan doesn't exceed borrowing capacity
    (asserts! (<= total-debt-after-loan max-borrowing-capacity) 
              (err ERR-COLLATERAL-RATIO-TOO-LOW))
    
    ;; Verify protocol has sufficient liquidity
    (asserts! (<= loan-amount (stx-get-balance (as-contract tx-sender))) 
              (err ERR-INSUFFICIENT-PROTOCOL-LIQUIDITY))
    
    ;; Transfer loan funds to borrower
    (try! (as-contract (stx-transfer? loan-amount 
                                     (as-contract tx-sender) 
                                     caller)))
    
    ;; Update position record
    (map-set user-lending-positions
      { user-address: caller }
      {
        collateral-amount: collateral-balance,
        debt-amount: total-debt-after-loan,
        last-update-block: block-height
      }
    )
    
    ;; Update global debt tracking
    (var-set total-outstanding-debt 
             (+ (var-get total-outstanding-debt) loan-amount))
    (ok true)
  ))
)

;; Repay loan with fees
(define-public (repay-loan (repayment-amount uint))
  (let (
    (caller tx-sender)
    (current-position (unwrap! (get-user-position caller) 
                               (err ERR-POSITION-NOT-FOUND)))
    (outstanding-debt (get debt-amount current-position))
  )
  ;; Validate repayment amount
  (asserts! (> repayment-amount u0) (err ERR-ZERO-AMOUNT-NOT-ALLOWED))
  
  ;; Calculate actual repayment and fee allocation
  (let (
    (actual-repayment (if (> repayment-amount outstanding-debt) 
                         outstanding-debt 
                         repayment-amount))
    (protocol-fee (/ (* actual-repayment (var-get protocol-fee-rate)) u100))
    (principal-payment (- actual-repayment protocol-fee))
  )
    ;; Process repayment transfer
    (try! (stx-transfer? actual-repayment caller (as-contract tx-sender)))
    
    ;; Update position record
    (map-set user-lending-positions
      { user-address: caller }
      {
        collateral-amount: (get collateral-amount current-position),
        debt-amount: (- outstanding-debt principal-payment),
        last-update-block: block-height
      }
    )
    
    ;; Update global debt tracking
    (var-set total-outstanding-debt 
             (- (var-get total-outstanding-debt) principal-payment))
    (ok true)
  ))
)

;; LIQUIDATION SYSTEM

;; Liquidate undercollateralized position
(define-public (liquidate-position (target-user principal))
  (let (
    (liquidator tx-sender)
    (target-position (unwrap! (get-user-position target-user) 
                             (err ERR-POSITION-NOT-FOUND)))
    (collateral-to-seize (get collateral-amount target-position))
    (debt-to-cover (get debt-amount target-position))
  )
  ;; Validate position has assets to liquidate
  (asserts! (> collateral-to-seize u0) (err ERR-INVALID-AMOUNT))
  (asserts! (> debt-to-cover u0) (err ERR-INVALID-AMOUNT))
  
  ;; Verify liquidation eligibility
  (let (
    (collateral-value-usd (* collateral-to-seize (get-stx-price)))
    (current-ratio (/ (* collateral-value-usd u100) debt-to-cover))
  )
    ;; Position must be below liquidation threshold
    (asserts! (< current-ratio liquidation-threshold-ratio) 
              (err ERR-LIQUIDATION-CONDITIONS-NOT-MET))
    
    ;; Liquidator pays off the debt
    (try! (stx-transfer? debt-to-cover liquidator (as-contract tx-sender)))
    
    ;; Liquidator receives all collateral (includes liquidation bonus)
    (try! (as-contract (stx-transfer? collateral-to-seize 
                                     (as-contract tx-sender) 
                                     liquidator)))
    
    ;; Clear the liquidated position
    (map-set user-lending-positions
      { user-address: target-user }
      {
        collateral-amount: u0,
        debt-amount: u0,
        last-update-block: block-height
      }
    )
    
    ;; Update global metrics
    (var-set total-locked-collateral 
             (- (var-get total-locked-collateral) collateral-to-seize))
    (var-set total-outstanding-debt 
             (- (var-get total-outstanding-debt) debt-to-cover))
    (ok true)
  ))
)

;; GOVERNANCE FUNCTIONS

;; Update asset price in oracle
(define-public (update-asset-price (asset-symbol (string-ascii 32)) (price-usd-cents uint))
  (begin
    ;; Verify caller is protocol owner
    (asserts! (is-eq tx-sender (var-get protocol-owner)) 
              (err ERR-UNAUTHORIZED-ACCESS))
    
    ;; Validate inputs
    (asserts! (> price-usd-cents u0) (err ERR-ZERO-AMOUNT-NOT-ALLOWED))
    (asserts! (> (len asset-symbol) u0) (err ERR-INVALID-AMOUNT))
    
    ;; Update price oracle
    (map-set asset-price-oracle 
      { asset-symbol: asset-symbol } 
      { price-usd-cents: price-usd-cents }
    )
    (ok true)
  )
)

;; Update protocol fee rate
(define-public (update-protocol-fee-rate (new-fee-rate uint))
  (begin
    ;; Verify caller is protocol owner
    (asserts! (is-eq tx-sender (var-get protocol-owner)) 
              (err ERR-UNAUTHORIZED-ACCESS))
    
    ;; Enforce maximum fee limit
    (asserts! (<= new-fee-rate maximum-fee-percentage) 
              (err ERR-FEE-EXCEEDS-MAXIMUM))
    
    ;; Update fee rate
    (var-set protocol-fee-rate new-fee-rate)
    (ok true))
)

;; Transfer protocol ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    ;; Verify caller is current owner
    (asserts! (is-eq tx-sender (var-get protocol-owner)) 
              (err ERR-UNAUTHORIZED-ACCESS))
    
    ;; Prevent transfer to null address
    (asserts! (not (is-eq new-owner 'SP000000000000000000002Q6VF78)) 
              (err ERR-UNAUTHORIZED-ACCESS))
    
    ;; Transfer ownership
    (var-set protocol-owner new-owner)
    (ok true))
)

;; ANALYTICS AND REPORTING

;; Get comprehensive protocol metrics
(define-read-only (get-protocol-metrics)
  {
    total-collateral-locked: (var-get total-locked-collateral),
    total-debt-outstanding: (var-get total-outstanding-debt),
    active-positions: (var-get active-positions-count),
    protocol-fee-rate: (var-get protocol-fee-rate),
    protocol-owner: (var-get protocol-owner),
    protocol-utilization-rate: (calculate-utilization-rate),
    stx-price-usd: (get-stx-price)
  }
)

;; Calculate protocol utilization rate
(define-read-only (calculate-utilization-rate)
  (let (
    (total-collateral-value (* (var-get total-locked-collateral) (get-stx-price)))
    (total-debt (var-get total-outstanding-debt))
  )
  (if (is-eq total-collateral-value u0)
    u0
    (/ (* total-debt u100) total-collateral-value)
  ))
)

;; Get comprehensive position information
(define-read-only (get-position-summary (user-address principal))
  (let (
    (position-data (get-user-position user-address))
  )
  (match position-data
    user-position
    {
      collateral-stx-amount: (get collateral-amount user-position),
      outstanding-debt-amount: (get debt-amount user-position),
      last-interaction-block: (get last-update-block user-position),
      position-health-factor: (get-position-health-factor user-address),
      collateral-ratio: (calculate-collateral-ratio user-address),
      available-borrowing-capacity: (get-borrowing-capacity user-address),
      eligible-for-liquidation: (is-liquidation-eligible user-address)
    }
    {
      collateral-stx-amount: u0,
      outstanding-debt-amount: u0,
      last-interaction-block: u0,
      position-health-factor: u0,
      collateral-ratio: u0,
      available-borrowing-capacity: u0,
      eligible-for-liquidation: false
    }
  ))
)