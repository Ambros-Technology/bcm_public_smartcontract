// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

import "./bcmupgradable.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IBlockchainMonster {
    function permitTrade(
        address owner, 
        address target, 
        uint256 tokenId,
        uint256 permitId,
        uint256 currency,
        uint256 price, 
        uint256 deadline, 
        bytes memory signature
    ) external;

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
} 

contract BCMTrade is BCMUpgradable {

    uint256 public total;
    uint256 public feeRateChainCoin; // percentage
    uint256 public feeRateBCMC; // percentage

    // data contract
    address public bcmERC721contract;
    address public bcmcERC20Contract;

    event TradeCompleteEvt(address indexed buyer, address indexed seller, uint256 tokenId, uint256 tradeId);

    function initialize() public initializer {
        BCMUpgradable.__BCMUpgradable_initialize();
        total = 0;
        feeRateChainCoin = 2;
        feeRateBCMC = 2;
    }

    modifier onlyBCMC() {
        require(
            bcmcERC20Contract != address(0) && msg.sender == bcmcERC20Contract
        );
        _;
    }    

    // moderator
    function setDepContracts(address erc721Contract, address erc20Contract)
        external
        onlyRole(MODERATOR_ROLE)
    {
        bcmERC721contract = erc721Contract;
        bcmcERC20Contract = erc20Contract;
    }

    function setFeeRate(uint256 chainRate, uint256 bcmcRate)
        external
        onlyRole(MODERATOR_ROLE)
    {
        feeRateChainCoin = chainRate;
        feeRateBCMC = bcmcRate;
    }

    function withdraw(address payable _sendTo, uint _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _sendTo.transfer(_amount);
    }

    function withdrawToken(address payable _sendTo, uint _amount) external onlyRole(DEFAULT_ADMIN_ROLE){
        IERC20Upgradeable token = IERC20Upgradeable(bcmcERC20Contract);
        token.transfer(_sendTo, _amount);
    }

    // bcmc
    function executeTradeUsingBCMC(address buyer, uint256 tradeId, address seller, uint256 tokenId, uint256 currency, 
        uint256 price, uint256 deadline, bytes memory signature) external virtual whenNotPaused onlyBCMC {
        require(currency == 2, "invalid_currency"); // must be BCMC
        IBlockchainMonster erc721Token = IBlockchainMonster(bcmERC721contract);
        erc721Token.permitTrade(seller, address(this), tokenId, tradeId, currency, price, deadline, signature);
        erc721Token.transferFrom(seller, buyer, tokenId);

        // send fund to seller
        uint256 totalFee = (feeRateBCMC * price) / 100;
        require(totalFee < price, "invalid_fee");
        IERC20Upgradeable erc20Token = IERC20Upgradeable(bcmcERC20Contract);
        erc20Token.transfer(seller, price - totalFee);
        emit TradeCompleteEvt(buyer, seller, tokenId, tradeId);
    }

    // public
    receive() external payable {}

    function executeTrade(uint256 tradeId, address payable seller, uint256 tokenId, uint256 currency, 
        uint256 price, uint256 deadline, bytes memory signature) external virtual payable whenNotPaused {
        require(currency == 1, "invalid_currency"); // must be chain currency (ETH, BNB)
        require(msg.value == price, "invalid_amount");        
        IBlockchainMonster erc721Token = IBlockchainMonster(bcmERC721contract);
        erc721Token.permitTrade(seller, address(this), tokenId, tradeId, currency, price, deadline, signature);
        erc721Token.transferFrom(seller, msg.sender, tokenId);

        // send fund to seller
        uint256 totalFee = (feeRateChainCoin * price) / 100;
        seller.transfer(msg.value - totalFee);
        emit TradeCompleteEvt(msg.sender, seller, tokenId, tradeId);
    }
}