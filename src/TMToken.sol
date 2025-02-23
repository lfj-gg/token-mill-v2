// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {ITMToken} from "./interfaces/ITMToken.sol";
import {ITMFactory} from "./interfaces/ITMFactory.sol";

contract TMToken is ERC20Upgradeable, ITMToken {
    address private immutable factory;

    constructor(address factory_) {
        _disableInitializers();

        factory = factory_;
    }

    function initialize(string memory name_, string memory symbol_) public override initializer returns (bool) {
        __ERC20_init(name_, symbol_);
        return true;
    }

    function getFactory() public view override returns (address) {
        return factory;
    }

    function mint(address to, uint256 amount) public override returns (bool) {
        if (amount == 0) revert ZeroAmount();
        if (totalSupply() > 0) revert AlreadyMinted();
        if (ITMFactory(factory).getMarketOf(address(this)) != msg.sender) revert Unauthorized();

        _mint(to, amount);
        return true;
    }
}
