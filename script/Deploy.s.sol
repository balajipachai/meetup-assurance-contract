// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MeetupAssurance} from "../src/MeetupAssurance.sol";

/// @notice Deploys a MeetupAssurance campaign. Terms come from the environment:
///         BENEFICIARY, TARGET_WEI, DURATION_SECONDS. The signer is supplied on the CLI
///         via `--account <keystore>`; no key is read from or written to any file.
contract Deploy is Script {
    function run() external returns (MeetupAssurance campaign) {
        address beneficiary = vm.envAddress("BENEFICIARY");
        uint256 target = vm.envUint("TARGET_WEI");
        uint256 duration = vm.envUint("DURATION_SECONDS");

        vm.startBroadcast();
        campaign = new MeetupAssurance(beneficiary, target, block.timestamp + duration);
        vm.stopBroadcast();

        console.log("MeetupAssurance deployed at", address(campaign));
    }
}
