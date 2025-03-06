// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "script/Deploy.s.sol";

contract TestDeploy is Deploy, Test {
    function setUp() public {
        vm.createSelectFork(StdChains.getChain("avalanche").rpcUrl, 57775388);
    }

    function test_Deploy() public {
        (address marketImp, address tokenImp,, address factoryProxy) = run();

        assertEq(ITMMarket(marketImp).getFactory(), factoryProxy, "test_Deploy::1");
        assertEq(ITMToken(tokenImp).getFactory(), factoryProxy, "test_Deploy::2");
        assertEq(ITMFactory(factoryProxy).getMarketImplementation(), marketImp, "test_Deploy::3");
        assertEq(ITMFactory(factoryProxy).getTokenImplementation(), tokenImp, "test_Deploy::4");
    }
}
