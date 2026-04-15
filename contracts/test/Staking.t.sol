//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Staking} from "../src/Staking.sol";
import {Test} from "forge-std/Test.sol";
import {SRTToken} from "../src/SRTToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FailingReceiver {
    Staking public staking;

    constructor(address _staking) {
        staking = Staking(_staking);
    }

    function doStake() external payable {
        staking.stake{value: msg.value}();
    }

    function doWithdraw(uint256 amount) external {
        staking.withdraw(amount);
    }

    receive() external payable {
        revert();
    }
}

contract StakingTest is Test {
    uint256 public constant LOCK_PERIOD = 6 hours;
    uint256 public constant REWARD_RATE = 10;
    uint256 public constant INITIAL_POOL = 1_000 ether;
    uint256 amount = 1000 ether;

    SRTToken token;
    Staking staking;

    address public owner = address(this);
    address public user = makeAddr("user");

    function setUp() public {
        token = new SRTToken(10_000 ether);
        staking = new Staking(address(token), REWARD_RATE, LOCK_PERIOD);

        token.approve(address(staking), INITIAL_POOL);
        staking.fundRewardPool(INITIAL_POOL);

        vm.deal(user, amount);
    }

    function test_stake() public {
        vm.prank(user);
        staking.stake{value: 2 ether}();
        assertEq(staking.stakedBalance(user), 2 ether);
        assertEq(staking.totalStaked(), 2 ether);
    }

    function test_tokenInitialSupply() public view {
        assertEq(token.totalSupply(), 10_000 ether);
    }

    function test_getOwner() public view {
        assertEq(staking.owner(), owner);
    }

    function test_rewardPoolFunded() public view {
        assertEq(staking.rewardPoolBalance(), INITIAL_POOL);
    }

    function test_earned() public {
        vm.prank(user);
        staking.stake{value: 2 ether}();
        vm.warp(block.timestamp + 1 days);
        uint256 e = staking.earned(user);
        assertGt(e, 0);
    }

    function test_timeUntilUnlock() public {
        vm.prank(user);
        staking.stake{value: 2 ether}();
        assertGt(staking.timeUntilUnlock(user), 0);

        vm.warp(block.timestamp + LOCK_PERIOD);
        assertEq(staking.timeUntilUnlock(user), 0);
    }

    function test_withdraw() public {
        vm.startPrank(user);
        staking.stake{value: 2 ether}();
        vm.warp(block.timestamp + LOCK_PERIOD);
        staking.withdraw(1 ether);
        assertEq(staking.stakedBalance(user), 1 ether);
    }

    function test_claimRewards() public {
        vm.startPrank(user);
        staking.stake{value: 2 ether}();
        vm.warp(block.timestamp + LOCK_PERIOD);
        staking.claimRewards();
        assertTrue(token.balanceOf(user) > 0);
    }

    function test_emergencyWithdraw() public {
        vm.startPrank(user);
        staking.stake{value: 2 ether}();
        uint256 ethBefore = user.balance;
        staking.emergencyWithdraw();
        assertEq(staking.stakedBalance(user), 0);
        assertEq(user.balance, ethBefore + 2 ether);
    }

    function test_setRewardRate() public {
        staking.setRewardRate(20);
        assertEq(staking.rewardRate(), 20);
    }

    function test_setLockPeriod() public {
        staking.setLockPeriod(2 days);
        assertEq(staking.lockPeriod(), 2 days);
    }

    function testRevert_IfStakeAmountIsZero() public {
        vm.prank(user);
        vm.expectRevert(Staking.Staking_AmountMustBeGreaterThanZero.selector);
        staking.stake{value: 0}();
    }

    function testRevert_IfWithdrawAmountIsZero() public {
        vm.startPrank(user);
        staking.stake{value: 2 ether}();
        vm.warp(block.timestamp + LOCK_PERIOD);
        vm.expectRevert(Staking.Staking_AmountMustBeGreaterThanZero.selector);
        staking.withdraw(0);
    }

    function testRevert_IfInsufficientBalance() public {
        vm.startPrank(user);
        staking.stake{value: 1 ether}();
        vm.warp(block.timestamp + LOCK_PERIOD);
        vm.expectRevert(Staking.Staking_InsufficientBalance.selector);
        staking.withdraw(2 ether);
    }

    function testRevert_IfWithdrawalTimelocked() public {
        vm.startPrank(user);
        staking.stake{value: 2 ether}();
        vm.expectRevert(
            abi.encodeWithSelector(
                Staking.Staking_WithdrawalTimelocked.selector,
                block.timestamp + LOCK_PERIOD
            )
        );
        staking.withdraw(1 ether);
    }

    function testRevert_IfETHTransferFails() public {
        FailingReceiver receiver = new FailingReceiver(address(staking));
        receiver.doStake{value: 2 ether}();
        vm.warp(block.timestamp + LOCK_PERIOD);
        vm.expectRevert(Staking.Staking_TransferFailed.selector);
        receiver.doWithdraw(1 ether);
    }

    function testRevert_IfTokenTransferFails() public {
        vm.startPrank(user);
        staking.stake{value: 2 ether}();
        vm.stopPrank();

        vm.warp(block.timestamp + LOCK_PERIOD);

        vm.mockCall(
            address(token),
            abi.encodeWithSelector(IERC20.transfer.selector),
            abi.encode(false)
        );

        vm.prank(user);
        vm.expectRevert(Staking.Staking_TransferFailed.selector);
        staking.withdraw(1 ether);
    }
}
