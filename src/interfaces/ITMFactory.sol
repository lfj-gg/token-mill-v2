// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITMFactory {
    error Unauthorized();
    error InsufficientFunds();
    error InvalidMarket();
    error InvalidFee();
    error QuoteTokenAlreadySupported();
    error QuoteTokenNotSupported();
    error MarketImplementationNotSet();
    error TokenImplementationNotSet();

    event MarketCreated(
        address indexed creator, address indexed quoteToken, address market, address token, string name, string symbol
    );
    event FeesCollected(address indexed sender, address indexed account, address indexed token, uint256 amount);
    event MarketDetailsUpdated(address indexed market, address indexed creator, address indexed feeRecipient);
    event ProtocolFeeShareSet(address indexed sender, uint256 protocolFeeShare);
    event DefaultFeeSet(address indexed sender, uint256 defaultFee);
    event QuoteTokenSet(address indexed sender, address quoteToken, bool supported);
    event MarketImplementationSet(address indexed sender, address marketImplementation);
    event TokenImplementationSet(address indexed sender, address tokenImplementation);
    event FeeReceived(
        address indexed market, address indexed token, address indexed feeRecipient, uint256 fee, uint256 protocolFee
    );

    struct MarketDetails {
        bool initialized;
        address feeRecipient;
        address creator;
    }

    function initialize(
        uint256 protocolFeeShare,
        uint256 defaultFee,
        address marketImplementation,
        address tokenImplementation,
        address admin
    ) external;

    function KOTM_FEE_RECIPIENT() external view returns (address);

    function KOTM_COLLECTOR_ROLE() external view returns (bytes32);

    function PROTOCOL_FEE_RECIPIENT() external view returns (address);

    function PROTOCOL_FEE_COLLECTOR_ROLE() external view returns (bytes32);

    function getMarketImplementation() external view returns (address);

    function getTokenImplementation() external view returns (address);

    function getProtocolFeeShare() external view returns (uint256);

    function getDefaultFee() external view returns (uint256);

    function getUnclaimedFees(address token, address account) external view returns (uint256);

    function getMarketDetails(address market) external view returns (MarketDetails memory);

    function getTokensLength() external view returns (uint256);

    function getTokenAt(uint256 index) external view returns (address);

    function getMarketsLength() external view returns (uint256);

    function getMarketAt(uint256 index) external view returns (address);

    function getMarketOf(address token) external view returns (address);

    function getQuoteTokensLength() external view returns (uint256);

    function getQuoteTokenAt(uint256 index) external view returns (address);

    function getMarketByCreatorLength(address creator) external view returns (uint256);

    function getMarketByCreatorAt(address creator, uint256 index) external view returns (address);

    function createMarket(string calldata name, string calldata symbol, address quoteToken)
        external
        returns (address token, address market);

    function collect(address token, address account, address recipient, uint256 amount) external returns (bool);

    function updateMarketDetails(address market, address creator, address feeRecipient) external returns (bool);

    function setProtocolFeeShare(uint256 protocolFeeShare) external returns (bool);

    function setDefaultFee(uint256 defaultFee) external returns (bool);

    function setQuoteToken(address quoteToken, bool supported) external returns (bool);

    function setMarketImplementation(address marketImplementation) external returns (bool);

    function setTokenImplementation(address tokenImplementation) external returns (bool);

    function onFeeReceived(address token, uint256 amount) external returns (bool);
}
