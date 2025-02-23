// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Math {
    error Int128Overflow();
    error Int256Overflow();
    error Uint127Overflow();
    error AddDeltaOverflow();
    error DivFailed();
    error FullMulDivFailed();

    function safeInt128(int256 x) internal pure returns (int256) {
        unchecked {
            if (uint256(x) + 2 ** 127 >= 2 ** 128) revert Int128Overflow();
            return x;
        }
    }

    function safeUint127(uint256 x) internal pure returns (uint256) {
        if (x >= 2 ** 127) revert Uint127Overflow();
        return x;
    }

    function toInt256(uint256 x) internal pure returns (int256) {
        if (int256(x) >= 0) return int256(x);
        revert Int256Overflow();
    }

    function addDelta128(uint256 x, int256 delta) internal pure returns (uint256 z) {
        unchecked {
            z = x + uint256(delta);
            if ((z | x) >= 2 ** 128) revert AddDeltaOverflow();
        }
    }

    function divUp(uint256 x, uint256 d) internal pure returns (uint256 z) {
        assembly {
            if iszero(d) {
                mstore(0x00, 0x65244e4e) // `DivFailed()`.
                revert(0x1c, 0x04)
            }
            z := add(iszero(iszero(mod(x, d))), div(x, d))
        }
    }

    function fullMulDiv(uint256 x, uint256 y, uint256 d) internal pure returns (uint256 z) {
        assembly {
            z := mul(x, y)
            for {} 1 {} {
                if iszero(mul(or(iszero(x), eq(div(z, x), y)), d)) {
                    let mm := mulmod(x, y, not(0))
                    let p1 := sub(mm, add(z, lt(mm, z)))
                    let r := mulmod(x, y, d)
                    let t := and(d, sub(0, d))
                    if iszero(gt(d, p1)) {
                        mstore(0x00, 0xae47f702) // `FullMulDivFailed()`.
                        revert(0x1c, 0x04)
                    }
                    d := div(d, t)
                    let inv := xor(2, mul(3, d))
                    inv := mul(inv, sub(2, mul(d, inv)))
                    inv := mul(inv, sub(2, mul(d, inv)))
                    inv := mul(inv, sub(2, mul(d, inv)))
                    inv := mul(inv, sub(2, mul(d, inv)))
                    inv := mul(inv, sub(2, mul(d, inv)))
                    z :=
                        mul(
                            or(mul(sub(p1, gt(r, z)), add(div(sub(0, t), t), 1)), div(sub(z, r), t)),
                            mul(sub(2, mul(d, inv)), inv)
                        )
                    break
                }
                z := div(z, d)
                break
            }
        }
    }

    function fullMulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256 z) {
        z = fullMulDiv(x, y, d);
        assembly {
            if mulmod(x, y, d) {
                z := add(z, 1)
                if iszero(z) {
                    mstore(0x00, 0xae47f702) // `FullMulDivFailed()`.
                    revert(0x1c, 0x04)
                }
            }
        }
    }
}
