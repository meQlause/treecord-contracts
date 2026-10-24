// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

contract MockUSDCTest is Test {
    MockUSDC internal usdc;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        usdc = new MockUSDC();
    }

    function test_Metadata() public view {
        assertEq(usdc.name(), "Mock USD Coin");
        assertEq(usdc.symbol(), "USDC");
        assertEq(usdc.decimals(), 6);
    }

    function test_AnyoneCanMintToAnyone() public {
        vm.prank(bob);
        usdc.mint(alice, 5e6);
        assertEq(usdc.balanceOf(alice), 5e6);
        assertEq(usdc.totalSupply(), 5e6);
    }

    function test_BurnReducesCallerBalanceAndSupply() public {
        usdc.mint(alice, 5e6);
        vm.prank(alice);
        usdc.burn(2e6);
        assertEq(usdc.balanceOf(alice), 3e6);
        assertEq(usdc.totalSupply(), 3e6);
    }

    function test_BurnOnlyTouchesTheCaller() public {
        usdc.mint(alice, 5e6);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, bob, 0, 1e6));
        usdc.burn(1e6);
        assertEq(usdc.balanceOf(alice), 5e6);
    }

    function test_RevertWhen_BurningMoreThanBalance() public {
        usdc.mint(alice, 1e6);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1e6, 1e6 + 1));
        usdc.burn(1e6 + 1);
    }

    function testFuzz_MintThenBurn(uint256 minted, uint256 burned) public {
        minted = bound(minted, 0, type(uint128).max);
        burned = bound(burned, 0, minted);
        usdc.mint(alice, minted);
        vm.prank(alice);
        usdc.burn(burned);
        assertEq(usdc.balanceOf(alice), minted - burned);
        assertEq(usdc.totalSupply(), minted - burned);
    }
}
