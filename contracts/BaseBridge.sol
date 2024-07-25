// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract BaseBridge is Ownable {
    event Bridged(uint256 indexed bridgeId, address indexed to, uint256 amount);

    IERC20 public token;
    mapping(uint256 => bool) public bridgedIds;
    uint256 public highestProcessedId;

    constructor() {}

    function setToken(address tokenAddress) external onlyOwner {
        token = IERC20(tokenAddress);
    }

    function bridgeTokens(uint256 bridgeId, address to, uint256 amount) external onlyOwner {
        require(!bridgedIds[bridgeId], "Bridge ID already used");
        require(token.transfer(to, amount), "Token transfer failed");

        bridgedIds[bridgeId] = true;
        highestProcessedId = bridgeId;
        emit Bridged(bridgeId, to, amount);
    }
}

