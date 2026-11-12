// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

/// @dev All generated amounts come from the test's ledger, never from token balances.
/// Expected failures are caught and their exact error data is checked, so an unexpected
/// handler revert remains a failure under the project's fail_on_revert setting.
contract AdversarialTokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    uint256 private constant ACTORS = 4;
    LaunchToken public immutable token;
    address[4] private actors;
    mapping(address => uint256) public modelBalance;
    mapping(address => mapping(address => uint256)) public modelAllowance;
    uint256 public positiveTransfers;
    uint256 public zeroTransfers;
    uint256 public approvals;
    uint256 public rejectedCalls;

    constructor() {
        actors = [address(this), makeAddr("sequence-alice"), makeAddr("sequence-bob"), makeAddr("sequence-carol")];
        token = new LaunchToken();
        modelBalance[address(this)] = SUPPLY;
        // Redistribute real constructor-minted tokens to explore several funded senders.
        // This fixture is not an implementation of the protocol's launch allocation.
        for (uint256 i = 1; i < ACTORS; ++i) {
            _move(address(this), actors[i], SUPPLY / ACTORS);
        }
        for (uint256 i; i < ACTORS; ++i) {
            _approve(actors[i], actors[(i + 1) % ACTORS], SUPPLY / 8);
        }
        positiveTransfers = 0;
        approvals = 0;
    }

    function actor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function transfer(uint256 ownerSeed, uint256 recipientSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        _move(owner, _actor(recipientSeed), _amount(amountSeed, modelBalance[owner]));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256 amount;
        uint256 mode = amountSeed % 6;
        if (mode == 0) amount = 0;
        else if (mode == 1) amount = 1;
        else if (mode == 2) amount = type(uint256).max;
        else if (mode == 3) amount = type(uint256).max - 1;
        else if (mode == 4) amount = bound(amountSeed, 0, SUPPLY);
        else amount = amountSeed;
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 limit = modelBalance[owner];
        uint256 allowed = modelAllowance[owner][spender];
        if (allowed < limit) limit = allowed;
        uint256 amount = _amount(amountSeed, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, _actor(recipientSeed), amount));
        if (allowed != type(uint256).max) modelAllowance[owner][spender] = allowed - amount;
        _recordMovement(owner, _actor(recipientSeed), amount);
        assertEq(token.allowance(owner, spender), modelAllowance[owner][spender]);
    }

    function rejectTransfer(uint256 ownerSeed, uint256 recipientSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        uint256 balance = modelBalance[owner];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        _reject(
            owner,
            abi.encodeCall(token.transfer, (_actor(recipientSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
    }

    function rejectAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed, uint256 amountSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = modelAllowance[owner][spender];
        // Infinite approval cannot be exceeded. Replace it with the adjacent finite boundary.
        if (allowed == type(uint256).max) {
            allowed = type(uint256).max - 1;
            _approve(owner, spender, allowed);
        }
        uint256 amount = bound(amountSeed, allowed + 1, type(uint256).max);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(recipientSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
    }

    function rejectBalanceAfterApproval(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed, bool infinite)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = modelBalance[owner];
        uint256 amount = balance + 1;
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(recipientSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool infinite) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(amountSeed, modelBalance[owner]);
        bytes memory expected = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        _reject(owner, abi.encodeCall(token.transfer, (address(0), amount)), expected);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        _reject(spender, abi.encodeCall(token.transferFrom, (owner, address(0), amount)), expected);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        _reject(
            _actor(ownerSeed),
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function revokeAndReject(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        _approve(owner, spender, 0);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(recipientSeed), 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    function roundTrip(uint256 ownerSeed, uint256 recipientSeed, uint256 amountSeed) external {
        uint256 index = ownerSeed % ACTORS;
        address owner = actors[index];
        address recipient = actors[(index + 1 + recipientSeed % (ACTORS - 1)) % ACTORS];
        uint256 ownerBefore = modelBalance[owner];
        uint256 recipientBefore = modelBalance[recipient];
        uint256 amount = _amount(amountSeed, ownerBefore);
        _move(owner, recipient, amount);
        _move(recipient, owner, amount);
        assertEq(token.balanceOf(owner), ownerBefore, "round trip lost or created value");
        assertEq(token.balanceOf(recipient), recipientBefore, "round trip changed recipient wealth");
    }

    function donateToToken(uint256 ownerSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        uint256 limit = modelBalance[owner];
        // Include unsolicited balances without letting a sink consume all actors' funds
        // and turn the rest of a campaign into exclusively zero transfers.
        if (limit > 1 ether) limit = 1 ether;
        _move(owner, address(token), _amount(amountSeed, limit));
    }

    function rejectMintOrBurn(uint256 callerSeed, uint256 recipientSeed, uint256 amountSeed, bool mint) external {
        address caller = _actor(callerSeed); // Includes the deploying contract.
        address recipient = _actor(recipientSeed);
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        bytes memory data = mint
            ? abi.encodeWithSignature("mint(address,uint256)", recipient, amount)
            : abi.encodeWithSignature("burnFrom(address,uint256)", recipient, amount);
        _reject(caller, data, bytes(""));
    }

    /// @dev Read-only oracle over all possible recipients and all tracked approval pairs.
    function assertModel() external view {
        uint256 sum = token.balanceOf(address(token));
        assertEq(sum, modelBalance[address(token)], "unsolicited token balance diverged");
        for (uint256 i; i < ACTORS; ++i) {
            address owner = actors[i];
            assertEq(token.balanceOf(owner), modelBalance[owner], "holder ledger diverged");
            sum += token.balanceOf(owner);
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < ACTORS; ++j) {
                address spender = actors[j];
                assertEq(token.allowance(owner, spender), modelAllowance[owner][spender], "approval ledger diverged");
            }
        }
        assertEq(sum, SUPPLY, "balances no longer conserve the constructor mint");
        assertEq(token.totalSupply(), SUPPLY, "fixed supply changed");
        assertEq(token.balanceOf(address(0)), 0);
    }

    function _move(address owner, address recipient, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.transfer(recipient, amount));
        _recordMovement(owner, recipient, amount);
    }

    function _recordMovement(address owner, address recipient, uint256 amount) private {
        // A self-transfer has no net balance effect, but must still be executed by the token.
        if (owner != recipient) {
            modelBalance[owner] -= amount;
            modelBalance[recipient] += amount;
        }
        assertEq(token.balanceOf(owner), modelBalance[owner], "sender delta is not exact");
        assertEq(token.balanceOf(recipient), modelBalance[recipient], "receiver delta is not exact");
        if (amount == 0) ++zeroTransfers;
        else ++positiveTransfers;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        modelAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
        ++approvals;
    }

    function _reject(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid call unexpectedly succeeded");
        assertEq(result, expectedError, "unexpected rejection reason");
        ++rejectedCalls;
        // The invariant checks the unchanged ledger after every handler call. Actions
        // with several calls also check immediately so later actions cannot mask damage.
        this.assertModel();
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % ACTORS];
    }

    function _amount(uint256 seed, uint256 limit) private pure returns (uint256) {
        if (limit == 0) return 0;
        uint256 mode = seed % 5;
        if (mode == 0) return 0;
        if (mode == 1) return 1;
        if (mode == 2) return limit;
        if (mode == 3) return limit - 1;
        return bound(seed, 0, limit);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
contract LaunchTokenStatefulTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    AdversarialTokenHandler private handler;
    LaunchToken private token;

    function setUp() public {
        handler = new AdversarialTokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = AdversarialTokenHandler.transfer.selector;
        selectors[1] = AdversarialTokenHandler.approve.selector;
        selectors[2] = AdversarialTokenHandler.transferFrom.selector;
        selectors[3] = AdversarialTokenHandler.rejectTransfer.selector;
        selectors[4] = AdversarialTokenHandler.rejectAllowance.selector;
        selectors[5] = AdversarialTokenHandler.rejectBalanceAfterApproval.selector;
        selectors[6] = AdversarialTokenHandler.rejectZeroRecipient.selector;
        selectors[7] = AdversarialTokenHandler.rejectZeroSpender.selector;
        selectors[8] = AdversarialTokenHandler.revokeAndReject.selector;
        selectors[9] = AdversarialTokenHandler.roundTrip.selector;
        selectors[10] = AdversarialTokenHandler.donateToToken.selector;
        selectors[11] = AdversarialTokenHandler.rejectMintOrBurn.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariantBalancesAndAllowancesMatchIndependentLedger() public view {
        handler.assertModel();
        assertEq(token.balanceOf(address(this)), 0, "tokens escaped the actor set");
    }

    function invariantIdentityNeverChanges() public view {
        assertEq(token.name(), "Extremely Long Dog");
        assertEq(token.symbol(), "XLONGDOG");
        assertEq(token.decimals(), 18);
    }

    /// @dev End-of-sequence liveness: every holder can empty its balance, including after
    /// adversarial calls. Token donations remain accounted for separately.
    function afterInvariant() public {
        assertGt(
            handler.positiveTransfers() + handler.zeroTransfers() + handler.approvals() + handler.rejectedCalls(), 0
        );
        address collector = handler.actor(0);
        for (uint256 i = 1; i < 4; ++i) {
            address owner = handler.actor(i);
            uint256 amount = handler.modelBalance(owner);
            vm.prank(owner);
            assertTrue(token.transfer(collector, amount));
            assertEq(token.balanceOf(owner), 0, "holder could not empty balance");
        }
        uint256 movableSupply = SUPPLY - handler.modelBalance(address(token));
        assertEq(token.balanceOf(collector), movableSupply);
        address recipient = handler.actor(1);
        vm.prank(collector);
        assertTrue(token.transfer(recipient, movableSupply));
        assertEq(token.balanceOf(collector), 0);
        assertEq(token.balanceOf(recipient), movableSupply);
        assertEq(token.balanceOf(address(token)), handler.modelBalance(address(token)));
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Deterministic reachability checks complement random selector coverage. In
    /// particular, delegated success, self-transfer, zero, max and reverts must all run.
    function testHandlerExercisesSuccessFailureAndBoundaryPaths() public {
        handler.transfer(0, 1, 1); // one minor unit
        handler.transfer(1, 1, 2); // full-balance self-transfer
        handler.transfer(2, 3, 0); // zero
        handler.approve(0, 1, 2); // infinite
        handler.transferFrom(0, 1, 2, 1);
        assertEq(token.allowance(handler.actor(0), handler.actor(1)), type(uint256).max);
        handler.rejectAllowance(0, 1, 2, type(uint256).max);
        handler.approve(0, 1, 3); // max minus one is finite
        handler.transferFrom(0, 1, 0, 1); // delegated self-transfer still consumes allowance
        assertEq(token.allowance(handler.actor(0), handler.actor(1)), type(uint256).max - 2);
        handler.rejectTransfer(0, 0, type(uint256).max);
        handler.rejectBalanceAfterApproval(0, 1, 2, false);
        handler.rejectBalanceAfterApproval(0, 1, 2, true);
        handler.rejectZeroRecipient(0, 1, 2, false);
        handler.rejectZeroRecipient(0, 1, 0, true);
        handler.rejectZeroSpender(0, type(uint256).max);
        handler.revokeAndReject(0, 1, 2);
        handler.roundTrip(0, 1, 2);
        handler.donateToToken(0, 1);
        handler.rejectMintOrBurn(0, 1, 1, true);
        handler.rejectMintOrBurn(1, 0, 1, false);
        handler.assertModel();
        assertEq(handler.rejectedCalls(), 12);
        assertGt(handler.positiveTransfers(), 0);
        assertGt(handler.zeroTransfers(), 0);
        assertGt(handler.approvals(), 0);
        afterInvariant();
    }
}
