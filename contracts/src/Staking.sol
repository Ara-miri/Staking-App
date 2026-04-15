//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Staking is ReentrancyGuard, Pausable, Ownable {
    IERC20 public immutable rewardToken;

    uint256 public rewardRate;
    uint256 public lockPeriod;
    uint256 public totalStaked;

    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => uint256) public lockUntil;
    mapping(address => uint256) public pendingRewards;

    event Staked(address indexed user, uint256 amount, uint256 lockUntil);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event EmergencyWithdrawn(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    event LockPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event RewardPoolFunded(address indexed funder, uint256 amount);
    event UnusedRewardsRecovered(address indexed owner, uint256 amount);

    error Staking_AmountMustBeGreaterThanZero();
    error Staking_InsufficientBalance();
    error Staking_WithdrawalTimelocked(uint256 lockUntil);
    error Staking_InsufficientRewardPool(uint256 available, uint256 required);
    error Staking_TransferFailed();

    constructor(
        address _rewardToken,
        uint256 _rewardRate,
        uint256 _lockPeriod
    ) Ownable(msg.sender) {
        rewardToken = IERC20(_rewardToken);
        rewardRate = _rewardRate;
        lockPeriod = _lockPeriod;
    }

    modifier updateReward(address _account) {
        pendingRewards[_account] = earned(_account);
        lastUpdateTime[_account] = block.timestamp;
        _;
    }

    function stake() external payable whenNotPaused updateReward(msg.sender) {
        if (msg.value == 0) revert Staking_AmountMustBeGreaterThanZero();

        stakedBalance[msg.sender] += msg.value;
        totalStaked += msg.value;
        lockUntil[msg.sender] = block.timestamp + lockPeriod;

        emit Staked(msg.sender, msg.value, lockUntil[msg.sender]);
    }

    function withdraw(
        uint256 _amount
    ) external nonReentrant whenNotPaused updateReward(msg.sender) {
        if (_amount == 0) revert Staking_AmountMustBeGreaterThanZero();
        if (stakedBalance[msg.sender] < _amount)
            revert Staking_InsufficientBalance();
        if (block.timestamp < lockUntil[msg.sender])
            revert Staking_WithdrawalTimelocked(lockUntil[msg.sender]);

        stakedBalance[msg.sender] -= _amount;
        totalStaked -= _amount;

        (bool ok, ) = payable(msg.sender).call{value: _amount}("");
        if (!ok) revert Staking_TransferFailed();

        emit Withdrawn(msg.sender, _amount);
        _claimReward();
    }

    function emergencyWithdraw()
        external
        nonReentrant
        updateReward(msg.sender)
    {
        uint256 amount = stakedBalance[msg.sender];
        if (amount == 0) revert Staking_AmountMustBeGreaterThanZero();

        stakedBalance[msg.sender] = 0;
        pendingRewards[msg.sender] = 0;
        lockUntil[msg.sender] = 0;
        totalStaked -= amount;

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert Staking_TransferFailed();

        emit EmergencyWithdrawn(msg.sender, amount);
    }

    function claimRewards()
        external
        nonReentrant
        whenNotPaused
        updateReward(msg.sender)
    {
        _claimReward();
    }

    function earned(address _account) public view returns (uint256) {
        uint256 timePassed = block.timestamp - lastUpdateTime[_account];
        return
            pendingRewards[_account] +
            (stakedBalance[_account] * timePassed * rewardRate) /
            1 days;
    }

    function timeUntilUnlock(address _account) external view returns (uint256) {
        if (block.timestamp >= lockUntil[_account]) return 0;
        return lockUntil[_account] - block.timestamp;
    }

    function getUserInfo(
        address _account
    )
        external
        view
        returns (
            uint256 staked,
            uint256 rewards,
            uint256 unlock,
            uint256 secondsLeft
        )
    {
        staked = stakedBalance[_account];
        rewards = earned(_account);
        unlock = lockUntil[_account];
        secondsLeft = block.timestamp >= unlock ? 0 : unlock - block.timestamp;
    }

    function rewardPoolBalance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    function fundRewardPool(uint256 _amount) external onlyOwner {
        bool ok = rewardToken.transferFrom(msg.sender, address(this), _amount);
        if (!ok) revert Staking_TransferFailed();
        emit RewardPoolFunded(msg.sender, _amount);
    }

    function recoverUnusedRewards() external onlyOwner {
        uint256 bal = rewardToken.balanceOf(address(this));
        if (bal == 0) revert Staking_AmountMustBeGreaterThanZero();
        bool ok = rewardToken.transfer(owner(), bal);
        if (!ok) revert Staking_TransferFailed();
        emit UnusedRewardsRecovered(owner(), bal);
    }

    function setRewardRate(uint256 _newRate) external onlyOwner {
        emit RewardRateUpdated(rewardRate, _newRate);
        rewardRate = _newRate;
    }

    function setLockPeriod(uint256 _newPeriod) external onlyOwner {
        emit LockPeriodUpdated(lockPeriod, _newPeriod);
        lockPeriod = _newPeriod;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _claimReward() internal updateReward(msg.sender) {
        uint256 reward = pendingRewards[msg.sender];
        if (reward == 0) return;

        uint256 pool = rewardToken.balanceOf(address(this));
        if (pool < reward) revert Staking_InsufficientRewardPool(pool, reward);

        pendingRewards[msg.sender] = 0;
        bool ok = rewardToken.transfer(msg.sender, reward);
        if (!ok) revert Staking_TransferFailed();

        emit RewardClaimed(msg.sender, reward);
    }
}
