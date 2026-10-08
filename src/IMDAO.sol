// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @notice Fixed supply, freely transferable, block-checkpointed LOCAL FIXTURE.
contract IMDAO is ERC20Votes {
    constructor(address fixtureHolder) ERC20("IMDAO", "IMDAO") EIP712("IMDAO", "1") {
        require(fixtureHolder != address(0), "zero holder");
        _mint(fixtureHolder, 1_000_000 ether);
    }
}

/// @notice Separate delegated voting fixture; no connection to live IMD or treasury assets.
contract MockIMD is ERC20Votes {
    constructor(address fixtureHolder) ERC20("Mock IMD Votes", "mIMD") EIP712("Mock IMD Votes", "1") {
        require(fixtureHolder != address(0), "zero holder");
        _mint(fixtureHolder, 1_000_000 ether);
    }
}

contract MockAsset is ERC20 {
    constructor(address fixtureHolder) ERC20("Valueless Pair Asset", "LOCAL") {
        require(fixtureHolder != address(0), "zero holder");
        _mint(fixtureHolder, 1_000_000 ether);
    }
}
