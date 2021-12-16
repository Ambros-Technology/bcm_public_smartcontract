// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC777/IERC777RecipientUpgradeable.sol";

contract BlockchainMonsterCoinBase is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 public constant PARTNER_CONTRACT_ROLE =
        keccak256("PARTNER_CONTRACT_ROLE");

    function __BlockchainMonsterCoinBase_initialize() public initializer {
        __ERC20_init("Blockchain Monster Coin", "BCMC");
        __ERC20Burnable_init();
        __Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init("Blockchain Monster Coin");
        __UUPSUpgradeable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
        _setupRole(UPGRADER_ROLE, msg.sender);
        _setupRole(MODERATOR_ROLE, msg.sender);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._burn(account, amount);
    }
}

interface IBlockchainMonster {
    function catchMonsterByBCMC(
        address sender,
        uint256 amount,
        uint256 blockNumber,
        uint256 blkSpecies,
        uint256 supportTokenId
    ) external;

    function battleMonsterByBCMC(
        address sender,
        uint256 amount,
        uint256 blockNumber,
        uint256 selectedMonId,
        uint256 d1,
        uint256 d2,
        bytes memory signature
    ) external;

    function portMonsterToken(
        address sender,
        uint256 monId,
        uint256 targetChainId,
        bytes memory signature
    ) external returns(uint256);
}

interface IBCMTrade {
    function executeTradeUsingBCMC(address buyer, uint256 tradeId, address seller, uint256 tokenId, uint256 currency, 
        uint256 price, uint256 deadline, bytes memory signature) external;
}

interface IBCMCPortalOut {
    function portBCMCToken(address owner, uint256 amount, uint256 targetChainId, 
        uint256 convertPercentage, bytes memory signature) external returns (uint256 fee);
}

contract BlockchainMonsterCoin is BlockchainMonsterCoinBase, ReentrancyGuardUpgradeable {
    uint256 public constant MAX_SUPPLY = 1000000000 * 10**18;

    uint256 public exchangeRate; // how many BCMC for 10000

    address public bcmERC721Contract;
    address public bcmTradeContract;

    address public bcmPortalOutContract;
    address public bcmPortalInContract;

    uint256 public maxBCMCPortConvertPercentage; // in percentage
    uint256 public maxBCMCPortConvertAmount; // in BCMC

    // event
    event AdminSet721Evt(address indexed sender, address value);
    event AdminSetTradeEvt(address indexed sender, address value);
    event AdminSetPortalEvt(address indexed sender, address portInValue, address portOutValue);
    event AdminSetExchangeRateEvt(address indexed sender, uint256 value);
    event AdminSetMaxBCMCPortConvert(address indexed sender, uint256 percentage, uint256 amount);

    modifier onlyNonContract {
        require(tx.origin == msg.sender, "only_non_contract_call");
        _;
    }

    function initialize() public initializer {
        BlockchainMonsterCoinBase.__BlockchainMonsterCoinBase_initialize();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init_unchained();
        exchangeRate = 100000; // 0.1 BCMC => 1 chain coin
        bcmERC721Contract = address(0);
        bcmTradeContract = address(0);
        maxBCMCPortConvertPercentage = 0;
    }

    // moderator
    // mint the token at the very beginning
    function initMint(address target, uint256 amount) 
        external
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(totalSupply() + amount <= MAX_SUPPLY, "exceed_max_supply");
        _mint(target, amount);
    }

    function setBCMERC721Contract(address value)
        external
        onlyRole(MODERATOR_ROLE)
    {
        bcmERC721Contract = value;
        emit AdminSet721Evt(msg.sender, value);
    }

    function setBCMTradeContract(address value)
        external
        onlyRole(MODERATOR_ROLE)
    {
        bcmTradeContract = value;
        emit AdminSetTradeEvt(msg.sender, value);
    }

    function setBCMPortalContracts(address inValue, address outValue) 
        external
        onlyRole(MODERATOR_ROLE)
    {
        bcmPortalInContract = inValue;
        bcmPortalOutContract = outValue;
        emit AdminSetPortalEvt(msg.sender, inValue, outValue);
    }

    function setExchangeRate(uint256 value) external onlyRole(MODERATOR_ROLE) {
        exchangeRate = value;
        emit AdminSetExchangeRateEvt(msg.sender, value);
    }

    function setMaxBCMCPortConvertPercentage(uint256 maxPercentage, uint256 maxAmount) external onlyRole(MODERATOR_ROLE) {
        require(maxPercentage <= 100, "invalid_percentage");
        maxBCMCPortConvertPercentage = maxPercentage;
        maxBCMCPortConvertAmount = maxAmount;
        emit AdminSetMaxBCMCPortConvert(msg.sender, maxPercentage, maxAmount);
    }   

    // using by portal contract
    function mintPortedToken(address target, uint256 amount) external {
        // only portal can call this function
        require(msg.sender == bcmPortalInContract, "invalid_sender");
        require(totalSupply() + amount <= MAX_SUPPLY, "exceed_max_supply");
        _mint(target, amount);
    }

    function cancelPortedToken(address target, uint256 amount, uint256 fee) external {
        // only portal can call this function
        require(msg.sender == bcmPortalOutContract, "invalid_portal_caller");
        require(totalSupply() + (amount - fee) <= MAX_SUPPLY, "exceed_max_supply");
        _mint(target, amount - fee);
        // transfer back the fee
        transfer(target, fee);
    }

    // public function
    function catchMonsterByBCMC(
        uint256 amount,
        uint256 blockNumber,
        uint256 blkSpecies,
        uint256 supportTokenId
    ) external virtual onlyNonContract whenNotPaused {
        require(bcmERC721Contract != address(0), "bcmrec721_required");
        IBlockchainMonster bcm = IBlockchainMonster(bcmERC721Contract);
        bcm.catchMonsterByBCMC(
            msg.sender,
            (amount * 10000) / exchangeRate,
            blockNumber,
            blkSpecies,
            supportTokenId
        );
        // deduct bcmc - it will be reverted if there is not enough amount
        transfer(bcmERC721Contract, amount);
    }

    function battleMonsterByBCMC(
        uint256 amount,
        uint256 blockNumber,
        uint256 selectedMonId,
        uint256 d1,
        uint256 d2,
        bytes memory signature
    ) external virtual onlyNonContract whenNotPaused {
        require(balanceOf(msg.sender) >= amount, "low_balance");
        require(bcmERC721Contract != address(0), "bcmrec721_required");
        IBlockchainMonster bcm = IBlockchainMonster(bcmERC721Contract);
        bcm.battleMonsterByBCMC(
            msg.sender,
            (amount * 10000) / exchangeRate,
            blockNumber,
            selectedMonId,
            d1,
            d2,
            signature
        );
        // deduct bcmc - it will be reverted if there is not enough amount
        transfer(bcmERC721Contract, amount);
    }


    function executeTradeByBCMC(uint256 tradeId, address seller, uint256 tokenId, uint256 currency, 
        uint256 price, uint256 deadline, bytes memory signature) external virtual whenNotPaused nonReentrant {
        require(balanceOf(msg.sender) >= price, "low_balance");
        require(bcmTradeContract != address(0), "bcmrec721_required");
        transfer(bcmTradeContract, price);

        IBCMTrade trade = IBCMTrade(bcmTradeContract);
        trade.executeTradeUsingBCMC(
            msg.sender,
            tradeId,
            seller,
            tokenId,
            currency,
            price,
            deadline,
            signature
        );
    }

    function portBCMCToken(uint256 amount, uint256 targetChainId, uint256 convertPercentage, bytes memory signature) external virtual whenNotPaused nonReentrant {
        require(convertPercentage <= maxBCMCPortConvertPercentage, "invalid_convert_percentage");
        require((amount * convertPercentage / 100) <= maxBCMCPortConvertAmount, "invalid_convert_amount");
        uint256 fee = IBCMCPortalOut(bcmPortalOutContract).portBCMCToken(msg.sender, amount, targetChainId, convertPercentage, signature);
        require(balanceOf(msg.sender) >= fee && balanceOf(msg.sender) >= amount, "low_balance");
        if (fee > 0) {
            require(amount - fee > 0, "zero_amount");
            transfer(bcmPortalOutContract, fee);
        }
        _burn(msg.sender, amount - fee);
    }

    function portMonsterToken(uint256 monId, uint256 targetChainId, bytes memory signature) external virtual whenNotPaused nonReentrant {
        uint fee = IBlockchainMonster(bcmERC721Contract).portMonsterToken(msg.sender, monId, targetChainId, signature);
        if (fee > 0) {
            transfer(bcmERC721Contract, fee);
        }
    }
}
