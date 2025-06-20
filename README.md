PowerConnect
============

A Peer-to-Peer Renewable Energy Trading Smart Contract
------------------------------------------------------

PowerConnect is a Clarity smart contract designed to facilitate direct, decentralized trading of renewable energy between prosumers (producers/consumers) on the Stacks blockchain. It establishes a transparent and automated marketplace for individuals to list, purchase, and exchange energy, complete with secure escrow payments and a dynamic reputation system to foster trust within the community.

✨ Features
----------

-   **Energy Listing:** Prosumers can list their surplus renewable energy (e.g., solar, wind, hydro) for sale, specifying the amount, price, type, location, and expiry.

-   **Automated Matching:** An intelligent matching algorithm helps buyers find the best energy listings based on price, energy type, desired amount, location proximity (conceptual in this contract, often handled off-chain), and seller reputation.

-   **Secure Escrow Payments:** Funds for energy purchases are held in escrow until the buyer confirms successful delivery, ensuring a secure transaction for both parties.

-   **Reputation Tracking:** A built-in reputation system tracks successful trades for each user, providing a trust score that influences matching and incentivizes reliable participation.

-   **Platform Fees:** A small, transparent platform fee is collected on successful trades to support the ecosystem.

-   **Flexible Purchases:** Buyers can purchase the full listed amount or a partial amount of energy from a listing.

📄 Contract Structure
---------------------

### Constants

-   `contract-owner`: The principal (address) that deployed the contract, with special permissions for certain administrative functions (though not explicitly used in public functions here, common for upgrades/pausing).

-   `err-owner-only` (u100): Error for owner-only operations.

-   `err-not-found` (u101): Error when a listing or trade is not found.

-   `err-insufficient-funds` (u102): Error for insufficient STX balance (handled by `stx-transfer?`).

-   `err-unauthorized` (u103): Error when `tx-sender` is not authorized for an action.

-   `err-invalid-amount` (u104): Error for invalid energy amounts or durations.

-   `err-trade-expired` (u105): Error when a trade listing has expired.

-   `err-trade-completed` (u106): Error when attempting to interact with an already completed trade.

-   `err-invalid-price` (u107): Error for invalid price inputs.

-   `platform-fee-bps` (u100): Defines the platform fee as 1% (100 basis points).

-   `max-energy-amount` (u10000): Maximum kWh allowed per listing.

-   `min-energy-amount` (u1): Minimum kWh required per listing.

### Data Maps and Variables

-   **`energy-listings`**: A map storing details of active energy listings.

    -   `listing-id`: Unique identifier for each listing.

    -   `seller`: Principal address of the energy seller.

    -   `energy-amount`: Amount of energy listed in kWh.

    -   `price-per-kwh`: Price per kWh in microSTX.

    -   `energy-type`: Type of renewable energy (e.g., "solar", "wind").

    -   `location`: Location details (string).

    -   `expiry-block`: Block height at which the listing expires.

    -   `is-active`: Boolean indicating if the listing is still available.

-   **`energy-trades`**: A map tracking completed energy trades.

    -   `trade-id`: Unique identifier for each trade.

    -   `listing-id`: The ID of the listing from which the energy was purchased.

    -   `buyer`: Principal address of the energy buyer.

    -   `seller`: Principal address of the energy seller.

    -   `energy-amount`: Amount of energy traded in kWh.

    -   `total-price`: Total price paid for the energy.

    -   `trade-block`: Block height at which the trade was initiated.

    -   `is-completed`: Boolean indicating if the trade has been confirmed.

-   **`user-reputation`**: A map storing reputation scores for users.

    -   `user`: Principal address of the user.

    -   `total-trades`: Total number of trades the user has participated in.

    -   `successful-trades`: Number of trades successfully completed.

    -   `reputation-score`: Current reputation score (0-1000 scale, default 500).

-   **`trade-escrow`**: A map holding funds in escrow for pending trades.

    -   `trade-id`: The ID of the trade for which funds are held.

    -   `amount`: The amount of microSTX held in escrow.

    -   `depositor`: The principal who deposited the funds (typically the buyer).

-   **`next-listing-id`**: A global data variable storing the next available listing ID.

-   **`next-trade-id`**: A global data variable storing the next available trade ID.

-   **`total-energy-traded`**: A global data variable tracking the total kWh traded on the platform.

-   **`platform-revenue`**: A global data variable tracking accumulated platform fees.

### Private Functions

Private functions are internal helper functions that can only be called from within the contract itself.

-   `(calculate-platform-fee (amount uint))`: Computes the platform fee for a given `amount` based on `platform-fee-bps`.

-   `(validate-listing-params (energy-amount uint) (price-per-kwh uint))`: Checks if energy `amount` is within min/max limits and `price-per-kwh` is positive.

-   `(min-uint (a uint) (b uint))`: Returns the minimum of two unsigned integers.

-   `(max-uint (a uint) (b uint))`: Returns the maximum of two unsigned integers.

-   `(update-reputation (user principal) (successful bool))`: Updates a user's `total-trades`, `successful-trades`, and `reputation-score` based on trade outcome.

### Public Functions

Public functions can be called by any authorized user and modify the contract's state.

-   `(create-energy-listing (energy-amount uint) (price-per-kwh uint) (energy-type (string-ascii 20)) (location (string-ascii 50)) (duration-blocks uint))`:

    -   Allows a prosumer to create a new energy listing.

    -   Requires valid `energy-amount`, `price-per-kwh`, and `duration-blocks`.

    -   Returns the new `listing-id` on success.

-   `(purchase-energy (listing-id uint) (energy-amount uint))`:

    -   Enables a buyer to purchase energy from an active listing.

    -   Transfers the total price from the buyer to the contract's escrow.

    -   Creates a new trade record and updates the listing's remaining energy.

    -   Returns the new `trade-id` on success.

-   `(confirm-delivery (trade-id uint))`:

    -   Called by the buyer to confirm that energy delivery was successful.

    -   Releases funds from escrow to the seller, collects the platform fee, marks the trade as completed, and updates both buyer's and seller's reputations.

    -   Returns `true` on success.

-   `(auto-match-energy-trade (buyer-max-price uint) (desired-energy-amount uint) (preferred-energy-type (string-ascii 20)) (max-distance-km uint) (min-seller-reputation uint))`:

    -   Initiates an automated search for the best energy listing based on specified criteria.

    -   Uses a `fold` operation to iterate and score potential listings.

    -   If a suitable match is found, it automatically calls `purchase-energy` to execute the trade.

    -   Returns the `trade-id` if a trade is executed, or `err-not-found` if no suitable match is found.

### Read-Only Functions

Read-only functions allow users to query the contract's state without making any modifications.

-   `(get-energy-listing (listing-id uint))`: Retrieves the full details of a specific energy listing.

-   `(get-trade-details (trade-id uint))`: Retrieves the full details of a specific energy trade.

-   `(get-user-reputation (user principal))`: Retrieves the reputation details (total trades, successful trades, score) for a given user. Defaults to initial values if no record exists.

## ⚠️ Error Codes

| Code | Constant | Description |
| :----- | :----- | :----- |
| `u100` | `err-owner-only` | Caller is not the contract owner. |
| `u101` | `err-not-found` | Listing or trade ID does not exist or is inactive. |
| `u102` | `err-insufficient-funds` | The buyer does not have enough STX to pay. |
| `u103` | `err-unauthorized` | The transaction sender is not permitted to perform this action. |
| `u104` | `err-invalid-amount` | Invalid energy amount, duration, or reputation score. |
| `u105` | `err-trade-expired` | The energy listing has expired. |
| `u106` | `err-trade-completed` | The trade has already been completed. |
| `u107` | `err-invalid-price` | The provided price is invalid (e.g., zero). |

🚀 Usage
--------

### Creating an Energy Listing

Prosumers can list their energy:

```
(contract-call? 'SP123...my-contract.power-connect create-energy-listing u500 u1000 "solar" "Lagos, Nigeria" u100)
;; Lists 500 kWh of solar energy at 1000 microSTX/kWh, located in Lagos, Nigeria, for 100 blocks.

```

### Purchasing Energy

Buyers can purchase energy from an existing listing:

```
(contract-call? 'SP123...my-contract.power-connect purchase-energy u1 u250)
;; Purchases 250 kWh from listing ID 1.

```

### Confirming Delivery

Once energy is delivered, the buyer confirms:

```
(contract-call? 'SP123...my-contract.power-connect confirm-delivery u1)
;; Confirms delivery for trade ID 1, releasing funds to seller and updating reputations.

```

### Auto-Matching Energy Trade

Buyers can use the automated matching system:

```
(contract-call? 'SP123...my-contract.power-connect auto-match-energy-trade u1200 u300 "wind" u50 u600)
;; Searches for a wind energy listing, up to 1200 microSTX/kWh, for 300 kWh, within 50 km (conceptual),
;; and from sellers with at least 600 reputation. If found, automatically executes the purchase.

```

### Querying Data

You can retrieve listing, trade, and reputation details:

```
(contract-call? 'SP123...my-contract.power-connect get-energy-listing u1)
(contract-call? 'SP123...my-contract.power-connect get-trade-details u1)
(contract-call? 'SP123...my-contract.power-connect get-user-reputation 'SPABC...user-address)

```

⚖️ Reputation System
--------------------

The `user-reputation` map tracks each user's trading history and reputation score.

-   Initially, users have a score of `u500`.

-   Upon `confirm-delivery` (successful trade):

    -   `reputation-score` increases by `u10`.

    -   `successful-trades` increments.

    -   `total-trades` increments.

-   If a trade is not confirmed (e.g., dispute resolution, though not implemented in this basic contract, would lead to `successful` being `false` for the non-performing party):

    -   `reputation-score` decreases by `u20`.

-   Reputation score is capped between `u0` and `u1000`.

This system encourages honest and reliable participation in the energy trading network.

🤝 Contributing
---------------

Contributions are welcome! If you have suggestions for improvements, new features, or bug fixes, please open an issue or submit a pull request on the GitHub repository.

📝 License
----------

This contract is released under the MIT License. You are free to use, modify, and distribute it, provided you adhere to the terms of the license.
