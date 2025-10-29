// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Math library
 * @dev Math library for performing various math operations
 */
library Math {
    error Int128Overflow();
    error Int256Overflow();
    error Uint127Overflow();
    error AddDeltaOverflow();
    error DivFailed();
    error FullMulDivFailed();

    /**
     * @dev Checks that `x` fits into a int128 and returns the same value.
     * This allows to safely cast the result to `uint128` or above.
     * If `x` is too large, reverts with `Int128Overflow()`.
     *
     * Requirements:
     *
     * - `x` must fit into a int128
     */
    function safeInt128(int256 x) internal pure returns (int256) {
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            if (uint256(x) + 2 ** 127 >= 2 ** 128) revert Int128Overflow();
            return x;
        }
    }

    /**
     * @dev Checks that `x` fits into 127 bits and returns the same value.
     * This allows to safely cast the result to `int128`, `uint128` or above.
     * If `x` is too large, reverts with `Uint127Overflow()`.
     *
     * Requirements:
     *
     * - `x` must fit into 127 bits
     */
    function safeUint127(uint256 x) internal pure returns (uint256) {
        if (x >= 2 ** 127) revert Uint127Overflow();
        return x;
    }

    /**
     * @dev Converts a uint256 to a int256 and return the new int256.
     * If the uint256 is too large, revert with `Int256Overflow()`.
     *
     * Requirements:
     *
     * - `x` must fit into a int256
     */
    function toInt256(uint256 x) internal pure returns (int256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        if (int256(x) >= 0) return int256(x);
        revert Int256Overflow();
    }

    /**
     * @dev Adds `delta` to `x` and returns the result.
     * If an overflow occurs, reverts with `AddDeltaOverflow()`.
     *
     * Requirements:
     *
     * - Both `x` and `delta` must fit into 128 bits.
     * - The result must fit into 128 bits.
     */
    function addDelta128(uint256 x, int256 delta) internal pure returns (uint256 z) {
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            z = x + uint256(delta);
            if ((z | x) >= 2 ** 128) revert AddDeltaOverflow();
        }
    }

    /**
     * @dev Performs `x / d` and returns the result, rounding up.
     * If `d` is zero, reverts with `DivFailed()`.
     * Credit to Solady:
     * https://github.com/Vectorized/solady/blob/6015421588b6e20c98fd60fb1f07f39eb8a1d049/src/utils/FixedPointMathLib.sol#L643-L654
     *
     * Requirements:
     *
     * - `d` must be non-zero
     */
    function divUp(uint256 x, uint256 d) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
            if iszero(d) {
                mstore(0x00, 0x65244e4e) // `DivFailed()`.
                revert(0x1c, 0x04)
            }
            z := add(iszero(iszero(mod(x, d))), div(x, d))
        }
    }

    /**
     * @dev Performs full `x * y / d` with full precision and returns the result.
     * If the result overflows, reverts with `FullMulDivFailed()`.
     * Credit to Solady:
     * https://github.com/Vectorized/solady/blob/6015421588b6e20c98fd60fb1f07f39eb8a1d049/src/utils/FixedPointMathLib.sol#L452-L512
     *
     * Requirements:
     *
     * - d must be non-zero
     * - The result must fit into 256 bits.
     */
    function fullMulDiv(uint256 x, uint256 y, uint256 d) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
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
                    z := mul(
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

    /**
     * @dev Performs full `x * y / d` with full precision and returns the result, rounding up.
     * If the result overflows, reverts with `FullMulDivFailed()`.
     * Credit to Solady:
     * https://github.com/Vectorized/solady/blob/6015421588b6e20c98fd60fb1f07f39eb8a1d049/src/utils/FixedPointMathLib.sol#L544-L560
     *
     * Requirements:
     *
     * - d must be non-zero
     * - The result must fit into 256 bits.
     */
    function fullMulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256 z) {
        z = fullMulDiv(x, y, d);
        assembly ("memory-safe") {
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
