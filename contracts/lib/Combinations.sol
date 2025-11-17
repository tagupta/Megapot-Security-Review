// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {LibBit} from "solady/src/utils/LibBit.sol";

library Combinations {
    uint256 constant UINT256_BIT_WIDTH = 256;
    /// @notice Compute number of combinations of size k from a set of n
    /// @param n Size of set to choose from
    /// @param k Size of subsets to choose

    function choose(uint256 n, uint256 k) internal pure returns (uint256 result) {
        // console2.log("n", n);
        // console2.log("K", k);
        assert(n >= k);
        assert(n <= 128); // Artificial limit to avoid overflow
        // "How to calculate binomial coefficients"
        // From: https://blog.plover.com/math/choose.html
        // This algorithm computes multiplication and division in alternation
        // to avoid overflow as much as possible.
        unchecked {
            uint256 out = 1;
            //@report-written missing symmery reduction, k = min(k, n-k)
            for (uint256 d = 1; d <= k; ++d) {
                out *= n--;
                out /= d;
            }
            // console2.log("Out: ", out);
            return out;
        }
    }

    /// @notice Generate all possible subsets of size k from a bit vector.
    /// @param set Bit vector to generate subsets from
    /// @param k Size of subsets to generate
    //@report-written k == 0, not handled leading to panic division by zero error
    function generateSubsets(uint256 set, uint256 k) internal pure returns (uint256[] memory subsets) {
        unchecked {
            uint256 n = LibBit.popCount(set); //no. of elements available
            assert(k <= n);
            subsets = new uint256[](choose(n, k)); //@note not validating that the n <= 128, else all the gas will be consumed
            uint256 bound = 1 << n;
            uint256 comb = (1 << k) - 1;
            uint256 count;
            while (comb < bound) {
                uint256 mapped;
                uint256 _set = set;
                uint256 _comb = comb;
                for (uint256 i; i < UINT256_BIT_WIDTH && _set != 0; ++i) {
                    if (_set & 1 == 1) {
                        if (_comb & 1 == 1) {
                            mapped |= (1 << i);
                        }
                        _comb >>= 1;
                    }
                    _set >>= 1;
                }

                subsets[count++] = mapped;

                // "Gosper's hack"
                uint256 c = comb & uint256(-int256(comb));
                uint256 r = comb + c;
                comb = (((r ^ comb) >> 2) / c) | r;
            }
            assert(count == choose(n, k));
        }
    }
}
