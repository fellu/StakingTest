// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract EthBridge is Ownable {
    event BridgeDeposit(uint256 indexed depositId, address indexed user, uint256 amount);

    struct Deposit {
        address user;
        uint256 amount;
    }


    mapping(uint256 => Deposit) public deposits;
    IERC20 public token;
    uint256 public bridgeId;

    constructor(address tokenAddress) {
        require(tokenAddress != address(0), "Token address cannot be zero");
        token = IERC20(tokenAddress);
    }

    function bridge(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        require(token.transferFrom(msg.sender, address(this), amount), "Token transfer failed");
        bridgeId++;
        deposits[bridgeId] = Deposit(msg.sender, amount);
        emit BridgeDeposit(bridgeId, msg.sender, amount);
    }


    function withdrawTokens(uint256 amount) external onlyOwner {
        require(token.transfer(owner(), amount), "Token transfer failed");
    }

    function withdrawNative(uint256 amount) external onlyOwner {
        payable(owner()).transfer(amount);
    }
}

