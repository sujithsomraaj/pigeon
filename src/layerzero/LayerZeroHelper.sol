// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./lib/LZPacket.sol";

interface ILayerZeroEndpoint {
    function receivePayload(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        address _dstAddress,
        uint64 _nonce,
        uint256 _gasLimit,
        bytes calldata _payload
    ) external;

    function estimateFees(
        uint16 _dstChainId,
        address _userApplication,
        bytes calldata _payload,
        bool _payInZRO,
        bytes calldata _adapterParam
    ) external returns (uint256 nativeFee, uint256 zroFee);
}

contract LayerZeroHelper is Test {
    // hardcoded defaultLibrary on ETH and Packet event selector
    function help(address endpoint, uint256 gasToSend, uint256 forkId, Vm.Log[] calldata logs) external {
        _help(
            endpoint,
            0x4D73AdB72bC3DD368966edD0f0b2148401A178E2,
            gasToSend,
            0xe9bded5f24a4168e4f3bf44e00298c993b22376aad8c58c7dda9718a54cbea82,
            forkId,
            logs,
            false
        );
    }

    function help(
        address endpoint,
        address defaultLibrary,
        uint256 gasToSend,
        bytes32 eventSelector,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        _help(endpoint, defaultLibrary, gasToSend, eventSelector, forkId, logs, false);
    }

    // hardcoded defaultLibrary on ETH and Packet event selector
    function helpWithEstimates(address endpoint, uint256 gasToSend, uint256 forkId, Vm.Log[] calldata logs) external {
        bool enableEstimates = vm.envOr("ENABLE_ESTIMATES", false);
        _help(
            endpoint,
            0x4D73AdB72bC3DD368966edD0f0b2148401A178E2,
            gasToSend,
            0xe9bded5f24a4168e4f3bf44e00298c993b22376aad8c58c7dda9718a54cbea82,
            forkId,
            logs,
            enableEstimates
        );
    }

    function helpWithEstimates(
        address endpoint,
        address defaultLibrary,
        uint256 gasToSend,
        bytes32 eventSelector,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        bool enableEstimates = vm.envOr("ENABLE_ESTIMATES", false);
        _help(endpoint, defaultLibrary, gasToSend, eventSelector, forkId, logs, enableEstimates);
    }

    function _help(
        address endpoint,
        address defaultLibrary,
        uint256 gasToSend,
        bytes32 eventSelector,
        uint256 forkId,
        Vm.Log[] memory logs,
        bool enableEstimates
    ) internal {
        uint256 prevForkId = vm.activeFork();
        vm.selectFork(forkId);
        // larps as default library
        vm.startBroadcast(defaultLibrary);
        for (uint256 i; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            // unsure if the default library always emits the event
            if ( /*log.emitter == defaultLibrary &&*/ log.topics[0] == eventSelector) {
                bytes memory payload = abi.decode(log.data, (bytes));
                LayerZeroPacket.Packet memory packet = LayerZeroPacket.getPacket(payload);

                _receivePayload(endpoint, packet, gasToSend, enableEstimates);
            }
        }
        vm.stopBroadcast();
        vm.selectFork(prevForkId);
    }

    function _estimateGas(
        address endpoint,
        uint16 destination,
        address userApplication,
        bytes memory payload,
        bool payInZRO,
        bytes memory adapterParam
    ) internal returns (uint256 gasEstimate) {
        (uint256 nativeGas,) =
            ILayerZeroEndpoint(endpoint).estimateFees(destination, userApplication, payload, payInZRO, adapterParam);
        return nativeGas;
    }

    function _receivePayload(
        address endpoint,
        LayerZeroPacket.Packet memory packet,
        uint256 gasToSend,
        bool enableEstimates
    ) internal {
        bytes memory path = abi.encodePacked(packet.srcAddress, packet.dstAddress);
        vm.store(
            address(endpoint),
            keccak256(abi.encodePacked(path, keccak256(abi.encodePacked(uint256(packet.srcChainId), uint256(5))))),
            bytes32(uint256(packet.nonce))
        );

        ILayerZeroEndpoint(endpoint).receivePayload(
            packet.srcChainId, path, packet.dstAddress, packet.nonce + 1, gasToSend, packet.payload
        );

        if (enableEstimates) {
            uint256 gasEstimate =
                _estimateGas(endpoint, packet.dstChainId, packet.dstAddress, packet.payload, false, "");
            emit log_named_uint("gasEstimate", gasEstimate);
        }
    }
}
