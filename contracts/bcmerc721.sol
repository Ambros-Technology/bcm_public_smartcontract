// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

// import "hardhat/console.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";

contract BlockchainMonsterBase is
    Initializable,
    ERC721Upgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ERC721BurnableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 public constant PARTNER_CONTRACT_ROLE =
        keccak256("PARTNER_CONTRACT_ROLE");

    function __BlockchainMonsterBase_initialize() public initializer {
        __ERC721_init("Blockchain Monster", "BCM");
        __Pausable_init();
        __AccessControl_init();
        __ERC721Burnable_init();
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
        uint256 tokenId
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

interface IBCMSettings {
    // return 0 if uncatchable
    function genGene(
        address sender,
        uint256 amount,
        uint256 blockNumber,
        uint256 current_count,
        uint256 blk_species,
        uint256 support_type,
        uint256 support_exp
    ) external returns (uint256 gene);

    function genBattle(
        address sender,
        uint256 amount,
        uint256 monId,
        uint256 blockNumber,
        uint256 d1,
        uint256 d2,
        bytes memory signature
    ) external returns (uint256 result, uint256 bcmc);
}

interface IBCMCPortalOut {
    function portMonsterToken(
        address owner, 
        uint256 tokenId, 
        uint256 tokenData, 
        uint256 targetChainId,
        bytes memory signature
    ) external returns(uint256 fee);
}

contract BlockchainMonster is BlockchainMonsterBase, EIP712Upgradeable {
    // solhint-disable-next-line var-name-mixedcase
    bytes32 private _PERMIT_TYPEHASH;
    
    string public baseURI;
    uint256 public total;
    mapping(uint256 => uint256) public monsters; // tokenid => monster gene
    mapping(uint256 => uint256) public blockMonCount; // block number => count
    mapping(address => mapping(uint256 => bool)) public markedUsedPermit;

    // data contract
    address public bcmSettingsContract;
    address public bcmcERC20Contract;
    address public bcmPortalOutContract;
    address public bcmPortalInContract;

    // extra info
    uint8 public internalChainId;

    // event
    event AdminSetDependentContracts(
        address indexed sender,
        address settingContract,
        address erc20Contract
    );
    event AdminSetPortalEvt(
        address indexed sender, 
        address portInValue, 
        address portOutValue
    );
    event AdminSetInternalChainIdEvt(
        address indexed sender, 
        uint8 value
    );
    event AdminWithdrawEvt(
        address indexed sender, 
        address target,
        uint256 amount
    );
    event AdminWithdrawTokenEvt(
        address indexed sender,
        address target,
        uint256 amount
    );
    event CatchMonsterEvt(
        address indexed account,
        uint256 indexed tokenId,
        uint256 catchBlockNo,
        uint256 gene
    );
    event BattleMonsterEvt(
        address indexed account,
        uint256 result,
        uint256 bcmc,
        uint256 catchBlockNo
    );
    event MonsterGeneUpdateEvt(address indexed tokenId, uint256 gene);
    event CancelPermitTradeEvt(address indexed owner, uint256 indexed permitId);

    modifier onlyBCMC() {
        require(
            bcmcERC20Contract != address(0) && msg.sender == bcmcERC20Contract
        );
        _;
    }

    modifier onlyNonContract {
        require(tx.origin == msg.sender, "only_non_contract_call");
        _;
    }

    function initialize() public initializer {
        BlockchainMonsterBase.__BlockchainMonsterBase_initialize();
         __EIP712_init_unchained("Blockchain Monsters", "1");
        _PERMIT_TYPEHASH = keccak256("PermitTrade(address owner,address target,uint256 tokenId,uint256 permitId,uint256 currency,uint256 price,uint256 deadline)");

        baseURI = "https://bcmhunt.com/erc/721/monster/";
    }

    // moderator
    function setDepContracts(address settingContract, address erc20Contract)
        external
        onlyRole(MODERATOR_ROLE)
    {
        bcmSettingsContract = settingContract;
        bcmcERC20Contract = erc20Contract;
        emit AdminSetDependentContracts(msg.sender, settingContract, erc20Contract);
    }

    function setBCMPortalContracts(address inValue, address outValue) 
        external
        onlyRole(MODERATOR_ROLE)
    {
        bcmPortalInContract = inValue;
        bcmPortalOutContract = outValue;
        emit AdminSetPortalEvt(msg.sender, inValue, outValue);
    }

    function setBaseUri(string memory uri) external onlyRole(MODERATOR_ROLE) {
        baseURI = uri;
    }

    function setInternalChainId(uint8 value) external onlyRole(MODERATOR_ROLE) {
        internalChainId = value;
        emit AdminSetInternalChainIdEvt(msg.sender, value);
    }

    function withdraw(address payable _sendTo, uint _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _sendTo.transfer(_amount);
        emit AdminWithdrawEvt(msg.sender, _sendTo, _amount);
    }

    function withdrawToken(address payable _sendTo, uint _amount) external onlyRole(DEFAULT_ADMIN_ROLE){
        IERC20Upgradeable token = IERC20Upgradeable(bcmcERC20Contract);
        token.transfer(_sendTo, _amount);
        emit AdminWithdrawTokenEvt(msg.sender, _sendTo, _amount);
    }

    // internal
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function _catchMonster(
        address sender,
        uint256 amount,
        uint256 blockNumber,
        uint256 blkSpecies,
        uint256 supportTokenId
    ) internal virtual {
        // check support ownership
        uint256 supportGene = 0;
        if (supportTokenId > 0) {
            require(ownerOf(supportTokenId) == sender, "not_support_owner");
            supportGene = monsters[supportTokenId];
        }

        // catch condition is checked in catch contract
        IBCMSettings settingManager = IBCMSettings(bcmSettingsContract);
        uint256 gene = settingManager.genGene(
            sender,
            amount,
            blockNumber,
            blockMonCount[blockNumber],
            blkSpecies,
            uint256(uint8(supportGene >> 144)),
            uint256(uint32(supportGene >> 56))
        );
        if (gene > 0) {
            total += 1;
            // generate token id from chain id
            uint256 tokenId = internalChainId;
            tokenId |= total << 8;
            monsters[tokenId] = gene;
            blockMonCount[blockNumber] += 1;
            _safeMint(sender, tokenId);
            emit CatchMonsterEvt(sender, tokenId, blockNumber, gene);
        } else {
            emit CatchMonsterEvt(sender, 0, blockNumber, 0);
        }
    }

    function _battleMonster(
        address sender,
        uint256 amount,
        uint256 blockNumber,
        uint256 selectedMonId,
        uint256 d1,
        uint256 d2,
        bytes memory signature
    ) internal virtual {
        require(_exists(selectedMonId), "not_exist");
        require(ownerOf(selectedMonId) == sender, "invalid_owner");

        IBCMSettings settingManager = IBCMSettings(bcmSettingsContract);
        (uint256 result, uint256 bcmc) = settingManager.genBattle(
            sender,
            amount,
            selectedMonId,
            blockNumber,
            d1,
            d2,
            signature
        );

        if (uint32(result >> 128) == 1) {
            _burn(selectedMonId);
        } else {
            monsters[selectedMonId] += uint256(uint32(result >> 160)) << 56;
        }

        if (bcmc > 0) {
            IERC20Upgradeable(bcmcERC20Contract).transfer(sender, bcmc);
        }

        emit BattleMonsterEvt(sender, result, bcmc, blockNumber);
    }

    function _splitSignature(bytes memory sig)
        internal
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "invalid_signature");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    // only trade contract can call it
    function permitTrade(
        address owner, 
        address target, 
        uint256 tokenId,
        uint256 permitId,
        uint256 currency,
        uint256 price, 
        uint256 deadline, 
        bytes memory signature
    ) external virtual onlyRole(PARTNER_CONTRACT_ROLE) {
        require(ownerOf(tokenId) == owner, "invalid_owner");
        require(markedUsedPermit[owner][permitId] == false, "used_permit");
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        require(deadline == 0 || block.timestamp <= deadline, "expired_deadline");
        bytes32 hash = _hashTypedDataV4(keccak256(abi.encode(_PERMIT_TYPEHASH, owner, target, tokenId, permitId, currency, price, deadline)));
        require(ECDSAUpgradeable.recover(hash, v, r, s) == owner, "invalid_signature");
        _approve(target, tokenId);
        markedUsedPermit[owner][permitId] = true;
    }

    // used by bcmc contract only
    function catchMonsterByBCMC(
        address sender,
        uint256 amount,
        uint256 blockNumber,
        uint256 blkSpecies,
        uint256 supportTokenId
    ) external virtual whenNotPaused onlyBCMC {
        _catchMonster(sender, amount, blockNumber, blkSpecies, supportTokenId);
    }

    function battleMonsterByBCMC(
        address sender,
        uint256 amount,
        uint256 blockNumber,
        uint256 selectedMonId,
        uint256 d1,
        uint256 d2,
        bytes memory signature
    ) external virtual whenNotPaused onlyBCMC {
        _battleMonster(
            sender,
            amount,
            blockNumber,
            selectedMonId,
            d1,
            d2,
            signature
        );
    }

    function portMonsterToken(
        address sender,
        uint256 monId,
        uint256 targetChainId,
        bytes memory signature
    ) external virtual whenNotPaused onlyBCMC returns(uint256 fee) {
        require(_exists(monId), "not_exist");
        require(ownerOf(monId) == sender, "invalid_owner");
        fee = IBCMCPortalOut(bcmPortalOutContract).portMonsterToken(sender, monId, monsters[monId], targetChainId, signature);
        _burn(monId);
    }

    // using by portal contract
    function mintPortedToken(address target, uint256 tokenId, uint256 tokenData) external returns(uint256) {
        // only portal can call this function
        require(msg.sender == bcmPortalInContract, "invalid_portal_caller");
        monsters[tokenId] = tokenData;
        _safeMint(target, tokenId);
        return tokenId;
    }

    function cancelPortedToken(address target, uint256 tokenId, uint256 fee) external {
        // only portal can call this function
        require(msg.sender == bcmPortalOutContract, "invalid_portal_caller");
        _safeMint(target, tokenId);
        // transfer back the fee
        IERC20Upgradeable token = IERC20Upgradeable(bcmcERC20Contract);
        token.transfer(target, fee);
    }


    // public
    receive() external payable {}

    function cancelPermitTrade(uint256 permitId) external virtual {
        markedUsedPermit[msg.sender][permitId] = true;
        emit CancelPermitTradeEvt(msg.sender, permitId);
    }

    function catchMonster(
        uint256 blockNumber,
        uint256 blkSpecies,
        uint256 supportTokenId
    ) external payable virtual onlyNonContract whenNotPaused {
        _catchMonster(
            msg.sender,
            msg.value,
            blockNumber,
            blkSpecies,
            supportTokenId
        );
    }

    function battleMonster(
        uint256 blockNumber,
        uint256 selectedMonId,
        uint256 d1,
        uint256 d2,
        bytes memory signature
    ) external payable virtual onlyNonContract whenNotPaused {
        _battleMonster(
            msg.sender,
            msg.value,
            blockNumber,
            selectedMonId,
            d1,
            d2,
            signature
        );
    }

    // read function
    function getMonsterBasic(uint256 tokenId)
        external
        view
        returns (
            uint8 kind,
            uint64 blockNumber,
            uint32 species,
            uint8 primary_type,
            uint8 secondary_type
        )
    {
        uint256 data = monsters[tokenId];
        kind = uint8(data >> 248);
        blockNumber = uint64(data >> 184);
        species = uint32(data >> 152);
        primary_type = uint8(data >> 144);
        secondary_type = uint8(data >> 136);
    }

    function getMonsterStas(uint256 tokenId)
        external
        view
        returns (
            uint8 hp,
            uint8 atk,
            uint8 def,
            uint8 spa,
            uint8 spd,
            uint8 sp,
            uint32 exp
        )
    {
        uint256 data = monsters[tokenId];
        hp = uint8(data >> 128);
        atk = uint8(data >> 120);
        def = uint8(data >> 112);
        spa = uint8(data >> 104);
        spd = uint8(data >> 96);
        sp = uint8(data >> 88);
        exp = uint32(data >> 56);
    }

    function getMonsterExp(uint256 tokenId) external view returns (uint32 exp) {
        exp = uint32(monsters[tokenId] >> 56);
    }
}
