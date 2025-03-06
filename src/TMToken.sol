// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {ITMToken} from "./interfaces/ITMToken.sol";
import {ITMFactory} from "./interfaces/ITMFactory.sol";

/**
 * @title TokenMill Token contract
 * @dev Simple ERC20 token with minting function that can only be called once.
 */
contract TMToken is ERC20Upgradeable, ITMToken {
    address private immutable factory;

    /**
     * @dev Sets the immutable values for {factory}.
     */
    constructor(address factory_) {
        _disableInitializers();

        factory = factory_;
    }

    /**
     * @dev Initializes the contract with {name_} and {symbol_}.
     */
    function initialize(string memory name_, string memory symbol_) public override initializer returns (bool) {
        __ERC20_init(name_, symbol_);
        return true;
    }

    /**
     * @dev Returns the address of the factory.
     * The factory is used to check if the caller is authorized to mint tokens.
     */
    function getFactory() public view override returns (address) {
        return factory;
    }

    /**
     * @dev Mints {amount} of tokens to {to}.
     * The caller must be the market that created this token.
     *
     * Requirements:
     *
     * - {amount} must be greater than 0
     * - The total supply must be 0 (no tokens minted yet)
     * - The caller must be the market that created this token
     * - This function was not called successfully before
     */
    function mint(address to, uint256 amount) public override returns (bool) {
        if (amount == 0) revert ZeroAmount();
        if (totalSupply() > 0) revert AlreadyMinted();
        if (ITMFactory(factory).getMarketOf(address(this)) != msg.sender) revert Unauthorized();

        _mint(to, amount);
        return true;
    }
}
