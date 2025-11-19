//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.28;

import {IEntropyV2} from "@pythnetwork/entropy-sdk-solidity/IEntropyV2.sol";

interface IEntropyComplete is IEntropyV2 {
    function register(
        uint128 feeInWei,
        bytes32 commitment,
        bytes calldata commitmentMetadata,
        uint64 chainLength,
        bytes calldata uri
    ) external;

    function revealWithCallback(
        address provider,
        uint64 sequenceNumber,
        bytes32 userRandomNumber,
        bytes32 providerRevelation
    ) external;
}
