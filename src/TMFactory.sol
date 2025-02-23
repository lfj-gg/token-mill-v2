// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Math} from "./libraries/Math.sol";
import {SwapMath} from "./libraries/SwapMath.sol";
import {ITMFactory} from "./interfaces/ITMFactory.sol";
import {ITMToken} from "./interfaces/ITMToken.sol";
import {ITMMarket} from "./interfaces/ITMMarket.sol";

contract TMFactory is AccessControlUpgradeable, ITMFactory {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    bytes32 public constant override KOTM_COLLECTOR_ROLE = keccak256("KOTM_COLLECTOR_ROLE");

    address public constant override PROTOCOL_FEE_RECIPIENT = address(0);
    bytes32 public constant override PROTOCOL_FEE_COLLECTOR_ROLE = keccak256("PROTOCOL_FEE_COLLECTOR_ROLE");

    address private _marketImplementation;
    address private _tokenImplementation;

    uint64 private _protocolFeeShare;
    uint64 private _defaultFee;

    mapping(address token => mapping(address account => uint256 unclaimedFees)) private _unclaimedFees;
    mapping(address market => MarketDetails) private _details;
    mapping(address token => address) private _marketOf;
    address[] private _tokens;
    address[] private _markets;

    EnumerableSet.AddressSet private _quoteTokens;
    mapping(address creator => EnumerableSet.AddressSet) private _marketsByCreator;

    constructor(
        uint256 protocolFeeShare,
        uint256 defaultFee,
        address marketImplementation,
        address tokenImplementation,
        address admin
    ) {
        initialize(protocolFeeShare, defaultFee, marketImplementation, tokenImplementation, admin);
    }

    function initialize(
        uint256 protocolFeeShare,
        uint256 defaultFee,
        address marketImplementation,
        address tokenImplementation,
        address admin
    ) public override initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        _setProtocolFeeShare(protocolFeeShare);
        _setDefaultFee(defaultFee);

        _setMarketImplementation(marketImplementation);
        _setTokenImplementation(tokenImplementation);
    }

    function KOTM_FEE_RECIPIENT() public view override returns (address) {
        return address(this);
    }

    function getMarketImplementation() external view override returns (address) {
        return _marketImplementation;
    }

    function getTokenImplementation() external view override returns (address) {
        return _tokenImplementation;
    }

    function getProtocolFeeShare() external view override returns (uint256) {
        return _protocolFeeShare;
    }

    function getDefaultFee() external view override returns (uint256) {
        return _defaultFee;
    }

    function getUnclaimedFees(address token, address account) external view override returns (uint256) {
        return _unclaimedFees[token][account];
    }

    function getMarketDetails(address market) external view override returns (MarketDetails memory) {
        return _details[market];
    }

    function getTokensLength() external view override returns (uint256) {
        return _tokens.length;
    }

    function getTokenAt(uint256 index) external view override returns (address) {
        return _tokens[index];
    }

    function getMarketsLength() external view override returns (uint256) {
        return _markets.length;
    }

    function getMarketAt(uint256 index) external view override returns (address) {
        return _markets[index];
    }

    function getMarketOf(address token) external view override returns (address) {
        return _marketOf[token];
    }

    function getQuoteTokensLength() external view override returns (uint256) {
        return _quoteTokens.length();
    }

    function getQuoteTokenAt(uint256 index) external view override returns (address) {
        return _quoteTokens.at(index);
    }

    function getMarketByCreatorLength(address creator) external view override returns (uint256) {
        return _marketsByCreator[creator].length();
    }

    function getMarketByCreatorAt(address creator, uint256 index) external view override returns (address) {
        return _marketsByCreator[creator].at(index);
    }

    function createMarket(string calldata name, string calldata symbol, address quoteToken)
        external
        override
        returns (address token, address market)
    {
        if (!_quoteTokens.contains(quoteToken)) revert QuoteTokenNotSupported();

        (token, market) = _createMarket(name, symbol, quoteToken);

        _tokens.push(token);
        _markets.push(market);

        _details[market] = MarketDetails({initialized: true, creator: msg.sender, feeRecipient: KOTM_FEE_RECIPIENT()});
        _marketsByCreator[msg.sender].add(market);

        emit MarketCreated(msg.sender, quoteToken, market, token, name, symbol);
        emit MarketDetailsUpdated(market, msg.sender, KOTM_FEE_RECIPIENT());
    }

    function collect(address token, address account, address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        if (
            account != msg.sender && (account != KOTM_FEE_RECIPIENT() || !hasRole(KOTM_COLLECTOR_ROLE, msg.sender))
                && (account != PROTOCOL_FEE_RECIPIENT || !hasRole(PROTOCOL_FEE_COLLECTOR_ROLE, msg.sender))
        ) {
            revert Unauthorized();
        }

        if (amount > 0) {
            uint256 unclaimed = _unclaimedFees[token][account];
            if (amount > unclaimed) revert InsufficientFunds();

            unchecked {
                _unclaimedFees[token][account] = unclaimed - amount;
            }

            IERC20(token).safeTransfer(recipient, amount);

            emit FeesCollected(msg.sender, account, token, amount);
        }

        return true;
    }

    function updateMarketDetails(address market, address creator, address feeRecipient)
        external
        override
        returns (bool)
    {
        MarketDetails storage details = _details[market];

        if (!details.initialized) revert InvalidMarket();
        if (details.creator != msg.sender) revert Unauthorized();

        details.creator = creator;
        details.feeRecipient = feeRecipient;

        _marketsByCreator[msg.sender].remove(market);
        _marketsByCreator[creator].add(market);

        emit MarketDetailsUpdated(market, creator, feeRecipient);
        return true;
    }

    function setProtocolFeeShare(uint256 protocolFeeShare)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bool)
    {
        _setProtocolFeeShare(protocolFeeShare);
        return true;
    }

    function setDefaultFee(uint256 defaultFee) external override onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        _setDefaultFee(defaultFee);
        return true;
    }

    function setQuoteToken(address quoteToken, bool supported)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bool)
    {
        if (supported) {
            if (!_quoteTokens.add(quoteToken)) revert QuoteTokenAlreadySupported();
        } else {
            if (!_quoteTokens.remove(quoteToken)) revert QuoteTokenNotSupported();
        }
        emit QuoteTokenSet(msg.sender, quoteToken, supported);
        return true;
    }

    function setMarketImplementation(address marketImplementation)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bool)
    {
        _setMarketImplementation(marketImplementation);
        return true;
    }

    function setTokenImplementation(address tokenImplementation)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bool)
    {
        _setTokenImplementation(tokenImplementation);
        return true;
    }

    function onFeeReceived(address token, uint256 amount) external override returns (bool) {
        MarketDetails storage details = _details[msg.sender];
        if (!details.initialized) revert InvalidMarket();

        uint256 protocolFee = Math.divUp((amount * _protocolFeeShare), SwapMath.MAX_FEE);
        uint256 fee = amount - protocolFee;

        address feeRecipient = details.feeRecipient;

        _unclaimedFees[token][PROTOCOL_FEE_RECIPIENT] += protocolFee;
        _unclaimedFees[token][feeRecipient] += fee;

        emit FeeReceived(msg.sender, token, feeRecipient, fee, protocolFee);

        return true;
    }

    function _createMarket(string calldata name, string calldata symbol, address quoteToken)
        internal
        returns (address token, address market)
    {
        address marketImplementation = _marketImplementation;
        address tokenImplementation = _tokenImplementation;

        if (marketImplementation == address(0)) revert MarketImplementationNotSet();
        if (tokenImplementation == address(0)) revert TokenImplementationNotSet();

        token = Clones.clone(_tokenImplementation);
        market = Clones.cloneDeterministic(marketImplementation, bytes32(uint256(uint160(token))));

        _marketOf[token] = market;

        ITMToken(token).initialize(name, symbol);
        ITMMarket(market).initialize(token, quoteToken, _defaultFee);
    }

    function _setProtocolFeeShare(uint256 protocolFeeShare) internal {
        if (protocolFeeShare > SwapMath.MAX_FEE) revert InvalidFee();

        _protocolFeeShare = uint64(protocolFeeShare);

        emit ProtocolFeeShareSet(msg.sender, protocolFeeShare);
    }

    function _setDefaultFee(uint256 defaultFee) internal {
        if (defaultFee > SwapMath.MAX_FEE) revert InvalidFee();

        _defaultFee = uint64(defaultFee);

        emit DefaultFeeSet(msg.sender, defaultFee);
    }

    function _setMarketImplementation(address marketImplementation) internal {
        _marketImplementation = marketImplementation;

        emit MarketImplementationSet(msg.sender, marketImplementation);
    }

    function _setTokenImplementation(address tokenImplementation) internal {
        _tokenImplementation = tokenImplementation;

        emit TokenImplementationSet(msg.sender, tokenImplementation);
    }
}
