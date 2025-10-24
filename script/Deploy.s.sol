// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Script} from "forge-std/Script.sol";

import {Parameters} from "script/Parameters.sol";
import {ITMFactory, TMFactory} from "src/TMFactory.sol";
import {TMMarket} from "src/TMMarket.sol";
import {TMToken} from "src/TMToken.sol";

contract Deploy is Script, Parameters {
    function run()
        public
        returns (
            address marketImplementation,
            address tokenImplementation,
            address factoryImplementation,
            address factoryProxy
        )
    {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address factoryProxyAddress = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 3);

        vm.startPrank(deployer);
        tokenImplementation = address(new TMToken(factoryProxyAddress));
        marketImplementation =
            address(new TMMarket(factoryProxyAddress, quoteToken, amount0A, amount0B, sqrtPrice0, sqrtPrice1));
        factoryImplementation = address(new TMFactory(0, 0, 0, 0, address(0), address(0), address(0), address(0)));

        factoryProxy = address(
            new TransparentUpgradeableProxy(
                factoryImplementation,
                deployer,
                abi.encodeCall(
                    ITMFactory.initialize,
                    (
                        defaultMinUpdateTime,
                        defaultProtocolFeeShare,
                        defaultFeeA,
                        defaultFeeB,
                        quoteToken,
                        marketImplementation,
                        tokenImplementation,
                        deployer
                    )
                )
            )
        );
        vm.stopPrank();

        require(factoryProxy == factoryProxyAddress, "run::1");
    }
}
