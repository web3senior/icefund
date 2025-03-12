// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

event Log(string message);
event FeeUpdated(uint256);
event Locked(address indexed token, uint256 amount, uint256 expiration, address indexed locker  ,uint256 dt);
event UnLocked(address indexed token, uint256 amount, uint256 expiration, address indexed locker  ,uint256 dt);