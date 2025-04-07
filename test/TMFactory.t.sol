// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "forge-std/Test.sol";

import "src/TMFactory.sol";
import "src/TMToken.sol";
import "src/TMMarket.sol";
import "test/mocks/MockERC20.sol";

contract TestTMFactory is Test {
    address tokenImplementation;
    address marketImplementation;
    address factory;

    uint256 defaultProtocolFeeShare = 0.2e6; // 20%
    uint256 defaultMinUpdateTime = 100;
    uint256 defaultFee = 0.01e6; // 1%

    address admin = makeAddr("admin");
    address quoteToken = makeAddr("quoteToken");

    uint256 constant supply = 1e18;

    function setUp() public {
        address factoryAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);

        tokenImplementation = address(new TMToken(factoryAddress));
        marketImplementation =
            address(new TMMarket(factoryAddress, quoteToken, supply / 2, supply / 2, 1 << 96, 2 << 96));

        factory = address(
            new TMFactory(
                defaultMinUpdateTime,
                defaultProtocolFeeShare,
                defaultFee,
                quoteToken,
                marketImplementation,
                tokenImplementation,
                admin
            )
        );

        assertEq(factory, factoryAddress, "setUp::1");
    }

    function test_Constructor() public {
        assertEq(TMFactory(factory).PROTOCOL_FEE_RECIPIENT(), address(0), "test_Constructor::1");
        assertEq(
            TMFactory(factory).PROTOCOL_FEE_COLLECTOR_ROLE(),
            keccak256("PROTOCOL_FEE_COLLECTOR_ROLE"),
            "test_Constructor::2"
        );
        assertEq(TMFactory(factory).KOTM_FEE_RECIPIENT(), factory, "test_Constructor::3");
        assertEq(TMFactory(factory).KOTM_COLLECTOR_ROLE(), keccak256("KOTM_COLLECTOR_ROLE"), "test_Constructor::4");

        assertEq(TMFactory(factory).hasRole(bytes32(0), admin), true, "test_Constructor::5");
        assertEq(TMFactory(factory).getMarketImplementation(quoteToken), marketImplementation, "test_Constructor::6");
        assertEq(TMFactory(factory).getTokenImplementation(), tokenImplementation, "test_Constructor::7");
        assertEq(TMFactory(factory).getMinUpdateTime(), defaultMinUpdateTime, "test_Constructor::8");
        assertEq(TMFactory(factory).getProtocolFeeShare(), defaultProtocolFeeShare, "test_Constructor::9");
        assertEq(TMFactory(factory).getDefaultFee(), defaultFee, "test_Constructor::10");
        assertEq(TMFactory(factory).getTokensLength(), 0, "test_Constructor::11");
        assertEq(TMFactory(factory).getMarketsLength(), 0, "test_Constructor::12");
        assertEq(TMFactory(factory).getQuoteTokensLength(), 1, "test_Constructor::13");
        assertEq(TMFactory(factory).getQuoteTokenAt(0), quoteToken, "test_Constructor::14");

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        TMFactory(factory).initialize(0, 0, 0, address(0), address(0), address(0), address(0));
    }

    function test_Fuzz_SetMinUpdateTime(uint256 minUpdateTime) public {
        minUpdateTime = bound(minUpdateTime, 1, type(uint88).max);

        vm.prank(admin);
        TMFactory(factory).setMinUpdateTime(minUpdateTime);

        assertEq(TMFactory(factory).getMinUpdateTime(), minUpdateTime, "test_Fuzz_SetMinUpdateTime::1");

        vm.prank(admin);
        TMFactory(factory).setMinUpdateTime(0);

        assertEq(TMFactory(factory).getMinUpdateTime(), 0, "test_Fuzz_SetMinUpdateTime::2");

        vm.prank(admin);
        TMFactory(factory).setMinUpdateTime(minUpdateTime);

        assertEq(TMFactory(factory).getMinUpdateTime(), minUpdateTime, "test_Fuzz_SetMinUpdateTime::3");
    }

    function test_Fuzz_Revert_SetMinUpdateTime(uint256 minUpdateTime) public {
        minUpdateTime = bound(minUpdateTime, uint256(type(uint88).max) + 1, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(1), bytes32(0))
        );
        vm.prank(address(1));
        TMFactory(factory).setMinUpdateTime(0);

        vm.prank(admin);
        vm.expectRevert(ITMFactory.InvalidMinUpdateTime.selector);
        TMFactory(factory).setMinUpdateTime(minUpdateTime);
    }

    function test_Fuzz_SetProtocolFeeShare(uint256 protocolFeeShare) public {
        protocolFeeShare = bound(protocolFeeShare, 0, 1e6);

        vm.prank(admin);
        TMFactory(factory).setProtocolFeeShare(protocolFeeShare);

        assertEq(TMFactory(factory).getProtocolFeeShare(), protocolFeeShare, "test_Fuzz_SetProtocolFeeShare::1");

        vm.prank(admin);
        TMFactory(factory).setProtocolFeeShare(0);

        assertEq(TMFactory(factory).getProtocolFeeShare(), 0, "test_Fuzz_SetProtocolFeeShare::2");

        vm.prank(admin);
        TMFactory(factory).setProtocolFeeShare(protocolFeeShare);

        assertEq(TMFactory(factory).getProtocolFeeShare(), protocolFeeShare, "test_Fuzz_SetProtocolFeeShare::3");
    }

    function test_Fuzz_Revert_SetProtocolFeeShare(address caller, uint256 protocolFeeShare) public {
        if (caller == admin) caller = address(1);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, bytes32(0))
        );
        vm.prank(caller);
        TMFactory(factory).setProtocolFeeShare(0);

        vm.prank(admin);
        vm.expectRevert(ITMFactory.InvalidFee.selector);
        TMFactory(factory).setProtocolFeeShare(bound(protocolFeeShare, 1e6 + 1, type(uint256).max));
    }

    function test_Fuzz_SetDefaultFee(uint256 fee) public {
        fee = bound(fee, 0, 1e6);

        vm.prank(admin);
        TMFactory(factory).setDefaultFee(fee);

        assertEq(TMFactory(factory).getDefaultFee(), fee, "test_Fuzz_SetDefaultFee::1");

        vm.prank(admin);
        TMFactory(factory).setDefaultFee(0);

        assertEq(TMFactory(factory).getDefaultFee(), 0, "test_Fuzz_SetDefaultFee::2");

        vm.prank(admin);
        TMFactory(factory).setDefaultFee(fee);

        assertEq(TMFactory(factory).getDefaultFee(), fee, "test_Fuzz_SetDefaultFee::3");
    }

    function test_Fuzz_Revert_SetDefaultFee(address caller, uint256 fee) public {
        if (caller == admin) caller = address(1);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, bytes32(0))
        );
        vm.prank(caller);
        TMFactory(factory).setDefaultFee(0);

        vm.prank(admin);
        vm.expectRevert(ITMFactory.InvalidFee.selector);
        TMFactory(factory).setDefaultFee(bound(fee, 1e6 + 1, type(uint256).max));
    }

    function test_Fuzz_SetMarketImplementation(address[] memory quotes, uint256 toRemove) public {
        vm.assume(quotes.length > 0);

        vm.prank(admin);
        ITMFactory(factory).setMarketImplementation(quoteToken, address(0)); // Reset market implementation

        uint256 length = quotes.length;
        if (length > 8) {
            length = 8;
            assembly ("memory-safe") {
                mstore(quotes, length)
            }
        }
        if (toRemove >= length) toRemove = length - 1;

        address[] memory implementations = new address[](length);

        address lastQuote;
        for (uint256 i = 0; i < length; i++) {
            quotes[i] =
                address(uint160(bound(uint160(quotes[i]), uint160(lastQuote) + 1, type(uint160).max - length + i)));
            implementations[i] = address(new MockMarketImplementation(quotes[i]));
            lastQuote = quotes[i];

            vm.prank(admin);
            TMFactory(factory).setMarketImplementation(quotes[i], implementations[i]);

            assertEq(
                TMFactory(factory).getMarketImplementation(quotes[i]),
                implementations[i],
                "test_Fuzz_SetMarketImplementation::1"
            );
            assertEq(TMFactory(factory).getQuoteTokensLength(), i + 1, "test_Fuzz_SetMarketImplementation::2");
            assertEq(TMFactory(factory).getQuoteTokenAt(i), quotes[i], "test_Fuzz_SetMarketImplementation::3");
        }

        vm.prank(admin);
        TMFactory(factory).setMarketImplementation(quotes[toRemove], address(0));

        assertEq(
            TMFactory(factory).getMarketImplementation(quotes[toRemove]),
            address(0),
            "test_Fuzz_SetMarketImplementation::4"
        );
        assertEq(TMFactory(factory).getQuoteTokensLength(), length - 1, "test_Fuzz_SetMarketImplementation::5");
        if (toRemove != length - 1) {
            assertEq(
                TMFactory(factory).getQuoteTokenAt(toRemove), quotes[length - 1], "test_Fuzz_SetMarketImplementation::6"
            );
        }
    }

    function test_SetMarketImplementation() public {
        vm.prank(admin);
        ITMFactory(factory).setMarketImplementation(quoteToken, address(0)); // Reset market implementation

        address quote0 = makeAddr("quote0");
        address quote1 = makeAddr("quote1");
        address imp0A = address(new MockMarketImplementation(quote0));
        address imp0B = address(new MockMarketImplementation(quote0));
        address imp1A = address(new MockMarketImplementation(quote1));
        address imp1B = address(new MockMarketImplementation(quote1));

        vm.startPrank(admin);
        TMFactory(factory).setMarketImplementation(quote0, imp0A);
        TMFactory(factory).setMarketImplementation(quote1, imp1A);

        assertEq(TMFactory(factory).getMarketImplementation(quote0), imp0A, "test_SetMarketImplementation::1");
        assertEq(TMFactory(factory).getMarketImplementation(quote1), imp1A, "test_SetMarketImplementation::2");
        assertEq(TMFactory(factory).getQuoteTokensLength(), 2, "test_SetMarketImplementation::3");
        assertEq(TMFactory(factory).getQuoteTokenAt(0), quote0, "test_SetMarketImplementation::4");
        assertEq(TMFactory(factory).getQuoteTokenAt(1), quote1, "test_SetMarketImplementation::5");

        TMFactory(factory).setMarketImplementation(quote0, imp0B);
        TMFactory(factory).setMarketImplementation(quote1, imp1B);

        assertEq(TMFactory(factory).getMarketImplementation(quote0), imp0B, "test_SetMarketImplementation::6");
        assertEq(TMFactory(factory).getMarketImplementation(quote1), imp1B, "test_SetMarketImplementation::7");
        assertEq(TMFactory(factory).getQuoteTokensLength(), 2, "test_SetMarketImplementation::8");
        assertEq(TMFactory(factory).getQuoteTokenAt(0), quote0, "test_SetMarketImplementation::9");
        assertEq(TMFactory(factory).getQuoteTokenAt(1), quote1, "test_SetMarketImplementation::10");

        TMFactory(factory).setMarketImplementation(quote0, address(0));

        assertEq(TMFactory(factory).getMarketImplementation(quote0), address(0), "test_SetMarketImplementation::11");
        assertEq(TMFactory(factory).getQuoteTokensLength(), 1, "test_SetMarketImplementation::12");
        assertEq(TMFactory(factory).getQuoteTokenAt(0), quote1, "test_SetMarketImplementation::13");

        TMFactory(factory).setMarketImplementation(quote1, address(0));

        assertEq(TMFactory(factory).getMarketImplementation(quote1), address(0), "test_SetMarketImplementation::14");
        assertEq(TMFactory(factory).getQuoteTokensLength(), 0, "test_SetMarketImplementation::15");

        TMFactory(factory).setMarketImplementation(quote0, imp0A);
        TMFactory(factory).setMarketImplementation(quote1, imp1A);

        assertEq(TMFactory(factory).getMarketImplementation(quote0), imp0A, "test_SetMarketImplementation::16");
        assertEq(TMFactory(factory).getMarketImplementation(quote1), imp1A, "test_SetMarketImplementation::17");
        assertEq(TMFactory(factory).getQuoteTokensLength(), 2, "test_SetMarketImplementation::18");
        assertEq(TMFactory(factory).getQuoteTokenAt(0), quote0, "test_SetMarketImplementation::19");
        assertEq(TMFactory(factory).getQuoteTokenAt(1), quote1, "test_SetMarketImplementation::20");
        vm.stopPrank();
    }

    function test_Fuzz_Revert_SetMarketImplementation(address caller, address quote) public {
        if (caller == admin) caller = address(1);
        if (quote == quoteToken) quote = address(0);

        vm.expectRevert(ITMFactory.MismatchedQuoteToken.selector);
        vm.prank(admin);
        TMFactory(factory).setMarketImplementation(quote, marketImplementation);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, bytes32(0))
        );
        vm.prank(caller);
        TMFactory(factory).setMarketImplementation(address(0), address(0));
    }

    function test_Fuzz_SetTokenImplementation(address implementation) public {
        vm.prank(admin);
        TMFactory(factory).setTokenImplementation(implementation);

        assertEq(TMFactory(factory).getTokenImplementation(), implementation, "test_Fuzz_SetTokenImplementation::1");

        vm.prank(admin);
        TMFactory(factory).setTokenImplementation(address(0));

        assertEq(TMFactory(factory).getTokenImplementation(), address(0), "test_Fuzz_SetTokenImplementation::2");

        vm.prank(admin);
        TMFactory(factory).setTokenImplementation(implementation);

        assertEq(TMFactory(factory).getTokenImplementation(), implementation, "test_Fuzz_SetTokenImplementation::3");
    }

    function test_Fuzz_Revert_SetTokenImplementation(address caller) public {
        if (caller == admin) caller = address(1);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, bytes32(0))
        );
        vm.prank(caller);
        TMFactory(factory).setTokenImplementation(address(0));
    }

    function test_Fuzz_CreateMarket(address caller) public {
        vm.prank(caller);
        (address token, address market) = TMFactory(factory).createMarket("Test Name", "Test Symbol", quoteToken);

        assertEq(ERC20(token).name(), "Test Name", "test_Fuzz_CreateMarket::1");
        assertEq(ERC20(token).symbol(), "Test Symbol", "test_Fuzz_CreateMarket::2");
        assertEq(ERC20(token).decimals(), 18, "test_Fuzz_CreateMarket::3");
        assertEq(ITMToken(token).getFactory(), factory, "test_Fuzz_CreateMarket::4");
        assertEq(ITMToken(token).totalSupply(), supply, "test_Fuzz_CreateMarket::5");
        assertEq(ITMToken(token).balanceOf(market), supply, "test_Fuzz_CreateMarket::6");

        assertEq(ITMMarket(market).getFactory(), factory, "test_Fuzz_CreateMarket::7");
        assertEq(ITMMarket(market).getBaseToken(), token, "test_Fuzz_CreateMarket::8");
        assertEq(ITMMarket(market).getQuoteToken(), quoteToken, "test_Fuzz_CreateMarket::9");
        assertEq(ITMMarket(market).getFee(), defaultFee, "test_Fuzz_CreateMarket::10");
        assertEq(ITMMarket(market).getCurrentSqrtRatio(), 1 << 96, "test_Fuzz_CreateMarket::11");

        assertEq(TMFactory(factory).getTokensLength(), 1, "test_Fuzz_CreateMarket::12");
        assertEq(TMFactory(factory).getTokenAt(0), token, "test_Fuzz_CreateMarket::13");
        assertEq(TMFactory(factory).getMarketsLength(), 1, "test_Fuzz_CreateMarket::14");
        assertEq(TMFactory(factory).getMarketAt(0), market, "test_Fuzz_CreateMarket::15");
        assertEq(TMFactory(factory).getMarketOf(token), market, "test_Fuzz_CreateMarket::16");
        assertEq(TMFactory(factory).getMarketByCreatorLength(caller), 1, "test_Fuzz_CreateMarket::17");
        assertEq(TMFactory(factory).getMarketByCreatorAt(caller, 0), market, "test_Fuzz_CreateMarket::18");

        ITMFactory.MarketDetails memory details = TMFactory(factory).getMarketDetails(market);
        assertEq(details.initialized, true, "test_Fuzz_CreateMarket::19");
        assertEq(details.creator, caller, "test_Fuzz_CreateMarket::20");
        assertEq(details.feeRecipient, ITMFactory(factory).KOTM_FEE_RECIPIENT(), "test_Fuzz_CreateMarket::21");
    }

    function test_Fuzz_Revert_CreateMarket(address quoteToken_) public {
        vm.prank(admin);
        TMFactory(factory).setMarketImplementation(quoteToken, address(0)); // Reset market implementation

        if (quoteToken_ == address(0)) quoteToken_ = address(1);
        address implementation = address(new MockMarketImplementation(quoteToken_));

        vm.expectRevert(ITMFactory.QuoteTokenNotSupported.selector);
        TMFactory(factory).createMarket("", "", quoteToken_);

        vm.startPrank(admin);
        TMFactory(factory).setMarketImplementation(quoteToken_, implementation);

        vm.expectRevert(ITMFactory.QuoteTokenNotSupported.selector);
        TMFactory(factory).createMarket("", "", address(0));

        TMFactory(factory).setTokenImplementation(address(0));

        vm.expectRevert(ITMFactory.TokenImplementationNotSet.selector);
        TMFactory(factory).createMarket("", "", quoteToken_);

        TMFactory(factory).setMarketImplementation(quoteToken_, address(0));

        vm.expectRevert(ITMFactory.QuoteTokenNotSupported.selector);
        TMFactory(factory).createMarket("", "", quoteToken_);

        vm.stopPrank();
    }

    function test_Fuzz_OnFeeReceivedAndCollect(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max / 1e6);

        quoteToken = address(new MockERC20());
        marketImplementation = address(new TMMarket(factory, quoteToken, supply / 2, supply / 2, 1 << 96, 2 << 96));
        vm.prank(admin);
        TMFactory(factory).setMarketImplementation(quoteToken, marketImplementation);

        (, address market) = TMFactory(factory).createMarket("Test Name", "Test Symbol", quoteToken);

        MockERC20(quoteToken).mint(factory, amount);
        vm.prank(market);
        TMFactory(factory).onFeeReceived(quoteToken, amount);

        address protocolFeeRecipient = ITMFactory(factory).PROTOCOL_FEE_RECIPIENT();
        address feeRecipient = ITMFactory(factory).getMarketDetails(market).feeRecipient;

        uint256 protocolFee = Math.divUp(amount * defaultProtocolFeeShare, 1e6);
        uint256 fee = amount - protocolFee;

        assertEq(MockERC20(quoteToken).balanceOf(factory), amount, "test_Fuzz_OnFeeReceivedAndCollect::1");
        assertEq(
            TMFactory(factory).getUnclaimedFees(quoteToken, feeRecipient), fee, "test_Fuzz_OnFeeReceivedAndCollect::2"
        );
        assertEq(
            TMFactory(factory).getUnclaimedFees(quoteToken, protocolFeeRecipient),
            protocolFee,
            "test_Fuzz_OnFeeReceivedAndCollect::3"
        );

        MockERC20(quoteToken).mint(factory, amount);
        vm.prank(market);
        TMFactory(factory).onFeeReceived(quoteToken, amount);

        assertEq(MockERC20(quoteToken).balanceOf(factory), amount * 2, "test_Fuzz_OnFeeReceivedAndCollect::4");
        assertEq(
            TMFactory(factory).getUnclaimedFees(quoteToken, feeRecipient),
            fee * 2,
            "test_Fuzz_OnFeeReceivedAndCollect::5"
        );
        assertEq(
            TMFactory(factory).getUnclaimedFees(quoteToken, protocolFeeRecipient),
            protocolFee * 2,
            "test_Fuzz_OnFeeReceivedAndCollect::6"
        );

        vm.startPrank(admin);
        TMFactory(factory).grantRole(TMFactory(factory).KOTM_COLLECTOR_ROLE(), address(1));
        TMFactory(factory).grantRole(TMFactory(factory).PROTOCOL_FEE_COLLECTOR_ROLE(), address(2));
        vm.stopPrank();

        vm.prank(address(1));
        TMFactory(factory).collect(quoteToken, feeRecipient, address(1), fee);

        assertEq(MockERC20(quoteToken).balanceOf(address(1)), fee, "test_Fuzz_OnFeeReceivedAndCollect::7");
        assertEq(
            TMFactory(factory).getUnclaimedFees(quoteToken, feeRecipient), fee, "test_Fuzz_OnFeeReceivedAndCollect::8"
        );

        vm.prank(address(2));
        TMFactory(factory).collect(quoteToken, protocolFeeRecipient, address(2), protocolFee);

        assertEq(MockERC20(quoteToken).balanceOf(address(2)), protocolFee, "test_Fuzz_OnFeeReceivedAndCollect::9");
        assertEq(
            TMFactory(factory).getUnclaimedFees(quoteToken, protocolFeeRecipient),
            protocolFee,
            "test_Fuzz_OnFeeReceivedAndCollect::10"
        );

        vm.prank(feeRecipient);
        TMFactory(factory).collect(quoteToken, feeRecipient, address(1), fee);

        assertEq(MockERC20(quoteToken).balanceOf(address(1)), fee * 2, "test_Fuzz_OnFeeReceivedAndCollect::11");
        assertEq(
            TMFactory(factory).getUnclaimedFees(quoteToken, feeRecipient), 0, "test_Fuzz_OnFeeReceivedAndCollect::12"
        );

        vm.prank(protocolFeeRecipient);
        TMFactory(factory).collect(quoteToken, protocolFeeRecipient, address(2), protocolFee);

        assertEq(MockERC20(quoteToken).balanceOf(address(2)), protocolFee * 2, "test_Fuzz_OnFeeReceivedAndCollect::13");
        assertEq(
            TMFactory(factory).getUnclaimedFees(quoteToken, protocolFeeRecipient),
            0,
            "test_Fuzz_OnFeeReceivedAndCollect::14"
        );
    }

    function test_Fuzz_Revert_OnFeeReceived(address invalidMarket) public {
        (, address market) = TMFactory(factory).createMarket("", "", quoteToken);

        if (invalidMarket == market) invalidMarket = address(1);

        vm.prank(invalidMarket);
        vm.expectRevert(ITMFactory.InvalidMarket.selector);
        TMFactory(factory).onFeeReceived(quoteToken, 0);
    }

    function test_Fuzz_Revert_Collect(address token, address caller, address account, address recipient, uint256 amount)
        public
    {
        amount = bound(amount, 1, type(uint256).max - 1);

        address protocolFeeRecipient = ITMFactory(factory).PROTOCOL_FEE_RECIPIENT();
        address feeRecipient = TMFactory(factory).KOTM_FEE_RECIPIENT();

        vm.assume(
            caller != account && caller != protocolFeeRecipient && caller != feeRecipient
                && account != protocolFeeRecipient && account != feeRecipient
        );

        vm.startPrank(admin);
        TMFactory(factory).setProtocolFeeShare(0);
        (, address market) = TMFactory(factory).createMarket("", "", quoteToken);
        vm.stopPrank();

        vm.prank(caller);
        vm.expectRevert(ITMFactory.Unauthorized.selector);
        TMFactory(factory).collect(token, account, recipient, amount);

        vm.startPrank(admin);
        TMFactory(factory).grantRole(TMFactory(factory).KOTM_COLLECTOR_ROLE(), caller);
        vm.stopPrank();

        vm.prank(caller);
        vm.expectRevert(ITMFactory.Unauthorized.selector);
        TMFactory(factory).collect(token, account, recipient, amount);

        vm.prank(caller);
        vm.expectRevert(ITMFactory.Unauthorized.selector);
        TMFactory(factory).collect(token, protocolFeeRecipient, recipient, amount);

        vm.startPrank(admin);
        TMFactory(factory).grantRole(TMFactory(factory).PROTOCOL_FEE_COLLECTOR_ROLE(), caller);
        TMFactory(factory).revokeRole(TMFactory(factory).KOTM_COLLECTOR_ROLE(), caller);
        vm.stopPrank();

        vm.prank(caller);
        vm.expectRevert(ITMFactory.Unauthorized.selector);
        TMFactory(factory).collect(token, account, recipient, amount);

        vm.prank(caller);
        vm.expectRevert(ITMFactory.Unauthorized.selector);
        TMFactory(factory).collect(token, feeRecipient, recipient, amount);

        vm.prank(caller);
        vm.expectRevert(ITMFactory.InsufficientFunds.selector);
        TMFactory(factory).collect(token, caller, recipient, amount);

        vm.prank(market);
        TMFactory(factory).onFeeReceived(token, amount);

        vm.prank(caller);
        vm.expectRevert(ITMFactory.InsufficientFunds.selector);
        TMFactory(factory).collect(token, caller, recipient, amount + 1);

        vm.prank(caller);
        vm.expectRevert(ITMFactory.InsufficientFunds.selector);
        TMFactory(factory).collect(token, protocolFeeRecipient, recipient, amount);
    }

    function test_Fuzz_UpdateMarketDetails(address creator, address feeRecipient) public {
        if (creator == address(this)) creator = address(1);

        vm.prank(admin);
        TMFactory(factory).setMinUpdateTime(100);

        (, address market) = TMFactory(factory).createMarket("", "", quoteToken);

        ITMFactory.MarketDetails memory details = TMFactory(factory).getMarketDetails(market);

        assertEq(details.initialized, true, "test_Fuzz_UpdateMarketDetails::1");
        assertEq(details.lastFeeRecipientUpdate, block.timestamp, "test_Fuzz_UpdateMarketDetails::2");
        assertEq(details.creator, address(this), "test_Fuzz_UpdateMarketDetails::3");
        assertEq(details.feeRecipient, ITMFactory(factory).KOTM_FEE_RECIPIENT(), "test_Fuzz_UpdateMarketDetails::4");

        assertEq(TMFactory(factory).getMarketByCreatorLength(address(this)), 1, "test_Fuzz_UpdateMarketDetails::5");
        assertEq(TMFactory(factory).getMarketByCreatorAt(address(this), 0), market, "test_Fuzz_UpdateMarketDetails::6");

        assertEq(TMFactory(factory).getMarketByCreatorLength(creator), 0, "test_Fuzz_UpdateMarketDetails::7");

        vm.warp(block.timestamp + 100);

        TMFactory(factory).updateMarketDetails(market, creator, feeRecipient);

        details = TMFactory(factory).getMarketDetails(market);

        assertEq(details.initialized, true, "test_Fuzz_UpdateMarketDetails::8");
        assertEq(details.lastFeeRecipientUpdate, block.timestamp, "test_Fuzz_UpdateMarketDetails::9");
        assertEq(details.creator, creator, "test_Fuzz_UpdateMarketDetails::10");
        assertEq(details.feeRecipient, feeRecipient, "test_Fuzz_UpdateMarketDetails::11");

        assertEq(TMFactory(factory).getMarketByCreatorLength(address(this)), 0, "test_Fuzz_UpdateMarketDetails::12");
        assertEq(TMFactory(factory).getMarketByCreatorLength(creator), 1, "test_Fuzz_UpdateMarketDetails::13");
        assertEq(TMFactory(factory).getMarketByCreatorAt(creator, 0), market, "test_Fuzz_UpdateMarketDetails::14");

        unchecked {
            vm.startPrank(creator);

            address newFeeRecipient = address(uint160(feeRecipient) + 1);

            vm.expectRevert(abi.encodeWithSelector(ITMFactory.MinUpdateTimeNotPassed.selector, block.timestamp + 100));
            TMFactory(factory).updateMarketDetails(market, creator, newFeeRecipient);

            vm.warp(block.timestamp + 99);
            vm.expectRevert(abi.encodeWithSelector(ITMFactory.MinUpdateTimeNotPassed.selector, block.timestamp + 1));
            TMFactory(factory).updateMarketDetails(market, creator, newFeeRecipient);

            vm.warp(block.timestamp + 1);
            TMFactory(factory).updateMarketDetails(market, creator, newFeeRecipient);

            vm.stopPrank();

            details = TMFactory(factory).getMarketDetails(market);

            assertEq(details.initialized, true, "test_Fuzz_UpdateMarketDetails::15");
            assertEq(details.lastFeeRecipientUpdate, block.timestamp, "test_Fuzz_UpdateMarketDetails::16");
            assertEq(details.creator, creator, "test_Fuzz_UpdateMarketDetails::17");
            assertEq(details.feeRecipient, newFeeRecipient, "test_Fuzz_UpdateMarketDetails::18");
        }
    }

    function test_Fuzz_Revert_UpdateMarketDetails(address caller, address market) public {
        if (caller == address(this)) caller = address(1);

        vm.expectRevert(ITMFactory.InvalidMarket.selector);
        TMFactory(factory).updateMarketDetails(market, address(0), address(0));

        (, market) = TMFactory(factory).createMarket("", "", quoteToken);

        vm.expectRevert(ITMFactory.Unauthorized.selector);
        vm.prank(caller);
        TMFactory(factory).updateMarketDetails(market, address(0), address(0));
    }
}

contract MockMarketImplementation {
    address public immutable getQuoteToken;

    constructor(address quoteToken) {
        getQuoteToken = quoteToken;
    }
}
