// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

library Commands {
    bytes1 internal constant SWAP = 0x00;
    bytes1 internal constant MODIFY = 0x01;
    bytes1 internal constant DONATE = 0x02;
    bytes1 internal constant TAKE = 0x03;
    bytes1 internal constant MINT = 0x04;
}
