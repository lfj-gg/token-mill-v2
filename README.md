# Token Mill V2

EVM token launcher from LFJ

## Bonding Curve

Token Mill V2 bonding curve is the combination of 2 Uni-V3 style pricing curves, called pool A and B in the code. Pool A will be in effect until 80% of the total supply is minted, and pool B for the rest, mimicking a graduation event. Those pools use two different virtual liquidity amounts, that will change the pricing dynamic when switching from one to the other.

![Price Curve](https://github.com/user-attachments/assets/f127c0b8-acf4-43c7-aed3-c9732db90fe2)

Fees can be different on the two sides of the curve.

## King of the Mill

Token Mill V2 redirects swap fees to a fee pool, that will be used for an aidrop program called King of the Mill (KotM). Every period, fees accumulated will be airdropped to a randomly selected set of holders of the winning token (selected based on market cap and volume).


## Contracts

### Factory

Creates token and manages protocol and KotM fees.

Token creation allows for an initial buy based on `amountQuoteIn`:
```solidity
function createMarket(
        string calldata name,
        string calldata symbol,
        address quoteToken,
        address feeRecipient,
        uint256 amountQuoteIn,
        uint256 minAmountBaseOut
    ) external payable returns (address token, address market, uint256 amountBaseOut)
```

To get the market address from a token:
```solidity
function getMarketOf(address token) external view returns (address)
```

### Market

Get quotes using `getDeltaAmounts`:
```solidity
function getDeltaAmounts(bool zeroForOne, int256 deltaAmount, uint256 sqrtRatioLimitX96)
        external
        view
        returns (int256 amount0, int256 amount1)
```

Buy and sell tokens using `swap`:
```solidity
function swap(address to, bool zeroForOne, int256 deltaAmount, uint256 sqrtRatioLimitX96)
        external
        returns (int256 amount0, int256 amount1)
```

Swaps rely on the `zeroForOne` and `deltaAmount` parameters.
- If zeroForOne is true, the input is token0 and the output is token1 ("**sell**")
- If zeroForOne is false, the input is token1 and the output is token0 ("**buy**")
- If deltaAmount is positive, it's an amount **in**
- If deltaAmount is negative, it's an amount **out**
- The positive amount returned must be sent to the contract prior to calling the swap function
- The negative amount returned will be sent to the recipient after the swap

If not used, `sqrtRatioLimitX96` can be set to `2^127 - 1` (max price) when buying and `market.getSqrtRatiosBounds().0` (min price, also called sqrtRatioAX96) when selling.

The swap function is meant to be used by a router that will properly handle token transfers and check slippage.

### Token

Regular ERC20 token with its supply minted on market creation.
