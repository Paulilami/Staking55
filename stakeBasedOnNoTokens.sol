// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC1155} from "@openzeppelin-5.0.1/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";

contract ERC1155StakingByTokenCount is Ownable {
    using SafeERC20 for IERC20;

    struct Stake {
        uint256 tokenId;
        uint256 amount;
        uint256 lockStart;
        bool withdrawn;
    }

    IERC1155 public immutable token1155;
    IERC20 public immutable rewardToken;
    uint256 public constant MAX_LOCKUP_PERIOD = 365 days;
    uint256 public totalRewardPool;
    uint256 public lastRewardDistribution;

    mapping(address => Stake[]) public stakes;
    mapping(uint256 => uint256) public totalTokenStaked; //total number of each tokenId staked

    constructor(IERC1155 _token1155, IERC20 _rewardToken) {
        token1155 = _token1155;
        rewardToken = _rewardToken;
        lastRewardDistribution = block.timestamp;
    }

    function stake(uint256 _tokenId, uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");

        token1155.safeTransferFrom(msg.sender, address(this), _tokenId, _amount, "");

        stakes[msg.sender].push(Stake(_tokenId, _amount, block.timestamp, false));
        totalTokenStaked[_tokenId] += _amount;
    }

    function depositRewards(uint256 _amount) external {
        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);
        totalRewardPool += _amount;
    }

    function distributeQuarterlyRewards() external onlyOwner {
        require(block.timestamp >= lastRewardDistribution + 90 days, "Quarterly distribution only");

        uint256 totalRewards = totalRewardPool;
        for (uint256 i = 0; i < stakes[msg.sender].length; i++) {
            Stake storage s = stakes[msg.sender][i];
            if (!s.withdrawn) {
                uint256 userTokenShare = (s.amount * 1e18) / totalTokenStaked[s.tokenId]; 
                uint256 rewardForUser = (userTokenShare * totalRewards) / 1e18;
                rewardToken.safeTransfer(msg.sender, rewardForUser);
            }
        }

        totalRewardPool = 0;
        lastRewardDistribution = block.timestamp;
    }

    function withdrawStake(uint256 _index) external {
        Stake storage s = stakes[msg.sender][_index];
        require(!s.withdrawn, "Stake already withdrawn");

        totalTokenStaked[s.tokenId] -= s.amount;

        token1155.safeTransferFrom(address(this), msg.sender, s.tokenId, s.amount, "");
        s.withdrawn = true;
    }

    function earlyWithdraw(uint256 _index) external {
        Stake storage s = stakes[msg.sender][_index];
        require(!s.withdrawn, "Stake already withdrawn");

        uint256 penalty = (s.amount * (block.timestamp - s.lockStart)) / MAX_LOCKUP_PERIOD;
        uint256 remaining = s.amount - penalty;

        totalTokenStaked[s.tokenId] -= s.amount;

        token1155.safeTransferFrom(address(this), msg.sender, s.tokenId, remaining, "");
        rewardToken.safeTransfer(owner(), penalty); //penalty goes to contract owner
        s.withdrawn = true;
    }

    receive() external payable {}
}
