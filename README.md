RewardNexus
===========

* * * * *

🚀 Protocol Summary: Algorithmic Redistribution System
------------------------------------------------------

The **RewardNexus** contract defines a sophisticated token redistribution mechanism implemented in Clarity. I designed this system to incentivize active participation and long-term holding among token owners. Instead of relying solely on token quantity, I utilize a dual-factor model that weights token holdings and dynamically adjusted participation scores, ensuring that ecosystem activity directly translates into increased rewards.

The core mechanism involves collecting a small transaction fee (2% currently) into a dedicated `redistribution-pool`. Rewards from this pool are distributed algorithmically, factoring in the duration a user has held their tokens (time-weighted holdings) and their recent interaction velocity. This approach minimizes rewards for inactive or short-term speculative actors and maximizes benefits for committed community members.

* * * * *

✨ System Mechanics and Economic Incentives
------------------------------------------

### 1\. Fee Collection and Pool Funding

Every time a token is transferred via the public `transfer` function:

-   A fixed fee of **200 basis points (2%)** is calculated using the `calculate-fee` private function.

-   The net amount is sent to the recipient.

-   The collected fee is immediately added to the `redistribution-pool` data variable.

### 2\. Dual-Factor Reward Allocation (Base Share)

The fundamental reward share for a user is determined by the `calculate-redistribution-share` private function, which employs a weighted split to balance passive holding and active participation:

-   **60% Weight:** Based on the user's current token balance proportional to the `total-supply`.

-   **40% Weight:** Based on the user's `participation-scores` proportional to the `total-participation-score` across all users.

This formula, Rbase​=Pool×[0.6×SupplyBalance​+0.4×TotalScoreScore​], ensures that even smaller holders can earn significant rewards by maintaining a high participation score.

### 3\. Dynamic Participation Scoring

The `participation-scores` map tracks user activity between 0 and 10000. The `update-participation-score` private function is called during crucial activities (transfers, claims) and operates on the following rules:

-   **Activity Boost:** If the user has been active recently (less than u1000 blocks since last activity), the score is boosted by 1% up to the maximum of u10000.

-   **Inactivity Decay:** If the user has been inactive for more than u1000 blocks (approximately 1.6 days), the score decays by 10% to promote continuous engagement.

-   **Registration Start:** New registered users start with a median score of u5000.

### 4\. Advanced Algorithmic Redistribution (`execute-algorithmic-redistribution`)

I have included an advanced function for high-frequency or batch reward distributions, which introduces time-based multipliers:

-   **Time-Weighted Multiplier:** Calculates a bonus factor (capped at 2.0×) based on how long the user has held their current balance (`blocks-held` vs. `min-holding-period`). This explicitly rewards loyal, long-term holders.

    Mtime​=min(2.0,1.0+10×MinHoldingPeriodBlocksHeld​)

-   **Velocity Bonus:** A 15% bonus (u1500) is applied if the user has claimed rewards relatively recently (within 2×min-holding-period), encouraging prompt interaction.

-   **Anti-Gaming Threshold:** Users must hold at least **0.1%** (1000Supply​) of the `total-supply` to be eligible for this distribution method, preventing reward sniping by minor accounts.

-   **Reward Distribution:** The final Radjusted​ is calculated by applying the Time-Weighted Multiplier and Velocity Bonus to the Rbase​ share.

* * * * *

🛠️ Data Structures and Errors
------------------------------

### Core Mappings

| Map Name | Type | Description |
| --- | --- | --- |
| `balances` | `(map principal uint)` | Token balance for each user. |
| `participation-scores` | `(map principal uint)` | User score from 0 to 10000. |
| `cumulative-holdings` | `(map principal uint)` | Tracks ∑(Balance×Time Held) for advanced rewards. |
| `last-activity-block` | `(map principal uint)` | Block height of the user's last interaction (transfer/claim). |
| `registered-users` | `(map principal bool)` | Confirms enrollment in the redistribution system. |

### Data Variables

| Variable Name | Type | Description |
| --- | --- | --- |
| `redistribution-pool` | `(var uint u0)` | The total amount of accumulated fees available for distribution. |
| `total-supply` | `(var uint u0)` | The current total number of tokens in existence. |
| `total-participation-score` | `(var uint u0)` | The aggregate sum of all user participation scores. |
| `redistribution-active` | `(var bool true)` | Global toggle for distribution status. |

### Error Codes

| Code | Error Constant | Meaning |
| --- | --- | --- |
| `u100` | `err-owner-only` | Unauthorized caller attempted an owner-only function. |
| `u101` | `err-insufficient-balance` | Transfer amount exceeds the sender's balance. |
| `u103` | `err-not-registered` | User must `register-user` before interacting. |
| `u106` | `err-redistribution-locked` | Distribution is paused or minimum holding period not met. |
| `u107` | `err-no-rewards` | The user is not eligible for any rewards in the pool. |

* * * * *

⚙️ Function Reference
---------------------

### Public Functions (API)

| Function | Input(s) | Output | Description |
| --- | --- | --- | --- |
| `register-user` | `none` | `(ok true)` | Enrolls the caller, setting initial score to u5000. |
| `mint` | `(amount uint), (recipient principal)` | `(ok true)` | **Owner-only.** Issues new tokens to a registered recipient. |
| `transfer` | `(amount uint), (sender principal), (recipient principal)` | `(ok true)` | Core token transfer function. **Funds the pool** and updates scores/holdings. |
| `claim-rewards` | `none` | `(ok uint reward-amount)` | Standard claim mechanism for the sender, subject to u144 block minimum holding. |
| `toggle-redistribution` | `none` | `(ok bool new-status)` | **Owner-only.** Activates or deactivates the reward system. |
| `execute-algorithmic-redistribution` | `(beneficiaries (list 10 principal))` | `(ok (list 10 uint))` | **Owner-only.** Executes the advanced, time-weighted, boosted reward distribution for a batch of users. |

### Private Functions (Internal Logic)

These functions encapsulate the core economic and scoring logic, ensuring the public functions remain clean and focused on access control and transaction flow.

| Function Name | Purpose | Key Logic & Calculation |
| --- | --- | --- |
| `calculate-fee(amount)` | **Fee Calculation** | Computes the **2% fee** (based on `redistribution-fee-bps`) on a given transfer `amount`. This is the mechanism by which the pool is funded. |
| `calculate-net-amount(amount)` | **Net Transfer Value** | Calculates the amount that is actually transferred to the recipient after the fee has been subtracted from the gross `amount`. |
| `update-participation-score(user)` | **Dynamic Scoring** | Adjusts the user's `participation-scores`: **decays by 10%** if inactive (>u1000 blocks) or **boosts by 1%** if active. Also manages the aggregate `total-participation-score`. |
| `calculate-redistribution-share(user)` | **Base Reward Share** | Determines the user's base proportional reward using the **60/40 weighted formula** based on their balance and participation score against the total supply and total score. |
| `update-cumulative-holdings(user)` | **Time-Weighted Tracking** | Updates the `cumulative-holdings` by adding the product of the user's **current balance** and the **number of blocks** they have held that balance since the last activity. Essential for the time-weighted bonus. |
| `process-beneficiary-redistribution(user)` | **Advanced Reward Calculation** | The core logic for the `execute-algorithmic-redistribution` function. It calculates and applies the **Time-Weighted Multiplier** (up to 2.0×) and the **Velocity Bonus** (15%) to the base reward share, while enforcing the **0.1% minimum holding threshold**. |

* * * * *

🔎 Read-Only Functions (Query)
------------------------------

-   `get-balance (user principal)`: Returns the current token balance of a specific user.

-   `get-participation-score (user principal)`: Returns the current dynamic activity score of the user.

-   `get-redistribution-pool`: Returns the total amount of fees currently available in the reward pool.

-   `get-pending-rewards (user principal)`: Returns the **base** calculated reward share for the user based on the 60/40 weighting.

-   `get-total-supply`: Returns the total circulating supply of the token.

* * * * *

⚖️ License
----------

### MIT License

Copyright (c) 2025 RewardNexus Protocol Team

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

* * * * *

🤝 Contribution Guidelines
--------------------------

I welcome all community contributions. Your input is vital for the continuous improvement and security of the **RewardNexus** system.

### Bug Reporting and Feature Suggestions

Please submit all issues and proposals through the project's issue tracker on GitHub. When reporting a bug, provide:

1.  A clear and descriptive title.

2.  A detailed description of the bug, including the expected and actual behavior.

3.  The necessary steps and transaction inputs to reproduce the issue.

### Pull Requests

For code contributions, please follow these steps:

1.  Fork the repository and clone it locally.

2.  Create a new, descriptive branch for your changes (`git checkout -b fix/issue-42` or `git checkout -b feat/new-feature`).

3.  Ensure your code adheres to Clarity best practices and passes all local tests.

4.  Submit a Pull Request targeting the `main` branch, including a brief explanation of your changes and why they are necessary.

My primary focus is on ensuring the economic integrity and security of the redistribution algorithm.

* * * * *

🛡️ Auditing and Security
-------------------------

The economic model is intentionally complex to prevent simple exploitation and promote fair distribution. Due to the management of user funds and complex time-weighted reward calculations, I stress the necessity of thorough security review.

-   **Economic Analysis:** The parameters, such as the 60/40 weighting, the 1% boost, 10% decay, and the 2.0× multiplier cap, must be continuously modeled and stress-tested to prevent unexpected economic consequences or inflationary pressure.

-   **Clarity Code Audit:** A professional third-party audit is highly recommended to verify the implementation logic against potential Clarity-specific vulnerabilities, especially around integer arithmetic and flow control in the private functions.

-   **Test Coverage:** Comprehensive unit and integration testing must cover all possible scenarios for the score updates, reward calculations, and edge cases (e.g., zero supply, zero pool, minimum thresholds).

I am committed to maintaining a robust and transparent smart contract and encourage independent security review.
