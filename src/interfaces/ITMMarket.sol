// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITMMarket {
    error InvalidRatiosOrder();
    error InvalidRatios();
    error AmountsOverflow();
    error LiquiditiesZero();
    error AlreadyInitialized();
    error SameTokens();
    error InvalidFee();
    error ZeroDeltaAmount();
    error ReentrantCall();
    error InsufficientBalance0();
    error InsufficientBalance1();
    error InvalidSqrtRatioLimit();
    error OnlyFactory();
    error MarketMigrated();

    event Swap(
        address indexed sender,
        address indexed to,
        int256 amount0,
        int256 amount1,
        uint256 feeAmountIn,
        uint256 feeAmount1,
        uint256 sqrtRatioX96
    );

    function initialize(address token0, uint256 feeA, uint256 feeB) external returns (bool);

    function getFactory() external view returns (address);

    function getLiquidities() external view returns (uint256 liquidityA, uint256 liquidityB);

    function getSqrtRatiosBounds()
        external
        view
        returns (uint256 sqrtRatioAX96, uint256 sqrtRatioBX96, uint256 sqrtRatioMaxX96);

    function getBaseToken() external view returns (address);

    function getQuoteToken() external view returns (address);

    function getCurrentSqrtRatio() external view returns (uint256 sqrtRatioX96);

    function getFees() external view returns (uint256 feeA, uint256 feeB);

    function getReserves() external view returns (uint256 reserve0, uint256 reserve1);

    function getDeltaAmounts(bool zeroForOne, int256 deltaAmount, uint256 sqrtRatioLimitX96)
        external
        returns (int256 amount0, int256 amount1);

    function swap(address to, bool zeroForOne, int256 deltaAmount, uint256 sqrtRatioLimitX96)
        external
        returns (int256 amount0, int256 amount1);

    function migrate(address recipient) external returns (uint256 amount0, uint256 amount1);
}
