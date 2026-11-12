// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

/// @dev Test-only actors and model. Every transfer destination is included in the conserved sum.
contract TokenHandler is Test {
    LaunchToken public immutable token;
    address[4] private actors;
    mapping(address owner => mapping(address spender => uint256)) public expectedAllowance;
    uint256 public successfulTransfers;

    constructor(LaunchToken token_) {
        token = token_;
        actors = [address(this), makeAddr("holder-one"), makeAddr("holder-two"), makeAddr("holder-three")];
    }

    function actor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balanceBefore = token.balanceOf(from);
        uint256 recipientBefore = token.balanceOf(to);
        uint256 amount = bound(amountSeed, 0, balanceBefore);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? balanceBefore : balanceBefore - amount);
        assertEq(token.balanceOf(to), from == to ? recipientBefore : recipientBefore + amount);
        ++successfulTransfers;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function moveApproved(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowanceBefore = expectedAllowance[owner][spender];
        uint256 balanceBefore = token.balanceOf(owner);
        uint256 recipientBefore = token.balanceOf(to);
        uint256 limit = allowanceBefore < balanceBefore ? allowanceBefore : balanceBefore;
        uint256 amount = bound(amountSeed, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (allowanceBefore != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        assertEq(token.balanceOf(owner), owner == to ? balanceBefore : balanceBefore - amount);
        assertEq(token.balanceOf(to), owner == to ? recipientBefore : recipientBefore + amount);
        ++successfulTransfers;
    }
}

contract LaunchTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    LaunchToken private token;
    TokenHandler private handler;

    function setUp() public {
        vm.chainId(4663);
        token = new LaunchToken();
        handler = new TokenHandler(token);
        assertTrue(token.transfer(address(handler), SUPPLY));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.move.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.moveApproved.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariantSupplyAndBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actor(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariantAllowancesMatchApprovalsAndSpending() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actor(i);
                address spender = handler.actor(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
