# Technical Specification Template - Clojure

## Executive Summary

[Provide a brief technical overview of the solution approach. Summarize the main architectural decisions and implementation strategy in 1-2 paragraphs.]

## System Architecture

### Component Overview

[Brief description of main components and their responsibilities following Diplomat Architecture:

- **Models**: Domain entities and schemas
- **Logic**: Pure business rules (functions without side effects)
- **Controllers**: Flow orchestration ("logic sandwich")
- **Diplomats**: External communication (http-client, http-server, producer, consumer)
- **Adapters**: Data transformation between layers
- **Wire**: Input/output schemas (wire.in - loose, wire.out - strict)]

## Implementation Design

### Main Interfaces

[Define main protocols or schemas (≤20 lines per example):

```clojure
(ns myservice.logic.core
  (:require [schema.core :as s]))

(s/defschema RequestInput
  {:customer-id s/Uuid
   :amount      s/Int
   (s/optional-key :metadata) {s/Keyword s/Any}})

(s/defschema ResponseOutput
  {:transaction-id s/Uuid
   :status         (s/enum :approved :rejected)
   :timestamp      s/Inst})

(s/defn process-transaction :- ResponseOutput
  [request :- RequestInput
   dependencies :- DependenciesSchema]
  ;; Logic implementation
  )
```

]

### Data Models

[Define essential data structures using Plumatic Schema:

**Domain Entities:**

```clojure
(ns myservice.models.transaction
  (:require [schema.core :as s]))

(s/defschema Transaction
  {:id           s/Uuid
   :customer-id  s/Uuid
   :amount       s/Int
   :status       (s/enum :pending :approved :rejected)
   :created-at   s/Inst
   :updated-at   s/Inst})
```

**Wire Schemas:**

```clojure
(ns myservice.wire.in)
;; Loose schema for input
(def TransactionRequest
  {:customer-id String
   :amount      String  ;; Will be coerced
   s/Keyword    s/Any})  ;; Accept extra fields

(ns myservice.wire.out)
;; Strict schema for output
(s/defschema TransactionResponse
  {:transaction-id s/Uuid
   :status         s/Str
   :timestamp      s/Inst})
```

**Datomic Schemas (if applicable):**

```clojure
(def transaction-schema
  [{:db/ident       :transaction/id
    :db/valueType   :db.type/uuid
    :db/cardinality :db.cardinality/one
    :db/unique      :db.unique/identity}
   {:db/ident       :transaction/customer-id
    :db/valueType   :db.type/uuid
    :db/cardinality :db.cardinality/one}
   {:db/ident       :transaction/amount
    :db/valueType   :db.type/long
    :db/cardinality :db.cardinality/one}])
```

]

### API Endpoints

[List API endpoints using Pedestal:

```clojure
(ns myservice.diplomat.http-server
  (:require [io.pedestal.http.route :as route]))

(def routes
  #{["/api/v0/transactions"
     :post
     [(common-io.interceptors.auth/trusted)
      (common-io.interceptors.coercion/coerce-request wire.in/TransactionRequest)
      (common-io.interceptors.adapt/externalize! {200 wire.out/TransactionResponse
                                                   400 wire.out/ErrorResponse})
      create-transaction-handler]
     :route-name :create-transaction]

    ["/api/v0/transactions/:transaction-id"
     :get
     [(common-io.interceptors.auth/user)
      (common-io.interceptors.adapt/externalize! {200 wire.out/TransactionResponse
                                                   404 wire.out/NotFoundResponse})
      get-transaction-handler]
     :route-name :get-transaction]})
```

**Endpoints:**

- `POST /api/v0/transactions` - Create new transaction (auth: trusted)
- `GET /api/v0/transactions/:transaction-id` - Fetch transaction (auth: user)
  ]

## Integration Points

[Include only if the functionality requires external integrations:

**HTTP Clients:**

```clojure
(ns myservice.diplomat.payment-service-client
  (:require [common-http.client :as http]))

(s/defn process-payment! :- PaymentResponse
  [payment-request :- PaymentRequest
   config :- HttpClientConfig]
  (http/post!
    (str (:base-url config) "/payments")
    {:body payment-request
     :headers {"Authorization" (str "Bearer " (:token config))}}))
```

**Kafka Producers:**

```clojure
(ns myservice.diplomat.transaction-producer
  (:require [common-kafka.producer :as producer]))

(s/defn publish-transaction-event! :- nil
  [event :- TransactionEvent
   producer :- ProducerComponent]
  (producer/send! producer
                  {:topic "transactions.created"
                   :key   (str (:customer-id event))
                   :value event}))
```

**Error Handling:**

- Use `ex-info` for structured errors
- Implement retry with exponential backoff
- Error logging using `nu.logging.api`
  ]

## Testing Approach

### Unit Tests

[Describe unit testing strategy using `clojure.test`:

```clojure
(ns myservice.logic.core-test
  (:require [clojure.test :refer [deftest testing is]]
            [schema.test :as st]
            [myservice.logic.core :as logic]))

(use-fixtures :once st/validate-schemas)

(deftest process-transaction-test
  (testing "should approve transaction when amount is valid"
    (let [request {:customer-id (random-uuid)
                   :amount 1000}
          deps {:config {:max-amount 10000}}
          result (logic/process-transaction request deps)]
      (is (= :approved (:status result)))
      (is (uuid? (:transaction-id result)))))

  (testing "should reject transaction when amount exceeds limit"
    (let [request {:customer-id (random-uuid)
                   :amount 20000}
          deps {:config {:max-amount 10000}}
          result (logic/process-transaction request deps)]
      (is (= :rejected (:status result))))))
```

**Components to test:**

- Pure logic (without side effects)
- Adapters (data transformations)
- Schema validations

**Necessary mocks:**

- Only for external services
- Use `with-redefs` or `component` test fixtures
  ]

### Integration Tests

[If necessary, use state-flow for integration tests:

```clojure
(ns myservice.integration.transaction-flow-test
  (:require [state-flow.api :refer [flow match?]]
            [state-flow.assertions.matcher-combinators :refer [match?]]
            [myservice.test-helpers :as th]))

(deftest create-transaction-flow-test
  (flow "should create and retrieve transaction"
    (th/with-system [system (th/test-system)]
      (flow "create transaction"
        (th/http-post "/api/v0/transactions"
                      {:customer-id (random-uuid)
                       :amount 1000})
        (match? {:status 200
                 :body {:status "approved"}}))

      (flow "retrieve created transaction"
        (th/http-get "/api/v0/transactions/:id")
        (match? {:status 200})))))
```

**Components to test:**

- Complete endpoint flows
- Datomic integration (if applicable)
- Kafka integration (using test containers)
  ]

## Development Sequencing

### Build Order

[Define implementation sequence following Diplomat Architecture:

1. **Models and Schemas** (First - foundation for everything)

   - Define domain schemas
   - Create wire.in and wire.out schemas
   - Datomic schemas setup (if applicable)

2. **Logic Layer** (Second - pure business rules)

   - Implement pure functions
   - Logic unit tests
   - Validations and transformations

3. **Adapters** (Third - transformations between layers)

   - wire.in -> models
   - models -> wire.out
   - Datomic -> models

4. **Diplomats** (Fourth - external communication)

   - HTTP server setup
   - HTTP clients for external services
   - Kafka producers/consumers

5. **Controllers** (Fifth - orchestration)

   - Implement "logic sandwich" pattern
   - Gather data -> Execute logic -> Produce effects

6. **Component System** (Sixth - dependency injection)
   - Components setup
   - Lifecycle management
7. **Integration Tests** (Final)
   - State-flow tests
   - End-to-end flows
     ]

### Technical Dependencies

[List any blocking dependencies:

**Required Libraries:**

```clojure
;; project.clj or deps.edn
{:dependencies [[org.clojure/clojure "1.11.1"]
                [prismatic/schema "1.4.1"]
                [com.stuartsierra/component "1.1.0"]
                [io.pedestal/pedestal.service "0.6.0"]
                [nubank/common-core "X.Y.Z"]
                [nubank/common-datomic "X.Y.Z"]
                [nubank/common-kafka "X.Y.Z"]
                [nubank/clockwise "X.Y.Z"]]}
```

**Infrastructure:**

- Datomic (if applicable)
- Kafka topics created
- Secrets configured in Vault
  ]

## Monitoring and Observability

[Define monitoring approach:

**Metrics (Prometheus):**

```clojure
(ns myservice.metrics
  (:require [nu.monitoring.api :as metrics]))

(def transaction-counter
  (metrics/counter "transactions_total"
                   "Total number of transactions"
                   ["status" "type"]))

(def transaction-duration
  (metrics/histogram "transaction_duration_seconds"
                     "Transaction processing duration"))

(defn record-transaction! [status type duration]
  (metrics/inc! transaction-counter [status type])
  (metrics/observe! transaction-duration duration))
```

**Logs:**

```clojure
(ns myservice.logic.core
  (:require [nu.logging.api :as log]))

(s/defn process-transaction :- ResponseOutput
  [request :- RequestInput]
  (log/info "Processing transaction"
            {:customer-id (:customer-id request)
             :amount (:amount request)})
  (try
    (let [result (do-process request)]
      (log/info "Transaction processed successfully"
                {:transaction-id (:id result)
                 :status (:status result)})
      result)
    (catch Exception e
      (log/error "Transaction processing failed"
                 {:customer-id (:customer-id request)
                  :error-type (class e)}
                 e)
      (throw e))))
```

**Sensitive Information Redaction:**

- Never log passwords, tokens, or PII
- Use `:customer-id` but not `:cpf` or `:email`

## Technical Considerations

### Main Decisions

[Document important technical decisions:]

**Choice of Diplomat Architecture:**

- Justification: Clear separation of responsibilities, testability
- Trade-offs: More files, more formal structure
- Alternatives: Monolithic implementation (rejected - difficult maintenance)

**Use of Plumatic Schema vs Spec:**

- Chosen: Schema (Nubank standard)
- Justification: Better integration with existing code
- Performance: Runtime validation with opt-out in production

**Security:**

```clojure
;; Use appropriate interceptors
(common-io.interceptors.auth/trusted)        ;; For internal services
(common-io.interceptors.auth/user)           ;; For clients
(common-io.interceptors.auth/public)         ;; ONLY for health checks

;; Validate identity vs path
(interceptors/identity-matches-path-id)
```

### Standards Compliance

[Search the rules in the .cursor/rules folder that fit this techspec and list them below:]

#### Applicable Security Rules

**Secure Clojure Rules:**

1. ✅ Use `clojure.edn/read-string` instead of `read-string`
2. ✅ Validate schemas with malli or spec on all inputs
3. ✅ Implement `identity-matches-path-id` on user-bound endpoints
4. ✅ Use specific scopes instead of generic `auth/admin`
5. ✅ `:internal` services not exposed externally
6. ✅ Validate date ranges to prevent DoS
7. ✅ Rate limiting on sensitive endpoints
8. ✅ Use `externalize!` interceptor to define output format
9. ✅ Sensitive information redaction with `nu.logging.api`
10. ❌ Avoid deprecated libraries (`common-crypto`, `common-schemata`, `midje`, `common-time`)
11. ✅ Sanitize shell commands (if applicable)
12. ✅ Use secure hash algorithms for sensitive data
13. ✅ Use secure protocols (TLS 1.3) in `SSLContext`
14. ✅ Use `clojure.data.xml` for XML parsing (XXE prevention)
15. ✅ Do not log sensitive data (passwords, tokens, PII)
16. ✅ Do not hardcode secrets

**Secure Datomic Rules (if applicable):**

1. ✅ Use parameterized queries (placeholders `?`)
2. ✅ Validate entity IDs before dereferencing
3. ✅ Apply access control on sensitive attributes
4. ✅ Audit on `:db.fn/retractEntity` operations
5. ✅ Validate inputs in transaction functions
6. ✅ Do not expose schema introspection in production

**Secure MCP Rules:**

1. ✅ Do not transmit PII through MCP
2. ✅ Do not execute system commands automatically
3. ✅ Require explicit approval for sensitive operations

**Clojure Best Practices:**

1. ✅ Follow Diplomat Architecture (models, logic, diplomats, adapters, wire)
2. ✅ Use Schema annotations on all functions
3. ✅ Prefer Plumatic Schema over Clojure Spec
4. ✅ Use "logic sandwich" in controllers
5. ✅ Use `clockwise.api` for time operations
6. ✅ Name functions with suffixes: `!` (side effects), `?` (predicates), `->` (transformations)
7. ✅ Use kebab-case for functions and variables
8. ✅ Use snake_case for directories and files
9. ✅ Avoid global state
10. ✅ Handle errors at the beginning of functions (early returns)
11. ✅ Use `ex-info` for structured errors
12. ✅ Prefer pure functions and immutability
13. ✅ Use lazy sequences and transducers for large datasets

#### Time Handling with Clockwise

**Always use `clockwise.api` for time operations:**

```clojure
(ns myservice.logic.core
  (:require [clockwise.api :as t]))

;; Get current timestamp
(t/now (t/utc-clock))

;; Create dates
(t/local-date 2023 3 10)

;; Arithmetic operations
(t/plus (t/now (t/utc-clock)) [1 :day])

;; Comparisons
(t/lt? date1 date2)

;; Serialization/Deserialization
(t/serialize (t/now (t/utc-clock)))
(t/deserialize :instant "2023-04-30T05:13:44.321Z")

;; In tests
(deftest my-test
  (let [clock (t/fixed-clock (t/deserialize :instant "2023-10-10T10:10:10Z"))]
    (is (= expected (my-fn clock)))))
```

### Relevant Files

[List here relevant codebase files that serve as reference:]

**Implementation Examples:**

- `src/myservice/models/` - Domain models
- `src/myservice/logic/` - Business logic
- `src/myservice/diplomat/http_server.clj` - API endpoints
- `src/myservice/diplomat/http_client.clj` - External service clients
- `src/myservice/wire/in.clj` - Input schemas
- `src/myservice/wire/out.clj` - Output schemas
- `src/myservice/adapters/` - Data transformations
- `test/myservice/logic/` - Unit tests
- `test/myservice/integration/` - Integration tests

**Configurations:**

- `project.clj` or `deps.edn` - Dependencies
- `resources/config.edn` - Application config
- `resources/datomic/schema.edn` - Datomic schemas

