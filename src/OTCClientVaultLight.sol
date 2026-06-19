// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OTCTypes} from "./types/OTCTypes.sol";
import {OTCConstants} from "./constants/OTCConstants.sol";
import {IOTCClientVaultLight} from "./interfaces/IOTCClientVaultLight.sol";
import {IOTCClientVaultLightErrors} from "./interfaces/IOTCClientVaultLightErrors.sol";
import {IOTCClientVaultLightEvents} from "./interfaces/IOTCClientVaultLightEvents.sol";
import {IOTCOperatorFactory} from "./interfaces/IOTCOperatorFactory.sol";
import {IOTCFactoryRegistry} from "./interfaces/IOTCFactoryRegistry.sol";

/// @title OTCClientVaultLight
/// @notice Lightweight vault that supports only direct-transfer deliveries (DeliveryOnly mode, no swaps).
contract OTCClientVaultLight is
    Ownable,
    Initializable,
    IOTCClientVaultLight,
    IOTCClientVaultLightErrors,
    IOTCClientVaultLightEvents,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    /// @notice Operator factory that created this vault.
    address public override factory;

    /// @notice Auto-incrementing id assigned to the next proposal.
    uint256 public nextProposalId;

    /// @notice Delivery fee rate in basis points cached from the factory.
    uint16 public override vaultFeeConfig;

    /// @notice Timestamp after which `token` may be withdrawn.
    mapping(address token => uint256 lockUntil) public tokenLockUntil;
    /// @notice Lock proposals keyed by proposal id.
    mapping(uint256 proposalId => OTCTypes.LockProposal) public lockProposals;

    mapping(uint256 proposalId => LightDeliveryProposal) private _deliveryProposals;

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

    /// @inheritdoc IOTCClientVaultLight
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
        (, uint16 deliveryBps,) = IOTCOperatorFactory(factory_).defaultFeeConfig();
        vaultFeeConfig = deliveryBps;
        _initializeDefaultLocks(defaultLockConfigs_);
    }

    /// @inheritdoc IOTCClientVaultLight
    function deposit(address token, uint256 amount) external override onlyOwner nonReentrant {
        require(token != address(0), InvalidAddress());
        require(amount > 0, InvalidAmount());

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, token, amount);
    }

    /// @inheritdoc IOTCClientVaultLight
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

    /// @inheritdoc IOTCClientVaultLight
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

    /// @inheritdoc IOTCClientVaultLight
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

    /// @inheritdoc IOTCClientVaultLight
    function cancelLockProposal(uint256 proposalId) external override onlyAuthorized {
        OTCTypes.LockProposal storage p = lockProposals[proposalId];
        require(p.deadline != 0, InvalidProposal());
        _requireNotExecutedOrCancelled(p.executed, p.cancelled);
        p.cancelled = true;
        emit ProposalCancelled(proposalId);
    }

    /// @inheritdoc IOTCClientVaultLight
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

    /// @inheritdoc IOTCClientVaultLight
    function proposeDelivery(LightDeliveryProposalParams calldata params, OTCTypes.ExtraFee calldata extraFee)
        external
        override
        returns (uint256 proposalId)
    {
        require(params.token != address(0), InvalidAddress());
        require(params.amount > 0, InvalidAmount());
        require(params.deliveryAddress != address(0), InvalidAddress());
        require(params.deadline > block.timestamp, InvalidDeadline());
        _validateExtraFee(extraFee);

        proposalId = _nextProposalId();
        LightDeliveryProposal storage p = _deliveryProposals[proposalId];
        p.feeMode = params.feeMode;
        p.token = params.token;
        p.amount = params.amount;
        p.deliveryAddress = params.deliveryAddress;
        p.deadline = params.deadline;
        p.feeSnapshot = _feeSnapshot();
        p.extraFee = extraFee;
        _approveDeliveryRole(p, msg.sender);

        emit DeliveryProposed(proposalId, params.token, params.amount, params.deliveryAddress);
    }

    /// @inheritdoc IOTCClientVaultLight
    function acceptDeliveryProposal(uint256 proposalId) external override {
        LightDeliveryProposal storage p = _deliveryProposals[proposalId];
        _requireActive(p.deadline, p.executed, p.cancelled);
        _approveDeliveryRole(p, msg.sender);
        emit DeliveryAccepted(proposalId);
    }

    /// @inheritdoc IOTCClientVaultLight
    function executeDelivery(uint256 proposalId) external override nonReentrant {
        LightDeliveryProposal storage p = _deliveryProposals[proposalId];
        _requireActive(p.deadline, p.executed, p.cancelled);
        _autoApproveDeliveryRole(p, msg.sender);
        require(p.clientApproved, ClientNotApproved());
        require(p.adminApproved, AdminNotApproved());

        (uint256 netAmount, uint256 feeAmount,) = _feeAmounts(p.amount, p.feeSnapshot.deliveryFeeBps, p.feeMode);
        p.executed = true;
        IERC20(p.token).safeTransfer(p.deliveryAddress, netAmount);
        _chargeFee(p.token, feeAmount, p.feeSnapshot);
        _chargeExtraFee(p.extraFee);
        emit DeliveryExecuted(proposalId, p.token, p.deliveryAddress);
    }

    /// @inheritdoc IOTCClientVaultLight
    function cancelDeliveryProposal(uint256 proposalId) external override {
        LightDeliveryProposal storage p = _deliveryProposals[proposalId];
        require(p.deadline != 0, InvalidProposal());
        _requireNotExecutedOrCancelled(p.executed, p.cancelled);
        require(_isClientAdminOrOwner(msg.sender), NotAuthorized());
        p.cancelled = true;
        emit ProposalCancelled(proposalId);
    }

    /// @inheritdoc IOTCClientVaultLight
    function deliveryProposals(uint256 proposalId) external view override returns (LightDeliveryProposal memory) {
        return _deliveryProposals[proposalId];
    }

    /// @inheritdoc IOTCClientVaultLight
    function syncFeeFromFactory() external override {
        require(_isClientAdminOrOwner(msg.sender), NotAuthorized());
        IOTCOperatorFactory f = IOTCOperatorFactory(factory);
        (, uint16 newDelivery,) = f.defaultFeeConfig();
        require(newDelivery <= vaultFeeConfig, FeeNotImproved());
        vaultFeeConfig = newDelivery;
        emit VaultFeeConfigSynced(newDelivery);
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

        IOTCOperatorFactory f = IOTCOperatorFactory(factory);
        uint16 protocolFeeShareBps = f.deliveryOnlyProtocolFeeShareBps();
        uint256 protocolFee = operatorFee * protocolFeeShareBps / OTCConstants.MAX_FEE_BPS;
        uint256 operatorNetFee = operatorFee - protocolFee;

        if (protocolFee > 0) {
            IERC20(token).safeTransfer(f.protocolFeeReceiver(), protocolFee);
        }
        if (operatorNetFee > 0) IERC20(token).safeTransfer(snapshot.operatorFeeReceiver, operatorNetFee);
    }

    function _chargeExtraFee(OTCTypes.ExtraFee memory extraFee) internal {
        if (extraFee.amount == 0) return;
        IERC20(extraFee.token).safeTransfer(extraFee.receiver, extraFee.amount);
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

    function _approveDeliveryRole(LightDeliveryProposal storage p, address approver) internal {
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

    function _autoApproveDeliveryRole(LightDeliveryProposal storage p, address approver) internal {
        if (approver == owner()) {
            p.clientApproved = true;
        }
        if (_isFactoryAdminOrOwner(approver)) {
            p.adminApproved = true;
        }
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
        require(_isFactoryAdminOrOwner(msg.sender), NotFactoryAdmin());
    }

    function _onlyAuthorized() internal view {
        require(_isClientAdminOrOwner(msg.sender), NotAuthorized());
    }

    function _isClientAdminOrOwner(address account) internal view returns (bool) {
        IOTCOperatorFactory operatorFactory = IOTCOperatorFactory(factory);
        return account == owner() || account == operatorFactory.admin() || account == Ownable(factory).owner();
    }

    function _isFactoryAdminOrOwner(address account) internal view returns (bool) {
        IOTCOperatorFactory operatorFactory = IOTCOperatorFactory(factory);
        return account == operatorFactory.admin() || account == Ownable(factory).owner();
    }

    function _feeSnapshot() internal view returns (OTCTypes.FeeSnapshot memory snapshot) {
        IOTCOperatorFactory f = IOTCOperatorFactory(factory);
        snapshot.deliveryFeeBps = vaultFeeConfig;
        snapshot.operatorFeeReceiver = f.operatorFeeReceiver();
        snapshot.protocolFeeReceiver = f.protocolFeeReceiver();
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
