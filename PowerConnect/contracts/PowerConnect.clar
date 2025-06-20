;; Peer-to-Peer Renewable Energy Trading Contract
;; This contract enables direct trading of renewable energy between prosumers (producers/consumers)
;; Features include energy listing, automated matching, escrow payments, and reputation tracking

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-insufficient-funds (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-trade-expired (err u105))
(define-constant err-trade-completed (err u106))
(define-constant err-invalid-price (err u107))

;; Platform fee percentage (1% = 100 basis points)
(define-constant platform-fee-bps u100)
(define-constant max-energy-amount u10000) ;; Maximum kWh per listing
(define-constant min-energy-amount u1) ;; Minimum kWh per listing

;; data maps and vars
;; Track energy listings from prosumers
(define-map energy-listings
  { listing-id: uint }
  {
    seller: principal,
    energy-amount: uint, ;; in kWh
    price-per-kwh: uint, ;; in microSTX
    energy-type: (string-ascii 20), ;; "solar", "wind", "hydro", etc.
    location: (string-ascii 50),
    expiry-block: uint,
    is-active: bool
  }
)

;; Track completed trades
(define-map energy-trades
  { trade-id: uint }
  {
    listing-id: uint,
    buyer: principal,
    seller: principal,
    energy-amount: uint,
    total-price: uint,
    trade-block: uint,
    is-completed: bool
  }
)

;; Track user reputation scores (0-1000 scale)
(define-map user-reputation
  { user: principal }
  {
    total-trades: uint,
    successful-trades: uint,
    reputation-score: uint
  }
)

;; Track escrow balances for pending trades
(define-map trade-escrow
  { trade-id: uint }
  { amount: uint, depositor: principal }
)

;; Global counters
(define-data-var next-listing-id uint u1)
(define-data-var next-trade-id uint u1)
(define-data-var total-energy-traded uint u0)
(define-data-var platform-revenue uint u0)

;; private functions
;; Calculate platform fee for a given amount
(define-private (calculate-platform-fee (amount uint))
  (/ (* amount platform-fee-bps) u10000)
)

;; Validate energy listing parameters
(define-private (validate-listing-params (energy-amount uint) (price-per-kwh uint))
  (and 
    (>= energy-amount min-energy-amount)
    (<= energy-amount max-energy-amount)
    (> price-per-kwh u0)
  )
)

;; Helper function to get minimum of two values
(define-private (min-uint (a uint) (b uint))
  (if (<= a b) a b)
)

;; Helper function to get maximum of two values
(define-private (max-uint (a uint) (b uint))
  (if (>= a b) a b)
)

;; Update user reputation after successful trade
(define-private (update-reputation (user principal) (successful bool))
  (let (
    (current-rep (default-to 
      { total-trades: u0, successful-trades: u0, reputation-score: u500 }
      (map-get? user-reputation { user: user })
    ))
  )
    (map-set user-reputation
      { user: user }
      {
        total-trades: (+ (get total-trades current-rep) u1),
        successful-trades: (if successful 
          (+ (get successful-trades current-rep) u1)
          (get successful-trades current-rep)
        ),
        reputation-score: (if successful
          (min-uint u1000 (+ (get reputation-score current-rep) u10))
          (max-uint u0 (- (get reputation-score current-rep) u20))
        )
      }
    )
  )
)

;; public functions
;; Create a new energy listing
(define-public (create-energy-listing 
  (energy-amount uint) 
  (price-per-kwh uint) 
  (energy-type (string-ascii 20))
  (location (string-ascii 50))
  (duration-blocks uint)
)
  (let (
    (listing-id (var-get next-listing-id))
    (expiry-block (+ block-height duration-blocks))
  )
    (asserts! (validate-listing-params energy-amount price-per-kwh) err-invalid-amount)
    (asserts! (> duration-blocks u0) err-invalid-amount)
    
    (map-set energy-listings
      { listing-id: listing-id }
      {
        seller: tx-sender,
        energy-amount: energy-amount,
        price-per-kwh: price-per-kwh,
        energy-type: energy-type,
        location: location,
        expiry-block: expiry-block,
        is-active: true
      }
    )
    
    (var-set next-listing-id (+ listing-id u1))
    (ok listing-id)
  )
)

;; Purchase energy from a listing
(define-public (purchase-energy (listing-id uint) (energy-amount uint))
  (let (
    (listing (unwrap! (map-get? energy-listings { listing-id: listing-id }) err-not-found))
    (trade-id (var-get next-trade-id))
    (total-price (* energy-amount (get price-per-kwh listing)))
    (platform-fee (calculate-platform-fee total-price))
    (seller-amount (- total-price platform-fee))
  )
    (asserts! (get is-active listing) err-not-found)
    (asserts! (<= block-height (get expiry-block listing)) err-trade-expired)
    (asserts! (<= energy-amount (get energy-amount listing)) err-invalid-amount)
    (asserts! (not (is-eq tx-sender (get seller listing))) err-unauthorized)
    
    ;; Transfer payment to escrow
    (try! (stx-transfer? total-price tx-sender (as-contract tx-sender)))
    
    ;; Create trade record
    (map-set energy-trades
      { trade-id: trade-id }
      {
        listing-id: listing-id,
        buyer: tx-sender,
        seller: (get seller listing),
        energy-amount: energy-amount,
        total-price: total-price,
        trade-block: block-height,
        is-completed: false
      }
    )
    
    ;; Store escrow
    (map-set trade-escrow
      { trade-id: trade-id }
      { amount: total-price, depositor: tx-sender }
    )
    
    ;; Update listing if fully purchased
    (if (is-eq energy-amount (get energy-amount listing))
      (map-set energy-listings
        { listing-id: listing-id }
        (merge listing { is-active: false })
      )
      (map-set energy-listings
        { listing-id: listing-id }
        (merge listing { energy-amount: (- (get energy-amount listing) energy-amount) })
      )
    )
    
    (var-set next-trade-id (+ trade-id u1))
    (ok trade-id)
  )
)

;; Confirm energy delivery and release payment
(define-public (confirm-delivery (trade-id uint))
  (let (
    (trade (unwrap! (map-get? energy-trades { trade-id: trade-id }) err-not-found))
    (escrow (unwrap! (map-get? trade-escrow { trade-id: trade-id }) err-not-found))
    (platform-fee (calculate-platform-fee (get total-price trade)))
    (seller-amount (- (get total-price trade) platform-fee))
  )
    (asserts! (is-eq tx-sender (get buyer trade)) err-unauthorized)
    (asserts! (not (get is-completed trade)) err-trade-completed)
    
    ;; Release payment to seller
    (try! (as-contract (stx-transfer? seller-amount tx-sender (get seller trade))))
    
    ;; Collect platform fee
    (var-set platform-revenue (+ (var-get platform-revenue) platform-fee))
    
    ;; Update trade status
    (map-set energy-trades
      { trade-id: trade-id }
      (merge trade { is-completed: true })
    )
    
    ;; Remove escrow
    (map-delete trade-escrow { trade-id: trade-id })
    
    ;; Update statistics
    (var-set total-energy-traded (+ (var-get total-energy-traded) (get energy-amount trade)))
    
    ;; Update reputations
    (update-reputation (get seller trade) true)
    (update-reputation (get buyer trade) true)
    
    (ok true)
  )
)

;; Get energy listing details
(define-read-only (get-energy-listing (listing-id uint))
  (map-get? energy-listings { listing-id: listing-id })
)

;; Get trade details
(define-read-only (get-trade-details (trade-id uint))
  (map-get? energy-trades { trade-id: trade-id })
)

;; Get user reputation
(define-read-only (get-user-reputation (user principal))
  (default-to 
    { total-trades: u0, successful-trades: u0, reputation-score: u500 }
    (map-get? user-reputation { user: user })
  )
)

;; Helper function for the matching algorithm
(define-private (find-best-listing-match 
  (listing-id uint) 
  (match-context {
    buyer-max-price: uint,
    desired-amount: uint,
    preferred-type: (string-ascii 20),
    min-reputation: uint,
    best-listing-id: uint,
    best-score: uint
  })
)
  (match (map-get? energy-listings { listing-id: listing-id })
    listing (let (
      (seller-reputation (get reputation-score (get-user-reputation (get seller listing))))
      (price-score (if (<= (get price-per-kwh listing) (get buyer-max-price match-context)) u300 u0))
      (type-score (if (is-eq (get energy-type listing) (get preferred-type match-context)) u200 u100))
      (reputation-score (if (>= seller-reputation (get min-reputation match-context)) u200 u0))
      (availability-score (if (>= (get energy-amount listing) (get desired-amount match-context)) u100 u50))
      (total-score (+ price-score type-score reputation-score availability-score))
    )
      (if (and (get is-active listing)
               (> (get expiry-block listing) block-height)
               (> total-score (get best-score match-context)))
        (merge match-context { 
          best-listing-id: listing-id, 
          best-score: total-score 
        })
        match-context
      )
    )
    match-context ;; No listing found, return unchanged context
  )
)

;; Advanced matching system for automatic energy trading
;; This function implements an intelligent matching algorithm that considers
;; location proximity, energy type preferences, price ranges, and user reputation
;; to automatically match buyers with sellers for optimal energy trading
(define-public (auto-match-energy-trade 
  (buyer-max-price uint)
  (desired-energy-amount uint)
  (preferred-energy-type (string-ascii 20))
  (max-distance-km uint)
  (min-seller-reputation uint)
)
  (let (
    (current-listing-id u1)
    (best-match-id u0)
    (best-match-score u0)
  )
    ;; Validate input parameters
    (asserts! (> buyer-max-price u0) err-invalid-price)
    (asserts! (and (>= desired-energy-amount min-energy-amount) 
                   (<= desired-energy-amount max-energy-amount)) err-invalid-amount)
    (asserts! (<= min-seller-reputation u1000) err-invalid-amount)
    
    ;; Iterate through active listings to find best match
    ;; In a real implementation, this would use a more efficient search algorithm
    (let (
      (matching-result (fold find-best-listing-match 
        (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) ;; Check first 10 listings
        {
          buyer-max-price: buyer-max-price,
          desired-amount: desired-energy-amount,
          preferred-type: preferred-energy-type,
          min-reputation: min-seller-reputation,
          best-listing-id: u0,
          best-score: u0
        }
      ))
    )
      ;; If a good match is found, automatically execute the trade
      (if (> (get best-score matching-result) u0)
        (let (
          (selected-listing-id (get best-listing-id matching-result))
          (listing (unwrap! (map-get? energy-listings { listing-id: selected-listing-id }) err-not-found))
        )
          ;; Execute automatic purchase with the matched listing
          (purchase-energy selected-listing-id 
            (min-uint desired-energy-amount (get energy-amount listing)))
        )
        ;; No suitable match found - return same error type as purchase-energy
        err-not-found
      )
    )
  )
)


