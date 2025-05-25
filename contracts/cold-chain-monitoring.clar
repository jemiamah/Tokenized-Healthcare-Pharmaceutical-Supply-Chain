;; Cold Chain Monitoring Contract
;; Tracks temperature-sensitive pharmaceutical storage and transport

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_SHIPMENT_NOT_FOUND (err u301))
(define-constant ERR_INVALID_TEMPERATURE (err u302))
(define-constant ERR_SHIPMENT_EXISTS (err u303))

;; Temperature reading structure
(define-map temperature-readings
  { shipment-id: (string-ascii 50), reading-id: uint }
  {
    temperature: int,
    humidity: uint,
    timestamp: uint,
    location: (string-ascii 100),
    sensor-id: (string-ascii 50),
    within-range: bool
  }
)

;; Shipment cold chain requirements
(define-map shipment-requirements
  { shipment-id: (string-ascii 50) }
  {
    product-id: (string-ascii 50),
    min-temp: int,
    max-temp: int,
    max-humidity: uint,
    start-time: uint,
    end-time: uint,
    status: (string-ascii 20),
    violations: uint
  }
)

;; Reading counter for each shipment
(define-map reading-counters
  { shipment-id: (string-ascii 50) }
  { count: uint }
)

;; Initialize cold chain monitoring for a shipment
(define-public (initialize-cold-chain
  (shipment-id (string-ascii 50))
  (product-id (string-ascii 50))
  (min-temp int)
  (max-temp int)
  (max-humidity uint))

  (begin
    (asserts! (is-none (map-get? shipment-requirements { shipment-id: shipment-id })) ERR_SHIPMENT_EXISTS)
    (asserts! (< min-temp max-temp) ERR_INVALID_TEMPERATURE)

    (map-set shipment-requirements
      { shipment-id: shipment-id }
      {
        product-id: product-id,
        min-temp: min-temp,
        max-temp: max-temp,
        max-humidity: max-humidity,
        start-time: block-height,
        end-time: u0,
        status: "ACTIVE",
        violations: u0
      }
    )

    (map-set reading-counters
      { shipment-id: shipment-id }
      { count: u0 }
    )

    (ok true)
  )
)

;; Record temperature reading
(define-public (record-temperature
  (shipment-id (string-ascii 50))
  (temperature int)
  (humidity uint)
  (location (string-ascii 100))
  (sensor-id (string-ascii 50)))

  (let (
    (requirements (unwrap! (map-get? shipment-requirements { shipment-id: shipment-id }) ERR_SHIPMENT_NOT_FOUND))
    (counter-data (unwrap! (map-get? reading-counters { shipment-id: shipment-id }) ERR_SHIPMENT_NOT_FOUND))
    (reading-id (+ (get count counter-data) u1))
    (within-range (and
      (>= temperature (get min-temp requirements))
      (<= temperature (get max-temp requirements))
      (<= humidity (get max-humidity requirements))
    ))
  )

    (map-set temperature-readings
      { shipment-id: shipment-id, reading-id: reading-id }
      {
        temperature: temperature,
        humidity: humidity,
        timestamp: block-height,
        location: location,
        sensor-id: sensor-id,
        within-range: within-range
      }
    )

    (map-set reading-counters
      { shipment-id: shipment-id }
      { count: reading-id }
    )

    ;; Update violations if temperature is out of range
    (if (not within-range)
      (map-set shipment-requirements
        { shipment-id: shipment-id }
        (merge requirements { violations: (+ (get violations requirements) u1) })
      )
      true
    )

    (ok within-range)
  )
)

;; Complete cold chain monitoring
(define-public (complete-cold-chain (shipment-id (string-ascii 50)))
  (let ((requirements (unwrap! (map-get? shipment-requirements { shipment-id: shipment-id }) ERR_SHIPMENT_NOT_FOUND)))
    (map-set shipment-requirements
      { shipment-id: shipment-id }
      (merge requirements {
        end-time: block-height,
        status: "COMPLETED"
      })
    )
    (ok true)
  )
)

;; Get shipment cold chain status
(define-read-only (get-cold-chain-status (shipment-id (string-ascii 50)))
  (map-get? shipment-requirements { shipment-id: shipment-id })
)

;; Get temperature reading
(define-read-only (get-temperature-reading (shipment-id (string-ascii 50)) (reading-id uint))
  (map-get? temperature-readings { shipment-id: shipment-id, reading-id: reading-id })
)

;; Check if cold chain was maintained
(define-read-only (is-cold-chain-maintained (shipment-id (string-ascii 50)))
  (match (map-get? shipment-requirements { shipment-id: shipment-id })
    requirements (is-eq (get violations requirements) u0)
    false
  )
)
