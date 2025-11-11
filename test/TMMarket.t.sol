// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, Vm} from "forge-std/Test.sol";

import {Parameters} from "script/Parameters.sol";
import {ITMFactory, TMFactory} from "src/TMFactory.sol";
import {ITMMarket, TMMarket} from "src/TMMarket.sol";
import {ITMToken, TMToken} from "src/TMToken.sol";
import {Math, SwapMath} from "src/libraries/SwapMath.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract TestTMMarket is Test, Parameters {
    address tokenImplementation;
    address marketImplementation;
    address factory;
    address market;
    address token;

    address admin = makeAddr("admin");

    bytes32 constant PRICE_SLOT = bytes32(uint256(1));

    struct SwapEvent {
        int256 amount0;
        int256 amount1;
        uint256 feeAmountIn;
        uint256 feeAmount1;
        uint256 sqrtRatioX96;
    }

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
                defaultFeeA,
                defaultFeeB,
                quoteToken,
                marketImplementation,
                tokenImplementation,
                admin,
                wnative
            )
        );

        (token, market,) = ITMFactory(factory)
            .createMarket("Test Name", "Test Symbol", quoteToken, ITMFactory(factory).KOTM_FEE_RECIPIENT(), 0, 0);
    }

    function test_Fuzz_TargetRatio(uint256 currentSqrtRatioX96, bool zeroForOne, uint256 sqrtRatioLimitX96)
        public
        view
    {
        (uint256 liquidityA, uint256 liquidityB) = ITMMarket(market).getLiquidities();
        (uint256 sqrtRatioAX96, uint256 sqrtRatioBX96, uint256 sqrtRatioCX96) = ITMMarket(market).getSqrtRatiosBounds();

        currentSqrtRatioX96 = zeroForOne
            ? bound(currentSqrtRatioX96, sqrtRatioAX96 + 1, sqrtRatioCX96)
            : bound(currentSqrtRatioX96, sqrtRatioAX96, sqrtRatioCX96 - 1);
        sqrtRatioLimitX96 = zeroForOne
            ? bound(sqrtRatioLimitX96, sqrtRatioAX96, currentSqrtRatioX96 - 1)
            : bound(sqrtRatioLimitX96, currentSqrtRatioX96 + 1, sqrtRatioCX96);

        uint256 liquidity = currentSqrtRatioX96 >= sqrtRatioBX96 ? liquidityB : liquidityA;
        uint256 targetRatioX96 = (zeroForOne
                ? currentSqrtRatioX96 >= sqrtRatioBX96 && sqrtRatioLimitX96 < sqrtRatioBX96
                : currentSqrtRatioX96 < sqrtRatioBX96 && sqrtRatioLimitX96 >= sqrtRatioBX96)
            ? sqrtRatioBX96
            : sqrtRatioLimitX96;

        if (currentSqrtRatioX96 >= sqrtRatioBX96) {
            assertEq(liquidity, liquidityB, "test_Fuzz_TargetRatio::1");
            assertLe(targetRatioX96, sqrtRatioCX96, "test_Fuzz_TargetRatio::2");
            assertGe(targetRatioX96, sqrtRatioBX96, "test_Fuzz_TargetRatio::3");

            if (zeroForOne) {
                if (sqrtRatioLimitX96 >= sqrtRatioBX96) {
                    assertEq(targetRatioX96, sqrtRatioLimitX96, "test_Fuzz_TargetRatio::4");
                } else {
                    assertEq(targetRatioX96, sqrtRatioBX96, "test_Fuzz_TargetRatio::5");
                }
            } else {
                assertEq(targetRatioX96, sqrtRatioLimitX96, "test_Fuzz_TargetRatio::6");
            }
        } else {
            assertEq(liquidity, liquidityA, "test_Fuzz_TargetRatio::7");
            assertLe(targetRatioX96, sqrtRatioBX96, "test_Fuzz_TargetRatio::8");
            assertGe(targetRatioX96, sqrtRatioAX96, "test_Fuzz_TargetRatio::9");

            if (zeroForOne) {
                assertEq(targetRatioX96, sqrtRatioLimitX96, "test_Fuzz_TargetRatio::10");
            } else {
                if (sqrtRatioLimitX96 >= sqrtRatioBX96) {
                    assertEq(targetRatioX96, sqrtRatioBX96, "test_Fuzz_TargetRatio::11");
                } else {
                    assertEq(targetRatioX96, sqrtRatioLimitX96, "test_Fuzz_TargetRatio::12");
                }
            }
        }

        if (targetRatioX96 != sqrtRatioLimitX96) {
            if (zeroForOne) {
                assertLe(sqrtRatioLimitX96, sqrtRatioBX96, "test_Fuzz_TargetRatio::13");
                assertGe(sqrtRatioLimitX96, sqrtRatioAX96, "test_Fuzz_TargetRatio::14");
            } else {
                assertLe(sqrtRatioLimitX96, sqrtRatioCX96, "test_Fuzz_TargetRatio::15");
                assertGe(sqrtRatioLimitX96, sqrtRatioBX96, "test_Fuzz_TargetRatio::16");
            }
        }
    }

    function test_Constructor() public view {
        assertEq(ITMMarket(market).getFactory(), factory, "test_Constructor::1");
        (uint256 sqrtPriceA_, uint256 sqrtPriceB_, uint256 sqrtPriceC_) = ITMMarket(market).getSqrtRatiosBounds();
        assertEq(sqrtPriceA_, sqrtPrice0, "test_Constructor::2");
        assertEq(sqrtPriceB_, sqrtPrice1, "test_Constructor::3");
        assertEq(sqrtPriceC_, 2 ** 127 - 1, "test_Constructor::4");
        (uint256 liquidityA, uint256 liquidityB) = ITMMarket(market).getLiquidities();
        assertEq(liquidityA, SwapMath.getLiquidity0(sqrtPrice0, sqrtPrice1, amount0A), "test_Constructor::5");
        assertEq(liquidityB, SwapMath.getLiquidity0(sqrtPrice1, 2 ** 127 - 1, amount0B), "test_Constructor::6");
        assertEq(ITMMarket(market).getBaseToken(), token, "test_Constructor::7");
        assertEq(ITMMarket(market).getQuoteToken(), quoteToken, "test_Constructor::8");
        assertEq(ITMMarket(market).getCurrentSqrtRatio(), sqrtPrice0, "test_Constructor::9");
        (uint256 feeA, uint256 feeB) = ITMMarket(market).getFees();
        assertEq(feeA, defaultFeeA, "test_Constructor::10");
        assertEq(feeB, defaultFeeB, "test_Constructor::11");
        (uint256 reserve0, uint256 reserve1) = ITMMarket(market).getReserves();
        assertEq(reserve0, amount0A + amount0B, "test_Constructor::12");
        assertEq(reserve1, 0, "test_Constructor::13");
        assertEq(ITMToken(token).getFactory(), factory, "test_Constructor::14");
        assertEq(ITMToken(token).totalSupply(), amount0A + amount0B, "test_Constructor::15");
        assertEq(ITMToken(token).balanceOf(market), amount0A + amount0B, "test_Constructor::16");
    }

    function test_Fuzz_Revert_Constructor(uint256 amountA, uint256 amountB, uint256 sqrtPriceA, uint256 sqrtPriceB)
        public
    {
        vm.expectRevert(ITMMarket.InvalidRatiosOrder.selector);
        new TMMarket(factory, address(0), 0, 0, sqrtPriceA, bound(sqrtPriceB, 0, sqrtPriceA));

        vm.expectRevert(ITMMarket.InvalidRatios.selector);
        new TMMarket(factory, address(0), 0, 0, 0, 1);

        vm.expectRevert(ITMMarket.InvalidRatios.selector);
        new TMMarket(factory, address(0), 0, 0, 1, bound(sqrtPriceB, 2 ** 127, type(uint256).max));

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
        sqrtPriceB = bound(sqrtPriceB, sqrtPriceA + 1, 2 ** 126 - 1);

        uint256 minAmountToOverflow =
            Math.fullMulDivUp(2 ** 127, (sqrtPriceB - sqrtPriceA) << 96, sqrtPriceA * sqrtPriceB);

        vm.expectRevert(Math.Uint127Overflow.selector);
        new TMMarket(factory, address(0), bound(amountA, minAmountToOverflow, 2 ** 127), 1, sqrtPriceA, sqrtPriceB);

        sqrtPriceB = 2 ** 96 + 1;
        minAmountToOverflow = Math.divUp(2 ** 127 * (2 ** 127 - 1 - sqrtPriceB), 2 ** 127 - 1);

        vm.expectRevert(Math.Uint127Overflow.selector);
        new TMMarket(factory, address(0), 1, bound(amountB, minAmountToOverflow, 2 ** 127), sqrtPriceA, sqrtPriceB);
    }

    function test_Revert_Initialize() public {
        vm.expectRevert(ITMMarket.AlreadyInitialized.selector);
        ITMMarket(market).initialize(address(0), 0, 0);

        vm.store(market, PRICE_SLOT, 0);

        vm.expectRevert(ITMMarket.SameTokens.selector);
        ITMMarket(market).initialize(quoteToken, 0, 0);

        vm.expectRevert(ITMMarket.InvalidFee.selector);
        ITMMarket(market).initialize(address(1), SwapMath.MAX_FEE + 1, 0);

        vm.expectRevert(ITMMarket.InvalidFee.selector);
        ITMMarket(market).initialize(address(1), 0, SwapMath.MAX_FEE + 1);
    }

    function test_revert_GetDeltaAmountsAndSwap() public {
        // Move Price away from the min price
        MockERC20(quoteToken).mint(market, 100e18);
        ITMMarket(market).swap(address(0xdead), false, 100e18, 2 ** 127 - 1);

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
        ITMMarket(market).getDeltaAmounts(false, 1, 2 ** 127);
        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).swap(address(1), false, 1, 2 ** 127);

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
        ITMMarket(market).getDeltaAmounts(true, 1, 2 ** 127);
        vm.expectRevert(ITMMarket.InvalidSqrtRatioLimit.selector);
        ITMMarket(market).swap(address(1), true, 1, 2 ** 127);

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
            (, int256 maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 127 - 1);
            before = bound(before, 1, uint256(maxAmount1) - 2);

            MockERC20(quoteToken).mint(market, before);
            ITMMarket(market).swap(address(1), false, int256(before), 2 ** 127 - 1);

            (, maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 127 - 1);
            amountA = bound(amountA, 1, uint256(maxAmount1) - 1);
            amountB = bound(amountB, 1, uint256(maxAmount1) - amountA);
        }

        uint256 snapshotId = vm.snapshotState();

        (int256 amountA0, int256 amountA1) = ITMMarket(market).getDeltaAmounts(false, int256(amountA), 2 ** 127 - 1);

        {
            MockERC20(quoteToken).mint(market, amountA);
            (int256 amountA0_, int256 amountA1_) =
                ITMMarket(market).swap(address(1), false, int256(amountA), 2 ** 127 - 1);

            assertEq(amountA0, amountA0_, "test_Fuzz_Swap_OneForZero_Gt0::1");
            assertEq(amountA1, amountA1_, "test_Fuzz_Swap_OneForZero_Gt0::2");
            assertEq(amountA1, int256(amountA), "test_Fuzz_Swap_OneForZero_Gt0::3");
        }

        (int256 amountB0, int256 amountB1) = ITMMarket(market).getDeltaAmounts(false, int256(amountB), 2 ** 127 - 1);

        {
            MockERC20(quoteToken).mint(market, amountB);
            (int256 amountB0_, int256 amountB1_) =
                ITMMarket(market).swap(address(1), false, int256(amountB), 2 ** 127 - 1);

            assertEq(amountB0, amountB0_, "test_Fuzz_Swap_OneForZero_Gt0::4");
            assertEq(amountB1, amountB1_, "test_Fuzz_Swap_OneForZero_Gt0::5");
            assertEq(amountB1, int256(amountB), "test_Fuzz_Swap_OneForZero_Gt0::6");
        }

        require(vm.revertToStateAndDelete(snapshotId), "panic");

        (int256 amountAB0, int256 amountAB1) =
            ITMMarket(market).getDeltaAmounts(false, int256(amountA + amountB), 2 ** 127 - 1);

        {
            MockERC20(quoteToken).mint(market, amountA + amountB);
            (int256 amountAB0_, int256 amountAB1_) =
                ITMMarket(market).swap(address(1), false, int256(amountA + amountB), 2 ** 127 - 1);

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
            (, int256 maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 127 - 1);
            before = bound(before, 1, uint256(maxAmount1));

            MockERC20(quoteToken).mint(market, before);
            (int256 maxAmount0,) = ITMMarket(market).swap(address(this), false, int256(before), 2 ** 127 - 1);

            vm.assume(ITMMarket(market).getCurrentSqrtRatio() > sqrtPrice0);

            amountA = bound(amountA, 1, uint256(-maxAmount0) - 1);
            amountB = bound(amountB, 1, uint256(-maxAmount0) - amountA);
        }

        uint256 snapshotId = vm.snapshotState();

        (int256 amountA0, int256 amountA1) = ITMMarket(market).getDeltaAmounts(true, int256(amountA), sqrtPrice0);

        {
            // forge-lint: disable-next-line(erc20-unchecked-transfer)
            IERC20(token).transfer(market, amountA);
            (int256 amountA0_, int256 amountA1_) = ITMMarket(market).swap(address(1), true, int256(amountA), sqrtPrice0);

            assertEq(amountA0, amountA0_, "test_Fuzz_Swap_ZeroForOne_Gt0::1");
            assertEq(amountA0, int256(amountA), "test_Fuzz_Swap_ZeroForOne_Gt0::2");
            assertEq(amountA1, amountA1_, "test_Fuzz_Swap_ZeroForOne_Gt0::3");
        }

        (int256 amountB0, int256 amountB1) = ITMMarket(market).getDeltaAmounts(true, int256(amountB), sqrtPrice0);

        {
            // forge-lint: disable-next-line(erc20-unchecked-transfer)
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
            // forge-lint: disable-next-line(erc20-unchecked-transfer)
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
            (, int256 maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 127 - 1);
            before = bound(before, 1, uint256(maxAmount1) - 2);

            MockERC20(quoteToken).mint(market, before);
            ITMMarket(market).swap(address(1), false, int256(before), 2 ** 127 - 1);

            (int256 maxAmount0,) = ITMMarket(market).getDeltaAmounts(false, -2 ** 127, 2 ** 127 - 1);
            vm.assume(-maxAmount0 >= 2);
            amountA = bound(amountA, 1, uint256(-maxAmount0) - 1);
            amountB = bound(amountB, 1, uint256(-maxAmount0) - amountA);
        }

        uint256 snapshotId = vm.snapshotState();

        (int256 amountA0, int256 amountA1) = ITMMarket(market).getDeltaAmounts(false, -int256(amountA), 2 ** 127 - 1);

        {
            MockERC20(quoteToken).mint(market, uint256(amountA1));
            (int256 amountA0_, int256 amountA1_) =
                ITMMarket(market).swap(address(1), false, -int256(amountA), 2 ** 127 - 1);

            assertEq(amountA0, amountA0_, "test_Fuzz_Swap_OneForZero_Lt0::1");
            assertEq(amountA0, -int256(amountA), "test_Fuzz_Swap_OneForZero_Lt0::2");
            assertEq(amountA1, amountA1_, "test_Fuzz_Swap_OneForZero_Lt0::3");
        }

        (int256 amountB0, int256 amountB1) = ITMMarket(market).getDeltaAmounts(false, -int256(amountB), 2 ** 127 - 1);

        {
            MockERC20(quoteToken).mint(market, uint256(amountB1));
            (int256 amountB0_, int256 amountB1_) =
                ITMMarket(market).swap(address(1), false, -int256(amountB), 2 ** 127 - 1);

            assertEq(amountB0, amountB0_, "test_Fuzz_Swap_OneForZero_Lt0::4");

            // As the price is rounded up, we might not be able to receive the exact amount
            assertLe(_abs(amountB0), amountB, "test_Fuzz_Swap_OneForZero_Lt0::5");
            assertEq(amountB1, amountB1_, "test_Fuzz_Swap_OneForZero_Lt0::6");
        }

        require(vm.revertToStateAndDelete(snapshotId), "panic");

        (int256 amountAB0, int256 amountAB1) =
            ITMMarket(market).getDeltaAmounts(false, -int256(amountA + amountB), 2 ** 127 - 1);

        {
            MockERC20(quoteToken).mint(market, uint256(amountAB1));
            (int256 amountAB0_, int256 amountAB1_) =
                ITMMarket(market).swap(address(1), false, -(int256(amountA + amountB)), 2 ** 127 - 1);

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
        // Set default fee to 0 to fully validate invariants 16
        vm.prank(admin);
        ITMFactory(factory).setDefaultFees(0, 0);

        (token, market,) = ITMFactory(factory)
            .createMarket("Test Name", "Test Symbol", quoteToken, ITMFactory(factory).KOTM_FEE_RECIPIENT(), 0, 0);

        {
            (, int256 maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 127 - 1);
            before = bound(before, 1, uint256(maxAmount1));

            MockERC20(quoteToken).mint(market, before);
            ITMMarket(market).swap(address(this), false, int256(before), 2 ** 127 - 1);

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

            // forge-lint: disable-next-line(erc20-unchecked-transfer)
            IERC20(token).transfer(market, uint256(amountA0));
            (int256 amountA0_, int256 amountA1_) =
                ITMMarket(market).swap(address(1), true, -int256(amountA), sqrtPrice0);

            assertEq(amountA0, amountA0_, "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::1");
            assertEq(amountA1, amountA1_, "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::2");
            assertEq(amountA1, -int256(amountA), "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::3");
        }

        (int256 amountB0, int256 amountB1) = ITMMarket(market).getDeltaAmounts(true, -int256(amountB), sqrtPrice0);

        {
            vm.assume(IERC20(token).balanceOf(address(this)) >= uint256(amountB0));

            // forge-lint: disable-next-line(erc20-unchecked-transfer)
            IERC20(token).transfer(market, uint256(amountB0));
            (int256 amountB0_, int256 amountB1_) =
                ITMMarket(market).swap(address(1), true, -int256(amountB), sqrtPrice0);

            assertEq(amountB0, amountB0_, "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::4");
            assertEq(amountB1, amountB1_, "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::5");

            // As the price is rounded down, we might not be able to receive the exact amount
            assertLe(_abs(amountB1), amountB, "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::6");
        }

        require(vm.revertToStateAndDelete(snapshotId), "panic");

        (int256 amountAB0, int256 amountAB1) =
            ITMMarket(market).getDeltaAmounts(true, -int256(amountA + amountB), sqrtPrice0);

        {
            // forge-lint: disable-next-line(erc20-unchecked-transfer)
            IERC20(token).transfer(market, uint256(amountAB0));
            (int256 amountAB0_, int256 amountAB1_) =
                ITMMarket(market).swap(address(1), true, -int256(amountA + amountB), sqrtPrice0);

            assertEq(amountAB0, amountAB0_, "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::7");
            assertEq(amountAB1, amountAB1_, "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::8");
            assertEq(amountAB1, -int256(amountA + amountB), "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::9");
        }

        assertGe(amountA0, 0, "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::10");
        assertGe(amountB0, 0, "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::11");
        assertGe(amountAB0, 0, "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::12");
        assertLe(amountA1, 0, "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::13");
        assertLe(amountB1, 0, "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::14");
        assertLe(amountAB1, 0, "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::15");

        assertGe(_abs(amountA0) + _abs(amountB0), _abs(amountAB0), "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::16");
        assertLe(_abs(amountA1) + _abs(amountB1), _abs(amountAB1), "test_Fuzz_Swap_ZeroForOne_Lt0_NoFees::17");
    }

    function test_Fuzz_Swap_ZeroForOne_Lt0_WithFees(uint256 before, uint256 amountA, uint256 amountB) public {
        (token, market,) = ITMFactory(factory)
            .createMarket("Test Name", "Test Symbol", quoteToken, ITMFactory(factory).KOTM_FEE_RECIPIENT(), 0, 0);

        {
            (, int256 maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 127 - 1);
            before = bound(before, 1, uint256(maxAmount1));

            MockERC20(quoteToken).mint(market, before);
            ITMMarket(market).swap(address(this), false, int256(before), 2 ** 127 - 1);

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

            // forge-lint: disable-next-line(erc20-unchecked-transfer)
            IERC20(token).transfer(market, uint256(amountA0));
            (int256 amountA0_, int256 amountA1_) =
                ITMMarket(market).swap(address(1), true, -int256(amountA), sqrtPrice0);

            assertEq(amountA0, amountA0_, "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::1");
            assertEq(amountA1, amountA1_, "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::2");
            assertEq(amountA1, -int256(amountA), "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::3");
        }

        (int256 amountB0, int256 amountB1) = ITMMarket(market).getDeltaAmounts(true, -int256(amountB), sqrtPrice0);

        {
            vm.assume(IERC20(token).balanceOf(address(this)) >= uint256(amountB0));

            // forge-lint: disable-next-line(erc20-unchecked-transfer)
            IERC20(token).transfer(market, uint256(amountB0));
            (int256 amountB0_, int256 amountB1_) =
                ITMMarket(market).swap(address(1), true, -int256(amountB), sqrtPrice0);

            assertEq(amountB0, amountB0_, "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::4");
            assertEq(amountB1, amountB1_, "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::5");

            // As the price is rounded down, we might not be able to receive the exact amount
            assertLe(_abs(amountB1), amountB, "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::6");
        }

        require(vm.revertToStateAndDelete(snapshotId), "panic");

        (int256 amountAB0, int256 amountAB1) =
            ITMMarket(market).getDeltaAmounts(true, -int256(amountA + amountB), sqrtPrice0);

        {
            // forge-lint: disable-next-line(erc20-unchecked-transfer)
            IERC20(token).transfer(market, uint256(amountAB0));
            (int256 amountAB0_, int256 amountAB1_) =
                ITMMarket(market).swap(address(1), true, -int256(amountA + amountB), sqrtPrice0);

            assertEq(amountAB0, amountAB0_, "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::7");
            assertEq(amountAB1, amountAB1_, "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::8");
            assertEq(amountAB1, -int256(amountA + amountB), "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::9");
        }

        assertGe(amountA0, 0, "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::10");
        assertGe(amountB0, 0, "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::11");
        assertGe(amountAB0, 0, "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::12");
        assertLe(amountA1, 0, "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::13");
        assertLe(amountB1, 0, "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::14");
        assertLe(amountAB1, 0, "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::15");

        // Error is due to fee0 swapped to token1, it increases the actual number of token received by the user
        // in this specific case. However, as the fuzz tests show, the error is less than 1e-18.
        assertGe(
            _abs(amountA0) + _abs(amountB0),
            _abs(amountAB0) * (1e18 - 1) / 1e18,
            "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::16"
        );
        assertLe(_abs(amountA1) + _abs(amountB1), _abs(amountAB1), "test_Fuzz_Swap_ZeroForOne_Lt0_WithFees::17");
    }

    function test_Fuzz_FeeSwitch_Lt0(uint256 supplyBefore, uint256 supplyBoughtInB) public {
        (token, market,) = ITMFactory(factory)
            .createMarket("Test Name", "Test Symbol", quoteToken, ITMFactory(factory).KOTM_FEE_RECIPIENT(), 0, 0);

        supplyBefore = bound(supplyBefore, 1, amount0A - 1);
        supplyBoughtInB = bound(supplyBoughtInB, 1, amount0B);

        {
            (, int256 amount1) = ITMMarket(market).getDeltaAmounts(false, -int256(supplyBefore), 2 ** 127 - 1);

            MockERC20(quoteToken).mint(market, uint256(amount1));
            ITMMarket(market).swap(address(this), false, -int256(supplyBefore), 2 ** 127 - 1);
        }

        uint256 snapshotId = vm.snapshotState();
        vm.recordLogs();

        uint256 feeAmountA;
        (, int256 amountA1) = ITMMarket(market).getDeltaAmounts(false, -int256(amount0A - supplyBefore), 2 ** 127 - 1);

        {
            MockERC20(quoteToken).mint(market, uint256(amountA1));
            (, int256 amountA1_) =
                ITMMarket(market).swap(address(1), false, -int256(amount0A - supplyBefore), 2 ** 127 - 1);

            Vm.Log memory swapLog = vm.getRecordedLogs()[2];
            feeAmountA = abi.decode(swapLog.data, (SwapEvent)).feeAmount1;

            assertApproxEqAbs(
                feeAmountA, (_abs(amountA1_) * defaultFeeA + 1e6 - 1) / 1e6, 1, "test_Fuzz_FeeSwitch_Lt0::1"
            );
        }

        uint256 feeAmountB;
        (, int256 amountB1) = ITMMarket(market).getDeltaAmounts(false, -int256(supplyBoughtInB), 2 ** 127 - 1);

        {
            MockERC20(quoteToken).mint(market, uint256(amountB1));
            (, int256 amountB1_) = ITMMarket(market).swap(address(1), false, -int256(supplyBoughtInB), 2 ** 127 - 1);

            Vm.Log memory swapLog = vm.getRecordedLogs()[2];
            feeAmountB = abi.decode(swapLog.data, (SwapEvent)).feeAmount1;

            assertApproxEqAbs(
                feeAmountB, (_abs(amountB1_) * defaultFeeB + 1e6 - 1) / 1e6, 1, "test_Fuzz_FeeSwitch_Lt0::2"
            );
        }

        require(vm.revertToStateAndDelete(snapshotId), "panic");
        uint256 buyAmount = amount0A - supplyBefore + supplyBoughtInB;

        uint256 feeAmountAB;
        (, int256 amountAB1) = ITMMarket(market).getDeltaAmounts(false, -int256(buyAmount), 2 ** 127 - 1);

        {
            MockERC20(quoteToken).mint(market, uint256(amountAB1));
            ITMMarket(market).swap(address(1), false, -int256(buyAmount), 2 ** 127 - 1);

            Vm.Log memory swapLog = vm.getRecordedLogs()[2];
            feeAmountAB = abi.decode(swapLog.data, (SwapEvent)).feeAmount1;
        }

        assertGe(feeAmountA + feeAmountB, feeAmountAB, "test_Fuzz_FeeSwitch_Lt0::3");
        assertApproxEqAbs(feeAmountA + feeAmountB, feeAmountAB, 1e6, "test_Fuzz_FeeSwitch_Lt0::4");
    }

    function test_Fuzz_FeeSwitch_Gt0(uint256 supplyBefore, uint256 supplyBoughtInB) public {
        (token, market,) = ITMFactory(factory)
            .createMarket("Test Name", "Test Symbol", quoteToken, ITMFactory(factory).KOTM_FEE_RECIPIENT(), 0, 0);

        supplyBefore = bound(supplyBefore, 1, amount0A - 1);
        supplyBoughtInB = bound(supplyBoughtInB, 1, amount0B - 1);

        {
            (, int256 amount1) = ITMMarket(market).getDeltaAmounts(false, -int256(supplyBefore), 2 ** 127 - 1);

            MockERC20(quoteToken).mint(market, uint256(amount1));
            ITMMarket(market).swap(address(this), false, -int256(supplyBefore), 2 ** 127 - 1);
        }

        uint256 snapshotId = vm.snapshotState();
        vm.recordLogs();

        uint256 feeAmountA;
        (, int256 amountA1) = ITMMarket(market).getDeltaAmounts(false, -int256(amount0A - supplyBefore), 2 ** 127 - 1);

        {
            MockERC20(quoteToken).mint(market, uint256(amountA1));
            (, int256 amountA1_) = ITMMarket(market).swap(address(1), false, amountA1, 2 ** 127 - 1);

            Vm.Log memory swapLog = vm.getRecordedLogs()[2];
            feeAmountA = abi.decode(swapLog.data, (SwapEvent)).feeAmount1;

            assertApproxEqAbs(
                feeAmountA, (_abs(amountA1_) * defaultFeeA + 1e6 - 1) / 1e6, 2, "test_Fuzz_FeeSwitch_Gt0::1"
            );
        }

        uint256 feeAmountB;
        (, int256 amountB1) = ITMMarket(market).getDeltaAmounts(false, -int256(supplyBoughtInB), 2 ** 127 - 1);

        {
            MockERC20(quoteToken).mint(market, uint256(amountB1));
            (, int256 amountB1_) = ITMMarket(market).swap(address(1), false, amountB1, 2 ** 127 - 1);

            Vm.Log memory swapLog = vm.getRecordedLogs()[2];
            feeAmountB = abi.decode(swapLog.data, (SwapEvent)).feeAmount1;

            assertApproxEqAbs(
                feeAmountB, (_abs(amountB1_) * defaultFeeB + 1e6 - 1) / 1e6, 2, "test_Fuzz_FeeSwitch_Gt0::2"
            );
        }

        require(vm.revertToStateAndDelete(snapshotId), "panic");

        uint256 feeAmountAB;
        (, int256 amountAB1) = ITMMarket(market).getDeltaAmounts(false, amountA1 + amountB1, 2 ** 127 - 1);

        {
            MockERC20(quoteToken).mint(market, uint256(amountAB1));
            ITMMarket(market).swap(address(1), false, amountAB1, 2 ** 127 - 1);

            Vm.Log memory swapLog = vm.getRecordedLogs()[2];
            feeAmountAB = abi.decode(swapLog.data, (SwapEvent)).feeAmount1;
        }

        assertGe(feeAmountA + feeAmountB, feeAmountAB, "test_Fuzz_FeeSwitch_Gt0::3");
        assertApproxEqAbs(feeAmountA + feeAmountB, feeAmountAB, 1e6, "test_Fuzz_FeeSwitch_Gt0::4");
    }

    function test_Fuzz_Revert_Swap(uint256 before, uint256 amount0, uint256 amount1) public {
        (, int256 maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 127 - 1);
        before = bound(before, 1, uint256(maxAmount1) - 2);

        MockERC20(quoteToken).mint(market, before);
        ITMMarket(market).swap(address(this), false, int256(before), 2 ** 127 - 1);

        (, maxAmount1) = ITMMarket(market).getDeltaAmounts(false, 2 ** 127 - 1, 2 ** 127 - 1);
        amount1 = bound(amount1, 1, uint256(maxAmount1) - 1);

        MockERC20(quoteToken).mint(market, amount1 - 1);

        vm.expectRevert(ITMMarket.InsufficientBalance1.selector);
        ITMMarket(market).swap(address(this), false, int256(amount1), 2 ** 127 - 1);

        MockERC20(quoteToken).mint(market, 1);
        ITMMarket(market).swap(address(this), false, int256(amount1), 2 ** 127 - 1);

        vm.assume(ITMMarket(market).getCurrentSqrtRatio() > sqrtPrice0);

        (int256 maxAmount0,) = ITMMarket(market).getDeltaAmounts(true, 2 ** 127 - 1, sqrtPrice0);
        amount0 = bound(amount0, 1, uint256(maxAmount0) - 1);
        uint256 balance = MockERC20(token).balanceOf(address(this));
        if (amount0 > balance) amount0 = balance;

        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(token).transfer(market, amount0 - 1);

        vm.expectRevert(ITMMarket.InsufficientBalance0.selector);
        ITMMarket(market).swap(address(this), true, int256(amount0), sqrtPrice0);
    }

    function test_Revert_Swap_Reentrancy() public {
        // Redirect the onFeeReceived call to this address to try to reenter
        vm.mockFunction(factory, address(this), abi.encodeWithSelector(ITMFactory.onFeeReceived.selector));

        MockERC20(quoteToken).mint(market, 1e18);

        vm.expectRevert(ITMMarket.ReentrantCall.selector);
        ITMMarket(market).swap(address(this), false, 1e18, 2 ** 127 - 1);
    }

    function test_MarketMigration() public {
        bytes32 marketMigratorRole = ITMFactory(factory).MARKET_MIGRATOR_ROLE();

        (token, market,) = ITMFactory(factory)
            .createMarket("Test Name", "Test Symbol", quoteToken, ITMFactory(factory).KOTM_FEE_RECIPIENT(), 0, 0);

        (int256 amount0, int256 amount1) =
            ITMMarket(market).getDeltaAmounts(false, -int256(600_000_000e18), 2 ** 127 - 1);
        MockERC20(quoteToken).mint(market, uint256(amount1));
        ITMMarket(market).swap(address(this), false, amount0, 2 ** 127 - 1);

        vm.expectRevert(ITMMarket.OnlyFactory.selector);
        ITMMarket(market).migrate(address(this));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), marketMigratorRole
            )
        );
        ITMFactory(factory).migrateMarket(market, address(this));

        vm.prank(admin);
        IAccessControl(factory).grantRole(marketMigratorRole, address(this));
        ITMFactory(factory).migrateMarket(market, address(this));

        vm.expectRevert(ITMMarket.MarketMigrated.selector);
        ITMMarket(market).swap(address(this), false, amount0, 2 ** 127 - 1);
    }

    function onFeeReceived(address, uint256) external returns (bool) {
        ITMMarket(msg.sender).swap(address(1), false, 1, 2 ** 127 - 1);
        return true;
    }

    function _abs(int256 x) internal pure returns (uint256) {
        return Math.safeInt128(x) > 0 ? uint256(x) : uint256(-x);
    }
}
