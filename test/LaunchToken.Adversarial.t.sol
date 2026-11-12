// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

/// @dev A real contract caller and recipient. Any unsolicited receiver hook reverts.
contract ERC20CallerProbe {
    function send(LaunchToken token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }

    function pull(LaunchToken token, address owner, address recipient, uint256 amount) external returns (bool) {
        return token.transferFrom(owner, recipient, amount);
    }

    fallback() external {
        revert("ERC20 must not call receiver hooks");
    }
}

/// @dev Complements the original tests with allowance lifecycles, caller identity and algebraic properties.
/// forge-config: default.fuzz.runs = 1000
contract LaunchTokenAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    LaunchToken private token;
    address private holder;
    address private recipient;
    address private spender;
    address private otherSpender;

    function setUp() public {
        holder = makeAddr("adversarial-holder");
        recipient = makeAddr("adversarial-recipient");
        spender = makeAddr("adversarial-spender");
        otherSpender = makeAddr("adversarial-other-spender");
        token = new LaunchToken();
        assertTrue(token.transfer(holder, SUPPLY));
    }

    function testOneMinorUnitMovesWithoutRoundingOrTax() public {
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 1));
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, 1));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function testMaxUintApprovalIsInfiniteButMaxMinusOneIsFinite() public {
        _approve(holder, spender, type(uint256).max - 1);
        _approve(holder, otherSpender, type(uint256).max);
        _spend(spender, holder, recipient, 1);
        _spend(otherSpender, holder, recipient, 1);
        assertEq(token.allowance(holder, spender), type(uint256).max - 2);
        assertEq(token.allowance(holder, otherSpender), type(uint256).max);
        assertEq(token.balanceOf(recipient), 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testMaxUintSpendWithInfiniteApprovalStillNeedsBalance() public {
        _approve(holder, spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, type(uint256).max);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function testSpentAllowanceDoesNotReviveWhenBalanceReturns() public {
        _approve(holder, spender, SUPPLY);
        _spend(spender, holder, recipient, SUPPLY);
        assertEq(token.allowance(holder, spender), 0);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, SUPPLY));
        _expectAllowanceFailure(spender, holder, recipient, 0, 1);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);

        _approve(holder, spender, 1);
        _spend(spender, holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(recipient), 1);
    }

    function testInfiniteApprovalCanBeReplacedAndRevoked() public {
        _approve(holder, spender, type(uint256).max);
        _spend(spender, holder, recipient, 1);
        _approve(holder, spender, 2);
        assertEq(token.allowance(holder, spender), 2);
        _expectAllowanceFailure(spender, holder, recipient, 2, 3);
        _spend(spender, holder, recipient, 2);
        _approve(holder, spender, type(uint256).max);
        _approve(holder, spender, 0);
        _expectAllowanceFailure(spender, holder, recipient, 0, 1);
        assertEq(token.balanceOf(recipient), 3);
    }

    function testHolderNeedsSelfApprovalForTransferFrom() public {
        _expectAllowanceFailure(holder, holder, recipient, 0, 1);
        _approve(holder, holder, 1);
        _spend(holder, holder, recipient, 1);
        assertEq(token.allowance(holder, holder), 0);
        assertEq(token.balanceOf(holder), SUPPLY - 1);
    }

    function testApprovalDoesNotReserveBalanceForSpender() public {
        _approve(holder, spender, SUPPLY);
        _approve(holder, otherSpender, SUPPLY);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, SUPPLY));
        assertEq(token.allowance(holder, spender), SUPPLY);
        assertEq(token.allowance(holder, otherSpender), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), SUPPLY);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, SUPPLY));
        _spend(otherSpender, holder, recipient, SUPPLY);
        assertEq(token.allowance(holder, spender), SUPPLY);
        assertEq(token.allowance(holder, otherSpender), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
    }

    function testApprovalFromEmptyHolderCanSpendOnlyAfterFunding() public {
        _approve(recipient, spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, recipient, 0, 1));
        vm.prank(spender);
        token.transferFrom(recipient, spender, 1);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 1));
        _spend(spender, recipient, spender, 1);
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(recipient, spender), type(uint256).max);
    }

    function testContractRecipientCannotBlockOrReenterTransfer() public {
        ERC20CallerProbe receiver = new ERC20CallerProbe();
        vm.prank(holder);
        assertTrue(token.transfer(address(receiver), SUPPLY));
        assertEq(token.balanceOf(address(receiver)), SUPPLY);
        assertTrue(receiver.send(token, holder, SUPPLY));
        _approve(holder, spender, SUPPLY);
        _spend(spender, holder, address(receiver), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(address(receiver)), SUPPLY);
        assertTrue(receiver.send(token, holder, SUPPLY));
        assertEq(token.balanceOf(holder), SUPPLY);
    }

    function testApprovedOriginCannotAuthorizeAnUnapprovedRelay() public {
        ERC20CallerProbe relay = new ERC20CallerProbe();
        _approve(holder, spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(relay), 0, 1));
        vm.prank(spender, spender);
        relay.pull(token, holder, recipient, 1);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.allowance(holder, spender), SUPPLY);
        assertEq(token.allowance(holder, address(relay)), 0);
    }

    function testApprovedRelaySpendsItsOwnAllowanceRegardlessOfOrigin() public {
        ERC20CallerProbe relay = new ERC20CallerProbe();
        _approve(holder, address(relay), SUPPLY);
        vm.prank(otherSpender, otherSpender);
        assertTrue(relay.pull(token, holder, recipient, SUPPLY));
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.allowance(holder, address(relay)), 0);
        assertEq(token.allowance(holder, otherSpender), 0);
    }

    function testZeroTransfersEmitWithoutConsumingFiniteOrInfiniteApproval() public {
        _approve(holder, spender, 1);
        _approve(holder, otherSpender, type(uint256).max);
        vm.recordLogs();
        _spend(spender, holder, holder, 0);
        _spend(otherSpender, holder, recipient, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        _assertTransferLog(logs[0], holder, holder, 0);
        _assertTransferLog(logs[1], holder, recipient, 0);
        assertEq(token.allowance(holder, spender), 1);
        assertEq(token.allowance(holder, otherSpender), type(uint256).max);
        assertEq(token.balanceOf(holder), SUPPLY);
    }

    function testZeroSpenderCannotBeApprovedEvenForZeroOrMax() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(holder);
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(holder);
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(holder, address(0)), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
    }

    function testZeroRecipientWithInfiniteApprovalCannotBurn() public {
        _approve(holder, spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testAdminAndMetadataProbesUseValidABIEncoding() public {
        // Dynamic arguments must be ABI-correct, or a decoder revert could conceal a real entrypoint.
        bytes[] memory calls = new bytes[](10);
        calls[0] = abi.encodeWithSignature("setContractURI(string)", "https://midaswhale.wtf/xlongdog");
        calls[1] = abi.encodeWithSignature("setName(string)", "Changed name");
        calls[2] = abi.encodeWithSignature("setSymbol(string)", "CHANGED");
        calls[3] = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", recipient, bytes(""));
        calls[4] = abi.encodeWithSignature("mint(address,uint256)", recipient, 1);
        calls[5] = abi.encodeWithSignature("burnFrom(address,uint256)", holder, 1);
        calls[6] = abi.encodeWithSignature("transferOwnership(address)", recipient);
        calls[7] = abi.encodeWithSignature("setTax(uint256)", 1000);
        calls[8] = abi.encodeWithSignature("setTradingEnabled(bool)", false);
        calls[9] = abi.encodeWithSignature("setBlacklist(address,bool)", holder, true);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerOK,) = address(token).call(calls[i]);
            assertFalse(deployerOK, "deployer acquired token administration");
            vm.prank(spender);
            (bool outsiderOK,) = address(token).call(calls[i]);
            assertFalse(outsiderOK, "outsider acquired token administration");
        }
        assertEq(token.name(), "Extremely Long Dog");
        assertEq(token.symbol(), "XLONGDOG");
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, SUPPLY));
        assertEq(token.balanceOf(recipient), SUPPLY);
    }

    function testEveryStateChangingEntrypointRejectsETHAtomically() public {
        vm.deal(spender, 3);
        _approve(holder, spender, SUPPLY);
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeCall(token.transfer, (recipient, 0));
        calls[1] = abi.encodeCall(token.approve, (recipient, SUPPLY));
        calls[2] = abi.encodeCall(token.transferFrom, (holder, recipient, SUPPLY));
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(spender);
            (bool success,) = address(token).call{value: 1}(calls[i]);
            assertFalse(success);
        }
        assertEq(spender.balance, 3);
        assertEq(address(token).balance, 0);
        assertEq(token.allowance(spender, recipient), 0);
        assertEq(token.allowance(holder, spender), SUPPLY);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function testFuzzTransferRoundTripsAreExact(uint256 amount, uint8 repetitions) public {
        amount = bound(amount, 0, SUPPLY);
        uint256 count = bound(repetitions, 1, 16);
        _approve(holder, spender, type(uint256).max);
        for (uint256 i; i < count; ++i) {
            _spend(spender, holder, recipient, amount);
            assertEq(token.balanceOf(recipient), amount);
            vm.prank(recipient);
            assertTrue(token.transfer(holder, amount));
            assertEq(token.balanceOf(holder), SUPPLY);
            assertEq(token.balanceOf(recipient), 0);
        }
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzSplittingTransfersHasSameResultAsOneTransfer(uint256 amount, uint256 first) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        LaunchToken single = new LaunchToken();
        assertTrue(single.transfer(holder, SUPPLY));
        vm.prank(holder);
        assertTrue(single.transfer(recipient, amount));
        vm.startPrank(holder);
        assertTrue(token.transfer(recipient, first));
        assertTrue(token.transfer(recipient, amount - first));
        vm.stopPrank();
        assertEq(token.balanceOf(holder), single.balanceOf(holder));
        assertEq(token.balanceOf(recipient), single.balanceOf(recipient));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzFiniteAllowanceCannotBeReplayed(uint256 approved, uint256 first) public {
        approved = bound(approved, 1, SUPPLY);
        first = bound(first, 0, approved);
        _approve(holder, spender, approved);
        _spend(spender, holder, recipient, first);
        _spend(spender, holder, recipient, approved - first);
        assertEq(token.allowance(holder, spender), 0);
        _expectAllowanceFailure(spender, holder, recipient, 0, 1);
        assertEq(token.balanceOf(recipient), approved);
        assertEq(token.balanceOf(holder), SUPPLY - approved);
    }

    function testFuzzFailedSpendPreservesAllowanceAndCanBeRetried(uint256 balance, uint256 requested) public {
        balance = bound(balance, 0, SUPPLY - 1);
        requested = bound(requested, balance + 1, SUPPLY);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, SUPPLY - balance));
        _approve(holder, spender, requested);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, requested)
        );
        vm.prank(spender);
        token.transferFrom(holder, spender, requested);
        assertEq(token.allowance(holder, spender), requested);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(spender), 0);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, requested - balance));
        _spend(spender, holder, spender, requested);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(spender), requested);
        assertEq(token.balanceOf(recipient), SUPPLY - requested);
    }

    function testFuzzApprovalOverwriteIsIdempotentAndIsolated(uint256 previous, uint256 replacement) public {
        _approve(holder, spender, previous);
        _approve(holder, otherSpender, previous);
        _approve(recipient, spender, previous);
        _approve(holder, spender, replacement);
        _approve(holder, spender, replacement);
        assertEq(token.allowance(holder, spender), replacement);
        assertEq(token.allowance(holder, otherSpender), previous);
        assertEq(token.allowance(recipient, spender), previous);
        assertEq(token.allowance(spender, holder), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTimeAndBlockChangesCannotRestrictTransfers(uint48 elapsed, uint48 blocksElapsed) public {
        vm.prank(holder);
        assertTrue(token.transfer(recipient, SUPPLY));
        vm.warp(block.timestamp + uint256(elapsed));
        vm.roll(block.number + uint256(blocksElapsed));
        vm.prank(recipient);
        assertTrue(token.transfer(holder, SUPPLY));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _approve(address owner, address operator, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(operator, amount));
    }

    function _spend(address operator, address owner, address to, uint256 amount) private {
        vm.prank(operator);
        assertTrue(token.transferFrom(owner, to, amount));
    }

    function _expectAllowanceFailure(address operator, address owner, address to, uint256 allowed, uint256 requested)
        private
    {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, operator, allowed, requested)
        );
        vm.prank(operator);
        token.transferFrom(owner, to, requested);
        assertEq(token.allowance(owner, operator), allowed);
    }

    function _assertTransferLog(Vm.Log memory entry, address from, address to, uint256 amount) private view {
        assertEq(entry.emitter, address(token));
        assertEq(entry.topics.length, 3);
        assertEq(entry.topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(entry.topics[1], bytes32(uint256(uint160(from))));
        assertEq(entry.topics[2], bytes32(uint256(uint160(to))));
        assertEq(abi.decode(entry.data, (uint256)), amount);
    }
}
