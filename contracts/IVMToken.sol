// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * IVM Token (ivm) – ERC20 with allocations, vesting, loyalty vault, and burn mechanics.
 * Supply: 500,000,000 IVM
 * - Community:            15% (immediate)
 * - Marketing:             5% (unlock 4 months after launch)
 * - Development & Tech:    5% (unlock 2027-02-01)
 * - Loyalty & Rewards:     5% (unlock 2026-12-31)
 * - Team:                 10% (2-year cliff, then 5% every 6 months)
 * - Reserve:              60% (5% every 2 years after a 2-year cliff)
 *
 * Burns:
 * - Voluntary burn (ERC20Burnable)
 * - Owner burn from owner balance
 * - Optional auto-burn on transfers (≤2%) with exemptions
 * - Buy-only burn: 0.08% when buying from liquidity pair
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// -----------------------------------------------------------------------
/// TrancheVestingWallet (OZ v5 Ownable)
/// -----------------------------------------------------------------------
contract TrancheVestingWallet is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public beneficiary;

    uint256 public immutable start;          // first release time
    uint256 public immutable period;         // seconds per tranche
    uint256 public immutable totalTranches;  // number of tranches
    uint256 public released;                 // total released so far

    event Released(uint256 amount, uint256 totalReleased);
    event BeneficiaryUpdated(address indexed oldB, address indexed newB);

    constructor(
        IERC20 _token,
        address _beneficiary,
        uint256 _start,
        uint256 _period,
        uint256 _totalTranches,
        address _owner
    ) Ownable(_owner) {
        require(address(_token) != address(0), "token=0");
        require(_beneficiary != address(0), "beneficiary=0");
        require(_period > 0, "period=0");
        require(_totalTranches > 0, "tranches=0");

        token = _token;
        beneficiary = _beneficiary;
        start = _start;
        period = _period;
        totalTranches = _totalTranches;
    }

    function setBeneficiary(address newBeneficiary) external onlyOwner {
        require(newBeneficiary != address(0), "beneficiary=0");
        emit BeneficiaryUpdated(beneficiary, newBeneficiary);
        beneficiary = newBeneficiary;
    }

    function releasable() public view returns (uint256) {
        return _vestedAmount() - released;
    }

    function release() external {
        uint256 amount = releasable();
        require(amount > 0, "nothing releasable");
        released += amount;
        token.safeTransfer(beneficiary, amount);
        emit Released(amount, released);
    }

    function _vestedAmount() internal view returns (uint256) {
        uint256 totalAllocation = token.balanceOf(address(this)) + released;
        if (block.timestamp < start) return 0;

        uint256 elapsedTranches = ((block.timestamp - start) / period) + 1;
        if (elapsedTranches > totalTranches) elapsedTranches = totalTranches;

        return (totalAllocation * elapsedTranches) / totalTranches;
    }
}

/// -----------------------------------------------------------------------
/// LoyaltyVault (OZ v5 Ownable)
/// -----------------------------------------------------------------------
contract LoyaltyVault is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    uint256 public immutable releaseTime;
    address public admin;

    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event Distributed(address indexed to, uint256 amount);
    event Swept(address indexed to, uint256 amount);

    constructor(
        IERC20 _token,
        uint256 _releaseTime,
        address _admin,
        address _owner
    ) Ownable(_owner) {
        require(address(_token) != address(0), "token=0");
        require(_admin != address(0), "admin=0");
        token = _token;
        releaseTime = _releaseTime;
        admin = _admin;
    }

    modifier onlyAfterRelease() {
        require(block.timestamp >= releaseTime, "locked");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin || msg.sender == owner(), "not admin");
        _;
    }

    function setAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "admin=0");
        emit AdminUpdated(admin, newAdmin);
        admin = newAdmin;
    }

    function distribute(address to, uint256 amount)
        external
        onlyAfterRelease
        onlyAdmin
    {
        require(to != address(0), "to=0");
        token.safeTransfer(to, amount);
        emit Distributed(to, amount);
    }

    function sweepRemaining(address to)
        external
        onlyAfterRelease
        onlyOwner
    {
        require(to != address(0), "to=0");
        uint256 bal = token.balanceOf(address(this));
        token.safeTransfer(to, bal);
        emit Swept(to, bal);
    }
}

/// -----------------------------------------------------------------------
/// IVMToken (main token)
/// -----------------------------------------------------------------------
contract IVMToken is ERC20, ERC20Burnable, Ownable {
    using SafeERC20 for IERC20;

    // ===== Supply & Allocations =====
    uint256 public constant TOTAL_SUPPLY           = 500_000_000 * 1e18;
    uint256 public constant COMMUNITY_AMT          = 75_000_000  * 1e18;  // 15%
    uint256 public constant MARKETING_AMT          = 25_000_000  * 1e18;  // 5%
    uint256 public constant DEV_TECH_AMT           = 25_000_000  * 1e18;  // 5%
    uint256 public constant LOYALTY_AMT            = 25_000_000  * 1e18;  // 5%
    uint256 public constant TEAM_AMT               = 50_000_000  * 1e18;  // 10%
    uint256 public constant RESERVE_AMT            = 300_000_000 * 1e18;  // 60%
    uint256 public constant MIN_CIRCULATING_SUPPLY = 21_000_000  * 1e18;  // burn cap target

    // ===== Timing =====
    uint256 public immutable launchTime;
    uint256 public constant TWO_YEARS = 730 days;              // approx
    uint256 public constant SIX_MONTHS = 182 days;             // approx half-year
    uint256 public constant FOUR_MONTHS = 120 days;            // approx
    uint256 public constant RESERVE_FIRST_RELEASE = 1_798_761_600; // 2027-01-01 00:00:00 UTC
    uint256 public constant RESERVE_TRANCHES = 12;              // 12 * 5% = 60%
    uint256 public constant DEV_TECH_RELEASE_TIME = 1_801_440_000; // 2027-02-01 00:00:00 UTC
    uint256 public constant LOYALTY_RELEASE_TIME = 1_798_675_200; // 2026-12-31 00:00:00 UTC

    // ===== Wallets / Vaults =====
    address public communityWallet;
    address public marketingWallet;
    TrancheVestingWallet public marketingVesting;
    address public devTechWallet;
    TrancheVestingWallet public devTechVesting;
    TrancheVestingWallet public teamVesting;
    TrancheVestingWallet public reserveVesting;
    LoyaltyVault public loyaltyVault;
    bool public allocationsInitialized;
    bool private _isReleasing;

    // ===== Burn Config =====
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address public burnWallet;

    // Optional general auto-burn (off by default)
    bool public autoBurnEnabled;
    uint16 public autoBurnBps; // ≤ 200 (2%)
    mapping(address => bool) public isExcludedFromAutoBurn;

    // Buy-only burn (0.08%) when tokens move from liquidity pair to buyer
    address public marketPair;
    bool public buyBurnEnabled = true;
    uint16 public buyBurnBps = 8; // 8 bps = 0.08%

    uint256 public totalAutoBurned;
    uint256 public totalBuyBurned;
    uint256 public totalManualBurned;
    uint256 public totalTokensSentToDead; // includes burns to address(0) and dead address

    // ===== Events =====
    event AllocationsInitialized(
        address indexed community,
        address indexed marketingBeneficiary,
        address indexed devTechBeneficiary,
        address marketingVesting,
        address devTechVesting,
        address teamVesting,
        address reserveVesting,
        address loyaltyVault
    );
    event AutoBurnUpdated(bool enabled, uint16 bps);
    event ExcludedFromAutoBurn(address indexed account, bool excluded);
    event MarketPairUpdated(address indexed pair);
    event BuyBurnUpdated(bool enabled, uint16 bps);
    event AutoBurn(address indexed from, address indexed wallet, uint256 amount);
    event BuyBurn(address indexed buyer, address indexed wallet, uint256 amount);
    event ManualBurn(address indexed from, address indexed wallet, uint256 amount);
    event AllocationReleased(address indexed vault, address indexed beneficiary, uint256 amount);
    event BurnWalletUpdated(address indexed previousWallet, address indexed newWallet);

    constructor() ERC20("ivm", "IVM") Ownable(msg.sender) {
        launchTime = block.timestamp;
        _mint(address(this), TOTAL_SUPPLY);
        burnWallet = DEAD;
        emit BurnWalletUpdated(address(0), burnWallet);
    }

    // ===== Setup allocations (one-time) =====
    function setupAllocations(
        address _communityWallet,
        address _marketingWallet,
        address _devTechWallet,
        address _teamBeneficiary,
        address _reserveBeneficiary,
        address _loyaltyAdmin
    ) external onlyOwner {
        require(!allocationsInitialized, "already initialized");
        require(_communityWallet != address(0), "community=0");
        require(_marketingWallet != address(0), "marketing=0");
        require(_devTechWallet != address(0), "devtech=0");
        require(_teamBeneficiary != address(0), "team=0");
        require(_reserveBeneficiary != address(0), "reserve=0");
        require(_loyaltyAdmin != address(0), "loyalty=0");

        communityWallet = _communityWallet;
        marketingWallet = _marketingWallet;
        devTechWallet = _devTechWallet;
        isExcludedFromAutoBurn[communityWallet] = true;
        isExcludedFromAutoBurn[marketingWallet] = true;
        isExcludedFromAutoBurn[devTechWallet] = true;

        // Marketing vesting: unlock 100% after 4 months
        marketingVesting = new TrancheVestingWallet(
            IERC20(address(this)),
            marketingWallet,
            launchTime + FOUR_MONTHS,
            1 days,
            1,
            owner()
        );

        // Development & Tech vesting: unlock 100% on Feb 1, 2027 (or later if deployed after)
        uint256 devStart = DEV_TECH_RELEASE_TIME;
        if (devStart < launchTime) {
            devStart = launchTime;
        }
        devTechVesting = new TrancheVestingWallet(
            IERC20(address(this)),
            devTechWallet,
            devStart,
            1 days,
            1,
            owner()
        );

        isExcludedFromAutoBurn[address(marketingVesting)] = true;
        isExcludedFromAutoBurn[address(devTechVesting)] = true;

        // Team vesting: 2-year cliff then 5% every 6 months (20 tranches of 5%)
        teamVesting = new TrancheVestingWallet(
            IERC20(address(this)),
            _teamBeneficiary,
            launchTime + TWO_YEARS,
            SIX_MONTHS,
            20,
            owner()
        );

        // Reserve vesting: 2-year cliff then 5% every 2 years (12 tranches)
        uint256 reserveStart = launchTime + TWO_YEARS;
        if (reserveStart < RESERVE_FIRST_RELEASE) {
            reserveStart = RESERVE_FIRST_RELEASE;
        }
        reserveVesting = new TrancheVestingWallet(
            IERC20(address(this)),
            _reserveBeneficiary,
            reserveStart,
            TWO_YEARS,
            RESERVE_TRANCHES,
            owner()
        );

        isExcludedFromAutoBurn[address(teamVesting)] = true;
        isExcludedFromAutoBurn[address(reserveVesting)] = true;

        // Loyalty & Rewards vault: distribution not allowed before 2026-12-31
        loyaltyVault = new LoyaltyVault(
            IERC20(address(this)),
            LOYALTY_RELEASE_TIME,
            _loyaltyAdmin,
            owner()
        );

        isExcludedFromAutoBurn[address(loyaltyVault)] = true;

        // Transfers of allocations
        _transfer(address(this), communityWallet, COMMUNITY_AMT);
        _transfer(address(this), address(marketingVesting), MARKETING_AMT);
        _transfer(address(this), address(devTechVesting), DEV_TECH_AMT);
        _transfer(address(this), address(teamVesting), TEAM_AMT);
        _transfer(address(this), address(reserveVesting), RESERVE_AMT);
        _transfer(address(this), address(loyaltyVault), LOYALTY_AMT);

        // Exclude system wallets from auto-burn
        allocationsInitialized = true;
        emit AllocationsInitialized(
            communityWallet,
            marketingWallet,
            devTechWallet,
            address(marketingVesting),
            address(devTechVesting),
            address(teamVesting),
            address(reserveVesting),
            address(loyaltyVault)
        );
    }

    // ===== Burn controls =====
    function setAutoBurn(bool enabled, uint16 bps) external onlyOwner {
        require(bps <= 200, "max 2%");
        autoBurnEnabled = enabled;
        autoBurnBps = bps;
        emit AutoBurnUpdated(enabled, bps);
    }

    function setExcludedFromAutoBurn(address account, bool excluded) external onlyOwner {
        require(account != address(0), "zero addr");
        isExcludedFromAutoBurn[account] = excluded;
        emit ExcludedFromAutoBurn(account, excluded);
    }

    function ownerBurn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }

    function setBurnWallet(address newBurnWallet) external onlyOwner {
        require(newBurnWallet != address(0), "burn wallet=0");
        address previous = burnWallet;
        burnWallet = newBurnWallet;
        emit BurnWalletUpdated(previous, newBurnWallet);
    }

    // ===== Buy-only burn controls =====
    function setMarketPair(address _pair) external onlyOwner {
        require(_pair != address(0), "pair=0");
        marketPair = _pair;
        emit MarketPairUpdated(_pair);
    }

    function setBuyBurn(bool enabled, uint16 bps) external onlyOwner {
        require(bps <= 100, "max 1%");
        buyBurnEnabled = enabled;
        buyBurnBps = bps;
        emit BuyBurnUpdated(enabled, bps);
    }

    function releaseUnlockedAllocations() public {
        _attemptAutoRelease();
    }

    // ===== Transfer hook with burn logic =====
    function _update(address from, address to, uint256 value) internal virtual override {
        if (!_isReleasing && allocationsInitialized) {
            _attemptAutoRelease();
        }

        if (from != address(0) && to == address(0)) {
            uint256 burnCapacity = _remainingBurnCapacity();
            require(burnCapacity >= value, "burn cap reached");

            super._update(from, to, value);

            totalManualBurned += value;
            totalTokensSentToDead += value;
            emit ManualBurn(from, to, value);
            return;
        }

        uint256 manualBurnAmount;

        // A) Optional general auto-burn
        if (
            autoBurnEnabled &&
            autoBurnBps > 0 &&
            from != address(0) &&
            to != address(0) &&
            !isExcludedFromAutoBurn[from] &&
            !isExcludedFromAutoBurn[to]
        ) {
            uint256 burnAmt = (value * autoBurnBps) / 10_000;
            uint256 burnCapacity = _remainingBurnCapacity();
            if (burnAmt > burnCapacity) {
                burnAmt = burnCapacity;
            }
            if (burnAmt > 0) {
                super._update(from, burnWallet, burnAmt);
                value -= burnAmt;
                totalAutoBurned += burnAmt;
                totalTokensSentToDead += burnAmt;
                emit AutoBurn(from, burnWallet, burnAmt);
            }
        }

        // B) Buy-only burn (0.08%) when from == marketPair (buy)
        if (
            buyBurnEnabled &&
            marketPair != address(0) &&
            from == marketPair &&
            to != address(0) &&
            !isExcludedFromAutoBurn[to]
        ) {
            uint256 buyBurnAmount = (value * buyBurnBps) / 10_000;
            uint256 burnCapacity = _remainingBurnCapacity();
            if (buyBurnAmount > burnCapacity) {
                buyBurnAmount = burnCapacity;
            }
            if (buyBurnAmount > 0) {
                super._update(from, burnWallet, buyBurnAmount);
                value -= buyBurnAmount;
                totalBuyBurned += buyBurnAmount;
                totalTokensSentToDead += buyBurnAmount;
                emit BuyBurn(to, burnWallet, buyBurnAmount);
            }
        }

        if ((to == burnWallet || to == DEAD) && from != address(0) && value > 0) {
            require(_remainingBurnCapacity() >= value, "burn cap reached");
            manualBurnAmount = value;
        }

        super._update(from, to, value);

        if (manualBurnAmount > 0) {
            totalManualBurned += manualBurnAmount;
            totalTokensSentToDead += manualBurnAmount;
            emit ManualBurn(from, to, manualBurnAmount);
        }
    }

    // Safety: reject stray ETH
    receive() external payable {
        revert("No ETH accepted");
    }

    function _remainingBurnCapacity() private view returns (uint256) {
        if (TOTAL_SUPPLY <= MIN_CIRCULATING_SUPPLY) {
            return 0;
        }
        uint256 targetBurnTotal = TOTAL_SUPPLY - MIN_CIRCULATING_SUPPLY;
        if (totalTokensSentToDead >= targetBurnTotal) {
            return 0;
        }
        return targetBurnTotal - totalTokensSentToDead;
    }

    function _attemptAutoRelease() private {
        if (_isReleasing || !allocationsInitialized) {
            return;
        }
        _isReleasing = true;
        _releaseIfReady(marketingVesting);
        _releaseIfReady(devTechVesting);
        _releaseIfReady(teamVesting);
        _releaseIfReady(reserveVesting);
        _isReleasing = false;
    }

    function _releaseIfReady(TrancheVestingWallet vesting) private {
        address vestingAddress = address(vesting);
        if (vestingAddress == address(0)) return;
        uint256 amount = vesting.releasable();
        if (amount == 0) return;

        address beneficiary = vesting.beneficiary();
        try vesting.release() {
            emit AllocationReleased(vestingAddress, beneficiary, amount);
        } catch {
            // no-op: keep tokens locked if release reverts
        }
    }
}
