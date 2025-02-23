    // SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "./Math.sol";

library SwapMath {
    error LiquidityOverflow0();
    error LiquidityOverflow1();

    uint256 internal constant MAX_FEE = 1e6;

    function getDeltaAmounts(
        uint256 sqrtRatioX96,
        uint256 sqrtTargetRatioX96,
        uint256 liquidity,
        int256 deltaAmount,
        uint256 fee
    ) internal pure returns (uint256 sqrtNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmountIn) {
        (
            function(uint256, uint256, uint256, bool) pure returns (uint256) getAmountIn,
            function(uint256, uint256, uint256, bool) pure returns (uint256) getAmountOut
        ) = sqrtRatioX96 > sqrtTargetRatioX96 ? (getAmount0, getAmount1) : (getAmount1, getAmount0);

        unchecked {
            if (deltaAmount > 0) {
                uint256 remainingAmountIn = uint256(deltaAmount) * (MAX_FEE - fee) / (MAX_FEE);
                amountIn = getAmountIn(sqrtRatioX96, sqrtTargetRatioX96, liquidity, true);

                if (amountIn > remainingAmountIn) {
                    sqrtNextX96 = sqrtRatioX96 > sqrtTargetRatioX96
                        ? getNextSqrtRatioFromAmount0(sqrtRatioX96, liquidity, int256(remainingAmountIn))
                        : getNextSqrtRatioFromAmount1(sqrtRatioX96, liquidity, int256(remainingAmountIn));
                    amountIn = getAmountIn(sqrtRatioX96, sqrtNextX96, liquidity, true);
                    feeAmountIn = uint256(deltaAmount) - amountIn;
                } else {
                    sqrtNextX96 = sqrtTargetRatioX96;
                    feeAmountIn = Math.divUp(amountIn * fee, MAX_FEE - fee);
                }

                amountOut = getAmountOut(sqrtRatioX96, sqrtNextX96, liquidity, false);
            } else {
                if (deltaAmount == 0) return (sqrtRatioX96, 0, 0, 0);

                uint256 remainingAmountOut = uint256(-deltaAmount);
                amountOut = getAmountOut(sqrtRatioX96, sqrtTargetRatioX96, liquidity, false);

                if (amountOut > remainingAmountOut) {
                    sqrtNextX96 = sqrtRatioX96 > sqrtTargetRatioX96
                        ? getNextSqrtRatioFromAmount1(sqrtRatioX96, liquidity, deltaAmount)
                        : getNextSqrtRatioFromAmount0(sqrtRatioX96, liquidity, deltaAmount);
                    amountOut = remainingAmountOut;
                } else {
                    sqrtNextX96 = sqrtTargetRatioX96;
                }

                amountIn = getAmountIn(sqrtRatioX96, sqrtNextX96, liquidity, true);
                feeAmountIn = Math.divUp(amountIn * fee, MAX_FEE - fee);
            }
        }
    }

    function getLiquidity0(uint256 sqrtRatioAX96, uint256 sqrtRatioBX96, uint256 amount0)
        internal
        pure
        returns (uint256)
    {
        return Math.fullMulDiv(sqrtRatioAX96 * sqrtRatioBX96, amount0, (sqrtRatioBX96 - sqrtRatioAX96) << 96);
    }

    function getAmount0(uint256 sqrtRatioAX96, uint256 sqrtRatioBX96, uint256 liquidity, bool adding)
        internal
        pure
        returns (uint256 amount0)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        unchecked {
            // Can't overflow as all parameters are all smaller than 2**128-1, and `sqrtRatioAX96 < sqrtRatioBX96`
            return adding
                ? Math.fullMulDivUp(liquidity << 96, (sqrtRatioBX96 - sqrtRatioAX96), sqrtRatioAX96 * sqrtRatioBX96)
                : Math.fullMulDiv(liquidity << 96, (sqrtRatioBX96 - sqrtRatioAX96), sqrtRatioAX96 * sqrtRatioBX96);
        }
    }

    function getAmount1(uint256 sqrtRatioAX96, uint256 sqrtRatioBX96, uint256 liquidity, bool adding)
        internal
        pure
        returns (uint256 amount1)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        unchecked {
            // Can't overflow as all parameters are all smaller than 2**128-1, and `sqrtRatioAX96 < sqrtRatioBX96`
            return adding
                ? Math.divUp(liquidity * (sqrtRatioBX96 - sqrtRatioAX96), 2 ** 96)
                : liquidity * (sqrtRatioBX96 - sqrtRatioAX96) >> 96;
        }
    }

    function getNextSqrtRatioFromAmount0(uint256 sqrtRatioX96, uint256 liquidity, int256 amount0)
        internal
        pure
        returns (uint256 sqrtNextX96)
    {
        liquidity <<= 96; // `liquidity << 96` can't overflow as it's a uint127
        unchecked {
            int256 denominator = int256(liquidity) + amount0 * int256(sqrtRatioX96); // `amount0 * sqrtRatioX96` can't overflow as it's a int128 * uint128
            if (denominator <= 0) revert LiquidityOverflow0();

            return Math.fullMulDivUp(liquidity, sqrtRatioX96, uint256(denominator));
        }
    }

    function getNextSqrtRatioFromAmount1(uint256 sqrtRatioX96, uint256 liquidity, int256 amount1)
        internal
        pure
        returns (uint256 sqrtNextX96)
    {
        unchecked {
            // `sqrtRatioX96 * liquidity` can't overflow as it's a uint128 * uint127, it fits in int256
            int256 numerator = int256(sqrtRatioX96 * liquidity) + (amount1 << 96); // `amount1 << 96` can't overflow as it's a int128
            if (numerator <= 0) revert LiquidityOverflow1();
            return uint256(numerator) / liquidity;
        }
    }
}
