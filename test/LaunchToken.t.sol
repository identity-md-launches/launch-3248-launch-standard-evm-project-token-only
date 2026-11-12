// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

/// @dev Test-only factory surrogate. Does not implement the IMD pool or distributor.
contract TokenFactoryProbe {
    function deploy() external returns (LaunchToken) {
        return new LaunchToken();
    }

    function deployAndSplit(address pool, address distributor) external returns (LaunchToken token) {
        token = new LaunchToken();
        uint256 supply = token.totalSupply();
        require(token.transfer(pool, supply * 9000 / 10_000));
        require(token.transfer(distributor, supply * 1000 / 10_000));
    }
}

contract LaunchTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    LaunchToken private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.chainId(4663);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new LaunchToken();
    }

    function testIdentityAndSupply() public view {
        assertEq(token.name(), "Extremely Long Dog");
        assertEq(token.symbol(), "XLONGDOG");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 10 ** 27);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testConstructorEmitsSingleMint() public {
        vm.recordLogs();
        LaunchToken created = new LaunchToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(created));
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function testFactoryReceivesSupplyWithoutExternalConfiguration() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        vm.prank(alice, bob);
        LaunchToken created = factory.deploy();
        assertEq(created.totalSupply(), SUPPLY);
        assertEq(created.balanceOf(address(factory)), SUPPLY);
        assertEq(created.balanceOf(alice), 0);
        assertEq(created.balanceOf(bob), 0);
        assertEq(created.balanceOf(address(this)), 0);
    }

    function testFactoryCanTransferNinetyPercentToPoolAndTenToDistributor() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        LaunchToken created = factory.deployAndSplit(alice, bob);
        assertEq(created.balanceOf(alice), 900_000_000 ether);
        assertEq(created.balanceOf(bob), 100_000_000 ether);
        assertEq(created.balanceOf(address(factory)), 0);
        assertEq(created.balanceOf(address(this)), 0);
        assertEq(created.totalSupply(), SUPPLY);
    }

    function testTransferReturnsTrueAndEmitsExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 123 ether);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testWholeSupplyCanMoveWithoutLimitsOrCooldowns() public {
        assertTrue(token.transfer(alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        vm.prank(bob);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testZeroTransferFromEmptyAccountSucceedsAndEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function testSelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferExceedingBalanceRevertsWithoutChanges() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testSelfTransferStillRequiresEnoughBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
    }

    function testApproveReplaceAndRevoke() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 100 ether);
        assertTrue(token.approve(spender, 100 ether));
        assertEq(token.allowance(address(this), spender), 100 ether);
        assertTrue(token.approve(spender, 42 ether));
        assertEq(token.allowance(address(this), spender), 42 ether);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
    }

    function testApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function testApprovalsBelongOnlyToCaller() public {
        token.approve(spender, 3);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        assertEq(token.allowance(address(this), spender), 3);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testTransferFromConsumesFiniteAllowanceAndEmitsTransfer() public {
        token.approve(spender, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40 ether));
        assertEq(token.allowance(address(this), spender), 60 ether);
        assertEq(token.balanceOf(alice), 40 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 60 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 60 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferFromPreservesInfiniteAllowance() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function testTransferFromToHolderConsumesAllowanceButPreservesBalance() public {
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function testTransferFromZeroAmountNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testTransferFromZeroSenderReverts() public {
        // ERC20 validates the allowance owner before reaching the transfer's sender check.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testUnapprovedSpenderCannotMoveTokens() public {
        token.approve(spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(address(this), spender), SUPPLY);
    }

    function testDeployerCannotMoveHolderTokensWithoutApproval() public {
        token.transfer(alice, SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, SUPPLY)
        );
        token.transferFrom(alice, address(this), SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function testTransferFromInsufficientAllowanceIsAtomic() public {
        token.approve(spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 2);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testTransferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(alice);
        token.approve(spender, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 2));
        vm.prank(spender);
        token.transferFrom(alice, bob, 2);
        assertEq(token.allowance(alice, spender), 2);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testTransferFromToZeroRollsBackAllowance() public {
        token.approve(spender, 42);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 42);
        assertEq(token.allowance(address(this), spender), 42);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testNoMintBurnAdminOrUpgradeEntrypoints() public {
        string[19] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "owner()",
            "pause()",
            "unpause()",
            "setMinter(address)",
            "setFee(uint256)",
            "setMaxBuy(uint256)",
            "blacklist(address)",
            "initialize(address)",
            "upgradeTo(address)",
            "upgradeToAndCall(address,bytes)",
            "setContractURI(string)",
            "setName(string)"
        ];
        token.transfer(alice, 100 ether);
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], bob, SUPPLY);
            (bool deployerSuccess,) = address(token).call(data);
            assertFalse(deployerSuccess, signatures[i]);
            vm.prank(bob);
            (bool outsiderSuccess,) = address(token).call(data);
            assertFalse(outsiderSuccess, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100 ether);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
    }

    function testRejectsNativeETHAndUnknownCalls() public {
        vm.deal(address(this), 2);
        (bool emptySuccess,) = address(token).call{value: 1}("");
        assertFalse(emptySuccess);
        (bool payableSuccess,) = address(token).call{value: 1}(abi.encodeCall(token.transfer, (alice, 1)));
        assertFalse(payableSuccess);
        (bool unknownSuccess,) = address(token).call(hex"ffffffff");
        assertFalse(unknownSuccess);
        assertEq(address(token).balance, 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testRuntimeIsBoundedAndHasNoForbiddenOpcodes() public view {
        bytes memory code = address(token).code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        bool reachable = true;
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op == 0x5b) reachable = true;
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            if (reachable) assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden runtime opcode");
            if (op == 0x00 || op == 0x56 || op == 0xf3 || op == 0xfd || op == 0xfe || op == 0xff) reachable = false;
        }
    }

    function testFuzzTransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferFromConservesSupplyAndAllowance(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzOverspendingBalanceReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzzOverspendingAllowanceReverts(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
