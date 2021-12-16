// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

interface IPToken {
    function redeem(
        uint256 amount,
        bytes memory data,
        string memory underlyingAssetRecipient
    ) external;
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address tokenHolder) external returns (uint256);
}

interface IVault {
    function pegIn(
        uint256 _tokenAmount,
        address _tokenAddress,
        string calldata _destinationAddress,
        bytes calldata _userData
    ) external returns (bool);
}

interface IBCMCERC20 {
    function balanceOf(address account) external returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function mintPortedToken(address target, uint256 amount) external;
    function cancelPortedToken(address target, uint256 amount, uint256 fee) external;
}

interface IBlockchainMonster {
    function mintPortedToken(address target, uint256 tokenId, uint256 tokenData) external returns(uint256);
    function cancelPortedToken(address target, uint256 tokenId, uint256 fee) external;
}