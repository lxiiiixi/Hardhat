// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFutureLimit {
    function createIncreaseOrder(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _notionalDelta,
        uint256 _sizeDelta,
        uint256 _execFee // in eth
    ) external payable returns (uint256);

    function updateIncreaseOrder(
        address _account,
        uint256 _orderIndex,
        uint256 _notionalDelta,
        uint256 _sizeDelta
    ) external;

    function cancelIncreaseOrder(
        address _account,
        uint256 _orderIndex,
        address _to,
        address payable _execFeeTo
    ) external;

    function execIncreaseOrder(
        address _account,
        uint256 _orderIndex,
        address payable _execFeeTo
    ) external;

    function createDecreaseOrder(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _notionalDelta,
        uint256 _minSizeDelta,
        uint256 _maxSizeDelta,
        uint256 _execFee
    ) external payable returns (uint256);

    function updateDecreaseOrder(
        address _account,
        uint256 _orderIndex,
        uint256 _notionalDelta,
        uint256 _minSizeDelta,
        uint256 _maxSizeDelta
    ) external;

    function cancelDecreaseOrder(
        address _account,
        uint256 _orderIndex,
        address payable _execFeeTo
    ) external;

    function execDecreaseOrder(
        address _account,
        uint256 _orderIndex,
        address _marginTo,
        address payable _execFeeTo
    ) external returns (uint256);

    function minExecFee() external view returns (uint256);

    function getIncreaseOrder(address _account, uint256 _orderIndex)
        external
        view
        returns (
            address collateralToken,
            address indexToken,
            address account,
            bool isLong,
            uint256 marginDelta,
            uint256 notionalDelta,
            uint256 sizeDelta,
            uint256 execFee
        );

    function getIncreaseOrderCollateralToken(address _account, uint256 _orderIndex)
        external
        view
        returns (address collateralToken);

    function getDecreaseOrder(address _account, uint256 _orderIndex)
        external
        view
        returns (
            address collateralToken,
            address indexToken,
            address account,
            bool isLong,
            uint256 notionalDelta,
            uint256 minSizeDelta,
            uint256 maxSizeDelta,
            uint256 execFee
        );

    function getDecreaseOrderCollateralToken(address _account, uint256 _orderIndex)
        external
        view
        returns (address collateralToken);

    function increaseOrderExecable(address account, uint256 orderIndex) external view returns(bool);

    function decreaseOrderExecable(address account, uint256 orderIndex) external view returns(bool);

    function validDecreaseOrderNotional(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _notionalDelta,
        bool _raise
    ) external view returns (bool);

    function validateIncreaseOrderPrice(
        address _account,
        uint256 _orderIndex,
        bool _raise
    ) external view returns (bool);

    function validateDecreaseOrderPrice(
        address _account,
        uint256 _orderIndex,
        bool _raise
    ) external view returns (bool takeProfitValid, bool stopLossValid);
}
