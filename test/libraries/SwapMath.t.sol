// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "src/libraries/SwapMath.sol";

contract SwapMathTest is Test {
    function test_fuzz_GetLiquidityAndAmount0(uint256 sqrtPriceAX96, uint256 sqrtPriceBX96, uint256 amount0)
        public
        view
    {
        sqrtPriceAX96 = bound(sqrtPriceAX96, 1, type(uint128).max - 1);
        sqrtPriceBX96 = bound(sqrtPriceBX96, sqrtPriceAX96 + 1, type(uint128).max);
        amount0 = bound(
            amount0,
            0,
            Math.fullMulDiv(type(uint224).max, sqrtPriceBX96 - sqrtPriceAX96, (sqrtPriceAX96 * sqrtPriceBX96))
        );

        uint256 liquidity0 = this.getLiquidity0(sqrtPriceAX96, sqrtPriceBX96, amount0);
        assertLt(liquidity0, type(uint160).max, "test_fuzz_GetLiquidityAndAmount0::1");

        uint256 amount0Up = this.getAmount0(sqrtPriceAX96, sqrtPriceBX96, liquidity0, true);
        uint256 amount0Down = this.getAmount0(sqrtPriceAX96, sqrtPriceBX96, liquidity0, false);

        assertLe(amount0Down, amount0, "test_fuzz_GetLiquidityAndAmount0::2");
        assertLe(amount0Up, amount0, "test_fuzz_GetLiquidityAndAmount0::3");

        amount0Up = this.getAmount0(sqrtPriceAX96, sqrtPriceBX96, liquidity0 + 1, true);
        amount0Down = this.getAmount0(sqrtPriceAX96, sqrtPriceBX96, liquidity0 + 1, false);

        assertGe(amount0Up, amount0Down, "test_fuzz_GetLiquidityAndAmount0::4");
        assertGt(amount0Up, amount0, "test_fuzz_GetLiquidityAndAmount0::5");
    }

    function test_fuzz_GetAmountAndLiquidity0(uint256 sqrtPriceAX96, uint256 sqrtPriceBX96, uint256 liquidity0)
        public
        view
    {
        sqrtPriceAX96 = bound(sqrtPriceAX96, 1, type(uint128).max - 1);
        sqrtPriceBX96 = bound(sqrtPriceBX96, sqrtPriceAX96 + 1, type(uint128).max);
        liquidity0 = bound(liquidity0, 0, uint128(type(int128).max));

        uint256 amount0Up = this.getAmount0(sqrtPriceAX96, sqrtPriceBX96, liquidity0, true);
        uint256 amount0Down = this.getAmount0(sqrtPriceAX96, sqrtPriceBX96, liquidity0, false);

        assertGe(amount0Up, amount0Down, "test_fuzz_GetAmountAndLiquidity0::1");
        assertLe(
            this.getLiquidity0(sqrtPriceAX96, sqrtPriceBX96, amount0Down),
            liquidity0,
            "test_fuzz_GetAmountAndLiquidity0::2"
        );
        assertGe(
            this.getLiquidity0(sqrtPriceAX96, sqrtPriceBX96, amount0Up),
            liquidity0,
            "test_fuzz_GetAmountAndLiquidity0::3"
        );
    }

    function test_Fuzz_GetAmount1(uint256 sqrtPriceAX96, uint256 sqrtPriceBX96, uint256 liquidity1) public view {
        sqrtPriceAX96 = bound(sqrtPriceAX96, 1, type(uint128).max - 1);
        sqrtPriceBX96 = bound(sqrtPriceBX96, sqrtPriceAX96 + 1, type(uint128).max);
        liquidity1 = bound(liquidity1, 0, uint128(type(int128).max));

        uint256 amount1Up = this.getAmount1(sqrtPriceAX96, sqrtPriceBX96, liquidity1, true);
        uint256 amount1Down = this.getAmount1(sqrtPriceAX96, sqrtPriceBX96, liquidity1, false);

        assertGe(amount1Up, amount1Down, "test_Fuzz_GetAmount1::1");
        assertLe(
            _getLiquidity1(sqrtPriceAX96, sqrtPriceBX96, uint256(amount1Down)), liquidity1, "test_Fuzz_GetAmount1::2"
        );
        assertGe(
            _getLiquidity1(sqrtPriceAX96, sqrtPriceBX96, uint256(amount1Up)), liquidity1, "test_Fuzz_GetAmount1::3"
        );
    }

    function _getLiquidity1(uint256 sqrtPriceAX96, uint256 sqrtPriceBX96, uint256 amount1)
        private
        pure
        returns (uint256 liquidity1)
    {
        return Math.fullMulDiv(amount1, 2 ** 96, sqrtPriceBX96 - sqrtPriceAX96);
    }

    function test_Fuzz_GetNextSqrtRatioFromAmount0_GreaterThanZero(
        uint256 sqrtRatioX96,
        uint256 liquidity,
        int256 amount0
    ) public view {
        liquidity = bound(liquidity, 1, uint128(type(int128).max));
        amount0 = bound(amount0, 1, int256(_min(uint128(type(int128).max), liquidity * 2 ** 96)));
        sqrtRatioX96 = bound(sqrtRatioX96, 1, _min(type(uint128).max, liquidity << 96) / uint256(amount0));

        uint256 sqrtNextX96 = this.getNextSqrtRatioFromAmount0(sqrtRatioX96, liquidity, amount0);
        assertLe(sqrtNextX96, sqrtRatioX96, "test_Fuzz_GetNextSqrtRatioFromAmount0_GreaterThanZero::1");

        // Make sure that we receive more than expected
        assertLe(
            this.getAmount0(sqrtNextX96, sqrtRatioX96, liquidity, true),
            _abs(amount0),
            "test_Fuzz_GetNextSqrtRatioFromAmount0_GreaterThanZero::2"
        );
    }

    function test_Fuzz_GetNextSqrtRatioFromAmount0_LowerThanZero(
        uint256 sqrtRatioX96,
        uint256 liquidity,
        int256 amount0
    ) public view {
        liquidity = bound(liquidity, 2, uint128(type(int128).max));
        amount0 = bound(amount0, -int256(_min(uint128(type(int128).max), (liquidity - 1) * 2 ** 96)), -1);
        sqrtRatioX96 = bound(sqrtRatioX96, 1, _min(type(uint128).max, (liquidity - 1) << 96) / uint256(-amount0));

        uint256 sqrtNextX96 = this.getNextSqrtRatioFromAmount0(sqrtRatioX96, liquidity, amount0);
        assertGe(sqrtNextX96, sqrtRatioX96, "test_Fuzz_GetNextSqrtRatioFromAmount0_LowerThanZero::1");

        // Make sure that we send less than expected
        assertGe(
            this.getAmount0(sqrtRatioX96, sqrtNextX96, liquidity, false),
            _abs(amount0),
            "test_Fuzz_GetNextSqrtRatioFromAmount0_LowerThanZero::2"
        );
    }

    function test_Fuzz_Revert_GetNextSqrtRatioFromAmount0(uint256 liquidity, int256 prod) public {
        vm.expectRevert(SwapMath.LiquidityOverflow0.selector);
        this.getNextSqrtRatioFromAmount0(1, type(uint160).max, int256(uint256(type(uint96).max) + 1));

        vm.expectRevert(SwapMath.LiquidityOverflow0.selector);
        this.getNextSqrtRatioFromAmount0(2 ** 48, 1, -int256(2 ** 48));

        vm.expectRevert(SwapMath.LiquidityOverflow0.selector);
        this.getNextSqrtRatioFromAmount0(0, 0, 1);

        vm.expectRevert(SwapMath.LiquidityOverflow0.selector);
        this.getNextSqrtRatioFromAmount0(0, 0, -1);

        liquidity = bound(liquidity, 1, uint128(type(int128).max));

        vm.expectRevert(SwapMath.LiquidityOverflow0.selector);
        this.getNextSqrtRatioFromAmount0(
            1, liquidity, bound(prod, type(int256).max - int256(liquidity * 2 ** 96) + 1, type(int256).max)
        );

        vm.expectRevert(SwapMath.LiquidityOverflow0.selector);
        this.getNextSqrtRatioFromAmount0(1, liquidity, bound(prod, type(int256).min, -int256(liquidity * 2 ** 96)));
    }

    function test_Fuzz_GetNextSqrtRatioFromAmount1_GreaterThanZero(
        uint256 sqrtRatioX96,
        uint256 liquidity,
        int256 amount1
    ) public view {
        amount1 = bound(amount1, 1, type(int128).max);
        sqrtRatioX96 = bound(sqrtRatioX96, 1, type(uint128).max);
        liquidity = bound(
            liquidity, 1, _min(uint128(type(int128).max), uint256(type(int256).max - (amount1 << 96)) / sqrtRatioX96)
        );

        uint256 sqrtNextX96 = this.getNextSqrtRatioFromAmount1(sqrtRatioX96, liquidity, amount1);
        assertLe(sqrtRatioX96, sqrtNextX96, "test_Fuzz_GetNextSqrtRatioFromAmount1_GreaterThanZero::1");

        // Make sure that we receive more than expected
        assertLe(
            this.getAmount1(sqrtRatioX96, sqrtNextX96, liquidity, true),
            _abs(amount1),
            "test_Fuzz_GetNextSqrtRatioFromAmount1_GreaterThanZero::2"
        );
    }

    function test_Fuzz_GetNextSqrtRatioFromAmount1_LowerThanZero(
        uint256 sqrtRatioX96,
        uint256 liquidity,
        int256 amount1
    ) public view {
        amount1 = bound(amount1, type(int128).min, -1);
        liquidity = bound(liquidity, Math.divUp(uint256(-amount1), 2 ** 31), uint128(type(int128).max));
        sqrtRatioX96 = bound(
            sqrtRatioX96,
            _min(type(uint128).max, Math.divUp(uint256(-amount1) * 2 ** 96, liquidity) + 1),
            type(uint128).max
        );

        uint256 sqrtNextX96 = this.getNextSqrtRatioFromAmount1(sqrtRatioX96, liquidity, amount1);
        assertGe(sqrtRatioX96, sqrtNextX96, "test_Fuzz_GetNextSqrtRatioFromAmount1_LowerThanZero::1");

        // Make sure that we send less than expected
        assertGe(
            this.getAmount1(sqrtNextX96, sqrtRatioX96, liquidity, false),
            _abs(amount1),
            "test_Fuzz_GetNextSqrtRatioFromAmount1_LowerThanZero::2"
        );
    }

    function test_Fuzz_Revert_GetNextSqrtRatioFromAmount1(uint256 prod, int256 amount1) public {
        vm.expectRevert(SwapMath.LiquidityOverflow1.selector);
        this.getNextSqrtRatioFromAmount1(1, uint256(type(int256).max) + uint256(type(uint96).max) + 2, type(int160).max);

        vm.expectRevert(SwapMath.LiquidityOverflow1.selector);
        this.getNextSqrtRatioFromAmount1(2 ** 48, 2 ** 48, -1);

        vm.expectRevert(SwapMath.LiquidityOverflow1.selector);
        this.getNextSqrtRatioFromAmount1(0, 1, 0);

        vm.expectRevert(SwapMath.LiquidityOverflow1.selector);
        this.getNextSqrtRatioFromAmount1(1, 0, 0);

        int256 amountGt0 = bound(amount1, 1, type(int128).max);
        prod = bound(prod, uint256(type(int256).max) - uint256(amountGt0) * 2 ** 96 + 1, uint256(type(int256).max));

        vm.expectRevert(SwapMath.LiquidityOverflow1.selector);
        this.getNextSqrtRatioFromAmount1(1, prod, amountGt0);

        prod = bound(prod, 1, uint256(int256(type(int160).max)) * 2 ** 96);
        int256 amountLt0 = bound(amount1, type(int160).min, -int256(Math.divUp(prod, 2 ** 96) + 1));

        vm.expectRevert(SwapMath.LiquidityOverflow1.selector);
        this.getNextSqrtRatioFromAmount1(1, prod, amountLt0);
    }

    function test_Fuzz_GetDeltaAmounts_Swap0to1_ExactInput_Excess(
        uint256 sqrtRatioX96,
        uint256 targetRatioX96,
        uint256 liquidity,
        int256 deltaAmount,
        uint256 fee
    ) public view {
        sqrtRatioX96 = bound(sqrtRatioX96, 2, type(uint128).max);
        targetRatioX96 = bound(targetRatioX96, 1, sqrtRatioX96 - 1);
        fee = bound(fee, 0, SwapMath.MAX_FEE - 1);

        {
            uint256 prodB = sqrtRatioX96 * targetRatioX96;
            uint256 denom = (sqrtRatioX96 - targetRatioX96) * 2 ** 96;

            uint256 maxLiq = _min(
                prodB / denom > type(uint128).max
                    ? type(uint128).max
                    : Math.fullMulDiv(
                        uint128(type(int128).max), sqrtRatioX96 * targetRatioX96, (sqrtRatioX96 - targetRatioX96) * 2 ** 96
                    ),
                uint256(uint128(type(int128).max)) * 2 ** 96 / (sqrtRatioX96 - targetRatioX96)
            );
            vm.assume(maxLiq > 0);

            liquidity = bound(liquidity, 1, _min(uint128(type(int128).max), maxLiq));
            int256 minDeltaAmount = int256(this.getAmount0(targetRatioX96, sqrtRatioX96, liquidity, true));
            minDeltaAmount = int256(Math.divUp(uint256(minDeltaAmount) * SwapMath.MAX_FEE, SwapMath.MAX_FEE - fee));
            vm.assume(minDeltaAmount < type(int128).max);
            deltaAmount = bound(deltaAmount, minDeltaAmount, type(int128).max);
        }

        (uint256 sqrtNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmountIn) =
            this.getDeltaAmounts(sqrtRatioX96, targetRatioX96, liquidity, deltaAmount, fee);

        assertEq(sqrtNextX96, targetRatioX96, "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactInput_Excess::1");
        assertLe(amountIn, _abs(deltaAmount), "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactInput_Excess::2");
        assertEq(
            amountIn,
            this.getAmount0(sqrtNextX96, sqrtRatioX96, liquidity, true),
            "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactInput_Excess::3"
        );
        assertEq(
            amountOut,
            this.getAmount1(sqrtNextX96, sqrtRatioX96, liquidity, false),
            "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactInput_Excess::4"
        );
        assertEq(
            feeAmountIn,
            Math.divUp(amountIn * fee, SwapMath.MAX_FEE - fee),
            "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactInput_Excess::5"
        );
    }

    function test_Fuzz_GetDeltaAmounts_Swap0to1_ExactInput_Under(
        uint256 sqrtRatioX96,
        uint256 targetRatioX96,
        uint256 liquidity,
        int256 deltaAmount,
        uint256 fee
    ) public view {
        sqrtRatioX96 = bound(sqrtRatioX96, 2, type(uint128).max);
        targetRatioX96 = bound(targetRatioX96, 1, sqrtRatioX96 - 1);
        fee = bound(fee, 0, SwapMath.MAX_FEE - 1);

        {
            uint256 prodB = sqrtRatioX96 * targetRatioX96;
            uint256 denom = (sqrtRatioX96 - targetRatioX96) * 2 ** 96;

            uint256 maxLiq = _min(
                prodB / denom > type(uint128).max
                    ? type(uint128).max
                    : Math.fullMulDiv(
                        uint128(type(int128).max), sqrtRatioX96 * targetRatioX96, (sqrtRatioX96 - targetRatioX96) * 2 ** 96
                    ),
                uint256(uint128(type(int128).max)) * 2 ** 96 / (sqrtRatioX96 - targetRatioX96)
            );
            vm.assume(maxLiq > 0);

            liquidity = bound(liquidity, 1, _min(uint128(type(int128).max), maxLiq));
            int256 maxDeltaAmount = int256(this.getAmount0(targetRatioX96, sqrtRatioX96, liquidity, true));
            maxDeltaAmount = maxDeltaAmount * int256(SwapMath.MAX_FEE) / int256(SwapMath.MAX_FEE - fee);
            vm.assume(maxDeltaAmount < type(int128).max);
            deltaAmount = bound(deltaAmount, 0, maxDeltaAmount);
        }

        (uint256 sqrtNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmountIn) =
            this.getDeltaAmounts(sqrtRatioX96, targetRatioX96, liquidity, deltaAmount, fee);

        assertGe(sqrtNextX96, targetRatioX96, "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactInput_Under::1");
        assertLe(sqrtNextX96, sqrtRatioX96, "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactInput_Under::2");
        assertEq(amountIn + feeAmountIn, _abs(deltaAmount), "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactInput_Under::3");
        assertEq(
            amountIn,
            this.getAmount0(sqrtNextX96, sqrtRatioX96, liquidity, true),
            "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactInput_Under::4"
        );
        assertEq(
            amountOut,
            this.getAmount1(sqrtNextX96, sqrtRatioX96, liquidity, false),
            "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactInput_Under::5"
        );
        assertEq(feeAmountIn, _abs(deltaAmount) - amountIn, "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactInput_Under::6");
    }

    function test_Fuzz_GetDeltaAmounts_Swap0to1_ExactOutput_Excess(
        uint256 sqrtRatioX96,
        uint256 targetRatioX96,
        uint256 liquidity,
        int256 deltaAmount,
        uint256 fee
    ) public view {
        sqrtRatioX96 = bound(sqrtRatioX96, 2, type(uint128).max);
        targetRatioX96 = bound(targetRatioX96, 1, sqrtRatioX96 - 1);
        fee = bound(fee, 0, SwapMath.MAX_FEE - 1);

        {
            uint256 prodB = sqrtRatioX96 * targetRatioX96;
            uint256 denom = (sqrtRatioX96 - targetRatioX96) * 2 ** 96;

            uint256 maxLiq = _min(
                prodB / denom > type(uint128).max
                    ? type(uint128).max
                    : Math.fullMulDiv(
                        uint128(type(int128).max), sqrtRatioX96 * targetRatioX96, (sqrtRatioX96 - targetRatioX96) * 2 ** 96
                    ),
                uint256(uint128(type(int128).max)) * 2 ** 96 / (sqrtRatioX96 - targetRatioX96)
            );
            vm.assume(maxLiq > 0);

            liquidity = bound(liquidity, 1, _min(uint128(type(int128).max), maxLiq));
            int256 minDeltaAmount = int256(this.getAmount1(targetRatioX96, sqrtRatioX96, liquidity, false));
            vm.assume(minDeltaAmount > 0);
            minDeltaAmount =
                -int256(uint256(minDeltaAmount) + Math.divUp(uint256(minDeltaAmount) * fee, SwapMath.MAX_FEE - fee));
            vm.assume(minDeltaAmount > type(int128).min);
            deltaAmount = bound(deltaAmount, type(int128).min, minDeltaAmount);
        }

        (uint256 sqrtNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmountIn) =
            this.getDeltaAmounts(sqrtRatioX96, targetRatioX96, liquidity, deltaAmount, fee);

        assertEq(sqrtNextX96, targetRatioX96, "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactOutput_Excess::1");
        assertLe(amountOut, _abs(deltaAmount), "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactOutput_Excess::2");
        assertEq(
            amountIn,
            this.getAmount0(sqrtNextX96, sqrtRatioX96, liquidity, true),
            "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactOutput_Excess::3"
        );
        assertEq(
            amountOut,
            this.getAmount1(sqrtNextX96, sqrtRatioX96, liquidity, false),
            "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactOutput_Excess::4"
        );
        assertEq(
            feeAmountIn,
            Math.divUp(amountIn * fee, SwapMath.MAX_FEE - fee),
            "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactOutput_Excess::5"
        );
    }

    function test_Fuzz_GetDeltaAmounts_Swap0to1_ExactOutput_Under(
        uint256 sqrtRatioX96,
        uint256 targetRatioX96,
        uint256 liquidity,
        int256 deltaAmount,
        uint256 fee
    ) public view {
        sqrtRatioX96 = bound(sqrtRatioX96, 2, type(uint128).max);
        targetRatioX96 = bound(targetRatioX96, 1, sqrtRatioX96 - 1);
        fee = bound(fee, 0, SwapMath.MAX_FEE - 1);

        {
            uint256 prodB = sqrtRatioX96 * targetRatioX96;
            uint256 denom = (sqrtRatioX96 - targetRatioX96) * 2 ** 96;

            uint256 maxLiq = _min(
                prodB / denom > type(uint128).max
                    ? type(uint128).max
                    : Math.fullMulDiv(
                        uint128(type(int128).max), sqrtRatioX96 * targetRatioX96, (sqrtRatioX96 - targetRatioX96) * 2 ** 96
                    ),
                uint256(uint128(type(int128).max)) * 2 ** 96 / (sqrtRatioX96 - targetRatioX96)
            );
            vm.assume(maxLiq > 0);

            liquidity = bound(liquidity, 1, _min(uint128(type(int128).max), maxLiq));
            int256 maxDeltaAmount = int256(this.getAmount1(targetRatioX96, sqrtRatioX96, liquidity, false));
            vm.assume(maxDeltaAmount < type(int128).max);
            deltaAmount = bound(deltaAmount, -int256(maxDeltaAmount), 0);
        }

        (uint256 sqrtNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmountIn) =
            this.getDeltaAmounts(sqrtRatioX96, targetRatioX96, liquidity, deltaAmount, fee);

        assertGe(sqrtNextX96, targetRatioX96, "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactOutput_Under::1");
        assertLe(sqrtNextX96, sqrtRatioX96, "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactOutput_Under::2");
        assertEq(amountOut, _abs(deltaAmount), "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactOutput_Under::3");
        assertLe(
            amountOut,
            this.getAmount1(sqrtNextX96, sqrtRatioX96, liquidity, false),
            "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactOutput_Under::4"
        );
        assertEq(
            amountIn,
            this.getAmount0(sqrtNextX96, sqrtRatioX96, liquidity, true),
            "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactOutput_Under::5"
        );
        assertEq(
            feeAmountIn,
            Math.divUp(amountIn * fee, SwapMath.MAX_FEE - fee),
            "test_Fuzz_GetDeltaAmounts_Swap0to1_ExactOutput_Under::6"
        );
    }

    function test_Fuzz_GetDeltaAmounts_Swap1to0_ExactInput_Excess(
        uint256 sqrtRatioX96,
        uint256 targetRatioX96,
        uint256 liquidity,
        int256 deltaAmount,
        uint256 fee
    ) public view {
        sqrtRatioX96 = bound(sqrtRatioX96, 1, type(uint128).max - 1);
        targetRatioX96 = bound(targetRatioX96, sqrtRatioX96 + 1, type(uint128).max);
        fee = bound(fee, 0, SwapMath.MAX_FEE - 1);

        {
            uint256 prodB = sqrtRatioX96 * targetRatioX96;
            uint256 denom = (targetRatioX96 - sqrtRatioX96) * 2 ** 96;

            uint256 maxLiq = _min(
                prodB / denom > type(uint128).max
                    ? type(uint128).max
                    : Math.fullMulDiv(
                        uint128(type(int128).max), sqrtRatioX96 * targetRatioX96, (targetRatioX96 - sqrtRatioX96) * 2 ** 96
                    ),
                uint256(uint128(type(int128).max)) * 2 ** 96 / (targetRatioX96 - sqrtRatioX96)
            );
            vm.assume(maxLiq > 0);

            liquidity = bound(liquidity, 1, _min(uint128(type(int128).max), maxLiq));
            int256 minDeltaAmount = int256(this.getAmount1(targetRatioX96, sqrtRatioX96, liquidity, true));
            minDeltaAmount = int256(Math.divUp(uint256(minDeltaAmount) * SwapMath.MAX_FEE, SwapMath.MAX_FEE - fee));
            vm.assume(minDeltaAmount < type(int128).max);
            deltaAmount = bound(deltaAmount, minDeltaAmount, type(int128).max);
        }

        (uint256 sqrtNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmountIn) =
            this.getDeltaAmounts(sqrtRatioX96, targetRatioX96, liquidity, deltaAmount, fee);

        assertEq(sqrtNextX96, targetRatioX96, "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactInput_Excess::1");
        assertLe(amountIn, _abs(deltaAmount), "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactInput_Excess::2");
        assertEq(
            amountIn,
            this.getAmount1(sqrtNextX96, sqrtRatioX96, liquidity, true),
            "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactInput_Excess::3"
        );
        assertEq(
            amountOut,
            this.getAmount0(sqrtNextX96, sqrtRatioX96, liquidity, false),
            "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactInput_Excess::4"
        );
        assertEq(
            feeAmountIn,
            Math.divUp(amountIn * fee, SwapMath.MAX_FEE - fee),
            "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactInput_Excess::5"
        );
    }

    function test_Fuzz_GetDeltaAmounts_Swap1to0_ExactInput_Under(
        uint256 sqrtRatioX96,
        uint256 targetRatioX96,
        uint256 liquidity,
        int256 deltaAmount,
        uint256 fee
    ) public view {
        sqrtRatioX96 = bound(sqrtRatioX96, 1, type(uint128).max - 1);
        targetRatioX96 = bound(targetRatioX96, sqrtRatioX96 + 1, type(uint128).max);
        fee = bound(fee, 0, SwapMath.MAX_FEE - 1);

        {
            uint256 prodB = sqrtRatioX96 * targetRatioX96;
            uint256 denom = (targetRatioX96 - sqrtRatioX96) * 2 ** 96;

            uint256 maxLiq = _min(
                prodB / denom > type(uint128).max
                    ? type(uint128).max
                    : Math.fullMulDiv(
                        uint128(type(int128).max), sqrtRatioX96 * targetRatioX96, (targetRatioX96 - sqrtRatioX96) * 2 ** 96
                    ),
                uint256(uint128(type(int128).max)) * 2 ** 96 / (targetRatioX96 - sqrtRatioX96)
            );
            vm.assume(maxLiq > 0);

            liquidity = bound(liquidity, 1, _min(uint128(type(int128).max), maxLiq));
            int256 maxDeltaAmount = int256(this.getAmount1(targetRatioX96, sqrtRatioX96, liquidity, true));
            maxDeltaAmount = maxDeltaAmount * int256(SwapMath.MAX_FEE) / int256(SwapMath.MAX_FEE - fee);
            vm.assume(maxDeltaAmount < type(int128).max);
            deltaAmount = bound(deltaAmount, 0, maxDeltaAmount);
        }

        (uint256 sqrtNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmountIn) =
            this.getDeltaAmounts(sqrtRatioX96, targetRatioX96, liquidity, deltaAmount, fee);

        assertLe(sqrtNextX96, targetRatioX96, "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactInput_Under::1");
        assertGe(sqrtNextX96, sqrtRatioX96, "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactInput_Under::2");
        assertEq(amountIn + feeAmountIn, _abs(deltaAmount), "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactInput_Under::3");
        assertEq(
            amountIn,
            this.getAmount1(sqrtNextX96, sqrtRatioX96, liquidity, true),
            "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactInput_Under::4"
        );
        assertEq(
            amountOut,
            this.getAmount0(sqrtNextX96, sqrtRatioX96, liquidity, false),
            "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactInput_Under::5"
        );
        assertGe(
            feeAmountIn,
            Math.divUp(amountIn * fee, SwapMath.MAX_FEE - fee),
            "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactInput_Under::6"
        );
    }

    function test_Fuzz_GetDeltaAmounts_Swap1to0_ExactOutput_Excess(
        uint256 sqrtRatioX96,
        uint256 targetRatioX96,
        uint256 liquidity,
        int256 deltaAmount,
        uint256 fee
    ) public view {
        sqrtRatioX96 = bound(sqrtRatioX96, 1, type(uint128).max - 1);
        targetRatioX96 = bound(targetRatioX96, sqrtRatioX96 + 1, type(uint128).max);
        fee = bound(fee, 0, SwapMath.MAX_FEE - 1);

        {
            uint256 prodB = sqrtRatioX96 * targetRatioX96;
            uint256 denom = (targetRatioX96 - sqrtRatioX96) * 2 ** 96;

            uint256 maxLiq = _min(
                prodB / denom > type(uint128).max
                    ? type(uint128).max
                    : Math.fullMulDiv(
                        uint128(type(int128).max), sqrtRatioX96 * targetRatioX96, (targetRatioX96 - sqrtRatioX96) * 2 ** 96
                    ),
                uint256(uint128(type(int128).max)) * 2 ** 96 / (targetRatioX96 - sqrtRatioX96)
            );
            vm.assume(maxLiq > 0);

            liquidity = bound(liquidity, 1, _min(uint128(type(int128).max), maxLiq));
            int256 minDeltaAmount = int256(this.getAmount0(targetRatioX96, sqrtRatioX96, liquidity, false));
            vm.assume(minDeltaAmount > 0);
            minDeltaAmount =
                -int256(uint256(minDeltaAmount) + Math.divUp(uint256(minDeltaAmount) * fee, SwapMath.MAX_FEE - fee));
            vm.assume(minDeltaAmount > type(int128).min);
            deltaAmount = bound(deltaAmount, type(int128).min, minDeltaAmount);
        }

        (uint256 sqrtNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmountIn) =
            this.getDeltaAmounts(sqrtRatioX96, targetRatioX96, liquidity, deltaAmount, fee);

        assertEq(sqrtNextX96, targetRatioX96, "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactOutput_Excess::1");
        assertLe(amountOut, _abs(deltaAmount), "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactOutput_Excess::2");
        assertEq(
            amountIn,
            this.getAmount1(sqrtNextX96, sqrtRatioX96, liquidity, true),
            "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactOutput_Excess::3"
        );
        assertEq(
            amountOut,
            this.getAmount0(sqrtNextX96, sqrtRatioX96, liquidity, false),
            "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactOutput_Excess::4"
        );
        assertEq(
            feeAmountIn,
            Math.divUp(amountIn * fee, SwapMath.MAX_FEE - fee),
            "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactOutput_Excess::5"
        );
    }

    function test_Fuzz_GetDeltaAmounts_Swap1to0_ExactOutput_Under(
        uint256 sqrtRatioX96,
        uint256 targetRatioX96,
        uint256 liquidity,
        int256 deltaAmount,
        uint256 fee
    ) public view {
        sqrtRatioX96 = bound(sqrtRatioX96, 1, type(uint128).max - 1);
        targetRatioX96 = bound(targetRatioX96, sqrtRatioX96 + 1, type(uint128).max);
        fee = bound(fee, 0, SwapMath.MAX_FEE - 1);

        {
            uint256 prodB = sqrtRatioX96 * targetRatioX96;
            uint256 denom = (targetRatioX96 - sqrtRatioX96) * 2 ** 96;

            uint256 maxLiq = _min(
                prodB / denom > type(uint128).max
                    ? type(uint128).max
                    : Math.fullMulDiv(
                        uint128(type(int128).max), sqrtRatioX96 * targetRatioX96, (targetRatioX96 - sqrtRatioX96) * 2 ** 96
                    ),
                uint256(uint128(type(int128).max)) * 2 ** 96 / (targetRatioX96 - sqrtRatioX96)
            );
            vm.assume(maxLiq > 0);

            liquidity = bound(liquidity, 1, _min(uint128(type(int128).max), maxLiq));
            int256 maxDeltaAmount = int256(this.getAmount0(targetRatioX96, sqrtRatioX96, liquidity, false));
            vm.assume(maxDeltaAmount < type(int128).max);
            deltaAmount = bound(deltaAmount, -int256(maxDeltaAmount), 0);
        }

        (uint256 sqrtNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmountIn) =
            this.getDeltaAmounts(sqrtRatioX96, targetRatioX96, liquidity, deltaAmount, fee);

        assertLe(sqrtNextX96, targetRatioX96, "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactOutput_Under::1");
        assertGe(sqrtNextX96, sqrtRatioX96, "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactOutput_Under::2");
        assertEq(amountOut, _abs(deltaAmount), "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactOutput_Under::3");
        assertLe(
            amountOut,
            this.getAmount0(sqrtNextX96, sqrtRatioX96, liquidity, false),
            "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactOutput_Under::4"
        );
        assertEq(
            amountIn,
            this.getAmount1(sqrtNextX96, sqrtRatioX96, liquidity, true),
            "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactOutput_Under::5"
        );
        assertEq(
            feeAmountIn,
            Math.divUp(amountIn * fee, SwapMath.MAX_FEE - fee),
            "test_Fuzz_GetDeltaAmounts_Swap1to0_ExactOutput_Under::6"
        );
    }

    // Helper functions
    function _abs(int256 x) private pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x < y ? x : y;
    }

    function getDeltaAmounts(
        uint256 sqrtRatioX96,
        uint256 targetRatioX96,
        uint256 liquidity,
        int256 deltaAmount,
        uint256 fee
    ) external pure returns (uint256 sqrtNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmountIn) {
        return SwapMath.getDeltaAmounts(sqrtRatioX96, targetRatioX96, liquidity, deltaAmount, fee);
    }

    function getLiquidity0(uint256 sqrtRatio0X96, uint256 sqrtRatio1X96, uint256 amount0)
        external
        pure
        returns (uint256)
    {
        return SwapMath.getLiquidity0(sqrtRatio0X96, sqrtRatio1X96, amount0);
    }

    function getAmount0(uint256 sqrtRatio0X96, uint256 sqrtRatio1X96, uint256 liquidity, bool roundUp)
        external
        pure
        returns (uint256)
    {
        return SwapMath.getAmount0(sqrtRatio0X96, sqrtRatio1X96, liquidity, roundUp);
    }

    function getAmount1(uint256 sqrtRatio0X96, uint256 sqrtRatio1X96, uint256 liquidity, bool roundUp)
        external
        pure
        returns (uint256)
    {
        return SwapMath.getAmount1(sqrtRatio0X96, sqrtRatio1X96, liquidity, roundUp);
    }

    function getNextSqrtRatioFromAmount0(uint256 sqrtRatioX96, uint256 liquidity, int256 amount0)
        external
        pure
        returns (uint256)
    {
        return SwapMath.getNextSqrtRatioFromAmount0(sqrtRatioX96, liquidity, amount0);
    }

    function getNextSqrtRatioFromAmount1(uint256 sqrtRatioX96, uint256 liquidity, int256 amount1)
        external
        pure
        returns (uint256)
    {
        return SwapMath.getNextSqrtRatioFromAmount1(sqrtRatioX96, liquidity, amount1);
    }
}
