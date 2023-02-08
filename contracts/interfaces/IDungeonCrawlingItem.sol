// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../../shared/IERC1155OnChainUpgradeable.sol";

interface IDungeonCrawlingItem is IERC1155OnChainUpgradeable {
    function mint(address _to, uint256 _id, uint256 _amount) external;

    function mintBatch(address _to, uint256[] calldata _ids, uint256[] calldata _amounts) external;

    function burn(address _from, uint256 _id, uint256 _amount) external;

    function burnBatch(address _from, uint256[] calldata _ids, uint256[] calldata _amount) external;

    function noApprovalSafeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount) external;

    function noApprovalSafeBatchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _amounts) external;
}