    // SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "./Math.sol";

/**
 * @title Swap Math library
 * @dev Math library to calculate conversions from/to liquidity to/from token amounts.
 * Inspired by Uniswap V3's libraries:
 * https://github.com/Uniswap/v3-core/tree/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries
 */
library SwapMath {
    error LiquidityOverflow0();
    error LiquidityOverflow1();

    uint256 internal constant MAX_FEE = 1e6;

    /**
     * @dev Get the next sqrt price, as well as the amount of token0 and token1 to be paid/received if a swap were to
     * occur. The fee is applied to the side that receives the input amount.
     * If the current ratio is greater than the target ratio, the input is token0 and the output is token1.
     * If the current ratio is less than the target ratio, the input is token1 and the output is token0.
     * In any case, the next ratio will always move towards the target ratio, without ever exceeding it.
     * If deltaAmount is positive, the function will try to swap as much input as possible, up to abs(deltaAmount).
     * If deltaAmount is negative, the function will try to swap as much input as possible in order to get
     * abs(deltaAmount) of output token.
     * In any case, the function will never exceed the exact input (if deltaAmount is positive) or output (if
     * deltaAmount is negative) amount.
     * The fee will always be paid in the input token.
     * **The requirements on the parameters need to be enforced by the caller.**
     *
     * Requirements:
     *
     * - `sqrtRatioX96` must fit into 127 bits
     * - `sqrtTargetRatioX96` must fit into 127 bits
     * - `liquidity` must fit into 127 bits
     * - `fee` must be less than MAX_FEE
     * - `deltaAmount` must fit into 128 bits
     */
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

    /**
     * @dev Get the amount of liquidity given two ratios and an amount of token0.
     * Always rounds down as it's only used to calculate the initial liquidity.
     * We can use the lossless version because of the restriction on sqrtRatioAX96, sqrtRatioBX96 and amount0.
     * **The requirements on the parameters need to be enforced by the caller.**
     *
     * Requirements:
     *
     * - `sqrtRatioAX96` must fit into 127 bits
     * - `sqrtRatioBX96` must fit into 127 bits
     * - `sqrtRatioAX96` must be lower or equal to `sqrtRatioBX96`
     * - `amount0` must fit into 128 bits
     */
    function getLiquidity0(uint256 sqrtRatioAX96, uint256 sqrtRatioBX96, uint256 amount0)
        internal
        pure
        returns (uint256)
    {
        return Math.fullMulDiv(sqrtRatioAX96 * sqrtRatioBX96, amount0, (sqrtRatioBX96 - sqrtRatioAX96) << 96);
    }

    /**
     * @dev Get the amount of token0 given two ratios and an amount of liquidity.
     * Rounds up if `adding` is true, rounds down otherwise.
     * We can use the lossless version because of the restriction on sqrtRatioAX96, sqrtRatioBX96, liquidity and
     * amount0.
     * **The requirements on the parameters need to be enforced by the caller.**
     *
     * Requirements:
     *
     * - `sqrtRatioAX96` must fit into 127 bits
     * - `sqrtRatioBX96` must fit into 127 bits
     * - `liquidity` must fit into 127 bits
     */
    function getAmount0(uint256 sqrtRatioAX96, uint256 sqrtRatioBX96, uint256 liquidity, bool adding)
        internal
        pure
        returns (uint256 amount0)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        unchecked {
            // The unchecked operations can't overflow as all parameters are all smaller than 2**127-1,
            // and `sqrtRatioAX96 < sqrtRatioBX96`. However, the result might not fit into 256 bits in
            // some cases, but these cases will be handled within the Math library.
            return adding
                ? Math.fullMulDivUp(liquidity << 96, (sqrtRatioBX96 - sqrtRatioAX96), sqrtRatioAX96 * sqrtRatioBX96)
                : Math.fullMulDiv(liquidity << 96, (sqrtRatioBX96 - sqrtRatioAX96), sqrtRatioAX96 * sqrtRatioBX96);
        }
    }

    /**
     * @dev Get the amount of token1 given two ratios and an amount of liquidity.
     * Rounds up if `adding` is true, rounds down otherwise.
     * We can use the lossless version because of the restriction on sqrtRatioAX96, sqrtRatioBX96, liquidity and
     * amount1.
     * **The requirements on the parameters need to be enforced by the caller.**
     *
     * Requirements:
     *
     * - `sqrtRatioAX96` must fit into 127 bits
     * - `sqrtRatioBX96` must fit into 127 bits
     * - `liquidity` must fit into 127 bits
     */
    function getAmount1(uint256 sqrtRatioAX96, uint256 sqrtRatioBX96, uint256 liquidity, bool adding)
        internal
        pure
        returns (uint256 amount1)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        unchecked {
            // Can't overflow as all parameters are all smaller than 2**127-1, and `sqrtRatioAX96 < sqrtRatioBX96`
            return adding
                ? Math.divUp(liquidity * (sqrtRatioBX96 - sqrtRatioAX96), 2 ** 96)
                : liquidity * (sqrtRatioBX96 - sqrtRatioAX96) >> 96;
        }
    }

    /**
     * @dev Get the next sqrt price from an amount of token0.
     * Always rounds up, because in the exact output case (increasing price) we need to move the price at least
     * far enough to get the desired output amount, and in the exact input case (decreasing price) we need to move the
     * price less in order to not send too much output.
     * We can use the lossless version because of the restriction on sqrtRatio, liquidity and amount0.
     * **The requirements on the parameters need to be enforced by the caller.**
     * If the result overflows or underflows, revert with `LiquidityOverflow0()`.
     *
     * Requirements:
     *
     * - `sqrtRatioX96` must fit into 127 bits
     * - `liquidity` must fit into 127 bits
     * - `amount0` must fit into 128 bits
     * - `sqrtNextX96` must not overflow or underflow
     */
    function getNextSqrtRatioFromAmount0(uint256 sqrtRatioX96, uint256 liquidity, int256 amount0)
        internal
        pure
        returns (uint256 sqrtNextX96)
    {
        liquidity <<= 96; // `liquidity << 96` can't overflow as it's a uint127
        unchecked {
            int256 denominator = int256(liquidity) + amount0 * int256(sqrtRatioX96); // `amount0 * sqrtRatioX96` can't
                // overflow as it's a int128 * uint128
            if (denominator <= 0) revert LiquidityOverflow0();

            return Math.fullMulDivUp(liquidity, sqrtRatioX96, uint256(denominator));
        }
    }

    /**
     * @dev Get the next sqrt price from an amount of token1.
     * Always rounds down, because in the exact output case (decreasing price) we need to move the price at least
     * far enough to get the desired output amount, and in the exact input case (increasing price) we need to move the
     * price less in order to not send too much output.
     * We can use the lossless version because of the restriction on sqrtRatio, liquidity and amount1.
     * **The requirements on the parameters need to be enforced by the caller.**
     * If the result overflows or underflows, revert with `LiquidityOverflow1()`.
     *
     * Requirements:
     *
     * - `sqrtRatioX96` must fit into 127 bits
     * - `liquidity` must fit into 127 bits
     * - `amount1` must fit into 128 bits
     * - `sqrtNextX96` must not overflow or underflow
     */
    function getNextSqrtRatioFromAmount1(uint256 sqrtRatioX96, uint256 liquidity, int256 amount1)
        internal
        pure
        returns (uint256 sqrtNextX96)
    {
        unchecked {
            // `sqrtRatioX96 * liquidity` can't overflow as it's a uint127 * uint127, it fits in int256
            int256 numerator = int256(sqrtRatioX96 * liquidity) + (amount1 << 96); // `amount1 << 96` can't overflow as
                // it's a int128
            if (numerator <= 0) revert LiquidityOverflow1();
            return uint256(numerator) / liquidity;
        }
    }
}
