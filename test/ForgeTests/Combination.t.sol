// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {Test, console2} from "forge-std/Test.sol";
import {Combinations} from "contracts/lib/Combinations.sol";
import {LibBit} from "solady/src/utils/LibBit.sol";
import {stdError} from "forge-std/StdError.sol";

contract CombinationTest is Test {
    function testCoefficient(uint256 n, uint256 k) external {
        n = bound(n, 0, 128);
        k = bound(k, 0, n);
        uint256 result = Combinations.choose(n, k);
    }

    function testGenerateSets(uint256 set, uint256 k) external {
        unchecked {
            uint256 mask = (uint256(1) << 128) - 1; // safe: shift < 256
            set &= mask; // zero out bits >= 128
        }

        uint256 n = LibBit.popCount(set);
        n = bound(n, 0, 128);
        k = bound(k, 0, n);

        Combinations.generateSubsets(set, k);
    }

    function testGenerateSetsWithZeroK(uint256 set) external {
        unchecked {
            uint256 mask = (uint256(1) << 128) - 1; // safe: shift < 256
            set &= mask; // zero out bits >= 128
        }

        uint256 n = LibBit.popCount(set);
        n = bound(n, 0, 128);
        uint256 k = 0;

        Combinations.generateSubsets(set, k);
    }
}
