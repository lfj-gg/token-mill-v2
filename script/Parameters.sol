// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Parameters {
    address internal quoteToken = 0x0000000000000000000000000000000000000000;
    uint256 internal defaultProtocolFeeShare = 0.2e6; // 20%
    uint256 internal defaultMinUpdateTime = 1 hours;
    uint256 internal defaultFee = 0.01e6; // 1%
    uint256 internal sqrtPrice0 = _sqrtX96(0.000_000_028e18); // 2.8e-8
    uint256 internal sqrtPrice1 = _sqrtX96(0.000_000_38e18); // 3.8e-7
    uint256 internal amount0A = 800_000_000e18; // 800e6
    uint256 internal amount0B = 200_000_000e18; // 200e6

    function _sqrtX96(uint256 x) internal pure returns (uint256 y) {
        uint256 xx = x;
        x = xx >= 2 ** 64 ? x * 2 ** 96 / 1e18 : (x * 2 ** 192) / 1e18;

        unchecked {
            uint256 z = (x + 1) / 2;
            y = x;
            while (z < y) {
                y = z;
                z = (x / z + z) / 2;
            }

            return xx >= 2 ** 64 ? y << 48 : y;
        }
    }
}
