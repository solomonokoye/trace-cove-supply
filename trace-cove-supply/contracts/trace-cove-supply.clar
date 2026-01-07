;; TraceCove Supply Chain Tracking Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-status (err u104))

;; Data Variables
(define-data-var shipment-nonce uint u0)

;; Shipment status types
(define-constant status-created u0)
(define-constant status-in-transit u1)
(define-constant status-delivered u2)
(define-constant status-verified u3)

;; Data Maps
(define-map shipments
  { shipment-id: uint }
  {
    origin: (string-ascii 100),
    destination: (string-ascii 100),
    product-type: (string-ascii 50),
    status: uint,
    creator: principal,
    created-at: uint,
    updated-at: uint
  }
)

(define-map shipment-checkpoints
  { shipment-id: uint, checkpoint-id: uint }
  {
    location: (string-ascii 100),
    timestamp: uint,
    temperature: int,
    humidity: uint,
    verified-by: principal
  }
)

(define-map checkpoint-count
  { shipment-id: uint }
  { count: uint }
)

(define-map authorized-validators
  { validator: principal }
  { authorized: bool }
)

;; Authorization Functions
(define-public (add-validator (validator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-validators { validator: validator } { authorized: true }))
  )
)

(define-public (remove-validator (validator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-validators { validator: validator } { authorized: false }))
  )
)

(define-read-only (is-validator (validator principal))
  (default-to false (get authorized (map-get? authorized-validators { validator: validator })))
)

;; Shipment Functions
(define-public (create-shipment 
  (origin (string-ascii 100))
  (destination (string-ascii 100))
  (product-type (string-ascii 50)))
  (let
    (
      (new-id (+ (var-get shipment-nonce) u1))
    )
    (map-set shipments
      { shipment-id: new-id }
      {
        origin: origin,
        destination: destination,
        product-type: product-type,
        status: status-created,
        creator: tx-sender,
        created-at: block-height,
        updated-at: block-height
      }
    )
    (map-set checkpoint-count { shipment-id: new-id } { count: u0 })
    (var-set shipment-nonce new-id)
    (ok new-id)
  )
)

(define-public (update-shipment-status (shipment-id uint) (new-status uint))
  (let
    (
      (shipment (unwrap! (map-get? shipments { shipment-id: shipment-id }) err-not-found))
    )
    (asserts! (or (is-eq tx-sender (get creator shipment)) (is-validator tx-sender)) err-unauthorized)
    (asserts! (<= new-status status-verified) err-invalid-status)
    (ok (map-set shipments
      { shipment-id: shipment-id }
      (merge shipment { status: new-status, updated-at: block-height })
    ))
  )
)

(define-public (add-checkpoint
  (shipment-id uint)
  (location (string-ascii 100))
  (temperature int)
  (humidity uint))
  (let
    (
      (shipment (unwrap! (map-get? shipments { shipment-id: shipment-id }) err-not-found))
      (current-count (default-to { count: u0 } (map-get? checkpoint-count { shipment-id: shipment-id })))
      (new-checkpoint-id (+ (get count current-count) u1))
    )
    (asserts! (is-validator tx-sender) err-unauthorized)
    (map-set shipment-checkpoints
      { shipment-id: shipment-id, checkpoint-id: new-checkpoint-id }
      {
        location: location,
        timestamp: block-height,
        temperature: temperature,
        humidity: humidity,
        verified-by: tx-sender
      }
    )
    (map-set checkpoint-count { shipment-id: shipment-id } { count: new-checkpoint-id })
    (ok new-checkpoint-id)
  )
)

;; Read-only Functions
(define-read-only (get-shipment (shipment-id uint))
  (ok (map-get? shipments { shipment-id: shipment-id }))
)

(define-read-only (get-checkpoint (shipment-id uint) (checkpoint-id uint))
  (ok (map-get? shipment-checkpoints { shipment-id: shipment-id, checkpoint-id: checkpoint-id }))
)

(define-read-only (get-checkpoint-count (shipment-id uint))
  (ok (default-to { count: u0 } (map-get? checkpoint-count { shipment-id: shipment-id })))
)

(define-read-only (get-current-nonce)
  (ok (var-get shipment-nonce))
)