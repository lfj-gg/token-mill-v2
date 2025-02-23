// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Math} from "./libraries/SwapMath.sol";
import {SwapMath} from "./libraries/SwapMath.sol";
import {ITMToken} from "./interfaces/ITMToken.sol";
import {ITMMarket} from "./interfaces/ITMMarket.sol";
import {ITMFactory} from "./interfaces/ITMFactory.sol";

contract TMMarket is ITMMarket {
    using SafeERC20 for IERC20;

    address private immutable factory;
    uint256 private immutable liquidityA; // Liquidity before graduation
    uint256 private immutable liquidityB; // Liquidity after graduation
    uint256 private immutable sqrtRatioAX96; // Start price, calculated as sqrt((price0 * 10^decimals1) / (price1 * 10^decimals0)) * 2^96
    uint256 private immutable sqrtRatioBX96; // Graduation price
    uint256 private constant sqrtRatioMaxX96 = type(uint128).max; // Maximum price
    uint256 private immutable maxSupply;

    address private _token0; // Base token
    address private _token1; // Quote token

    uint128 private _sqrtRatioX96; // Current price
    uint64 private _fee;
    uint64 private _state;

    uint128 private _reserve0;
    uint128 private _reserve1;

    modifier nonReentrant() {
        if (_state == 1) revert ReentrantCall();
        _state = 1;
        _;
        _state = 0;
    }

    constructor(address factory_, uint256 amount0A, uint256 amount0B, uint256 sqrtRatioAX96_, uint256 sqrtRatioBX96_) {
        if (sqrtRatioAX96_ >= sqrtRatioBX96_) revert InvalidRatiosOrder();
        if (sqrtRatioAX96_ == 0 || sqrtRatioBX96_ > sqrtRatioMaxX96) revert InvalidRatios();

        factory = factory_;
        sqrtRatioAX96 = sqrtRatioAX96_;
        sqrtRatioBX96 = sqrtRatioBX96_;
        maxSupply = Math.safeUint127(amount0A + amount0B);

        uint256 liquidityA_ = SwapMath.getLiquidity0(sqrtRatioAX96_, sqrtRatioBX96_, amount0A);
        uint256 liquidityB_ = SwapMath.getLiquidity0(sqrtRatioBX96, sqrtRatioMaxX96, amount0B);

        if (liquidityA_ == 0 || liquidityB_ == 0) revert LiquiditiesZero();

        liquidityA = Math.safeUint127(liquidityA_);
        liquidityB = Math.safeUint127(liquidityB_);

        _sqrtRatioX96 = 1; // Prevent the implementation from being initialized
    }

    function initialize(address token0_, address token1_, uint256 fee_) external override returns (bool) {
        if (_sqrtRatioX96 != 0) revert AlreadyInitialized();
        if (token0_ == token1_) revert SameTokens();
        if (fee_ > SwapMath.MAX_FEE) revert InvalidFee();

        _token0 = token0_;
        _token1 = token1_;

        _sqrtRatioX96 = uint128(sqrtRatioAX96);
        _fee = uint64(fee_);

        ITMToken(token0_).mint(address(this), maxSupply);
        _reserve0 = uint128(maxSupply);

        return true;
    }

    function getFactory() external view override returns (address) {
        return factory;
    }

    function getLiquidities() external view override returns (uint256, uint256) {
        return (liquidityA, liquidityB);
    }

    function getSqrtRatios() external view override returns (uint256, uint256, uint256) {
        return (sqrtRatioAX96, sqrtRatioBX96, sqrtRatioMaxX96);
    }

    function getBaseToken() external view override returns (address) {
        return _token0;
    }

    function getQuoteToken() external view override returns (address) {
        return _token1;
    }

    function getSqrtRatio() external view override returns (uint256) {
        return _sqrtRatioX96;
    }

    function getFee() external view override returns (uint256) {
        return _fee;
    }

    function getReserves() external view override returns (uint256, uint256) {
        return (_reserve0, _reserve1);
    }

    function getDeltaAmounts(bool zeroForOne, int256 deltaAmount, uint256 sqrtRatioLimitX96)
        external
        view
        override
        returns (int256 amount0, int256 amount1)
    {
        (, uint256 amountIn, uint256 amountOut,) =
            _getDeltaAmounts(zeroForOne, deltaAmount, sqrtRatioLimitX96, _sqrtRatioX96, _fee);

        return zeroForOne ? (int256(amountIn), -int256(amountOut)) : (-int256(amountOut), int256(amountIn));
    }

    function swap(address to, bool zeroForOne, int256 deltaAmount, uint256 sqrtRatioLimitX96)
        external
        override
        nonReentrant
        returns (int256 amount0, int256 amount1)
    {
        if (deltaAmount == 0) revert ZeroDeltaAmount();

        (uint256 nextSqrtRatioX96, uint256 amountIn, uint256 amountOut, uint256 feeAmountIn) =
            _getDeltaAmounts(zeroForOne, deltaAmount, sqrtRatioLimitX96, _sqrtRatioX96, _fee);

        address token1 = _token1;
        uint256 reserve0 = _reserve0;
        uint256 reserve1 = _reserve1;

        uint256 feeAmount1;
        unchecked {
            if (zeroForOne) {
                amount0 = int256(amountIn);
                amount1 = -int256(amountOut);

                reserve0 = Math.addDelta128(reserve0, amount0);
                reserve1 = Math.addDelta128(reserve1, amount1);

                if (reserve0 > IERC20(_token0).balanceOf(address(this))) revert InsufficientBalance0();
                IERC20(token1).safeTransfer(to, uint256(-amount1));

                // Swap fee0 to fee1
                (nextSqrtRatioX96,, feeAmount1,) =
                    _getDeltaAmounts(zeroForOne, int256(feeAmountIn), sqrtRatioAX96, nextSqrtRatioX96, 0);
            } else {
                amount0 = -int256(amountOut);
                amount1 = int256(amountIn);

                reserve1 = Math.addDelta128(reserve1, amount1);
                reserve0 = Math.addDelta128(reserve0, amount0);

                if (reserve1 + feeAmount1 > IERC20(token1).balanceOf(address(this))) revert InsufficientBalance1();
                IERC20(_token0).safeTransfer(to, uint256(-amount0));

                feeAmount1 = feeAmountIn;
            }

            emit Swap(msg.sender, to, amount0, amount1, feeAmountIn, feeAmount1, nextSqrtRatioX96);

            if (feeAmount1 > 0) {
                reserve1 = Math.addDelta128(reserve1, -int256(feeAmount1));

                IERC20(token1).safeTransfer(factory, feeAmount1);
                ITMFactory(factory).onFeeReceived(token1, feeAmount1);
            }
        }

        _sqrtRatioX96 = uint128(nextSqrtRatioX96);
        _reserve0 = uint128(reserve0);
        _reserve1 = uint128(reserve1);
    }

    function _getDeltaAmounts(
        bool zeroForOne,
        int256 deltaAmount,
        uint256 sqrtRatioLimitX96,
        uint256 currentSqrtRatioX96,
        uint256 fee
    ) internal view returns (uint256 nextSqrtRatioX96, uint256 amountIn, uint256 amountOut, uint256 feeAmountIn) {
        if (
            zeroForOne
                ? sqrtRatioLimitX96 >= currentSqrtRatioX96 || sqrtRatioLimitX96 < sqrtRatioAX96
                : sqrtRatioLimitX96 <= currentSqrtRatioX96 || sqrtRatioLimitX96 > sqrtRatioMaxX96
        ) revert InvalidSqrtRatioLimit();
        if (Math.safeInt128(deltaAmount) == 0) return (currentSqrtRatioX96, 0, 0, 0);

        // First range
        {
            uint256 liquidity = currentSqrtRatioX96 >= sqrtRatioBX96 ? liquidityB : liquidityA;
            uint256 targetRatioX96 =
                currentSqrtRatioX96 >= sqrtRatioBX96 == zeroForOne ? sqrtRatioBX96 : sqrtRatioLimitX96;

            (nextSqrtRatioX96, amountIn, amountOut, feeAmountIn) =
                SwapMath.getDeltaAmounts(currentSqrtRatioX96, targetRatioX96, liquidity, deltaAmount, fee);
        }

        deltaAmount = deltaAmount > 0
            ? deltaAmount - Math.toInt256(amountIn + feeAmountIn)
            : deltaAmount + Math.toInt256(amountOut);

        // Second range
        if (deltaAmount != 0 && nextSqrtRatioX96 != sqrtRatioLimitX96) {
            uint256 liquidity = sqrtRatioLimitX96 > sqrtRatioBX96 ? liquidityB : liquidityA;

            uint256 amountIn_;
            uint256 amountOut_;
            uint256 feeAmountIn_;
            (nextSqrtRatioX96, amountIn_, amountOut_, feeAmountIn_) =
                SwapMath.getDeltaAmounts(nextSqrtRatioX96, sqrtRatioLimitX96, liquidity, deltaAmount, fee);

            amountIn += amountIn_;
            amountOut += amountOut_;
            feeAmountIn += feeAmountIn_;
        }

        // If `amountIn + feeAmountIn < 2**127`, then `feeAmountIn < 2**127`. All results can be casted to `int128`, `uint128` or above.
        return (nextSqrtRatioX96, Math.safeUint127(amountIn + feeAmountIn), Math.safeUint127(amountOut), feeAmountIn);
    }
}
