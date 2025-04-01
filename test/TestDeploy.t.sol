// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "script/Deploy.s.sol";

contract TestDeploy is Deploy, Test {
    address constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    function setUp() public {
        vm.createSelectFork(StdChains.getChain("avalanche").rpcUrl, 57775388);
        quoteToken = WAVAX;
    }

    function test_Deploy() public {
        (address marketImp, address tokenImp,, address factoryProxy) = run();

        assertEq(ITMMarket(marketImp).getFactory(), factoryProxy, "test_Deploy::1");
        assertEq(ITMMarket(marketImp).getQuoteToken(), WAVAX, "test_Deploy::2");
        assertEq(ITMToken(tokenImp).getFactory(), factoryProxy, "test_Deploy::3");
        assertEq(ITMFactory(factoryProxy).getMarketImplementation(WAVAX), marketImp, "test_Deploy::4");
        assertEq(ITMFactory(factoryProxy).getTokenImplementation(), tokenImp, "test_Deploy::5");
    }
}
