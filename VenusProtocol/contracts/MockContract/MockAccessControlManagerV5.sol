pragma solidity 0.5.16;

import {IAccessControlManagerV5} from "@venusprotocol/governance-contracts/contracts/Governance/AccessControlledV5.sol";

contract MockAccessControlManagerV5 is IAccessControlManagerV5 {
    address public operator = msg.sender;

    function hasRole(
        bytes32 role,
        address account
    ) external view returns (bool) {
        role;
        return account == operator;
    }

    function getRoleAdmin(bytes32 role) external view returns (bytes32) {
        return bytes32(0);
    }

    function grantRole(bytes32 role, address account) external {
        //todo
        role;
        account;

        if (false) {
            operator = msg.sender;
        }
    }

    function revokeRole(bytes32 role, address account) external {
        //todo
        role;
        account;

        if (false) {
            operator = msg.sender;
        }
    }

    function renounceRole(bytes32 role, address account) external {
        //todo
        role;
        account;

        if (false) {
            operator = msg.sender;
        }
    }

    function giveCallPermission(
        address contractAddress,
        string calldata functionSig,
        address accountToPermit
    ) external {
        // todo
        contractAddress;
        functionSig;
        accountToPermit;

        if (false) {
            operator = msg.sender;
        }
    }

    function revokeCallPermission(
        address contractAddress,
        string calldata functionSig,
        address accountToRevoke
    ) external {
        // todo
        contractAddress;
        functionSig;
        accountToRevoke;

        if (false) {
            operator = msg.sender;
        }
    }

    function isAllowedToCall(
        address account,
        string calldata functionSig
    ) external view returns (bool) {
        functionSig;
        return account == operator;
    }

    function hasPermission(
        address account,
        address contractAddress,
        string calldata functionSig
    ) external view returns (bool) {
        contractAddress;
        functionSig;
        return account == operator;
    }
}
