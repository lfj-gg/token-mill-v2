// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "src/TMMarket.sol";
import "src/TMToken.sol";
import "src/TMFactory.sol";
import "script/Parameters.sol";
import "test/mocks/MockERC20.sol";

contract TestTMMarket is Test, Parameters {
    address tokenImplementation;
    address marketImplementation;
    address factory;
    address market;
    address token;

    address admin = makeAddr("admin");

    bytes32 constant PRICE_SLOT = bytes32(uint256(1));

    function setUp() public {
        quoteToken = address(new MockERC20());
        address factoryAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);

        tokenImplementation = address(new TMToken(factoryAddress));
        marketImplementation =
            address(new TMMarket(factoryAddress, quoteToken, amount0A, amount0B, sqrtPrice0, sqrtPrice1));

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

        (token, market) = ITMFactory(factory).createMarket("Test Name", "Test Symbol", quoteToken);
    }

    function test_Constructor() public view {
        assertEq(ITMMarket(market).getFactory(), factory, "test_Constructor::1");
        (uint256 sqrtPriceA_, uint256 sqrtPriceB_, uint256 sqrtPriceC_) = ITMMarket(market).getSqrtRatiosBounds();
        assertEq(sqrtPriceA_, sqrtPrice0, "test_Constructor::2");
        assertEq(sqrtPriceB_, sqrtPrice1, "test_Constructor::3");
        assertEq(sqrtPriceC_, 2 ** 128 - 1, "test_Constructor::4");
        (uint256 liquidityA, uint256 liquidityB) = ITMMarket(market).getLiquidities();
        assertEq(liquidityA, SwapMath.getLiquidity0(sqrtPrice0, sqrtPrice1, amount0A), "test_Constructor::5");
        assertEq(liquidityB, SwapMath.getLiquidity0(sqrtPrice1, 2 ** 128 - 1, amount0B), "test_Constructor::6");
        assertEq(ITMMarket(market).getBaseToken(), token, "test_Constructor::7");
        assertEq(ITMMarket(market).getQuoteToken(), quoteToken, "test_Constructor::8");
        assertEq(ITMMarket(market).getCurrentSqrtRatio(), sqrtPrice0, "test_Constructor::9");
        assertEq(ITMMarket(market).getFee(), defaultFee, "test_Constructor::10");
        (uint256 reserve0, uint256 reserve1) = ITMMarket(market).getReserves();
        assertEq(reserve0, amount0A + amount0B, "test_Constructor::11");
        assertEq(reserve1, 0, "test_Constructor::12");
        assertEq(ITMToken(token).getFactory(), factory, "test_Constructor::13");
        assertEq(ITMToken(token).totalSupply(), amount0A + amount0B, "test_Constructor::14");
        assertEq(ITMToken(token).balanceOf(market), amount0A + amount0B, "test_Constructor::15");
    }

    function test_Fuzz_Revert_Constructor(uint256 amountA, uint256 amountB, uint256 sqrtPriceA, uint256 sqrtPriceB)
        public
    {
        vm.expectRevert(ITMMarket.InvalidRatiosOrder.selector);
        new TMMarket(factory, address(0), 0, 0, sqrtPriceA, bound(sqrtPriceB, 0, sqrtPriceA));

        vm.expectRevert(ITMMarket.InvalidRatios.selector);
        new TMMarket(factory, address(0), 0, 0, 0, 1);

        vm.expectRevert(ITMMarket.InvalidRatios.selector);
        new TMMarket(factory, address(0), 0, 0, 1, bound(sqrtPriceB, 2 ** 128, type(uint256).max));

        vm.expectRevert(Math.Uint127Overflow.selector);
        new TMMarket(
            factory,
            address(0),
            amountA,
            bound(amountB, amountA > 2 ** 127 ? 0 : 2 ** 127 - amountA, type(uint256).max - amountA),
            2 ** 96,
            2 ** 96 + 1
        );

        vm.expectRevert(ITMMarket.LiquiditiesZero.selector);
        new TMMarket(factory, address(0), 0, 1, 2 ** 96, 2 ** 96 + 1);

        vm.expectRevert(ITMMarket.LiquiditiesZero.selector);
        new TMMarket(factory, address(0), 1, 0, 2 ** 96, 2 ** 96 + 1);

        vm.expectRevert(ITMMarket.LiquiditiesZero.selector);
        new TMMarket(factory, address(0), 0, 0, 2 ** 96, 2 ** 96 + 1);

        sqrtPriceA = 2 ** 96;
        sqrtPriceB = bound(sqrtPriceB, sqrtPriceA + 1, 2 ** 127 - 1);

        uint256 minAmountToOverflow = Math.divUp(2 ** 127 * (sqrtPriceB - sqrtPriceA), sqrtPriceB);

        vm.expectRevert(Math.Uint127Overflow.selector);
        new TMMarket(factory, address(0), bound(amountA, minAmountToOverflow, 2 ** 127), 1, sqrtPriceA, sqrtPriceB);

        sqrtPriceB = 2 ** 96 + 1;
        minAmountToOverflow = Math.divUp(2 ** 127 * (2 ** 128 - 1 - sqrtPriceB), 2 ** 128 - 1);

        vm.expectRevert(Math.Uint127Overflow.selector);
        new TMMarket(factory, address(0), 1, bound(amountB, minAmountToOverflow, 2 ** 127), sqrtPriceA, sqrtPriceB);
    }

    function test_Revert_Initialize() public {
        vm.expectRevert(ITMMarket.AlreadyInitialized.selector);
        ITMMarket(market).initialize(address(0), 0);

        vm.store(market, PRICE_SLOT, 0);

        vm.expectRevert(ITMMarket.SameTokens.selector);
        ITMMarket(market).initialize(quoteToken, 0);

        vm.expectRevert(ITMMarket.InvalidFee.selector);
        ITMMarket(market).initialize(address(1), SwapMath.MAX_FEE + 1);
    }

    function test_revert_GetDeltaAmountsAndSwap() public {
        // Move Price away from the min price
        MockERC20(quoteToken).mint(market, 100e18);
        ITMMarket(market).swap(address(0xdead), false, 100e18, 2 ** 128 - 1);

        uint256 sqrtRatio = ITMMarket(market).getCurrentSqrtRatio();

        vm.expectRevert(ITMMarket.ZeroDeltaAmount.selector);
        ITMMarket(market).swap(address(1), false, 0, 0);

        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).getDeltaAmounts(false, 1, sqrtPrice0 - 1);
        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).swap(address(1), false, 1, sqrtPrice0 - 1);

        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).getDeltaAmounts(false, 1, sqrtPrice0 - 1);
        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).swap(address(1), false, 1, sqrtPrice0 - 1);

        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).getDeltaAmounts(false, 1, sqrtRatio - 1);
        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).swap(address(1), false, 1, sqrtRatio - 1);

        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).getDeltaAmounts(false, 1, 2 ** 128);
        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).swap(address(1), false, 1, 2 ** 128);

        vm.expectRevert(Math.Int128Overflow.selector);
        ITMMarket(market).getDeltaAmounts(false, 2 ** 127, sqrtRatio + 1);
        vm.expectRevert(Math.Int128Overflow.selector);
        ITMMarket(market).swap(address(1), false, 2 ** 127, sqrtRatio + 1);

        vm.expectRevert(Math.Int128Overflow.selector);
        ITMMarket(market).getDeltaAmounts(false, -2 ** 127 - 1, sqrtRatio + 1);
        vm.expectRevert(Math.Int128Overflow.selector);
        ITMMarket(market).swap(address(1), false, -2 ** 127 - 1, sqrtRatio + 1);

        vm.expectRevert(ITMMarket.ZeroDeltaAmount.selector);
        ITMMarket(market).swap(address(1), true, 0, 0);

        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).getDeltaAmounts(true, 1, 0);
        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).swap(address(1), true, 1, 0);

        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).getDeltaAmounts(true, 1, sqrtPrice0 - 1);
        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).swap(address(1), true, 1, sqrtPrice0 - 1);

        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).getDeltaAmounts(true, 1, sqrtRatio + 1);
        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).swap(address(1), true, 1, sqrtRatio + 1);

        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).getDeltaAmounts(true, 1, 2 ** 128);
        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).swap(address(1), true, 1, 2 ** 128);

        vm.expectRevert(Math.Int128Overflow.selector);
        ITMMarket(market).getDeltaAmounts(true, 2 ** 127, sqrtRatio - 1);
        vm.expectRevert(Math.Int128Overflow.selector);
        ITMMarket(market).swap(address(1), true, 2 ** 127, sqrtRatio - 1);

        vm.expectRevert(Math.Int128Overflow.selector);
        ITMMarket(market).getDeltaAmounts(true, -2 ** 127 - 1, sqrtRatio - 1);
        vm.expectRevert(Math.Int128Overflow.selector);
        ITMMarket(market).swap(address(1), true, -2 ** 127 - 1, sqrtRatio - 1);
    }

    function test_Fuzz_Swap_OneForZero_Gt0(uint256 before, uint256 amountA, uint256 amountB) public {
        {
            (, int256 maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 128 - 1);
            before = bound(before, 1, uint256(maxAmount1) - 2);

            MockERC20(quoteToken).mint(market, before);
            ITMMarket(market).swap(address(1), false, int256(before), 2 ** 128 - 1);

            (, maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 128 - 1);
            amountA = bound(amountA, 1, uint256(maxAmount1) - 1);
            amountB = bound(amountB, 1, uint256(maxAmount1) - amountA);
        }

        uint256 snapshotId = vm.snapshotState();

        (int256 amountA0, int256 amountA1) = ITMMarket(market).getDeltaAmounts(false, int256(amountA), 2 ** 128 - 1);

        {
            MockERC20(quoteToken).mint(market, amountA);
            (int256 amountA0_, int256 amountA1_) =
                ITMMarket(market).swap(address(1), false, int256(amountA), 2 ** 128 - 1);

            assertEq(amountA0, amountA0_, "test_Fuzz_Swap_OneForZero_Gt0::1");
            assertEq(amountA1, amountA1_, "test_Fuzz_Swap_OneForZero_Gt0::2");
            assertEq(amountA1, int256(amountA), "test_Fuzz_Swap_OneForZero_Gt0::3");
        }

        (int256 amountB0, int256 amountB1) = ITMMarket(market).getDeltaAmounts(false, int256(amountB), 2 ** 128 - 1);

        {
            MockERC20(quoteToken).mint(market, amountB);
            (int256 amountB0_, int256 amountB1_) =
                ITMMarket(market).swap(address(1), false, int256(amountB), 2 ** 128 - 1);

            assertEq(amountB0, amountB0_, "test_Fuzz_Swap_OneForZero_Gt0::4");
            assertEq(amountB1, amountB1_, "test_Fuzz_Swap_OneForZero_Gt0::5");
            assertEq(amountB1, int256(amountB), "test_Fuzz_Swap_OneForZero_Gt0::6");
        }

        require(vm.revertToStateAndDelete(snapshotId), "panic");

        (int256 amountAB0, int256 amountAB1) =
            ITMMarket(market).getDeltaAmounts(false, int256(amountA + amountB), 2 ** 128 - 1);

        {
            MockERC20(quoteToken).mint(market, amountA + amountB);
            (int256 amountAB0_, int256 amountAB1_) =
                ITMMarket(market).swap(address(1), false, int256(amountA + amountB), 2 ** 128 - 1);

            assertEq(amountAB0, amountAB0_, "test_Fuzz_Swap_OneForZero_Gt0::7");
            assertEq(amountAB1, amountAB1_, "test_Fuzz_Swap_OneForZero_Gt0::8");
            assertEq(amountAB1, int256(amountA + amountB), "test_Fuzz_Swap_OneForZero_Gt0::9");
        }

        assertLe(amountA0, 0, "test_Fuzz_Swap_OneForZero_Gt0::10");
        assertLe(amountB0, 0, "test_Fuzz_Swap_OneForZero_Gt0::11");
        assertLe(amountAB0, 0, "test_Fuzz_Swap_OneForZero_Gt0::12");
        assertGe(amountA1, 0, "test_Fuzz_Swap_OneForZero_Gt0::13");
        assertGe(amountB1, 0, "test_Fuzz_Swap_OneForZero_Gt0::14");
        assertGe(amountAB1, 0, "test_Fuzz_Swap_OneForZero_Gt0::15");

        assertLe(_abs(amountA0) + _abs(amountB0), _abs(amountAB0), "test_Fuzz_Swap_OneForZero_Gt0::16");
        assertEq(_abs(amountA1) + _abs(amountB1), _abs(amountAB1), "test_Fuzz_Swap_OneForZero_Gt0::17");
    }

    function test_Fuzz_Swap_ZeroForOne_Gt0(uint256 before, uint256 amountA, uint256 amountB) public {
        {
            (, int256 maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 128 - 1);
            before = bound(before, 1, uint256(maxAmount1));

            MockERC20(quoteToken).mint(market, before);
            (int256 maxAmount0,) = ITMMarket(market).swap(address(this), false, int256(before), 2 ** 128 - 1);

            vm.assume(ITMMarket(market).getCurrentSqrtRatio() > sqrtPrice0);

            amountA = bound(amountA, 1, uint256(-maxAmount0) - 1);
            amountB = bound(amountB, 1, uint256(-maxAmount0) - amountA);
        }

        uint256 snapshotId = vm.snapshotState();

        (int256 amountA0, int256 amountA1) = ITMMarket(market).getDeltaAmounts(true, int256(amountA), sqrtPrice0);

        {
            IERC20(token).transfer(market, amountA);
            (int256 amountA0_, int256 amountA1_) = ITMMarket(market).swap(address(1), true, int256(amountA), sqrtPrice0);

            assertEq(amountA0, amountA0_, "test_Fuzz_Swap_ZeroForOne_Gt0::1");
            assertEq(amountA0, int256(amountA), "test_Fuzz_Swap_ZeroForOne_Gt0::2");
            assertEq(amountA1, amountA1_, "test_Fuzz_Swap_ZeroForOne_Gt0::3");
        }

        (int256 amountB0, int256 amountB1) = ITMMarket(market).getDeltaAmounts(true, int256(amountB), sqrtPrice0);

        {
            IERC20(token).transfer(market, amountB);
            (int256 amountB0_, int256 amountB1_) = ITMMarket(market).swap(address(1), true, int256(amountB), sqrtPrice0);

            assertEq(amountB0, amountB0_, "test_Fuzz_Swap_ZeroForOne_Gt0::4");
            assertEq(amountB0, int256(amountB), "test_Fuzz_Swap_ZeroForOne_Gt0::5");
            assertEq(amountB1, amountB1_, "test_Fuzz_Swap_ZeroForOne_Gt0::6");
        }

        require(vm.revertToStateAndDelete(snapshotId), "panic");

        (int256 amountAB0, int256 amountAB1) =
            ITMMarket(market).getDeltaAmounts(true, int256(amountA + amountB), sqrtPrice0);

        {
            IERC20(token).transfer(market, amountA + amountB);
            (int256 amountAB0_, int256 amountAB1_) =
                ITMMarket(market).swap(address(1), true, int256(amountA + amountB), sqrtPrice0);

            assertEq(amountAB0, amountAB0_, "test_Fuzz_Swap_ZeroForOne_Gt0::7");
            assertEq(amountAB0, int256(amountA + amountB), "test_Fuzz_Swap_ZeroForOne_Gt0::8");
            assertEq(amountAB1, amountAB1_, "test_Fuzz_Swap_ZeroForOne_Gt0::9");
        }

        assertGe(amountA0, 0, "test_Fuzz_Swap_ZeroForOne_Gt0::10");
        assertGe(amountB0, 0, "test_Fuzz_Swap_ZeroForOne_Gt0::11");
        assertGe(amountAB0, 0, "test_Fuzz_Swap_ZeroForOne_Gt0::12");
        assertLe(amountA1, 0, "test_Fuzz_Swap_ZeroForOne_Gt0::13");
        assertLe(amountB1, 0, "test_Fuzz_Swap_ZeroForOne_Gt0::14");
        assertLe(amountAB1, 0, "test_Fuzz_Swap_ZeroForOne_Gt0::15");

        assertEq(_abs(amountA0) + _abs(amountB0), _abs(amountAB0), "test_Fuzz_Swap_ZeroForOne_Gt0::16");
        assertLe(_abs(amountA1) + _abs(amountB1), _abs(amountAB1), "test_Fuzz_Swap_ZeroForOne_Gt0::17");
    }

    function test_Fuzz_Swap_OneForZero_Lt0(uint256 before, uint256 amountA, uint256 amountB) public {
        {
            (, int256 maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 128 - 1);
            before = bound(before, 1, uint256(maxAmount1) - 2);

            MockERC20(quoteToken).mint(market, before);
            ITMMarket(market).swap(address(1), false, int256(before), 2 ** 128 - 1);

            (int256 maxAmount0,) = ITMMarket(market).getDeltaAmounts(false, -2 ** 127, 2 ** 128 - 1);
            vm.assume(-maxAmount0 >= 2);
            amountA = bound(amountA, 1, uint256(-maxAmount0) - 1);
            amountB = bound(amountB, 1, uint256(-maxAmount0) - amountA);
        }

        uint256 snapshotId = vm.snapshotState();

        (int256 amountA0, int256 amountA1) = ITMMarket(market).getDeltaAmounts(false, -int256(amountA), 2 ** 128 - 1);

        {
            MockERC20(quoteToken).mint(market, uint256(amountA1));
            (int256 amountA0_, int256 amountA1_) =
                ITMMarket(market).swap(address(1), false, -int256(amountA), 2 ** 128 - 1);

            assertEq(amountA0, amountA0_, "test_Fuzz_Swap_OneForZero_Lt0::1");
            assertEq(amountA0, -int256(amountA), "test_Fuzz_Swap_OneForZero_Lt0::2");
            assertEq(amountA1, amountA1_, "test_Fuzz_Swap_OneForZero_Lt0::3");
        }

        (int256 amountB0, int256 amountB1) = ITMMarket(market).getDeltaAmounts(false, -int256(amountB), 2 ** 128 - 1);

        {
            MockERC20(quoteToken).mint(market, uint256(amountB1));
            (int256 amountB0_, int256 amountB1_) =
                ITMMarket(market).swap(address(1), false, -int256(amountB), 2 ** 128 - 1);

            assertEq(amountB0, amountB0_, "test_Fuzz_Swap_OneForZero_Lt0::4");
            assertLe(_abs(amountB0), amountB, "test_Fuzz_Swap_OneForZero_FirstSegment_Gt0::6"); // As the price is rounded up, we might not be able to receive the exact amou, "test_Fuzz_Swap_OneForZero_Lt0::5");
            assertEq(amountB1, amountB1_, "test_Fuzz_Swap_OneForZero_Lt0::6");
        }

        require(vm.revertToStateAndDelete(snapshotId), "panic");

        (int256 amountAB0, int256 amountAB1) =
            ITMMarket(market).getDeltaAmounts(false, -int256(amountA + amountB), 2 ** 128 - 1);

        {
            MockERC20(quoteToken).mint(market, uint256(amountAB1));
            (int256 amountAB0_, int256 amountAB1_) =
                ITMMarket(market).swap(address(1), false, -(int256(amountA + amountB)), 2 ** 128 - 1);

            assertEq(amountAB0, amountAB0_, "test_Fuzz_Swap_OneForZero_Lt0::7");
            assertEq(amountAB0, -int256(amountA + amountB), "test_Fuzz_Swap_OneForZero_Lt0::8");
            assertEq(amountAB1, amountAB1_, "test_Fuzz_Swap_OneForZero_Lt0::9");
        }

        assertLe(amountA0, 0, "test_Fuzz_Swap_OneForZero_Lt0::10");
        assertLe(amountB0, 0, "test_Fuzz_Swap_OneForZero_Lt0::11");
        assertLe(amountAB0, 0, "test_Fuzz_Swap_OneForZero_Lt0::12");
        assertGe(amountA1, 0, "test_Fuzz_Swap_OneForZero_Lt0::13");
        assertGe(amountB1, 0, "test_Fuzz_Swap_OneForZero_Lt0::14");
        assertGe(amountAB1, 0, "test_Fuzz_Swap_OneForZero_Lt0::15");

        assertLe(_abs(amountA0) + _abs(amountB0), _abs(amountAB0), "test_Fuzz_Swap_OneForZero_Lt0::16");
        assertGe(_abs(amountA1) + _abs(amountB1), _abs(amountAB1), "test_Fuzz_Swap_OneForZero_Lt0::17");
    }

    function test_Fuzz_Swap_ZeroForOne_Lt0_NoFees(uint256 before, uint256 amountA, uint256 amountB) public {
        vm.prank(admin);
        ITMFactory(factory).setDefaultFee(0); // Set default fee to 0 to fully validate invariants 16

        (token, market) = ITMFactory(factory).createMarket("Test Name", "Test Symbol", quoteToken);

        {
            (, int256 maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 128 - 1);
            before = bound(before, 1, uint256(maxAmount1));

            MockERC20(quoteToken).mint(market, before);
            ITMMarket(market).swap(address(this), false, int256(before), 2 ** 128 - 1);

            vm.assume(ITMMarket(market).getCurrentSqrtRatio() > sqrtPrice0);

            (, maxAmount1) = ITMMarket(market).getDeltaAmounts(true, 2 ** 127 - 1, sqrtPrice0);

            vm.assume(-maxAmount1 >= 2);

            amountA = bound(amountA, 1, uint256(-maxAmount1) - 1);
            amountB = bound(amountB, 1, uint256(-maxAmount1) - amountA);
        }

        uint256 snapshotId = vm.snapshotState();

        (int256 amountA0, int256 amountA1) = ITMMarket(market).getDeltaAmounts(true, -int256(amountA), sqrtPrice0);

        {
            vm.assume(IERC20(token).balanceOf(address(this)) >= uint256(amountA0));

            IERC20(token).transfer(market, uint256(amountA0));
            (int256 amountA0_, int256 amountA1_) =
                ITMMarket(market).swap(address(1), true, -int256(amountA), sqrtPrice0);

            assertEq(amountA0, amountA0_, "test_Fuzz_Swap_ZeroForOne_Lt0::1");
            assertEq(amountA1, amountA1_, "test_Fuzz_Swap_ZeroForOne_Lt0::2");
            assertEq(amountA1, -int256(amountA), "test_Fuzz_Swap_ZeroForOne_Lt0::3");
        }

        (int256 amountB0, int256 amountB1) = ITMMarket(market).getDeltaAmounts(true, -int256(amountB), sqrtPrice0);

        {
            vm.assume(IERC20(token).balanceOf(address(this)) >= uint256(amountB0));

            IERC20(token).transfer(market, uint256(amountB0));
            (int256 amountB0_, int256 amountB1_) =
                ITMMarket(market).swap(address(1), true, -int256(amountB), sqrtPrice0);

            assertEq(amountB0, amountB0_, "test_Fuzz_Swap_ZeroForOne_Lt0::4");
            assertEq(amountB1, amountB1_, "test_Fuzz_Swap_ZeroForOne_Lt0::5");
            assertLe(_abs(amountB1), amountB, "test_Fuzz_Swap_OneForZero_FirstSegment_Gt0::6"); // As the price is rounded down, we might not be able to receive the exact amou, "test_Fuzz_Swap_ZeroForOne_Lt0::6");
        }

        require(vm.revertToStateAndDelete(snapshotId), "panic");

        (int256 amountAB0, int256 amountAB1) =
            ITMMarket(market).getDeltaAmounts(true, -int256(amountA + amountB), sqrtPrice0);

        {
            IERC20(token).transfer(market, uint256(amountAB0));
            (int256 amountAB0_, int256 amountAB1_) =
                ITMMarket(market).swap(address(1), true, -int256(amountA + amountB), sqrtPrice0);

            assertEq(amountAB0, amountAB0_, "test_Fuzz_Swap_ZeroForOne_Lt0::7");
            assertEq(amountAB1, amountAB1_, "test_Fuzz_Swap_ZeroForOne_Lt0::8");
            assertEq(amountAB1, -int256(amountA + amountB), "test_Fuzz_Swap_ZeroForOne_Lt0::9");
        }

        assertGe(amountA0, 0, "test_Fuzz_Swap_ZeroForOne_Lt0::10");
        assertGe(amountB0, 0, "test_Fuzz_Swap_ZeroForOne_Lt0::11");
        assertGe(amountAB0, 0, "test_Fuzz_Swap_ZeroForOne_Lt0::12");
        assertLe(amountA1, 0, "test_Fuzz_Swap_ZeroForOne_Lt0::13");
        assertLe(amountB1, 0, "test_Fuzz_Swap_ZeroForOne_Lt0::14");
        assertLe(amountAB1, 0, "test_Fuzz_Swap_ZeroForOne_Lt0::15");

        assertGe(_abs(amountA0) + _abs(amountB0), _abs(amountAB0), "test_Fuzz_Swap_ZeroForOne_Lt0::16");
        assertLe(_abs(amountA1) + _abs(amountB1), _abs(amountAB1), "test_Fuzz_Swap_ZeroForOne_Lt0::17");
    }

    function test_Fuzz_Swap_ZeroForOne_Lt0_WithFees(uint256 before, uint256 amountA, uint256 amountB) public {
        (token, market) = ITMFactory(factory).createMarket("Test Name", "Test Symbol", quoteToken);

        {
            (, int256 maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 128 - 1);
            before = bound(before, 1, uint256(maxAmount1));

            MockERC20(quoteToken).mint(market, before);
            ITMMarket(market).swap(address(this), false, int256(before), 2 ** 128 - 1);

            vm.assume(ITMMarket(market).getCurrentSqrtRatio() > sqrtPrice0);

            (, maxAmount1) = ITMMarket(market).getDeltaAmounts(true, 2 ** 127 - 1, sqrtPrice0);

            vm.assume(-maxAmount1 >= 2);

            amountA = bound(amountA, 1, uint256(-maxAmount1) - 1);
            amountB = bound(amountB, 1, uint256(-maxAmount1) - amountA);
        }

        uint256 snapshotId = vm.snapshotState();

        (int256 amountA0, int256 amountA1) = ITMMarket(market).getDeltaAmounts(true, -int256(amountA), sqrtPrice0);

        {
            vm.assume(IERC20(token).balanceOf(address(this)) >= uint256(amountA0));

            IERC20(token).transfer(market, uint256(amountA0));
            (int256 amountA0_, int256 amountA1_) =
                ITMMarket(market).swap(address(1), true, -int256(amountA), sqrtPrice0);

            assertEq(amountA0, amountA0_, "test_Fuzz_Swap_ZeroForOne_Lt0::1");
            assertEq(amountA1, amountA1_, "test_Fuzz_Swap_ZeroForOne_Lt0::2");
            assertEq(amountA1, -int256(amountA), "test_Fuzz_Swap_ZeroForOne_Lt0::3");
        }

        (int256 amountB0, int256 amountB1) = ITMMarket(market).getDeltaAmounts(true, -int256(amountB), sqrtPrice0);

        {
            vm.assume(IERC20(token).balanceOf(address(this)) >= uint256(amountB0));

            IERC20(token).transfer(market, uint256(amountB0));
            (int256 amountB0_, int256 amountB1_) =
                ITMMarket(market).swap(address(1), true, -int256(amountB), sqrtPrice0);

            assertEq(amountB0, amountB0_, "test_Fuzz_Swap_ZeroForOne_Lt0::4");
            assertEq(amountB1, amountB1_, "test_Fuzz_Swap_ZeroForOne_Lt0::5");
            assertLe(_abs(amountB1), amountB, "test_Fuzz_Swap_OneForZero_FirstSegment_Gt0::6"); // As the price is rounded down, we might not be able to receive the exact amou, "test_Fuzz_Swap_ZeroForOne_Lt0::6");
        }

        require(vm.revertToStateAndDelete(snapshotId), "panic");

        (int256 amountAB0, int256 amountAB1) =
            ITMMarket(market).getDeltaAmounts(true, -int256(amountA + amountB), sqrtPrice0);

        {
            IERC20(token).transfer(market, uint256(amountAB0));
            (int256 amountAB0_, int256 amountAB1_) =
                ITMMarket(market).swap(address(1), true, -int256(amountA + amountB), sqrtPrice0);

            assertEq(amountAB0, amountAB0_, "test_Fuzz_Swap_ZeroForOne_Lt0::7");
            assertEq(amountAB1, amountAB1_, "test_Fuzz_Swap_ZeroForOne_Lt0::8");
            assertEq(amountAB1, -int256(amountA + amountB), "test_Fuzz_Swap_ZeroForOne_Lt0::9");
        }

        assertGe(amountA0, 0, "test_Fuzz_Swap_ZeroForOne_Lt0::10");
        assertGe(amountB0, 0, "test_Fuzz_Swap_ZeroForOne_Lt0::11");
        assertGe(amountAB0, 0, "test_Fuzz_Swap_ZeroForOne_Lt0::12");
        assertLe(amountA1, 0, "test_Fuzz_Swap_ZeroForOne_Lt0::13");
        assertLe(amountB1, 0, "test_Fuzz_Swap_ZeroForOne_Lt0::14");
        assertLe(amountAB1, 0, "test_Fuzz_Swap_ZeroForOne_Lt0::15");

        // Error is due to fee0 swapped to token1, it increases the actual number of token received by the user
        // in this specific case. However, as the fuzz tests show, the error is less than 1e-18.
        assertGe(
            _abs(amountA0) + _abs(amountB0), _abs(amountAB0) * (1e18 - 1) / 1e18, "test_Fuzz_Swap_ZeroForOne_Lt0::16"
        );
        assertLe(_abs(amountA1) + _abs(amountB1), _abs(amountAB1), "test_Fuzz_Swap_ZeroForOne_Lt0::17");
    }

    function test_Fuzz_Revert_Swap(uint256 before, uint256 amount0, uint256 amount1) public {
        (, int256 maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 128 - 1);
        before = bound(before, 1, uint256(maxAmount1) - 2);

        MockERC20(quoteToken).mint(market, before);
        ITMMarket(market).swap(address(this), false, int256(before), 2 ** 128 - 1);

        (, maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 128 - 1);
        amount1 = bound(amount1, 1, uint256(maxAmount1) - 1);

        MockERC20(quoteToken).mint(market, amount1 - 1);

        vm.expectRevert(ITMMarket.InsufficientBalance1.selector);
        ITMMarket(market).swap(address(this), false, int256(amount1), 2 ** 128 - 1);

        MockERC20(quoteToken).mint(market, 1);
        ITMMarket(market).swap(address(this), false, int256(amount1), 2 ** 128 - 1);

        vm.assume(ITMMarket(market).getCurrentSqrtRatio() > sqrtPrice0);

        (int256 maxAmount0,) = ITMMarket(market).getDeltaAmounts(true, 2 ** 127 - 1, sqrtPrice0);
        amount0 = bound(amount0, 1, uint256(maxAmount0) - 1);
        uint256 balance = MockERC20(token).balanceOf(address(this));
        if (amount0 > balance) amount0 = balance;

        IERC20(token).transfer(market, amount0 - 1);

        vm.expectRevert(ITMMarket.InsufficientBalance0.selector);
        ITMMarket(market).swap(address(this), true, int256(amount0), sqrtPrice0);
    }

    function test_Revert_Swap_Reentrancy() public {
        // Redirect the onFeeReceived call to this address to try to reenter
        vm.mockFunction(factory, address(this), abi.encodeWithSelector(ITMFactory.onFeeReceived.selector));

        MockERC20(quoteToken).mint(market, 1e18);

        vm.expectRevert(ITMMarket.ReentrantCall.selector);
        ITMMarket(market).swap(address(this), false, 1e18, 2 ** 128 - 1);
    }

    function onFeeReceived(address, uint256) external returns (bool) {
        ITMMarket(msg.sender).swap(address(1), false, 1, 2 ** 128 - 1);
        return true;
    }

    function _abs(int256 x) internal pure returns (uint256) {
        return Math.safeInt128(x) > 0 ? uint256(x) : uint256(-x);
    }
}
