// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITMFactory} from "./interfaces/ITMFactory.sol";
import {ITMMarket} from "./interfaces/ITMMarket.sol";
import {ITMToken} from "./interfaces/ITMToken.sol";
import {Math} from "./libraries/SwapMath.sol";
import {SwapMath} from "./libraries/SwapMath.sol";

/**
 * @title TokenMill Market contract
 * @dev Market contract that allows swapping tokens with a fixed fee.
 * The fee amount will be sent to the factory if the token is the quote token (token1). If it is the base token
 * (token0), the fee will be directly swapped to the quote token and sent to the factory as well.
 * The market behaves like 2 uniswap v2 pools, the first one will range from sqrtRatioAX96 to sqrtRatioBX96,
 * and the second one will range from sqrtRatioBX96 to sqrtRatioMaxX96. The liquidity available in each internal pool
 * is decided at the creation of the contract and allows each pool to offer at most amount0A and amount0B of token0 (the
 * parameters of the constructor).
 * The number of token must be sent prior to calling the swap function. In the case of an exact output swap, the caller
 * should use the `getDeltaAmounts` function to calculate the correct amount of token to send.
 * Any excess token sent will be kept in the contract and will be used by future swaps.
 */
contract TMMarket is ITMMarket {
    using SafeERC20 for IERC20;

    address private immutable factory;
    address private immutable quoteToken; // Quote token
    uint256 private immutable liquidityA; // Liquidity before graduation
    uint256 private immutable liquidityB; // Liquidity after graduation
    uint256 private immutable sqrtRatioAX96; // Start price, calculated as sqrt((price0 * 10^decimals1) / (price1 * 10^decimals0)) * 2^96
    uint256 private immutable sqrtRatioBX96; // Graduation price, calculated in the same way as sqrtRatioAX96
    uint256 private constant sqrtRatioMaxX96 = 2 ** 127 - 1; // Maximum price
    uint256 private immutable maxSupply;

    address private _token0; // Base token

    uint128 private _sqrtRatioX96; // Current price
    uint64 private _fee;
    uint64 private _state;

    uint128 private _reserve0;
    uint128 private _reserve1;

    bool private _isMigrated;

    modifier nonReentrant() {
        if (_state == 1) revert ReentrantCall();
        _state = 1;
        _;
        _state = 0;
    }

    /**
     * @dev Sets the immutable values for {factory}, {quoteToken}, {liquidityA}, {liquidityB}, {sqrtRatioAX96},
     * {sqrtRatioBX96} and {maxSupply}.
     * The ratios must have been calculated correctly accounting for the decimals of each token, the formula is:
     * `sqrt((price0 * 10^decimals1) / (price1 * 10^decimals0)) * 2^96`.
     * The liquidityA and liquidityB parameters are the liquidity of the two xyk pools before and after the graduation
     * price.
     * They will be calculated directly from the amount0 and ratio parameters.
     * The maximum supply of the token is the sum of amount0A and amount0B, each pool will never offer more than its
     * respective amount.
     *
     * Requirements:
     *
     * - `sqrtRatioAX96_` must be strictly less than `sqrtRatioBX96_`
     * - `sqrtRatioAX96_` must be strictly greater than 0
     * - `sqrtRatioBX96_` must be strictly less than `sqrtRatioMaxX96`
     * - The sum of `amount0A` and `amount0B` must fit into 127 bits
     * - The liquidityA and liquidityB must be greater than 0 and fit into 127 bits
     */
    constructor(
        address factory_,
        address quoteToken_,
        uint256 amount0A,
        uint256 amount0B,
        uint256 sqrtRatioAX96_,
        uint256 sqrtRatioBX96_
    ) {
        if (sqrtRatioAX96_ >= sqrtRatioBX96_) revert InvalidRatiosOrder();
        if (sqrtRatioAX96_ == 0 || sqrtRatioBX96_ > sqrtRatioMaxX96) revert InvalidRatios();

        factory = factory_;
        quoteToken = quoteToken_;
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

    /**
     * @dev Initializes the contract with {token0_}, and {fee_}.
     * The fee must be less than or equal to SwapMath.MAX_FEE.
     * The market will mint the maximum supply of token0 and set the reserve0 to the maximum supply.
     *
     * Requirements:
     *
     * - The contract must not have been initialized yet
     * - The tokens must be different
     * - The fee must be less than or equal to SwapMath.MAX_FEE
     */
    function initialize(address token, uint256 fee_) external override returns (bool) {
        if (_sqrtRatioX96 != 0) revert AlreadyInitialized();
        if (token == quoteToken) revert SameTokens();
        if (fee_ > SwapMath.MAX_FEE) revert InvalidFee();

        _token0 = token;

        // forge-lint: disable-next-line(unsafe-typecast)
        _sqrtRatioX96 = uint128(sqrtRatioAX96);
        // forge-lint: disable-next-line(unsafe-typecast)
        _fee = uint64(fee_);

        ITMToken(token).mint(address(this), maxSupply);
        // forge-lint: disable-next-line(unsafe-typecast)
        _reserve0 = uint128(maxSupply);

        return true;
    }

    /**
     * @dev Returns the address of the factory.
     * The factory will receive the swap fees and the `onFeeReceived` function will be called to notify the factory.
     */
    function getFactory() external view override returns (address) {
        return factory;
    }

    /**
     * @dev Returns the liquidity of the two xyk pools.
     */
    function getLiquidities() external view override returns (uint256, uint256) {
        return (liquidityA, liquidityB);
    }

    /**
     * @dev Returns the sqrt ratios of the two xyk pools.
     * The first pool will be from sqrtRatioAX96 to sqrtRatioBX96, and the second pool will be from sqrtRatioBX96 to
     * sqrtRatioMaxX96.
     */
    function getSqrtRatiosBounds() external view override returns (uint256, uint256, uint256) {
        return (sqrtRatioAX96, sqrtRatioBX96, sqrtRatioMaxX96);
    }

    /**
     * @dev Returns the base token of the market.
     */
    function getBaseToken() external view override returns (address) {
        return _token0;
    }

    /**
     * @dev Returns the quote token of the market.
     */
    function getQuoteToken() external view override returns (address) {
        return quoteToken;
    }

    /**
     * @dev Returns the current sqrt ratio of the market.
     */
    function getCurrentSqrtRatio() external view override returns (uint256) {
        return _sqrtRatioX96;
    }

    /**
     * @dev Returns the fee of the market (in millionths).
     */
    function getFee() external view override returns (uint256) {
        return _fee;
    }

    /**
     * @dev Returns the reserves of the market.
     */
    function getReserves() external view override returns (uint256, uint256) {
        return (_reserve0, _reserve1);
    }

    /**
     * @dev Returns whether the market has been migrated.
     */
    function getIsMigrated() external view returns (bool) {
        return _isMigrated;
    }

    /**
     * @dev Returns the amount of token0 and token1 that will be swapped given a delta amount.
     * If zeroForOne is true, the input is token0 and the output is token1.
     * If zeroForOne is false, the input is token1 and the output is token0.
     * If deltaAmount is positive, the function will try to swap as much input as possible, up to abs(deltaAmount).
     * If deltaAmount is negative, the function will try to swap as much input as possible in order to get
     * abs(deltaAmount)
     * of output token.
     * In any case, the function will never exceed the exact input (if deltaAmount is positive) or output (if
     * deltaAmount
     * is negative) amount.
     * The positive amount returned must be sent to the contract prior to calling the swap function.
     * The negative amount returned will be sent to the caller after the swap.
     *
     * Requirements:
     *
     * - The sqrtRatioLimitX96 must be within the limits of the market and in the correct direction.
     */
    function getDeltaAmounts(bool zeroForOne, int256 deltaAmount, uint256 sqrtRatioLimitX96)
        external
        view
        override
        returns (int256 amount0, int256 amount1)
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        (, uint256 amountIn, uint256 amountOut,) =
            _getDeltaAmounts(zeroForOne, deltaAmount, sqrtRatioLimitX96, _sqrtRatioX96, _fee);

        // forge-lint: disable-next-line(unsafe-typecast)
        return zeroForOne ? (int256(amountIn), -int256(amountOut)) : (-int256(amountOut), int256(amountIn));
    }

    /**
     * @dev Swaps `deltaAmount` of token0 for token1 or vice versa.
     * If `zeroForOne` is true, the input is token0 and the output is token1.
     * If `zeroForOne` is false, the input is token1 and the output is token0.
     * The `deltaAmount` defines whether the swap is an exact input or output swap.
     * The `sqrtRatioLimitX96` is the price limit in 32x96 format. If zero for one, the price cannot be less than this
     * value after the swap.
     * If one for zero, the price cannot be greater than this value after the swap
     * The function will emit a `Swap` event with the details of the swap.
     * The fee will be sent to the factory if the token is the quote token (token1). If it is the base token (token0),
     * the fee will be directly swapped to the quote token and sent to the factory as well.
     *
     * Requirements:
     *
     * - The caller must have sent the correct amount of token prior to calling the function
     * - The `deltaAmount` must be different from 0
     * - The `sqrtRatioLimitX96` must be within the limits of the market and in the correct direction
     * - The call must not be reentrant
     */
    function swap(address to, bool zeroForOne, int256 deltaAmount, uint256 sqrtRatioLimitX96)
        external
        override
        nonReentrant
        returns (int256 amount0, int256 amount1)
    {
        if (deltaAmount == 0) revert ZeroDeltaAmount();
        if (_isMigrated) revert MarketMigrated();

        (uint256 nextSqrtRatioX96, uint256 amountIn, uint256 amountOut, uint256 feeAmountIn) =
            _getDeltaAmounts(zeroForOne, deltaAmount, sqrtRatioLimitX96, _sqrtRatioX96, _fee);

        address token1 = quoteToken;
        uint256 reserve0 = _reserve0;
        uint256 reserve1 = _reserve1;

        uint256 feeAmount1;
        unchecked {
            if (zeroForOne) {
                // forge-lint: disable-next-line(unsafe-typecast)
                amount0 = int256(amountIn);
                // forge-lint: disable-next-line(unsafe-typecast)
                amount1 = -int256(amountOut);

                reserve0 = Math.addDelta128(reserve0, amount0);
                reserve1 = Math.addDelta128(reserve1, amount1);

                if (reserve0 > IERC20(_token0).balanceOf(address(this))) revert InsufficientBalance0();
                // forge-lint: disable-next-line(unsafe-typecast)
                IERC20(token1).safeTransfer(to, uint256(-amount1));

                // Swap fee0 to fee1
                (nextSqrtRatioX96,, feeAmount1,) =
                    // forge-lint: disable-next-line(unsafe-typecast)
                    _getDeltaAmounts(zeroForOne, int256(feeAmountIn), sqrtRatioAX96, nextSqrtRatioX96, 0);
            } else {
                // forge-lint: disable-next-line(unsafe-typecast)
                amount0 = -int256(amountOut);
                // forge-lint: disable-next-line(unsafe-typecast)
                amount1 = int256(amountIn);

                reserve1 = Math.addDelta128(reserve1, amount1);
                reserve0 = Math.addDelta128(reserve0, amount0);

                if (reserve1 > IERC20(token1).balanceOf(address(this))) revert InsufficientBalance1();
                // forge-lint: disable-next-line(unsafe-typecast)
                IERC20(_token0).safeTransfer(to, uint256(-amount0));

                feeAmount1 = feeAmountIn;
            }

            emit Swap(msg.sender, to, amount0, amount1, feeAmountIn, feeAmount1, nextSqrtRatioX96);

            if (feeAmount1 > 0) {
                // forge-lint: disable-next-line(unsafe-typecast)
                reserve1 = Math.addDelta128(reserve1, -int256(feeAmount1));

                IERC20(token1).safeTransfer(factory, feeAmount1);
                ITMFactory(factory).onFeeReceived(token1, feeAmount1);
            }
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        _sqrtRatioX96 = uint128(nextSqrtRatioX96);
        // forge-lint: disable-next-line(unsafe-typecast)
        _reserve0 = uint128(reserve0);
        // forge-lint: disable-next-line(unsafe-typecast)
        _reserve1 = uint128(reserve1);
    }

    /**
     * @dev Migrates all tokens in the market to the {recipient}.
     * The function will transfer all the token0 and token1 held by the market to the recipient.
     * The market will be marked as migrated and no further swaps will be possible.
     *
     * Requirements:
     *
     * - The caller must be the factory
     * - The market must not have been migrated yet
     */
    function migrate(address recipient) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (msg.sender != factory) revert OnlyFactory();
        if (_isMigrated) revert MarketMigrated();

        address token0 = _token0;
        address token1 = quoteToken;

        amount0 = IERC20(token0).balanceOf(address(this));
        if (amount0 > 0) {
            IERC20(token0).safeTransfer(recipient, amount0);
        }

        amount1 = IERC20(token1).balanceOf(address(this));
        if (amount1 > 0) {
            IERC20(token1).safeTransfer(recipient, amount1);
        }

        _isMigrated = true;
    }

    /**
     * @dev Returns the amounts of token0 and token1 that will be swapped given a delta amount.
     * The function will iterate over the two xyk pools to calculate the amounts if the swap exceeds the liquidity of
     * the current pool.
     *
     * Requirements:
     *
     * - The sqrtRatioLimitX96 must be within the limits of the market and in the correct direction
     */
    function _getDeltaAmounts(
        bool zeroForOne,
        int256 deltaAmount,
        uint256 sqrtRatioLimitX96,
        uint256 currentSqrtRatioX96,
        uint256 fee
    ) internal view returns (uint256 nextSqrtRatioX96, uint256 amountIn, uint256 amountOut, uint256 feeAmountIn) {
        if (zeroForOne
                ? sqrtRatioLimitX96 >= currentSqrtRatioX96 || sqrtRatioLimitX96 < sqrtRatioAX96
                : sqrtRatioLimitX96 <= currentSqrtRatioX96 || sqrtRatioLimitX96 > sqrtRatioMaxX96) revert InvalidSqrtRatioLimit();
        if (Math.safeInt128(deltaAmount) == 0) return (currentSqrtRatioX96, 0, 0, 0);

        // First pool
        {
            uint256 liquidity = currentSqrtRatioX96 >= sqrtRatioBX96 ? liquidityB : liquidityA;
            uint256 targetRatioX96 = (zeroForOne
                        ? currentSqrtRatioX96 >= sqrtRatioBX96 && sqrtRatioLimitX96 < sqrtRatioBX96
                        : currentSqrtRatioX96 < sqrtRatioBX96 && sqrtRatioLimitX96 >= sqrtRatioBX96)
                ? sqrtRatioBX96
                : sqrtRatioLimitX96;

            (nextSqrtRatioX96, amountIn, amountOut, feeAmountIn) =
                SwapMath.getDeltaAmounts(currentSqrtRatioX96, targetRatioX96, liquidity, deltaAmount, fee);
        }

        deltaAmount = deltaAmount > 0
            ? deltaAmount - Math.toInt256(amountIn + feeAmountIn)
            : deltaAmount + Math.toInt256(amountOut);

        // Second pool
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

        // If `amountIn + feeAmountIn < 2**127`, then `feeAmountIn < 2**127`. All results can be casted to `int128`,
        // `uint128` or above.
        return (nextSqrtRatioX96, Math.safeUint127(amountIn + feeAmountIn), Math.safeUint127(amountOut), feeAmountIn);
    }
}
