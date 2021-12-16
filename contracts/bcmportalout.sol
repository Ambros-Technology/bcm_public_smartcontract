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

contract BCMPortalOut is BCMUpgradable, IERC777RecipientUpgradeable {
    IERC1820RegistryUpgradeable internal constant _ERC1820_REGISTRY = IERC1820RegistryUpgradeable(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    struct PortData { 
        uint256 data;
        address sender;
        uint8 portType;
    }

    uint256 public total;
    mapping(uint256 => mapping(uint256 => PortData)) public processedPortData; // chainid => portid => data
    mapping(uint256 => uint256) public portalFees; // chainid => fee in BCMC
    mapping(uint256 => uint256) public portalBCMCRequirements; // chainid => value in BCMC
    mapping(uint256 => address) public portalAddresses; // chainid => bcmc portal address    

    // transport
    mapping(uint256 => address) public pTokenAddresses;
    mapping(uint256 => address) public vaultAddresses;
    mapping(uint256 => address) public transportTokenAddresses;
    mapping(uint256 => uint256) public transportTokenAmounts; // chainid => min transport Token

    address public bcmcERC20Contract;
    address public bcmERC721Contract;

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
        uint256 fee,
        uint256 requirement,
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
    event PortOutBCMCEvt(
        uint256 indexed portId,
        address indexed account,
        uint256 fromChainId,
        uint256 toChainId,
        uint256 amount,
        uint256 convertPercentage
    );
    event PortOutMonsterEvt(
        uint256 indexed portId,
        address indexed account,
        uint256 fromChainId,
        uint256 fromTokenId,
        uint256 toChainId
    );
    event PortOutCancelEvt(
        uint256 indexed portType,
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
        uint256 fee,
        uint256 requirement,
        address portalAddress
    ) external onlyRole(MODERATOR_ROLE) {
        portalFees[chainId] = fee; // in BCMC
        portalBCMCRequirements[chainId] = requirement; // in BCMC
        portalAddresses[chainId] = portalAddress;
        emit AdminSetPortalSettingsEvt(msg.sender, chainId, fee, requirement, portalAddress);
    }

    function setBCMContracts(address bcmcValue, address bcmValue) external onlyRole(MODERATOR_ROLE) {
        bcmcERC20Contract = bcmcValue;
        bcmERC721Contract = bcmValue;
        emit AdminSetBCMContractsEvt(msg.sender, bcmcValue, bcmValue);
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

    // only call by bcmc erc20
    function portBCMCToken(address owner, uint256 amount, uint256 targetChainId, uint256 convertPercentage, bytes memory signature) external whenNotPaused returns(uint256 fee) {
        // ensure only bcmcERC20Contract can call this
        require(msg.sender == bcmcERC20Contract, "invalid_caller");
        require(targetChainId != block.chainid, "port_same_chain");
        require(portalAddresses[targetChainId] != address(0), "invalid_portal_address");
        require(amount > portalFees[targetChainId], "invalid_amount");

        if (portalBCMCRequirements[targetChainId] > 0) {
            // require stacking BCMC
            require(IBCMCERC20(bcmcERC20Contract).balanceOf(owner) >= portalBCMCRequirements[targetChainId], "invalid_requirement");
        }

        total += 1; // port_type(1), port_id, current_chain_id, owner, data1 (transfer amount), data2 (convert percentage), signature
        bytes memory data = abi.encode(1, total, block.chainid, owner, amount - portalFees[targetChainId], convertPercentage, signature);
        
        if (vaultAddresses[targetChainId] != address(0)) {
            // case 1: vault and transport token
            require(transportTokenAddresses[targetChainId] != address(0), "invalid_transport_token_addr");
            IERC20 transportToken = IERC20(transportTokenAddresses[targetChainId]);
            require(transportToken.balanceOf(address(this)) >= transportTokenAmounts[targetChainId], "insufficient_transport_token");
            transportToken.approve(vaultAddresses[targetChainId], transportTokenAmounts[targetChainId]);
            bool result = IVault(vaultAddresses[targetChainId]).pegIn(transportTokenAmounts[targetChainId], transportTokenAddresses[targetChainId], Utils.toAsciiString(address(portalAddresses[targetChainId])), data);
            require(result == true, "vault_peg_in_fail");
        } else if (pTokenAddresses[targetChainId] != address(0)) {
            IPToken pToken = IPToken(pTokenAddresses[targetChainId]);
            require(pToken.balanceOf(address(this)) >= transportTokenAmounts[targetChainId], "insufficient_iptoken");
            // case 2: ptoken
            pToken.redeem(transportTokenAmounts[targetChainId], data, Utils.toAsciiString(portalAddresses[targetChainId]));
        } else {
            revert("no_setting");
        }

        processedPortData[targetChainId][total] = PortData(amount, owner, 1);
        emit PortOutBCMCEvt(total, owner, block.chainid, targetChainId, amount, convertPercentage);
        return portalFees[targetChainId];
    }

    // only call by bcm erc721
    function portMonsterToken(address owner, uint256 tokenId, uint256 tokenData, uint256 targetChainId, bytes memory signature) external whenNotPaused returns(uint256 fee) {
        // ensure only bcmERC721Contract can call this
        require(msg.sender == bcmERC721Contract, "invalid_caller");
        require(targetChainId != block.chainid, "port_same_chain");
        require(portalAddresses[targetChainId] != address(0), "invalid_portal_address");

        if (portalBCMCRequirements[targetChainId] > 0) {
            // require stacking BCMC
            require(IBCMCERC20(bcmcERC20Contract).balanceOf(owner) >= portalBCMCRequirements[targetChainId], "invalid_requirement");
        }

        total += 1; // port_type(2), port_id, current_chain_id, owner, data1, data2, signature
        bytes memory data = abi.encode(2, total, block.chainid, owner, tokenId, tokenData, signature);
        
        if (vaultAddresses[targetChainId] != address(0)) {
            // case 1: vault and transport token
            require(transportTokenAddresses[targetChainId] != (address(0)), "invalid_transport_token_addr");
            IERC20 transportToken = IERC20(transportTokenAddresses[targetChainId]);
            require(transportToken.balanceOf(address(this)) >= transportTokenAmounts[targetChainId], "insufficient_transport_token");
            transportToken.approve(vaultAddresses[targetChainId], transportTokenAmounts[targetChainId]);
            bool result = IVault(vaultAddresses[targetChainId]).pegIn(transportTokenAmounts[targetChainId], transportTokenAddresses[targetChainId], Utils.toAsciiString(portalAddresses[targetChainId]), data);
            require(result == true, "vault_peg_in_fail");
        } else if (pTokenAddresses[targetChainId] != address(0)) {
            IPToken pToken = IPToken(pTokenAddresses[targetChainId]);
            require(pToken.balanceOf(address(this)) >= transportTokenAmounts[targetChainId], "insufficient_iptoken");
            // case 2: ptoken
            pToken.redeem(transportTokenAmounts[targetChainId], data, Utils.toAsciiString(portalAddresses[targetChainId]));
        } else {
            revert("no_setting");
        }

        processedPortData[targetChainId][total] = PortData(tokenId, owner, 2);
        emit PortOutMonsterEvt(total, owner, block.chainid, tokenId, targetChainId);
        return portalFees[targetChainId];
    }

    // sigining for incoming cancel
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
        uint256 portId,
        uint256 fromChainId
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    keccak256(abi.encodePacked(portId, fromChainId))
                )
            );
    }

    function isValid(
        uint256 portId,
        uint256 fromChainId,
        bytes memory signature
    ) public view returns (bool) {
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        bytes32 messageHash = _getMessageHash(portId, fromChainId);
        return hasRole(SIGNER_ROLE, ecrecover(messageHash, v, r, s));
    }


    // call by ERC777 for cancel case
    function tokensReceived(
        address, /*_operator*/
        address _from,
        address, /*_to,*/
        uint256, /*_amount*/
        bytes calldata _userData,
        bytes calldata /*_operatorData*/
    ) external override whenNotPaused {
        if (_userData.length > 0) {
            (, bytes memory userData, , address originAddress) = abi.decode(_userData, (bytes1, bytes, bytes4, address));
            (uint256 portId, uint256 fromChainId, bytes memory signature) = abi.decode(userData, (uint256, uint256, bytes));
            require(isValid(portId, fromChainId, signature), "invalid_signer");
            PortData memory processedData = processedPortData[fromChainId][portId];
            require(portId > 0, "invalid_port_id");
            require(fromChainId != block.chainid, "port_same_chain");
            require(processedData.portType != 0, "port_id_not_exist");
            require(originAddress == portalAddresses[fromChainId], "invalid_org_address");

            if (vaultAddresses[fromChainId] != address(0)) {
                // case 1: vault & transport token
                require(transportTokenAddresses[fromChainId] != address(0), "invalid_transport_token_addr");
                require(msg.sender == transportTokenAddresses[fromChainId], "invalid_sender");
                require(_from == vaultAddresses[fromChainId], "invalid_from");
            } else if (pTokenAddresses[fromChainId] != address(0)) {
                // case 2: ptoken
                require(msg.sender == pTokenAddresses[fromChainId], "invalid_sender");
                require(_from == address(0), "invalid_from");
            } else {
                revert("invalid_settings");
            }

            // revert the change
            if (processedData.portType == 1) {
                // BCMC
                IBCMCERC20(bcmcERC20Contract).cancelPortedToken(processedData.sender, processedData.data, portalFees[fromChainId]);
                delete processedPortData[fromChainId][portId];
            } else if (processedData.portType == 2) {
                // BCM
                IBlockchainMonster(bcmERC721Contract).cancelPortedToken(processedData.sender, processedData.data, portalFees[fromChainId]);
                delete processedPortData[fromChainId][portId];
            } else {
                revert("invalid_port_type");
            }

            emit PortOutCancelEvt(processedData.portType, portId, fromChainId, block.chainid);
        }
    }

    receive() external payable {}
}