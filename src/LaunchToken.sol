// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Extremely Long Dog (XLONGDOG)
/// @notice Fixed-supply launch token; the deploying factory receives the entire supply.
/// @custom:website https://midaswhale.wtf/xlongdog
/// @custom:source-post https://x.com/taylor_/status/2120975103148359750
/// @dev Unofficial fan meme, not affiliated with or endorsed by the post's author.
///      Supply allocation and pool fees are handled by the launch protocol, outside this token.
contract LaunchToken is ERC20 {
    constructor() ERC20("Extremely Long Dog", "XLONGDOG") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
