// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {Test} from "forge-std/Test.sol";

import {ITMToken, TMToken} from "src/TMToken.sol";

contract TestTMToken is Test {
    address implementation;
    address token;

    address market = makeAddr("market");

    function getMarketOf(address) public view returns (address) {
        return market;
    }

    function setUp() public {
        implementation = address(new TMToken(address(this)));
        token = Clones.clone(implementation);

        TMToken(token).initialize("Token Name", "Token Symbol");
    }

    function test_Constructor() public {
        assertEq(TMToken(token).getFactory(), address(this), "test_Constructor::1");
        assertEq(TMToken(implementation).getFactory(), address(this), "test_Constructor::2");
        assertEq(TMToken(token).name(), "Token Name", "test_Constructor::3");
        assertEq(TMToken(token).symbol(), "Token Symbol", "test_Constructor::4");
        assertEq(TMToken(token).decimals(), 18, "test_Constructor::5");

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        TMToken(implementation).initialize("", "");
    }

    function test_Fuzz_Mint(address to, uint256 amount) public {
        if (to == address(0)) to = address(1);
        amount = bound(amount, 1, type(uint256).max);

        vm.prank(market);
        ITMToken(token).mint(to, amount);

        assertEq(TMToken(token).balanceOf(to), amount, "test_Fuzz_Mint::1");
    }

    function test_Fuzz_Revert_Mint(address caller) public {
        if (caller == market) caller = address(1);

        vm.expectRevert(ITMToken.ZeroAmount.selector);
        ITMToken(token).mint(address(1), 0);

        vm.prank(caller);
        vm.expectRevert(ITMToken.Unauthorized.selector);
        ITMToken(token).mint(address(1), 1);

        vm.prank(market);
        ITMToken(token).mint(address(1), 1);

        vm.expectRevert(ITMToken.AlreadyMinted.selector);
        vm.prank(market);
        ITMToken(token).mint(address(1), 1);

        vm.expectRevert(ITMToken.AlreadyMinted.selector);
        vm.prank(caller);
        ITMToken(token).mint(address(1), 1);
    }
}
