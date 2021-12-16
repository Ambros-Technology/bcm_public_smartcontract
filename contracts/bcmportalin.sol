// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

// import "hardhat/console.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./bcmupgradable.sol";
import "./utils.sol";
import "./bcmportalinterface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC777/IERC777RecipientUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC1820RegistryUpgradeable.sol";

contract BCMPortalIn is BCMUpgradable, IERC777RecipientUpgradeable {
    IERC1820RegistryUpgradeable internal constant _ERC1820_REGISTRY = IERC1820RegistryUpgradeable(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    bytes32 public constant CANCEL_ROLE = keccak256("CANCEL_ROLE");

    uint256 public total;
    mapping(uint256 => mapping(uint256 => uint256)) public processedPortIds; // chainid => portid => 0/1
    mapping(uint256 => address) public portalAddresses; // chainid => bcmc portal address    

    // transport
    mapping(uint256 => address) public pTokenAddresses;
    mapping(uint256 => address) public vaultAddresses;
    mapping(uint256 => address) public transportTokenAddresses;
    mapping(uint256 => uint256) public transportTokenAmounts; // chainid => min transport Token

    address public bcmcERC20Contract;
    address public bcmERC721Contract;

    uint256 public exchangeRate; // how many BCMC for 10000

    // event
    event AdminSetTransportSettingsEvt(
        address indexed sender,
        uint256 chainId,
        address pTokenAddress,
        address vaultAddress,
        address transportTokenAddress,
        uint256 transportTokenAmount
    );
    event AdminSetPortalSettingsEvt(
        address indexed sender,
        uint256 chainId,
        address portalAddress
    );
    event AdminSetBCMContractsEvt(
        address indexed sender,
        address erc20Value,
        address erc721Value
    );
    event AdminWithdrawEvt(
        address indexed sender, 
        address target,
        uint256 amount
    );
    event AdminWithdrawBCMCTokenEvt(
        address indexed sender,
        address target,
        uint256 amount
    );
    event AdminWithdrawTransportTokenEvt(
        address indexed sender,
        uint256 chainId,
        address target,
        uint256 amount
    );
    event AdminWithdrawPTokenEvt(
        address indexed sender,
        uint256 chainId,
        address target,
        uint256 amount
    );
    event AdminResetCancelPortEvt(
        address indexed sender,
        uint256 targetChainId, 
        uint256 portId
    );
    event AdminSetExchangeRateEvt(
        address indexed sender, 
        uint256 value
    );
    event PortInBCMCEvt(
        uint256 indexed portId,
        address indexed account,
        uint256 fromChainId,
        uint256 toChainId,
        uint256 bcmcAmount,
        uint256 nativeAmount
    );
    event PortInMonsterEvt(
        uint256 indexed portId,
        address indexed account,
        uint256 fromChainId,
        uint256 fromTokenId,
        uint256 toChainId,
        uint256 toTokenId
    );
    event PortInCancelEvt(
        uint256 indexed portId,
        uint256 fromChainId,
        uint256 toChainId
    );

    function initialize() public initializer {
        BCMUpgradable.__BCMUpgradable_initialize();
        // register interfaces
        __ERC777_init_unchained();
        total = 0;
        _setupRole(SIGNER_ROLE, msg.sender);
        _setupRole(CANCEL_ROLE, msg.sender);
    }

    function __ERC777_init_unchained() internal virtual initializer {
        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));
    }

    function setTransportSettings(
        uint256 chainId,
        address pTokenAddress,
        address vaultAddress,
        address transportTokenAddress,
        uint256 transportTokenAmount
    ) external onlyRole(MODERATOR_ROLE) {
        pTokenAddresses[chainId] = pTokenAddress;
        vaultAddresses[chainId] = vaultAddress;
        transportTokenAddresses[chainId] = transportTokenAddress;
        transportTokenAmounts[chainId] = transportTokenAmount;
        emit AdminSetTransportSettingsEvt(msg.sender, chainId, pTokenAddress, vaultAddress, transportTokenAddress, transportTokenAmount);
    }

    function setPortalSettings(
        uint256 chainId,
        address portalAddress
    ) external onlyRole(MODERATOR_ROLE) {
        portalAddresses[chainId] = portalAddress;
        emit AdminSetPortalSettingsEvt(msg.sender, chainId, portalAddress);
    }

    function setBCMContracts(address bcmcValue, address bcmValue) external onlyRole(MODERATOR_ROLE) {
        bcmcERC20Contract = bcmcValue;
        bcmERC721Contract = bcmValue;
        emit AdminSetBCMContractsEvt(msg.sender, bcmcValue, bcmValue);
    }

    function setExchangeRate(uint256 value) external onlyRole(MODERATOR_ROLE) {
        exchangeRate = value;
        emit AdminSetExchangeRateEvt(msg.sender, value);
    }

    // as this contract collects portal fee, so we can collect it
    function withdraw(address payable _sendTo, uint _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _sendTo.transfer(_amount);
        emit AdminWithdrawEvt(msg.sender, _sendTo, _amount);
    }

    function withdrawBCMCToken(address payable _sendTo, uint _amount) external onlyRole(DEFAULT_ADMIN_ROLE){
        IBCMCERC20(bcmcERC20Contract).transfer(_sendTo, _amount);
        emit AdminWithdrawBCMCTokenEvt(msg.sender, _sendTo, _amount);
    }

    function withdrawTransportToken(uint256 chainId, address payable _sendTo, uint _amount) external onlyRole(DEFAULT_ADMIN_ROLE){
        require(transportTokenAddresses[chainId] != address(0), "address_not_set");
        IERC20(transportTokenAddresses[chainId]).transfer(_sendTo, _amount);
        emit AdminWithdrawTransportTokenEvt(msg.sender, chainId, _sendTo, _amount);
    }

    function withdrawPToken(uint256 chainId, address payable _sendTo, uint _amount) external onlyRole(DEFAULT_ADMIN_ROLE){
        require(pTokenAddresses[chainId] != address(0), "address_not_set");
        IPToken(pTokenAddresses[chainId]).transfer(_sendTo, _amount);
        emit AdminWithdrawPTokenEvt(msg.sender, chainId, _sendTo, _amount);
    }

    function resetCancelPort(uint256 targetChainId, uint256 portId) external onlyRole(MODERATOR_ROLE){
        processedPortIds[targetChainId][portId] = 0;
        emit AdminResetCancelPortEvt(msg.sender, targetChainId, portId);
    }

    function cancelPort(uint256 targetChainId, uint256 portId, bytes memory signature) external onlyRole(CANCEL_ROLE) {
        require(processedPortIds[targetChainId][portId] == 0, "used_port_id");
        processedPortIds[targetChainId][portId] = 1;
        // type, portid, 
        bytes memory data = abi.encode(portId, block.chainid, signature);
        // trigger the origin side
        if (vaultAddresses[targetChainId] != address(0)) {
            // case 1: vault and transport token
            require(transportTokenAddresses[targetChainId] != address(0), "invalid_transport_token_addr");
            IERC20 transportToken = IERC20(transportTokenAddresses[targetChainId]);
            require(transportToken.balanceOf(address(this)) >= transportTokenAmounts[targetChainId], "insufficient_transport_token");
            transportToken.approve(vaultAddresses[targetChainId], transportTokenAmounts[targetChainId]);
            bool result = IVault(vaultAddresses[targetChainId]).pegIn(transportTokenAmounts[targetChainId], transportTokenAddresses[targetChainId], Utils.toAsciiString(address(portalAddresses[targetChainId])), data);
            require(result == true, "vault_peg_in_fail");
        } else if (pTokenAddresses[targetChainId] != address(0)) {
            // case 2: ptoken
            IPToken pToken = IPToken(pTokenAddresses[targetChainId]);
            require(pToken.balanceOf(address(this)) >= transportTokenAmounts[targetChainId], "insufficient_iptoken");
            pToken.redeem(transportTokenAmounts[targetChainId], data, Utils.toAsciiString(portalAddresses[targetChainId]));
        } else {
            revert("no_setting");
        }

        emit PortInCancelEvt(portId, block.chainid, targetChainId);
    }

    // signing for incoming porting request
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

    function _getMessageHash(
        uint256 portType,
        uint256 portId,
        uint256 fromChainId,
        address owner,
        uint256 data1,
        uint256 data2
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    keccak256(abi.encodePacked(portType, portId, fromChainId, owner, data1, data2))
                )
            );
    }

    function isValid(
        uint256 portType,
        uint256 portId,
        uint256 fromChainId,
        address owner,
        uint256 data1,
        uint256 data2,
        bytes memory signature
    ) public view returns (bool) {
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        bytes32 messageHash = _getMessageHash(portType, portId, fromChainId, owner, data1, data2);
        return hasRole(SIGNER_ROLE, ecrecover(messageHash, v, r, s));
    }

    // ERC777
    function tokensReceived(
        address, /*_operator*/
        address _from,
        address, /*_to,*/
        uint256, /*_amount*/
        bytes calldata _userData,
        bytes calldata /*_operatorData*/
    ) external override whenNotPaused {
        if (_userData.length > 0) {
            uint256 portType; 
            uint256 portId;
            uint256 fromChainId;
            address payable owner;
            uint256 data1;
            uint256 data2;
            {
                bytes memory signature;
                (, bytes memory userData, , address originAddress) = abi.decode(_userData, (bytes1, bytes, bytes4, address));    
                (portType, portId, fromChainId, owner, data1, data2, signature) = abi.decode(userData, (uint256, uint256, uint256, address, uint256, uint256, bytes));
                require(isValid(portType, portId, fromChainId, owner, data1, data2, signature), "invalid_signer");
                require(originAddress == portalAddresses[fromChainId], "invalid_org_address");
            }
            require(portId > 0, "invalid_port_id");
            require(owner != address(0), "invalid_owner");
            require(processedPortIds[fromChainId][portId] == 0, "used_port_id");
            require(fromChainId != block.chainid, "port_same_chain");

            if (vaultAddresses[fromChainId] != address(0)) {
                // case 1: vault & transport token
                require(transportTokenAddresses[fromChainId] != (address(0)), "invalid_transport_token_addr");
                require(msg.sender == transportTokenAddresses[fromChainId], "invalid_sender");
                require(_from == vaultAddresses[fromChainId], "invalid_from");
            } else if (pTokenAddresses[fromChainId] != address(0)) {
                // case 2: ptoken
                require(msg.sender == pTokenAddresses[fromChainId], "invalid_sender");
                require(_from == address(0), "invalid_from");
            } else {
                revert("invalid_settings");
            }

            // mark port id done
            processedPortIds[fromChainId][portId] = 1;
            if (portType == 1) {
                // BCMC
                if (data2 > 0) {
                    require(data2 <= 100, "invalid_convert_percentage");
                    require(exchangeRate > 0, "invalid_exchange_rate");
                    uint convert = data1 * data2 / 100;
                    IBCMCERC20(bcmcERC20Contract).mintPortedToken(owner, data1 - convert);
                    // transfer converted value to the native chain token
                    convert = (convert * 10000) / exchangeRate;
                    owner.transfer(convert);
                } else {
                    IBCMCERC20(bcmcERC20Contract).mintPortedToken(owner, data1);
                    emit PortInBCMCEvt(portId, owner, fromChainId, block.chainid, data1, 0);
                }
            } else if (portType == 2) {
                // BCM
                uint256 tokenId = IBlockchainMonster(bcmERC721Contract).mintPortedToken(owner, data1, data2);
                emit PortInMonsterEvt(portId, owner, fromChainId, data1, block.chainid, tokenId);
            } else {
                revert("invalid_port_type");
            }
        }
    }

    receive() external payable {}
}