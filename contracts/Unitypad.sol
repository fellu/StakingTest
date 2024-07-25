// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract Unitypad is ERC20, ERC20Burnable, Ownable {
    uint256 private FEE = 1;
    address private FEE_ADDRESS = 0x7988a575F1Ac14143f4BC661E048d375bB456BE7;

    address private PAIR_ADDRESS;
    address private BRIDGE_ADDRESS;


    mapping(address => bool) public _isExcludedFromFee;


    constructor(address bridgeAddress)
        ERC20("TESTUnitypad", "TESTUPAD")
    {
        require(bridgeAddress != address(0), "Token address cannot be zero");
        BRIDGE_ADDRESS = bridgeAddress;
        _mint(msg.sender, 1000000000 * 10 ** decimals());
        //_mint(BRIDGE_ADDRESS, 1000000000 * 10 ** decimals());

        _isExcludedFromFee[msg.sender] = true;
        _isExcludedFromFee[FEE_ADDRESS] = true;
        _isExcludedFromFee[BRIDGE_ADDRESS] = true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override(ERC20) {
        if (_isExcludedFromFee[sender] || _isExcludedFromFee[recipient]) {
            super._transfer(sender, recipient, amount);
        } else {
            if (sender == PAIR_ADDRESS || recipient == PAIR_ADDRESS) {
                uint256 feeAmount = ((amount * FEE) / 100);
                super._transfer(sender, FEE_ADDRESS, feeAmount);

                amount = amount - feeAmount;
            }

            super._transfer(sender, recipient, amount);
        }
    }


    function excludeFromFee(address account, bool status) public onlyOwner {
        _isExcludedFromFee[account] = status;
    }

    function setPairAddress(address pairAddress) public onlyOwner {
        PAIR_ADDRESS = pairAddress;
    }
}
