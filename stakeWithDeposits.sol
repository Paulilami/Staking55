// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC1155} from "@openzeppelin-5.0.1/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";

contract ERC1155StakingWithNetworkFees is Ownable {
    using SafeERC20 for IERC20;
    using Address for address;

    struct Stake {
        uint256 amount;
        uint256 lockPeriod;
        uint256 lockStart;
        uint256 rewardWeight;
        bool withdrawn;
    }

    IERC1155 public immutable token1155;
    IERC20 public immutable rewardToken;
    uint256 public constant MAX_LOCKUP_PERIOD = 24 * 30 days;
    uint256 public totalLockedFunds;
    uint256 public totalRewardWeight;
    uint256 public totalRewardPool;
    uint256 public lastRewardDistribution;

    mapping(address => Stake[]) public stakes;

    constructor(IERC1155 _token1155, IERC20 _rewardToken) {
        token1155 = _token1155;
        rewardToken = _rewardToken;
        lastRewardDistribution = block.timestamp;
    }

    function stake(uint256 _id, uint256 _amount, uint256 _lockPeriod) external {
        require(_lockPeriod > 0 && _lockPeriod <= MAX_LOCKUP_PERIOD, "Invalid lock period");

        token1155.safeTransferFrom(msg.sender, address(this), _id, _amount, "");

        uint256 rewardWeight = calculateRewardWeight(_lockPeriod, _amount);
        totalRewardWeight += rewardWeight;

        stakes[msg.sender].push(Stake(_amount, _lockPeriod, block.timestamp, rewardWeight, false));
    }

    function calculateRewardWeight(uint256 _lockPeriod, uint256 _amount) internal pure returns (uint256) {
        return (_lockPeriod * _amount) / 1e18;
    }

    function depositNetworkFees(uint256 _amount) external {
        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);
        totalRewardPool += _amount;
    }

    function withdrawStake(uint256 _index) external {
        Stake storage s = stakes[msg.sender][_index];
        require(!s.withdrawn, "Stake already withdrawn");
        require(block.timestamp >= s.lockStart + s.lockPeriod, "Lockup period not over");

        totalRewardWeight -= s.rewardWeight;

        token1155.safeTransferFrom(address(this), msg.sender, _index, s.amount, "");
        s.withdrawn = true;
    }

    function earlyWithdraw(uint256 _index) external {
        Stake storage s = stakes[msg.sender][_index];
        require(!s.withdrawn, "Stake already withdrawn");
        require(block.timestamp < s.lockStart + s.lockPeriod, "Cannot withdraw after lockup");

        uint256 penalty = (s.amount * (s.lockPeriod - (block.timestamp - s.lockStart))) / s.lockPeriod;
        uint256 remaining = s.amount - penalty;

        totalRewardWeight -= s.rewardWeight;

        totalLockedFunds += penalty;

        token1155.safeTransferFrom(address(this), msg.sender, _index, remaining, "");
        s.withdrawn = true;
    }

    function distributeQuarterlyRewards() external onlyOwner {
        require(block.timestamp >= lastRewardDistribution + 90 days, "Quarterly distribution only");

        uint256 rewardPerWeight = totalRewardPool / totalRewardWeight;

        for (uint256 i = 0; i < stakes[msg.sender].length; i++) {
            Stake storage s = stakes[msg.sender][i];
            if (!s.withdrawn) {
                uint256 reward = (s.rewardWeight * rewardPerWeight);
                rewardToken.safeTransfer(msg.sender, reward);
            }
        }

        totalRewardPool = 0;
        lastRewardDistribution = block.timestamp;
    }

    receive() external payable {
        totalLockedFunds += msg.value;
    }
}
