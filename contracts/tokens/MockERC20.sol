// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev THIS CONTRACT IS FOR TESTING PURPOSES ONLY.
 */

contract MockERC20 is ERC20 {
    uint8 internal decimals_;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol) {
        decimals_ = _decimals;
    }

    function mint(address to, uint256 _amount) external returns (bool) {
        _mint(to, _amount);
        return true;
    }

    function decimals() public view virtual override returns (uint8) {
        return decimals_;
    }
}
