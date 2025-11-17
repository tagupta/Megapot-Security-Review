### [QA-1] Uninitialized `newAccumulator` for `_drawingId == 0` in `processDrawingSettlement` leads to brittle accounting logic

**Description** In `processDrawingSettlement()`, the variable `newAccumulator` is assigned only when `_drawingId > 0`.
When `_drawingId == 0`, the code skips initialization and continues using an uninitialized newAccumulator `(default = 0)` to convert pending withdrawals.

_Code Snippet:_

```solidity
        if (_drawingId > 0) {
            newAccumulator = currentLP.lpPoolTotal == 0 ? PRECISE_UNIT :
                (drawingAccumulator[_drawingId - 1] * postDrawLpValue) / currentLP.lpPoolTotal;
            drawingAccumulator[_drawingId] = newAccumulator;
        }

        uint256 withdrawalsInUSDC = currentLP.pendingWithdrawals * newAccumulator / PRECISE_UNIT;
```

Today, this does not cause incorrect payouts because the protocol prevents LPs from initiating withdrawals in `drawing == 0` (thus `pendingWithdrawals == 0` always). However, the logic is fragile:

- It relies on external rules (initiation restrictions) rather than local correctness.
- Any future code change that introduces pending withdrawals in drawing 0 will silently break LP economics.

This is a correctness and maintainability issue, not an immediate financial exploit.

**Impact**

- No current exploitable financial loss because `pendingWithdrawals == 0` for drawing == 0.
- Makes the system fragile to future refactors.
- It violates the documented invariant: **accumulator[0] must always be initialized to PRECISE_UNIT.**

**Recommended mitigation**
Explicitly initialize `newAccumulator` for `_drawingId == 0` using the pre-initialized accumulator value:

```diff
if (_drawingId > 0) {
    newAccumulator =
        currentLP.lpPoolTotal == 0
            ? PRECISE_UNIT
            : Math.mulDiv(
                drawingAccumulator[_drawingId - 1],
                postDrawLpValue,
                currentLP.lpPoolTotal
            );

    drawingAccumulator[_drawingId] = newAccumulator;

}
+   else {
+    // Defensive: accumulator[0] should already be initialized via initializeLP()
+    newAccumulator = drawingAccumulator[0];
+   }

```

### [QA-2] Unbounded drawing scheduling `_initialDrawingTime & drawingDurationInSeconds` can lead to DoS / economic manipulation risk

**Description** Two related scheduling surfaces are currently unchecked:

1. `initializeJackpot(uint256 _initialDrawingTime)` accepts an arbitrary timestamp and passes it through to `_setNewDrawingState(...)` without validating that the initial drawing time is sane (future, not too soon, not absurdly far).
2. `drawingDurationInSeconds` settable via constructor or setter has no bounds or cooldowns. The code uses this value to schedule subsequent drawings `(currentDrawingState.drawingTime + drawingDurationInSeconds)` and to compute next drawing times inside entropy callbacks.

Together these gaps let the owner (or a compromised owner key) set scheduling values that break the intended cadence or freeze/accelerate drawings:

- set the initial drawing time far in the future; effectively freeze drawings and lock prize realization and LP settlement,
- set it in the past or very near now; allow immediate drawing/sampling before users/LPs had time to participate,
- set `drawingDurationInSeconds` to extremely large or extremely small values; enable denial-of-service or rapid-fire draws that undermine intended economics.

This issue is a governance and economic control vulnerability rather than a pure code bug; it enables owner-controlled timing changes that have direct monetary consequences.

**Impact**

- _Denial-of-Service / Funds Frozen (High):_ Owner can set `_initialDrawingTime` or `drawingDurationInSeconds` to enormous values (e.g., years) so drawings never execute in a practical timeframe — players cannot claim prizes and LPs cannot realize/share funds.
- Owner can set `_initialDrawingTime` in the past (or very close to `block.timestamp`), enabling draws before purchasers or LPs had a fair window to act (ticket purchases or deposits), causing unfair payouts or LP losses.
- Owner can run draws too frequently (very small duration) or schedule draws to advantage certain actors (timing-based gaming).
- _Governance Risk:_ If owner key is compromised, attacker can weaponize scheduling to cause real financial harm.

**Recommended mitigation** Apply constraints on these parameters:

- In `initializeJackpot(uint256 _initialDrawingTime)`, require that `_initialDrawingTime` is at least `X` minutes/hours in the future and not more than `Y` days/weeks ahead of `block.timestamp`.
- In the constructor and setter for `drawingDurationInSeconds`, enforce minimum and maximum bounds (e.g., between `1 hour` and `30 days`) to prevent extreme scheduling.
- Optionally, add a governance delay or multi-sig requirement for changing these parameters to prevent rapid malicious changes.

### [QA-3] Missing handling for `k == 0` leads to panic / DoS / OOG in `generateSubsets()`

**Description** `generateSubsets(uint256 set, uint256 k)` assumes `k >= 1` and uses algorithms `(Gosper's hack)` that `require k > 0`. When `k == 0` the function misbehaves:

`comb = (1 << k) - 1` becomes 0, which breaks the Gosper loop and logic: the code will iterate incorrectly (or the Gosper update will behave unpredictably), and the final` assert(count == choose(n,k))` will end up panicking.

Although, the subset size (k) is always started from `1` in the current usage, the function itself does not enforce this precondition.

**Impact** Passing `k == 0` causes panics (assert or other failures), leading to DoS or OOG conditions.

**Proof of Concepts**
Following test case triggers the issue and failes with panic: _panic: division or modulo by zero (0x12)_

```solidity
function testGenerateSetsWithZeroK(uint256 set) external {
        unchecked {
        uint256 mask = (uint256(1) << 128) - 1; // safe: shift < 256
        set &= mask; // zero out bits >= 128
    }

        uint256 n = LibBit.popCount(set);
        n = bound(n, 0, 128);
        uint256 k = 0;

        Combinations.generateSubsets(set,k);
    }
```

**Recommended mitigation**

Add a require check for `k > 0` at the start of `generateSubsets()`, or special-case `k == 0` to return the single empty subset:

```solidity
        if (k == 0) {
            subsets = new uint256[](1);
            subsets[0] = 0;
            return subsets;
        }
```

Else `require(k > 0, "subsets: k==0");`

### [QA-4] Missing symmetry reduction `(k = min(k, n-k))` in `choose()` increases gas and intermediate magnitude

**Description** The implementation of the binomial coefficient calculation does not apply the standard symmetry optimization:

```
nCk = nC(n-k)
```

Using the smaller of `k` and `n-k` significantly reduces - loop iterations, size of intermediate multiplication values, risk of hitting Solidity's uint256 limit in future parameter changes and finally gas costs.

Although the contract `asserts n ≤ 128`, which makes overflow unlikely, this is a standard safety and efficiency pattern, and omitting it wastes gas unnecessarily.

**Impact**

- _Minor gas inefficiency:_ up to ~2× more iterations when k > n/2
- _Reduced overflow margin:_ intermediate values are larger than necessary
- _No functional vulnerability_, but not optimal for performance or robustness

_Current Code Snippet:_

```solidity
function choose(
        uint256 n,
        uint256 k
    ) internal pure returns (uint256 result) {
        assert(n >= k);
        assert(n <= 128);
        unchecked {
            uint256 out = 1;
            for (uint256 d = 1; d <= k; ++d) {
                out *= n--;
                out /= d;
            }
            return out;

        }
    }
```

For Example: When `n=128`, `k=80`, loop runs 80 iterations.
If symmetry reduction were applied loop drops from `80 to 48`.

**Recommended mitigation**
Apply symmetry reduction before the loop:

```diff
        uint256 n,
        uint256 k
    ) internal pure returns (uint256 result) {
        assert(n >= k);
        assert(n <= 128);
        unchecked {
            uint256 out = 1;
+            if (k > n - k) {
+                k = n - k;
+            }

            for (uint256 d = 1; d <= k; ++d) {
                out *= n--;
                out /= d;
            }
            return out;

        }
    }
```

### [QA-5] `ProtocolFeeCollected` event emitted even when protocol fee is zero, leading to misleading logs

**Description** `_transferProtocolFee()` computes protocol fees only when:

```solidity
if (_lpEarnings > _drawingUserWinnings &&
    _lpEarnings - _drawingUserWinnings > protocolFeeThreshold)
{
    protocolFeeAmount = (...);
    usdc.safeTransfer(protocolFeeAddress, protocolFeeAmount);
}

```

However, the event:

```solidity
    emit ProtocolFeeCollected(currentDrawingId, protocolFeeAmount);
```

is emitted _unconditionally_, including when the fee is **zero**.

**Impact** Logs become misleading, harming transparency and creating potential confusion for indexers, dashboards, auditors, and future governance analysis.

**Recommended mitigation**

1. Emit the event only when `protocolFeeAmount > 0`, or include an explicit flag:

```solidity
if (protocolFeeAmount > 0) {
    emit ProtocolFeeCollected(currentDrawingId, protocolFeeAmount);
}
```

2. Emit an event with semantic clarity:

```solidity
emit ProtocolFeeCollected(currentDrawingId, protocolFeeAmount, protocolFeeAmount > 0);
```

### [QA-6] Redundant recomputation of subsets in `_countSubsetMatches` leading to excessive gas and memory churn

**Description** `_countSubsetMatches()` recomputes `Combinations.generateSubsets(_normalBallsBitVector, k)` inside the bonusball loop, even though the subsets depend only on `k` and the winning normals, not on `i` ,the bonusball.

```solidity
for (uint8 i = 1; i <= _tracker.bonusballMax; i++) {
    for (uint8 k = 1; k <= _tracker.normalTiers; k++) {
        uint256[] memory subsets = Combinations.generateSubsets(...); // recomputed for every i
        ...
    }
}
```

The causes:

- Repeated memory allocation `(new uint256[])` for identical subset arrays
- Repeated combinatorial computations
- Gas usage scaled by bonusballMax

Subsets for a given `k` should be computed once per `k`, not once per `(i,k)`.

**Impact**

- High gas consumption for every drawing settlement
- Memory bloat due to repeated allocations

**Recommended mitigation**
Move generateSubsets outside the bonusball loop so it runs once per `k`:

```solidity
function _countSubsetMatches(...) internal view returns (...) {
    uint8 normalTiers = _tracker.normalTiers;
    uint8 bonusballMax = _tracker.bonusballMax;

    matches = new uint256[]((normalTiers+1)*2);
    dupMatches = new uint256[]((normalTiers+1)*2);

    for (uint8 k = 1; k <= normalTiers; ++k) {
        uint256[] memory subsets =
            Combinations.generateSubsets(_normalBallsBitVector, k);

        uint256 len = subsets.length;

        for (uint8 i = 1; i <= bonusballMax; ++i) {
            bool matchBonus = (i == _bonusball);

            for (uint256 idx = 0; idx < len; ++idx) {
                uint256 subset = subsets[idx];
                if (matchBonus) {
                    matches[(k*2)+1] += _tracker.comboCounts[i][subset].count;
                    dupMatches[(k*2)+1] += _tracker.comboCounts[i][subset].dupCount;
                } else {
                    matches[(k*2)] += _tracker.comboCounts[i][subset].count;
                    dupMatches[(k*2)] += _tracker.comboCounts[i][subset].dupCount;
                }
            }
        }
    }
}
```

### [QA-7] Stale `ticketOwner` and `userTickets` mappings not cleared in `claimWinnings()` casuing inconsistent state, increased storage bloat

**Description** In `BridgeManager.claimWinnings()` the contract validates ownership of the winning tickets using `_validateTicketOwnership(_userTicketIds, signer);` and then triggers `jackpot.claimWinnings(_userTicketIds);`.

Inside the Jackpot contract, claiming causes the NFT tickets to be burned, which is the authoritative source of ownership.
However, the BridgeManager maintains its own duplicate ownership mappings:

```solidity
mapping(address => mapping(uint256 => UserTickets)) public userTickets;
mapping(uint256 => address) public ticketOwner;
```

These mappings are never cleared in claimWinnings().
After claim:

- The NFT is burned.
- The Jackpot contract no longer tracks the ticket.
- But BridgeManager still permanently believes the user owns the ticket.

**Impact** This results in stale and misleading state, inconsistent with the actual NFT ownership.

**Recommended mitigation**
After successful `jackpot.claimWinnings(_userTicketIds)`, iterate through the ticket IDs and clear the BridgeManager state:

```solidity
for (uint256 i = 0; i < _userTicketIds.length; i++) {
    uint256 ticketId = _userTicketIds[i];
    address owner = ticketOwner[ticketId];

    delete ticketOwner[ticketId];

    // Optionally clear from userTickets[owner][drawingId]
    // depending on data structure:
    UserTickets storage t = userTickets[owner][currentDrawingId];
    // remove ticketId from t.ticketIds array or mark it claimed
}

```
