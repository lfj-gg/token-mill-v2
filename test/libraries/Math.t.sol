// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "src/libraries/Math.sol";

contract MathTest is Test {
    function test_Fuzz_SafeInt128(int256 x) public pure {
        x = bound(x, type(int128).min, type(int128).max);

        assertEq(Math.safeInt128(x), x, "test_Fuzz_SafeInt128::1");
    }

    function test_Fuzz_Revert_SafeInt128(int256 x) public {
        int256 x0 = bound(x, type(int256).min, int256(type(int128).min) - 1);
        int256 x1 = bound(x, int256(type(int128).max) + 1, type(int256).max);

        vm.expectRevert(Math.Int128Overflow.selector);
        this.safeInt128(x0);

        vm.expectRevert(Math.Int128Overflow.selector);
        this.safeInt128(x1);
    }

    function test_Fuzz_toInt256(uint256 x) public pure {
        x = bound(x, 0, uint256(type(int256).max));

        assertEq(Math.toInt256(x), int256(x), "test_Fuzz_toInt256::1");
    }

    function test_Fuzz_Revert_toInt256(uint256 x) public {
        uint256 x0 = bound(x, uint256(type(int256).max) + 1, type(uint256).max);

        vm.expectRevert(Math.Int256Overflow.selector);
        this.toInt256(x0);
    }

    function test_Fuzz_SafeUint127(uint256 x) public pure {
        x = bound(x, 0, 2 ** 127 - 1);

        assertEq(Math.safeUint127(x), x, "test_Fuzz_SafeUint127::1");
    }

    function test_Fuzz_Revert_SafeUint127(uint256 x) public {
        uint256 x0 = bound(x, 2 ** 127, type(uint256).max);

        vm.expectRevert(Math.Uint127Overflow.selector);
        this.safeUint127(x0);
    }

    function test_Fuzz_AddDelta128(uint256 x, int256 delta) public pure {
        x = bound(x, 0, type(uint128).max);
        delta = bound(delta, -int256(x), int256(uint256(type(uint128).max) - x));

        if (delta >= 0) {
            assertEq(Math.addDelta128(x, delta), x + uint256(delta), "test_Fuzz_AddDelta128::1");
        } else {
            assertEq(Math.addDelta128(x, delta), x - uint256(-delta), "test_Fuzz_AddDelta128::2");
        }
    }

    function test_Fuzz_Revert_AddDelta128(uint256 x, int256 delta) public {
        uint256 x0 = bound(x, 0, type(uint128).max);
        int256 delta0A = bound(delta, int256(uint256(type(uint128).max) - x0) + 1, type(int256).max);

        vm.expectRevert(Math.AddDeltaOverflow.selector);
        this.addDelta128(x0, delta0A);

        int256 delta0B = bound(delta, type(int256).min, -int256(x0) - 1);

        vm.expectRevert(Math.AddDeltaOverflow.selector);
        this.addDelta128(x0, delta0B);

        int256 delta1 = bound(delta, 0, type(int128).max);
        uint256 x1 = bound(x, uint256(int256(uint256(type(uint128).max)) - delta1 + 1), type(uint256).max);

        vm.expectRevert(Math.AddDeltaOverflow.selector);
        this.addDelta128(x1, delta1);

        int256 delta2 = bound(delta, type(int128).min, -1);
        uint256 x2 = bound(x, 0, uint256(-delta2) - 1);

        vm.expectRevert(Math.AddDeltaOverflow.selector);
        this.addDelta128(x2, delta2);

        uint256 x3 = bound(x, uint256(type(uint128).max) + 1, type(uint256).max);
        int256 delta3 = delta;

        vm.expectRevert(Math.AddDeltaOverflow.selector);
        this.addDelta128(x3, delta3);

        int256 delta4 = delta > 0
            ? bound(delta, int256(uint256(type(uint128).max)) + 1, type(int256).max)
            : bound(delta, type(int256).min, int256(type(int128).min) - 1);
        uint256 x4 = x;

        vm.expectRevert(Math.AddDeltaOverflow.selector);
        this.addDelta128(x4, delta4);
    }

    function test_Fuzz_DivUp(uint256 x, uint256 d) public pure {
        d = bound(d, 1, type(uint256).max);

        if (x % d == 0) {
            assertEq(Math.divUp(x, d), x / d, "test_Fuzz_DivUp::1");
        } else {
            assertEq(Math.divUp(x, d), x / d + 1, "test_Fuzz_DivUp::2");
        }
    }

    function test_Revert_DivUp() public {
        vm.expectRevert(Math.DivFailed.selector);
        this.divUp(1, 0);
    }

    function test_Fuzz_FullMulDiv(uint256 x, uint256 y, uint256 d) public pure {
        d = bound(d, 1, type(uint256).max);
        y = bound(y, 0, d);

        uint256 z;
        assembly ("memory-safe") {
            z := div(mul(x, y), y)
        }

        if (z == y) {
            assertEq(Math.fullMulDiv(x, y, d), x * y / d, "test_Fuzz_FullMulDiv::1");
        } else {
            assertGe(Math.fullMulDiv(x, y, d), x / d * y, "test_Fuzz_FullMulDiv::2");

            z = ((x / d) + (x % d > 0 ? 1 : 0));
            if (z <= type(uint256).max / y) {
                assertLe(Math.fullMulDiv(x, y, d), z * y, "test_Fuzz_FullMulDiv::3");
            }
        }
    }

    function test_Fuzz_Revert_FullMulDiv(uint256 x, uint256 d) public {
        vm.expectRevert(Math.FullMulDivFailed.selector);
        this.fullMulDiv(1, 1, 0);

        d = bound(d, 1, type(uint256).max - 1);
        x = bound(x, d + 1, type(uint256).max);

        vm.expectRevert(Math.FullMulDivFailed.selector);
        this.fullMulDiv(x, type(uint256).max, d);
    }

    function test_Fuzz_FullMulDivUp(uint256 x, uint256 y, uint256 d) public pure {
        d = bound(d, 1, type(uint256).max);
        y = bound(y, 0, d);

        uint256 z;
        assembly ("memory-safe") {
            z := div(mul(x, y), y)
        }

        if (z == y) {
            z = x * y;
            assertEq(Math.fullMulDivUp(x, y, d), z / d + (z % d > 0 ? 1 : 0), "test_Fuzz_FullMulDivUp::1");
        } else {
            assertGe(Math.fullMulDivUp(x, y, d), x / d * y, "test_Fuzz_FullMulDivUp::2");

            z = ((x / d) + (x % d > 0 ? 1 : 0));
            if (z <= type(uint256).max / y) {
                assertLe(Math.fullMulDivUp(x, y, d), z * y, "test_Fuzz_FullMulDivUp::3");
            }
        }
    }

    function test_Fuzz_Revert_FullMulDivUp(uint256 x, uint256 d) public {
        vm.expectRevert(Math.FullMulDivFailed.selector);
        this.fullMulDivUp(1, 1, 0);

        assertEq(this.fullMulDiv(2 ** 129 - 1, 2 ** 129 + 1, 4), type(uint256).max, "test_Fuzz_Revert_FullMulDivUp::1");

        vm.expectRevert(Math.FullMulDivFailed.selector);
        this.fullMulDivUp(2 ** 129 - 1, 2 ** 129 + 1, 4);

        d = bound(d, 1, type(uint256).max - 1);
        x = bound(x, d + 1, type(uint256).max);

        vm.expectRevert(Math.FullMulDivFailed.selector);
        this.fullMulDivUp(x, type(uint256).max, d);
    }

    // Helper functions
    function safeInt128(int256 x) external pure returns (int256) {
        return Math.safeInt128(x);
    }

    function toInt256(uint256 x) external pure returns (int256) {
        return Math.toInt256(x);
    }

    function safeUint127(uint256 x) external pure returns (uint256) {
        return Math.safeUint127(x);
    }

    function addDelta128(uint256 x, int256 delta) external pure returns (uint256 z) {
        return Math.addDelta128(x, delta);
    }

    function divUp(uint256 x, uint256 d) external pure returns (uint256 z) {
        return Math.divUp(x, d);
    }

    function fullMulDiv(uint256 x, uint256 y, uint256 d) external pure returns (uint256 z) {
        return Math.fullMulDiv(x, y, d);
    }

    function fullMulDivUp(uint256 x, uint256 y, uint256 d) external pure returns (uint256 z) {
        return Math.fullMulDivUp(x, y, d);
    }
}
