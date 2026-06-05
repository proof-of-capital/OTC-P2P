// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OTCTypes} from "./types/OTCTypes.sol";
import {OTCConstants} from "./constants/OTCConstants.sol";
import {IOTCClientVault} from "./interfaces/IOTCClientVault.sol";
import {IOTCClientVaultErrors} from "./interfaces/IOTCClientVaultErrors.sol";
import {IOTCClientVaultEvents} from "./interfaces/IOTCClientVaultEvents.sol";
import {IOTCOperatorFactory} from "./interfaces/IOTCOperatorFactory.sol";

/// @title OTCClientVault
/// @notice Holds a client's assets and executes multi-party OTC trades through a proposal-and-approval flow.
contract OTCClientVault is
    Ownable,
    Initializable,
    IOTCClientVault,
    IOTCClientVaultErrors,
    IOTCClientVaultEvents,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    /// @notice Operator factory that created this vault.
    address public override factory;

    /// @notice Auto-incrementing id assigned to the next proposal.
    uint256 public nextProposalId;

    /// @notice Timestamp after which `token` may be withdrawn or used in open P2P swaps.
    mapping(address token => uint256 lockUntil) public tokenLockUntil;
    /// @notice Lock proposals keyed by proposal id.
    mapping(uint256 proposalId => OTCTypes.LockProposal) public lockProposals;
    /// @inheritdoc IOTCClientVault
    OTCTypes.SwapAccessLevel public override swapAccessLevel;

    mapping(uint256 proposalId => OTCTypes.DeliveryProposal) private _deliveryProposals;
    mapping(uint256 proposalId => OTCTypes.SwapProposal) private _swapProposals;

    modifier onlyFactoryAdmin() {
        _onlyFactoryAdmin();
        _;
    }

    modifier onlyAuthorized() {
        _onlyAuthorized();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() Ownable(address(this)) {
        _disableInitializers();
    }

    /// @inheritdoc IOTCClientVault
    function initialize(address factory_, address client_, OTCTypes.DefaultLockConfig[] memory defaultLockConfigs_)
        external
        override
        initializer
    {
        require(factory_ != address(0), InvalidAddress());
        require(client_ != address(0), InvalidAddress());

        _transferOwnership(client_);
        factory = factory_;
        nextProposalId = 1;
        swapAccessLevel = OTCTypes.SwapAccessLevel.DeliveryOnly;
        _initializeDefaultLocks(defaultLockConfigs_);
    }

    /// @inheritdoc IOTCClientVault
    receive() external payable override {}

    /// @inheritdoc IOTCClientVault
    /// @dev This path is optional and exists to reduce user mistakes with vault addresses.
    /// Tokens can be funded directly by transferring ERC20 to the vault address.
    function deposit(address token, uint256 amount) external override onlyOwner nonReentrant {
        require(token != address(0), InvalidAddress());
        require(amount > 0, InvalidAmount());

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, token, amount);
    }

    /// @inheritdoc IOTCClientVault
    function withdraw(address token, uint256 amount, address to) external override onlyOwner nonReentrant {
        require(token != address(0), InvalidAddress());
        require(to != address(0), InvalidAddress());
        _requireUnlocked(token);

        if (amount == type(uint256).max) {
            amount = IERC20(token).balanceOf(address(this));
        } else {
            require(amount > 0, InvalidAmount());
        }

        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(to, token, amount);
    }

    // ── Lock proposals ──────────────────────────────────────────────────────────

    /// @inheritdoc IOTCClientVault
    function proposeLock(address token, uint256 newLockUntil, uint256 deadline)
        external
        override
        onlyFactoryAdmin
        returns (uint256 proposalId)
    {
        require(token != address(0), InvalidAddress());
        require(newLockUntil > block.timestamp, InvalidLockUntil());
        uint256 lockDuration = newLockUntil - block.timestamp;
        require(
            lockDuration <= OTCConstants.MAX_LOCK_DURATION,
            LockDurationTooLarge(lockDuration, OTCConstants.MAX_LOCK_DURATION)
        );
        require(deadline > block.timestamp, InvalidDeadline());

        proposalId = _nextProposalId();
        OTCTypes.LockProposal storage p = lockProposals[proposalId];
        p.token = token;
        p.newLockUntil = newLockUntil;
        p.deadline = deadline;

        emit LockProposed(proposalId, token, newLockUntil);
    }

    /// @inheritdoc IOTCClientVault
    function acceptLockProposal(uint256 proposalId) external override onlyOwner nonReentrant {
        OTCTypes.LockProposal storage p = lockProposals[proposalId];
        _requireActive(p.deadline, p.executed, p.cancelled);

        uint256 lockUntil = tokenLockUntil[p.token];
        if (p.newLockUntil > lockUntil) {
            tokenLockUntil[p.token] = p.newLockUntil;
            lockUntil = p.newLockUntil;
        }
        p.clientApproved = true;
        p.executed = true;

        emit LockAccepted(proposalId, p.token, lockUntil);
    }

    /// @inheritdoc IOTCClientVault
    function cancelLockProposal(uint256 proposalId) external override onlyAuthorized {
        OTCTypes.LockProposal storage p = lockProposals[proposalId];
        require(p.deadline != 0, InvalidProposal());
        _requireNotExecutedOrCancelled(p.executed, p.cancelled);
        p.cancelled = true;
        emit ProposalCancelled(proposalId);
    }

    /// @inheritdoc IOTCClientVault
    function adminDecreaseLock(address token, uint256 newLockUntil) external override onlyFactoryAdmin {
        require(token != address(0), InvalidAddress());
        require(newLockUntil > block.timestamp, InvalidLockUntil());

        uint256 previousLockUntil = tokenLockUntil[token];
        require(previousLockUntil > block.timestamp, TokenNotLocked());
        require(newLockUntil < previousLockUntil, LockNotDecreased());

        tokenLockUntil[token] = newLockUntil;
        emit TokenLockDecreasedByAdmin(token, previousLockUntil, newLockUntil);
    }

    // ── Delivery proposals ──────────────────────────────────────────────────────

    /// @inheritdoc IOTCClientVault
    function proposeDelivery(OTCTypes.DeliveryProposalParams calldata params, OTCTypes.ExtraFee calldata extraFee)
        external
        override
        returns (uint256 proposalId)
    {
        _validateDeliveryBase(
            params.token, params.amount, params.expectedReceivedToken, params.minExpectedReceivedAmount, params.deadline
        );
        if (params.useAllowanceCall) {
            _validateAllowanceDelivery(params.deliveryAddress, params.target, params.callData);
        } else {
            _validateDirectDelivery(
                params.deliveryAddress, params.target, params.callData, params.expectedReceivedToken
            );
        }
        _validateExtraFee(extraFee);

        proposalId = _nextProposalId();
        OTCTypes.DeliveryProposal storage p = _storeDeliveryProposal(proposalId, params, extraFee);
        _approveDeliveryRole(p, msg.sender);
        emit DeliveryProposed(proposalId, params.token, params.amount, params.target);
    }

    /// @inheritdoc IOTCClientVault
    function acceptDeliveryProposal(uint256 proposalId) external override {
        OTCTypes.DeliveryProposal storage p = _deliveryProposals[proposalId];
        _requireActive(p.deadline, p.executed, p.cancelled);
        _approveDeliveryRole(p, msg.sender);
        emit DeliveryAccepted(proposalId);
    }

    /// @inheritdoc IOTCClientVault
    function executeDelivery(uint256 proposalId) external override nonReentrant {
        OTCTypes.DeliveryProposal storage p = _deliveryProposals[proposalId];
        _requireActive(p.deadline, p.executed, p.cancelled);
        _autoApproveDeliveryRole(p, msg.sender);
        require(p.clientApproved, ClientNotApproved());

        if (!p.adminApproved) {
            if (swapAccessLevel == OTCTypes.SwapAccessLevel.OpenP2P) {
                _requireUnlocked(p.token);
            } else {
                revert AdminNotApproved();
            }
        }

        (uint256 netAmount, uint256 feeAmount,) = _feeAmounts(p.amount, p.feeSnapshot.deliveryFeeBps, p.feeMode);
        p.executed = true;
        if (p.useAllowanceCall) {
            _executeAllowanceCallDelivery(p, netAmount);
        } else {
            _executeDirectDelivery(p, netAmount);
        }

        _chargeFee(p.token, feeAmount, p.feeSnapshot);
        _chargeExtraFee(p.extraFee, p.adminApproved);
        emit DeliveryExecuted(proposalId, p.token, p.target, p.expectedReceivedToken, p.minExpectedReceivedAmount);
    }

    /// @inheritdoc IOTCClientVault
    function cancelDeliveryProposal(uint256 proposalId) external override onlyAuthorized {
        OTCTypes.DeliveryProposal storage p = _deliveryProposals[proposalId];
        require(p.deadline != 0, InvalidProposal());
        _requireNotExecutedOrCancelled(p.executed, p.cancelled);
        p.cancelled = true;
        emit ProposalCancelled(proposalId);
    }

    // ── Swap proposals ──────────────────────────────────────────────────────────

    /// @inheritdoc IOTCClientVault
    function setSwapAccessLevel(OTCTypes.SwapAccessLevel newLevel) external override onlyOwner {
        OTCTypes.SwapAccessLevel oldLevel = swapAccessLevel;
        swapAccessLevel = newLevel;
        emit SwapAccessLevelUpdated(oldLevel, newLevel);
    }

    /// @inheritdoc IOTCClientVault
    function createSwapProposal(OTCTypes.SwapProposalParams calldata params, OTCTypes.ExtraFee calldata extraFee)
        external
        override
        returns (uint256 proposalId)
    {
        _validateSwapProposal(params);
        _validateExtraFee(extraFee);

        proposalId = _nextProposalId();
        OTCTypes.SwapProposal storage p = _storeSwapProposal(proposalId, params, extraFee);
        _approveSwapRole(p, msg.sender);

        emit SwapProposed(
            proposalId,
            params.level,
            msg.sender,
            params.counterparty,
            params.tokenOut,
            params.tokenIn,
            params.amountOut,
            params.amountIn
        );
    }

    /// @inheritdoc IOTCClientVault
    function approveSwap(uint256 proposalId) external override {
        OTCTypes.SwapProposal storage p = _swapProposals[proposalId];
        _requireActive(p.deadline, p.executed, p.cancelled);
        require(uint8(p.level) <= uint8(swapAccessLevel), SwapLevelNotAllowed());
        if (p.level == OTCTypes.SwapAccessLevel.OpenP2P) {
            _requireUnlocked(p.tokenOut);
        }
        _approveSwapRole(p, msg.sender);
        emit SwapApproved(proposalId, msg.sender);
    }

    /// @inheritdoc IOTCClientVault
    function executeSwap(uint256 proposalId) external override nonReentrant {
        OTCTypes.SwapProposal storage p = _swapProposals[proposalId];
        _requireActive(p.deadline, p.executed, p.cancelled);
        _autoApproveSwapRole(p, msg.sender);
        _requireSwapApprovals(p);

        if (p.level == OTCTypes.SwapAccessLevel.OpenP2P) {
            _requireUnlocked(p.tokenOut);
        }

        p.executed = true;
        uint16 feeBps =
            p.level == OTCTypes.SwapAccessLevel.OpenP2P ? p.feeSnapshot.openP2PFeeBps : p.feeSnapshot.takerFeeBps;
        (,, uint256 grossAmount) = _feeAmounts(p.amountIn, feeBps, p.feeMode);

        IERC20(p.tokenIn).safeTransferFrom(p.counterparty, address(this), grossAmount);
        IERC20(p.tokenOut).safeTransfer(p.counterparty, p.amountOut);

        if (p.level == OTCTypes.SwapAccessLevel.OpenP2P) {
            (, uint256 feeAmount,) = _feeAmounts(p.amountIn, p.feeSnapshot.openP2PFeeBps, p.feeMode);
            _chargeFee(p.tokenIn, feeAmount, p.feeSnapshot);
        } else {
            (, uint256 feeAmount,) = _feeAmounts(p.amountIn, p.feeSnapshot.takerFeeBps, p.feeMode);
            _chargeFee(p.tokenIn, feeAmount, p.feeSnapshot);
        }

        _chargeExtraFee(p.extraFee, p.adminApproved);
        emit SwapExecuted(proposalId);
    }

    /// @inheritdoc IOTCClientVault
    function cancelSwapProposal(uint256 proposalId) external override {
        OTCTypes.SwapProposal storage p = _swapProposals[proposalId];
        require(p.deadline != 0, InvalidProposal());
        require(_isClientAdminOrOwner(msg.sender) || msg.sender == p.counterparty, NotAuthorized());
        _requireNotExecutedOrCancelled(p.executed, p.cancelled);
        p.cancelled = true;
        emit ProposalCancelled(proposalId);
    }

    /// @inheritdoc IOTCClientVault
    function deliveryProposals(uint256 proposalId) external view override returns (OTCTypes.DeliveryProposal memory) {
        return _deliveryProposals[proposalId];
    }

    /// @inheritdoc IOTCClientVault
    function swapProposals(uint256 proposalId) external view override returns (OTCTypes.SwapProposal memory) {
        return _swapProposals[proposalId];
    }

    function _executeDirectDelivery(OTCTypes.DeliveryProposal storage p, uint256 netAmount) internal {
        IERC20(p.token).safeTransfer(p.deliveryAddress, netAmount);
    }

    function _executeAllowanceCallDelivery(OTCTypes.DeliveryProposal storage p, uint256 netAmount) internal {
        uint256 receivedBefore;
        if (p.expectedReceivedToken != address(0)) {
            receivedBefore = IERC20(p.expectedReceivedToken).balanceOf(address(this));
        }

        IERC20(p.token).forceApprove(p.deliveryAddress, 0);
        IERC20(p.token).forceApprove(p.deliveryAddress, netAmount);

        (bool ok,) = p.target.call(p.callData);
        require(ok, DeliveryCallFailed());

        IERC20(p.token).forceApprove(p.deliveryAddress, 0);

        if (p.expectedReceivedToken != address(0)) {
            uint256 receivedAfter = IERC20(p.expectedReceivedToken).balanceOf(address(this));
            uint256 received = receivedAfter - receivedBefore;
            require(
                received >= p.minExpectedReceivedAmount, InsufficientReceived(received, p.minExpectedReceivedAmount)
            );
        }
    }

    function _feeAmounts(uint256 amount, uint16 feeBps, OTCTypes.FeeMode feeMode)
        internal
        pure
        returns (uint256 netAmount, uint256 feeAmount, uint256 grossAmount)
    {
        feeAmount = amount * feeBps / OTCConstants.MAX_FEE_BPS;
        if (feeMode == OTCTypes.FeeMode.Gross) {
            netAmount = amount;
            grossAmount = amount + feeAmount;
        } else {
            netAmount = amount - feeAmount;
            grossAmount = amount;
        }
    }

    function _chargeFee(address token, uint256 operatorFee, OTCTypes.FeeSnapshot memory snapshot) internal {
        if (operatorFee == 0) return;

        uint256 protocolFee = operatorFee * snapshot.protocolFeeShareBps / OTCConstants.MAX_FEE_BPS;
        uint256 operatorNetFee = operatorFee - protocolFee;

        if (protocolFee > 0) IERC20(token).safeTransfer(snapshot.protocolFeeReceiver, protocolFee);
        if (operatorNetFee > 0) IERC20(token).safeTransfer(snapshot.operatorFeeReceiver, operatorNetFee);
    }

    function _chargeExtraFee(OTCTypes.ExtraFee memory extraFee, bool adminApproved) internal {
        if (extraFee.amount == 0) return;
        if (!adminApproved) _requireUnlocked(extraFee.token);
        IERC20(extraFee.token).safeTransfer(extraFee.receiver, extraFee.amount);
    }

    function _validateDeliveryBase(
        address token,
        uint256 amount,
        address expectedReceivedToken,
        uint256 minExpectedReceivedAmount,
        uint256 deadline
    ) internal view {
        require(token != address(0), InvalidAddress());
        require(amount > 0, InvalidAmount());
        require(deadline > block.timestamp, InvalidDeadline());
        if (expectedReceivedToken == address(0)) {
            require(minExpectedReceivedAmount == 0, InvalidExpectedAmount());
        }
    }

    function _validateAllowanceDelivery(address deliveryAddress, address target, bytes calldata callData)
        internal
        pure
    {
        require(
            deliveryAddress != address(0) && target != address(0) && callData.length > 0,
            AllowanceDeliveryInvalidFields()
        );
    }

    function _validateDirectDelivery(
        address deliveryAddress,
        address target,
        bytes calldata callData,
        address expectedReceivedToken
    ) internal pure {
        require(deliveryAddress != address(0), InvalidAddress());
        require(
            target == address(0) && callData.length == 0 && expectedReceivedToken == address(0),
            DirectDeliveryInvalidFields()
        );
    }

    function _validateSwap(address tokenOut, uint256 amountOut, address tokenIn, uint256 amountIn, uint256 deadline)
        internal
        view
    {
        require(tokenOut != address(0) && tokenIn != address(0), InvalidSwapTokens());
        require(amountOut > 0 && amountIn > 0, InvalidSwapAmounts());
        require(deadline > block.timestamp, InvalidDeadline());
    }

    function _validateSwapProposal(OTCTypes.SwapProposalParams calldata params) internal view {
        require(params.level != OTCTypes.SwapAccessLevel.DeliveryOnly, InvalidSwapLevel());
        require(uint8(params.level) <= uint8(swapAccessLevel), SwapLevelNotAllowed());
        require(params.counterparty != address(0), InvalidAddress());
        _validateSwap(params.tokenOut, params.amountOut, params.tokenIn, params.amountIn, params.deadline);

        if (params.level == OTCTypes.SwapAccessLevel.SupplierOnly) {
            require(_isFactoryAdmin(msg.sender), NotFactoryAdmin());
        } else if (params.level == OTCTypes.SwapAccessLevel.ManagedP2P) {
            require(_isSwapParticipant(msg.sender, params.counterparty, true), NotSwapParticipant());
        } else {
            require(_isSwapParticipant(msg.sender, params.counterparty, false), NotSwapParticipant());
            _requireUnlocked(params.tokenOut);
        }
    }

    function _approveSwapRole(OTCTypes.SwapProposal storage p, address approver) internal {
        bool approved;

        if (_isFactoryAdmin(approver)) {
            p.adminApproved = true;
            approved = true;
        }

        if (approver == owner()) {
            p.clientApproved = true;
            approved = true;
        }

        if (approver == p.counterparty) {
            p.counterpartyApproved = true;
            approved = true;
        }

        require(approved, NotSwapParticipant());
    }

    function _approveDeliveryRole(OTCTypes.DeliveryProposal storage p, address approver) internal {
        bool approved;

        if (approver == owner()) {
            p.clientApproved = true;
            approved = true;
        }

        if (_isFactoryAdminOrOwner(approver)) {
            p.adminApproved = true;
            approved = true;
        }

        require(approved, NotAuthorized());
    }

    function _autoApproveDeliveryRole(OTCTypes.DeliveryProposal storage p, address approver) internal {
        if (approver == owner()) {
            p.clientApproved = true;
        }
        if (_isFactoryAdminOrOwner(approver)) {
            p.adminApproved = true;
        }
    }

    function _autoApproveSwapRole(OTCTypes.SwapProposal storage p, address approver) internal {
        if (_isFactoryAdmin(approver)) {
            p.adminApproved = true;
        }
        if (approver == owner()) {
            p.clientApproved = true;
        }
        if (approver == p.counterparty) {
            p.counterpartyApproved = true;
        }
    }

    function _requireSwapApprovals(OTCTypes.SwapProposal storage p) internal view {
        require(uint8(p.level) <= uint8(swapAccessLevel), SwapLevelNotAllowed());
        require(p.clientApproved, ClientNotApproved());
        require(p.counterpartyApproved, CounterpartyNotApproved());

        if (p.level != OTCTypes.SwapAccessLevel.OpenP2P) {
            require(p.adminApproved, AdminNotApproved());
        }
    }

    function _isSwapParticipant(address account, address counterparty, bool includeAdmin) internal view returns (bool) {
        return account == owner() || account == counterparty || (includeAdmin && _isFactoryAdmin(account));
    }

    function _validateExtraFee(OTCTypes.ExtraFee calldata extraFee) internal pure {
        if (extraFee.amount == 0) {
            require(extraFee.token == address(0), InvalidExtraFeeToken());
            require(extraFee.receiver == address(0), InvalidExtraFeeReceiver());
            return;
        }
        require(extraFee.token != address(0), InvalidExtraFeeToken());
        require(extraFee.receiver != address(0), InvalidExtraFeeReceiver());
    }

    function _requireActive(uint256 deadline, bool executed, bool cancelled) internal view {
        require(deadline != 0, InvalidProposal());
        require(!executed, ProposalAlreadyExecuted());
        require(!cancelled, ProposalAlreadyCancelled());
        require(block.timestamp <= deadline, ProposalExpired(deadline, block.timestamp));
    }

    function _requireNotExecutedOrCancelled(bool executed, bool cancelled) internal pure {
        require(!executed, ProposalAlreadyExecuted());
        require(!cancelled, ProposalAlreadyCancelled());
    }

    function _requireUnlocked(address token) internal view {
        uint256 unlocksAt = tokenLockUntil[token];
        require(block.timestamp >= unlocksAt, TokenLocked(token, unlocksAt));
    }

    function _onlyFactoryAdmin() internal view {
        require(_isFactoryAdmin(msg.sender), NotFactoryAdmin());
    }

    function _onlyAuthorized() internal view {
        require(_isClientAdminOrOwner(msg.sender), NotAuthorized());
    }

    function _isClientAdminOrOwner(address account) internal view returns (bool) {
        IOTCOperatorFactory operatorFactory = IOTCOperatorFactory(factory);
        return account == owner() || account == operatorFactory.admin() || account == operatorFactory.owner();
    }

    function _isFactoryAdminOrOwner(address account) internal view returns (bool) {
        IOTCOperatorFactory operatorFactory = IOTCOperatorFactory(factory);
        return account == operatorFactory.admin() || account == operatorFactory.owner();
    }

    function _isFactoryAdmin(address account) internal view returns (bool) {
        return account == IOTCOperatorFactory(factory).admin();
    }

    function _feeSnapshot() internal view returns (OTCTypes.FeeSnapshot memory) {
        return IOTCOperatorFactory(factory).getCurrentFeeSnapshot();
    }

    function _storeDeliveryProposal(
        uint256 proposalId,
        OTCTypes.DeliveryProposalParams calldata params,
        OTCTypes.ExtraFee calldata extraFee
    ) internal returns (OTCTypes.DeliveryProposal storage p) {
        p = _deliveryProposals[proposalId];
        p.useAllowanceCall = params.useAllowanceCall;
        p.feeMode = params.feeMode;
        p.token = params.token;
        p.amount = params.amount;
        p.deliveryAddress = params.deliveryAddress;
        p.target = params.target;
        p.callData = params.callData;
        p.expectedReceivedToken = params.expectedReceivedToken;
        p.minExpectedReceivedAmount = params.minExpectedReceivedAmount;
        p.deadline = params.deadline;
        p.feeSnapshot = _feeSnapshot();
        p.extraFee = extraFee;
    }

    function _storeSwapProposal(
        uint256 proposalId,
        OTCTypes.SwapProposalParams calldata params,
        OTCTypes.ExtraFee calldata extraFee
    ) internal returns (OTCTypes.SwapProposal storage p) {
        p = _swapProposals[proposalId];
        p.level = params.level;
        p.feeMode = _isFactoryAdmin(msg.sender) ? params.feeMode : OTCTypes.FeeMode.Inclusive;
        p.proposer = msg.sender;
        p.counterparty = params.counterparty;
        p.tokenOut = params.tokenOut;
        p.amountOut = params.amountOut;
        p.tokenIn = params.tokenIn;
        p.amountIn = params.amountIn;
        p.deadline = params.deadline;
        p.feeSnapshot = _feeSnapshot();
        p.extraFee = extraFee;
    }

    function _initializeDefaultLocks(OTCTypes.DefaultLockConfig[] memory defaultLockConfigs_) internal {
        uint256 n = defaultLockConfigs_.length;
        for (uint256 i = 0; i < n;) {
            OTCTypes.DefaultLockConfig memory config = defaultLockConfigs_[i];
            if (config.duration > 0) {
                require(config.token != address(0), InvalidAddress());
                require(
                    config.duration <= OTCConstants.MAX_LOCK_DURATION,
                    LockDurationTooLarge(config.duration, OTCConstants.MAX_LOCK_DURATION)
                );
                tokenLockUntil[config.token] = block.timestamp + config.duration;
            }
            unchecked {
                ++i;
            }
        }
    }

    function _nextProposalId() internal returns (uint256 proposalId) {
        proposalId = nextProposalId++;
    }
}
