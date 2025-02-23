// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITMToken is IERC20 {
    error ZeroAmount();
    error AlreadyMinted();
    error Unauthorized();

    function initialize(string memory name_, string memory symbol_) external returns (bool);
    function getFactory() external view returns (address);
    function mint(address to, uint256 amount) external returns (bool);
}
