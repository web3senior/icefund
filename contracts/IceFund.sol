// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {_LSP4_TOKEN_TYPE_TOKEN, _LSP4_TOKEN_TYPE_COLLECTION, _LSP4_METADATA_KEY} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import {ILSP8IdentifiableDigitalAsset as ILSP8} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/ILSP8IdentifiableDigitalAsset.sol";
import {LSP8IdentifiableDigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAsset.sol";
import {ILSP7DigitalAsset as ILSP7} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/ILSP7DigitalAsset.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./Event.sol";
import "./Error.sol";

/// @title IceFund
/// @author Aratta Labs
/// @notice A contract for managing the IceFund, enabling locking LSP7, and minting dynamic NFT.
/// @dev Deployed contract addresses are available in the project repository.
/// @custom:emoji 🧊
/// @custom:security-contact atenyun@gmail.com
contract IceFund is LSP8IdentifiableDigitalAsset("ICEFUND", "ICF", msg.sender, _LSP4_TOKEN_TYPE_COLLECTION, _LSP4_TOKEN_TYPE_TOKEN), Pausable {
    using Counters for Counters.Counter;
    Counters.Counter public _lockCounter;

    uint8 public fee;
    string failedMessage = "Failed to send Ether!";

    struct LockStruct {
        bytes32 tokenId;
        address token;
        uint256 amount;
        uint256 expiration;
        uint256 dt;
    }

    mapping(address => LockStruct[]) public lockPool;

    constructor() {}

    /// @notice Update fee
    /// @dev Fee can be 0-100
    /// @param _fee new value
    function updateFee(uint8 _fee) public onlyOwner {
        assert(fee < 100);
        fee = _fee;
        emit FeeUpdated(_fee);
    }

    function getLockerPool(address locker) public view returns (uint256 len, LockStruct[] memory data) {
        return (lockPool[locker].length, lockPool[locker]);
    }

    /// @notice Create verifiable metadata for the LSP8 standard
    function getMetadata(string memory metadata) public pure returns (bytes memory) {
        bytes memory verfiableURI = bytes.concat(hex"00006f357c6a0020", keccak256(bytes(metadata)), abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(metadata))));
        return verfiableURI;
    }

    ///@notice Luck
    function lock(
        address token,
        uint256 amount,
        uint256 expiration,
        string memory metadata
    ) public payable whenNotPaused returns (bool) {
        // Assert that expiration is grather than zero
        assert(expiration > 0);

        // Check if the price is not zero otherwise just trnasfer the token with no fee
        uint256 authorizedAmount = ILSP7(token).authorizedAmountFor(address(this), _msgSender());
        if (authorizedAmount < amount) revert NotAuthorizedAmount(amount, authorizedAmount);

        ILSP7(token).transfer(_msgSender(), address(this), amount, true, "");

        if (fee > 0) {
            if (msg.value < fee) revert InsufficientBalance(msg.value);
            (bool success, ) = owner().call{value: msg.value}("");
            require(success, failedMessage);
        }

        // Mint
        _lockCounter.increment();
        bytes32 tokenId = bytes32(_lockCounter.current());
        _mint({to: _msgSender(), tokenId: tokenId, force: true, data: ""});

        // Set data
        _setDataForTokenId(tokenId, _LSP4_METADATA_KEY, getMetadata(metadata));

        lockPool[_msgSender()].push(LockStruct(bytes32(_lockCounter.current()), token, amount, (expiration * 1 days) + block.timestamp, block.timestamp));

        // Log
        emit Locked(token, amount, (expiration * 1 days) + block.timestamp, _msgSender(), block.timestamp);
        return true;
    }

    /// @notice Unlock
    ///@param tokenId Token Id in bytes32
    ///@return bool
    function unlock(bytes32 tokenId) public whenNotPaused returns (bool) {
        // Check if sender is the owner of the token
        if (tokenOwnerOf(tokenId) != _msgSender()) revert Unauthorized();

        bool found = false;
        for (uint256 i = 0; i < lockPool[_msgSender()].length; i++) {
            if (lockPool[_msgSender()][i].tokenId == tokenId) {
                found = true;
                require(lockPool[_msgSender()][i].expiration < block.timestamp, "Too early");
                _burn(tokenId, "");
                ILSP7(lockPool[_msgSender()][i].token).transfer(address(this), _msgSender(), lockPool[_msgSender()][i].amount, true, "");

                // remove
                if (lockPool[_msgSender()].length > i + 1) lockPool[_msgSender()][i] = lockPool[_msgSender()][i + 1];

                // Decrement counter
                _lockCounter.decrement();

                emit UnLocked(lockPool[_msgSender()][i].token, lockPool[_msgSender()][i].amount, lockPool[_msgSender()][i].expiration, _msgSender(), block.timestamp);
            }
        }

        if (found) lockPool[_msgSender()].pop();

        return true;
    }

    function lsp7AuthorizedAmountFor(address token) public view returns (uint256) {
        return ILSP7(token).authorizedAmountFor(address(this), msg.sender);
    }

    function lsp7Balance(address token) public view onlyOwner returns (uint256) {
        return ILSP7(token).balanceOf(address(this));
    }

    ///@notice calcPercentage percentage
    ///@param _amount The total amount
    ///@param _bps The precentage
    ///@return percentage %
    function calcPercentage(uint256 _amount, uint256 _bps) public pure returns (uint256) {
        if (_bps == 0) return 0;
        require((_amount * _bps) >= 100);
        return (_amount * _bps) / 100;
    }

    ///@notice Withdraw LSP7 token
    function withdrawToken(
        address _token,
        address _to,
        uint256 _amount,
        bool _force,
        bytes memory _data
    ) public onlyOwner {
        ILSP7(_token).transfer(address(this), _to, _amount, _force, _data);
    }

    ///@notice Withdraw the balance from this contract to the owner's address
    function withdraw() public onlyOwner {
        uint256 amount = address(this).balance;
        (bool success, ) = owner().call{value: amount}("");
        require(success, "Failed to send Ether");
    }

    ///@notice Transfer balance from this contract to input address
    function transferBalance(address payable _to, uint256 _amount) public onlyOwner {
        // Note that "to" is declared as payable
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "Failed to send Ether");
    }

    /// @notice Return the balance of this contract
    function getBalance() public view onlyOwner returns (uint256) {
        return address(this).balance;
    }

    /// @notice Pause mint
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpause mint
    function unpause() public onlyOwner {
        _unpause();
    }

    function getNow() public view returns (uint256) {
        return block.timestamp;
    }
}
