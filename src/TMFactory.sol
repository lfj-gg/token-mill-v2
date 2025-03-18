// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Math} from "./libraries/Math.sol";
import {SwapMath} from "./libraries/SwapMath.sol";
import {ITMFactory} from "./interfaces/ITMFactory.sol";
import {ITMToken} from "./interfaces/ITMToken.sol";
import {ITMMarket} from "./interfaces/ITMMarket.sol";

/**
 * @title TokenMill Factory contract
 * @dev Factory contract for creating markets and tokens.
 * The admin of this contract can update the default fee, quote tokens, market and token implementations that
 * will be used by newly created markets and tokens. The admin can also update the protocol fee share that will be
 * collected on each swap for all markets created by this factory.
 * The admin can also grant and revoke the roles to collect fees on behalf of the protocol and
 * the King Of The Mill (KOTM).
 * On each swap, the swap fee is split into two parts: the protocol fee and the market fee that goes to the
 * fee recipient of the market. Those fees can then be called by the fee recipient (for creator fees) or by the operator
 * that has the KOTM_COLLECTOR_ROLE for the KOTM fees and the PROTOCOL_FEE_COLLECTOR_ROLE for the protocol fees.
 * The factory also keeps track of the markets and tokens created by each creator.
 * This contract can either be used as an immutable contract or as the implementation of an upgradeable proxy.
 */
contract TMFactory is AccessControlUpgradeable, ITMFactory {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    bytes32 public constant override KOTM_COLLECTOR_ROLE = keccak256("KOTM_COLLECTOR_ROLE");

    address public constant override PROTOCOL_FEE_RECIPIENT = address(0);
    bytes32 public constant override PROTOCOL_FEE_COLLECTOR_ROLE = keccak256("PROTOCOL_FEE_COLLECTOR_ROLE");

    address private _marketImplementation;
    address private _tokenImplementation;

    uint88 private _minUpdateTime;
    uint64 private _protocolFeeShare;
    uint64 private _defaultFee;

    mapping(address token => mapping(address account => uint256 unclaimedFees)) private _unclaimedFees;
    mapping(address market => MarketDetails) private _details;
    mapping(address token => address) private _marketOf;
    address[] private _tokens;
    address[] private _markets;

    EnumerableSet.AddressSet private _quoteTokens;
    mapping(address creator => EnumerableSet.AddressSet) private _marketsByCreator;

    /**
     * @dev Sets the initial values for {minUpdateTime}, {protocolFeeShare}, {defaultFee}, {marketImplementation},
     * {tokenImplementation} and {admin}.
     */
    constructor(
        uint256 minUpdateTime,
        uint256 protocolFeeShare,
        uint256 defaultFee,
        address marketImplementation,
        address tokenImplementation,
        address admin
    ) {
        initialize(minUpdateTime, protocolFeeShare, defaultFee, marketImplementation, tokenImplementation, admin);
    }

    /**
     * @dev Initializes the contract with {minUpdateTime}, {protocolFeeShare}, {defaultFee}, {marketImplementation},
     * {tokenImplementation} and {admin}.
     */
    function initialize(
        uint256 minUpdateTime,
        uint256 protocolFeeShare,
        uint256 defaultFee,
        address marketImplementation,
        address tokenImplementation,
        address admin
    ) public override initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        _setMinUpdateTime(minUpdateTime);
        _setProtocolFeeShare(protocolFeeShare);
        _setDefaultFee(defaultFee);

        _setMarketImplementation(marketImplementation);
        _setTokenImplementation(tokenImplementation);
    }

    /**
     * @dev Returns the address of the King Of The Mill (KOTM) fee recipient.
     */
    function KOTM_FEE_RECIPIENT() public view override returns (address) {
        return address(this);
    }

    /**
     * @dev Returns the market implementation address.
     */
    function getMarketImplementation() external view override returns (address) {
        return _marketImplementation;
    }

    /**
     * @dev Returns the token implementation address.
     */
    function getTokenImplementation() external view override returns (address) {
        return _tokenImplementation;
    }

    /**
     * @dev Returns the minimum time between fee recipient updates.
     */
    function getMinUpdateTime() external view override returns (uint256) {
        return _minUpdateTime;
    }

    /**
     * @dev Returns the protocol fee share.
     */
    function getProtocolFeeShare() external view override returns (uint256) {
        return _protocolFeeShare;
    }

    /**
     * @dev Returns the default fee.
     */
    function getDefaultFee() external view override returns (uint256) {
        return _defaultFee;
    }

    /**
     * @dev Returns the unclaimed fees of {token} for {account}.
     */
    function getUnclaimedFees(address token, address account) external view override returns (uint256) {
        return _unclaimedFees[token][account];
    }

    /**
     * @dev Returns wether the market is initialized, the fee recipient and the creator address of the {market}.
     */
    function getMarketDetails(address market) external view override returns (MarketDetails memory) {
        return _details[market];
    }

    /**
     * @dev Returns the number of tokens created.
     */
    function getTokensLength() external view override returns (uint256) {
        return _tokens.length;
    }

    /**
     * @dev Returns the token address at {index}.
     */
    function getTokenAt(uint256 index) external view override returns (address) {
        return _tokens[index];
    }

    /**
     * @dev Returns the number of markets created.
     */
    function getMarketsLength() external view override returns (uint256) {
        return _markets.length;
    }

    /**
     * @dev Returns the market address at {index}.
     */
    function getMarketAt(uint256 index) external view override returns (address) {
        return _markets[index];
    }

    /**
     * @dev Returns the market address of the {token}.
     */
    function getMarketOf(address token) external view override returns (address) {
        return _marketOf[token];
    }

    /**
     * @dev Returns the number of quote tokens supported.
     */
    function getQuoteTokensLength() external view override returns (uint256) {
        return _quoteTokens.length();
    }

    /**
     * @dev Returns the quote token address at {index}.
     */
    function getQuoteTokenAt(uint256 index) external view override returns (address) {
        return _quoteTokens.at(index);
    }

    /**
     * @dev Returns the number of markets owned by the {creator}.
     * If the current creator transfers the ownership of a market, it will be removed from this list.
     */
    function getMarketByCreatorLength(address creator) external view override returns (uint256) {
        return _marketsByCreator[creator].length();
    }

    /**
     * @dev Returns the market address at {index} owned by the {creator}.
     */
    function getMarketByCreatorAt(address creator, uint256 index) external view override returns (address) {
        return _marketsByCreator[creator].at(index);
    }

    /**
     * @dev Creates a new market with {name}, {symbol} and {quoteToken}.
     * The market will be created with the default fee and the creator will be set to the caller of this function.
     * By default, the fee recipient will be set to the KOTM fee recipient. To opt-out of the KOTM feature, the creator
     * can update the fee recipient to another address.
     * Emits a {MarketCreated} event with the creator, quote token, market, token, name and symbol.
     * Emits a {MarketDetailsUpdated} event with the market, creator and fee recipient.
     *
     * Requirements:
     *
     * - The {quoteToken} must be supported by the factory.
     */
    function createMarket(string calldata name, string calldata symbol, address quoteToken)
        external
        override
        returns (address token, address market)
    {
        if (!_quoteTokens.contains(quoteToken)) revert QuoteTokenNotSupported();

        (token, market) = _createMarket(name, symbol, quoteToken);

        _tokens.push(token);
        _markets.push(market);

        _details[market] = MarketDetails({
            initialized: true,
            lastFeeRecipientUpdate: uint88(block.timestamp),
            creator: msg.sender,
            feeRecipient: KOTM_FEE_RECIPIENT()
        });
        _marketsByCreator[msg.sender].add(market);

        emit MarketCreated(msg.sender, quoteToken, market, token, name, symbol);
        emit MarketDetailsUpdated(market, msg.sender, KOTM_FEE_RECIPIENT());
    }

    /**
     * @dev Collects the {amount} of {token} from the {account} and sends it to the {recipient}.
     * The {account} can only collect its own fees, unless the {account} is the KOTM fee recipient or
     * the protocol fee recipient. In that case, any operator with the KOTM_COLLECTOR_ROLE or the
     * PROTOCOL_FEE_COLLECTOR_ROLE can collect the fees on behalf of it respectively.
     * Emits a {FeesCollected} event with the collector, account, token and amount.
     *
     * Requirements:
     *
     * - The {account} must be the caller or an operator with the correct collector role.
     * - The {amount} must be less than or equal to the unclaimed fees of the {account}.
     */
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

    /**
     * @dev Updates the {creator} and {feeRecipient} of the {market}.
     * Emits a {MarketDetailsUpdated} event with the market, creator and fee recipient.
     *
     * Requirements:
     *
     * - The {market} must be initialized.
     * - The caller must be the current creator of the {market}.
     */
    function updateMarketDetails(address market, address creator, address feeRecipient)
        external
        override
        returns (bool)
    {
        MarketDetails storage details = _details[market];

        if (!details.initialized) revert InvalidMarket();
        if (details.creator != msg.sender) revert Unauthorized();

        details.creator = creator;

        if (feeRecipient != details.feeRecipient) {
            uint256 nextUpdateTime = uint256(details.lastFeeRecipientUpdate) + _minUpdateTime;
            if (nextUpdateTime > block.timestamp) revert MinUpdateTimeNotPassed(nextUpdateTime);

            details.lastFeeRecipientUpdate = uint88(block.timestamp);
            details.feeRecipient = feeRecipient;
        }

        _marketsByCreator[msg.sender].remove(market);
        _marketsByCreator[creator].add(market);

        emit MarketDetailsUpdated(market, creator, feeRecipient);
        return true;
    }

    /**
     * @dev Updates the minimum time between fee recipient updates.
     * Emits a {MinUpdateTimeSet} event with the sender and the {minUpdateTime}.
     *
     * Requirements:
     *
     * - The caller must have the DEFAULT_ADMIN_ROLE.
     */
    function setMinUpdateTime(uint256 minUpdateTime) external override onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        _setMinUpdateTime(minUpdateTime);
        return true;
    }

    /**
     * @dev Updates the {protocolFeeShare} percent that will be collected on each swap for all markets created by this factory.
     * Emits a {ProtocolFeeShareSet} event with the sender and the {protocolFeeShare}.
     *
     * Requirements:
     *
     * - The {protocolFeeShare} must be less than or equal to the maximum fee.
     */
    function setProtocolFeeShare(uint256 protocolFeeShare)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bool)
    {
        _setProtocolFeeShare(protocolFeeShare);
        return true;
    }

    /**
     * @dev Updates the {defaultFee} that will be used by newly created markets.
     * Emits a {DefaultFeeSet} event with the sender and the {defaultFee}.
     *
     * Requirements:
     *
     * - The {defaultFee} must be less than or equal to the maximum fee.
     * - The caller must have the DEFAULT_ADMIN_ROLE.
     */
    function setDefaultFee(uint256 defaultFee) external override onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        _setDefaultFee(defaultFee);
        return true;
    }

    /**
     * @dev Adds (if {supported} is true) or removes (if {supported} is false) the {quoteToken} from the supported quote tokens.
     * Emits a {QuoteTokenSet} event with the sender, the {quoteToken} and wether it is supported or not.
     *
     * Requirements:
     *
     * - The {quoteToken} must not be already supported if {supported} is true
     * - The {quoteToken} must be supported if {supported} is false
     * - The caller must have the DEFAULT_ADMIN_ROLE.
     */
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

    /**
     * @dev Updates the {marketImplementation} that will be used by newly created markets.
     * Emits a {MarketImplementationSet} event with the sender and the {marketImplementation}.
     *
     * Requirements:
     *
     * - The caller must have the DEFAULT_ADMIN_ROLE.
     */
    function setMarketImplementation(address marketImplementation)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bool)
    {
        _setMarketImplementation(marketImplementation);
        return true;
    }

    /**
     * @dev Updates the {tokenImplementation} that will be used by newly created tokens.
     * Emits a {TokenImplementationSet} event with the sender and the {tokenImplementation}.
     *
     * Requirements:
     *
     * - The caller must have the DEFAULT_ADMIN_ROLE.
     */
    function setTokenImplementation(address tokenImplementation)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bool)
    {
        _setTokenImplementation(tokenImplementation);
        return true;
    }

    /**
     * @dev Receives the {amount} of {token} from a market and splits the fee between the protocol and the fee recipient.
     * The protocol fee is calculated based on the {protocolFeeShare} and the rest is sent to the fee recipient.
     * Emits a {FeeReceived} event with the market, token, fee recipient, fee and protocol fee.
     *
     * Requirements:
     *
     * - The caller must be a valid market (ie, the market must have been created by this factory).
     */
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

    /**
     * @dev Helper function to create a new market with {name}, {symbol} and {quoteToken}.
     * The market will be created with the default fee.
     *
     * Requirements:
     *
     * - The market implementation must be set.
     * - The token implementation must be set.
     */
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

    /**
     * @dev Helper function to set the {minUpdateTime}.
     * Emits a {MinUpdateTimeSet} event with the sender and the {minUpdateTime}.
     */
    function _setMinUpdateTime(uint256 minUpdateTime) internal {
        if (minUpdateTime >= 2 ** 88) revert InvalidMinUpdateTime();

        _minUpdateTime = uint88(minUpdateTime);

        emit MinUpdateTimeSet(msg.sender, minUpdateTime);
    }

    /**
     * @dev Helper function to set the {protocolFeeShare}.
     * Emits a {ProtocolFeeShareSet} event with the sender and the {protocolFeeShare}.
     *
     * Requirements:
     *
     * - The {protocolFeeShare} must be less than or equal to the maximum fee.
     */
    function _setProtocolFeeShare(uint256 protocolFeeShare) internal {
        if (protocolFeeShare > SwapMath.MAX_FEE) revert InvalidFee();

        _protocolFeeShare = uint64(protocolFeeShare);

        emit ProtocolFeeShareSet(msg.sender, protocolFeeShare);
    }

    /**
     * @dev Helper function to set the {defaultFee}.
     * Emits a {DefaultFeeSet} event with the sender and the {defaultFee}.
     *
     * Requirements:
     *
     * - The {defaultFee} must be less than or equal to the maximum fee.
     */
    function _setDefaultFee(uint256 defaultFee) internal {
        if (defaultFee > SwapMath.MAX_FEE) revert InvalidFee();

        _defaultFee = uint64(defaultFee);

        emit DefaultFeeSet(msg.sender, defaultFee);
    }

    /**
     * @dev Helper function to set the {marketImplementation}.
     * Emits a {MarketImplementationSet} event with the sender and the {marketImplementation}.
     */
    function _setMarketImplementation(address marketImplementation) internal {
        _marketImplementation = marketImplementation;

        emit MarketImplementationSet(msg.sender, marketImplementation);
    }

    /**
     * @dev Helper function to set the {tokenImplementation}.
     * Emits a {TokenImplementationSet} event with the sender and the {tokenImplementation}.
     */
    function _setTokenImplementation(address tokenImplementation) internal {
        _tokenImplementation = tokenImplementation;

        emit TokenImplementationSet(msg.sender, tokenImplementation);
    }
}
