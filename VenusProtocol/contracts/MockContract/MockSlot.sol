
pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

contract CustomMinERC1967Proxy {
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address implement) public {
        require(implement != address(0),"zero implement");
        assembly {
            sstore(_IMPLEMENTATION_SLOT,implement)
        }
    }

    function updateTo(address implement) external {
        assembly {
            sstore(_IMPLEMENTATION_SLOT,implement)
        }
    }

    function () external payable {
        assembly {
            let implementation := sload(_IMPLEMENTATION_SLOT)
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}

contract MockSlot {
    struct WithdrawalRequest {
        uint256 amount;
        uint256 lockedUntil;
    } 
    mapping(uint => WithdrawalRequest[]) internal requests;

    function setRequest(WithdrawalRequest memory request, uint index) public {
        requests[index].push(request);
    }

    function getRequest(uint index) external view returns(WithdrawalRequest[] memory) {
        return requests[index];
    }
}

contract MockSlotNew {
    struct WithdrawalRequest {
        uint256 amount;
        uint128 lockedUntil;
        uint128 afterUpgrade;
    } 
    mapping(uint => WithdrawalRequest[]) internal requests;

    function setRequest(WithdrawalRequest memory request, uint index) public {
        requests[index].push(request);
    }

    function getRequest(uint index) external view returns(WithdrawalRequest[] memory) {
        return requests[index];
    }
}