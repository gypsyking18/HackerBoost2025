// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MockV3Aggregator} from "../test/mock/MockV3Aggregator.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

abstract contract CodeConstants {
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000e8;

    /*//////////////////////////////////////////////////////////////
                               CHAIN IDS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
    uint256 constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;
}

contract HelperConfig is CodeConstants, Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        address priceFeed;
        address usdcAddress;
        uint256 campaignIdCounter;
        uint256 initialVotingDuration;
        address payable _ethPoolAddress;
        address _usdcPoolAddress;
        uint256 _campaignDuration;
        address daoAddress;
    }

    NetworkConfig public activeNetworkConfig;
    mapping(uint256 => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        networkConfigs[ETH_MAINNET_CHAIN_ID] = getMainnetEthConfig();
        networkConfigs[ARBITRUM_SEPOLIA_CHAIN_ID] = getSepoliaArbConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function setConfig(uint256 chainId, NetworkConfig memory networkConfig) public {
        networkConfigs[chainId] = networkConfig;
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].priceFeed != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getMainnetEthConfig() public pure returns (NetworkConfig memory mainnetNetworkConfig) {
        mainnetNetworkConfig = NetworkConfig({
            priceFeed: 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4,
            usdcAddress: 0xB7489f4d000F30410f75b7FD7a03e3F27c6268b6,
            campaignIdCounter: 0,
            initialVotingDuration: 13 * 24 * 60 * 60, // 13 days in seconds
            _ethPoolAddress: payable(0xB7489f4d000F30410f75b7FD7a03e3F27c6268b6),
            _usdcPoolAddress: 0xA3915e59148c67AAaE39F5D73Bb49fdd22C00124,
            _campaignDuration: 120 * 24 * 60 * 60, // 120 days in seconds
            daoAddress: 0x095418A82BC2439703b69fbE1210824F2247D77c
        });
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            priceFeed: 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4,
            usdcAddress: 0xB7489f4d000F30410f75b7FD7a03e3F27c6268b6,
            campaignIdCounter: 0,
            initialVotingDuration: 13 * 24 * 60 * 60, // 13 days in seconds
            _ethPoolAddress: payable(0xB7489f4d000F30410f75b7FD7a03e3F27c6268b6),
            _usdcPoolAddress: 0xA3915e59148c67AAaE39F5D73Bb49fdd22C00124,
            _campaignDuration: 120 * 24 * 60 * 60, // 120 days in seconds
            daoAddress: 0x095418A82BC2439703b69fbE1210824F2247D77c
        });
    }

    function getSepoliaArbConfig() public pure returns (NetworkConfig memory arbNetworkConfig) {
        arbNetworkConfig = NetworkConfig({
            priceFeed: 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4,
            usdcAddress: 0xB7489f4d000F30410f75b7FD7a03e3F27c6268b6,
            campaignIdCounter: 0,
            initialVotingDuration: 13 * 24 * 60 * 60, // 13 days in seconds
            _ethPoolAddress: payable(0xB7489f4d000F30410f75b7FD7a03e3F27c6268b6),
            _usdcPoolAddress: 0xA3915e59148c67AAaE39F5D73Bb49fdd22C00124,
            _campaignDuration: 120 * 24 * 60 * 60, // 120 days in seconds
            daoAddress: 0x095418A82BC2439703b69fbE1210824F2247D77c
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.priceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
        vm.stopBroadcast();

        activeNetworkConfig = NetworkConfig({
            priceFeed: address(mockPriceFeed),
            usdcAddress: 0xB7489f4d000F30410f75b7FD7a03e3F27c6268b6,
            campaignIdCounter: 0,
            initialVotingDuration: 13 * 24 * 60 * 60, // 13 days in seconds
            _ethPoolAddress: payable(0xB7489f4d000F30410f75b7FD7a03e3F27c6268b6),
            _usdcPoolAddress: 0xA3915e59148c67AAaE39F5D73Bb49fdd22C00124,
            _campaignDuration: 120 * 24 * 60 * 60, // 120 days in seconds
            daoAddress: 0x095418A82BC2439703b69fbE1210824F2247D77c
        });
        return activeNetworkConfig;
    }
}
