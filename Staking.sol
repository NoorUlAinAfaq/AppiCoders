// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract StakingWithNFT is Ownable {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    // Staking token
    IERC20 public stakingToken;
    
    // LP tokens as NFTs
    LPToken public lpToken;
    
    // Achievement badges as NFTs
    AchievementBadge public achievementBadge;
    
    // Tier thresholds in tokens earned
    uint256[] public tiers = [1000, 5000, 10000];
    string[] public tierNames = ["Bronze", "Silver", "Gold"];
    
    // Fixed rewards rate - 10% APR
    uint256 public constant REWARD_RATE = 10;
    uint256 public constant REWARD_RATE_DENOMINATOR = 100;
    uint256 public constant SECONDS_IN_YEAR = 365 days;
    
    // Staker information
    struct StakerInfo {
        uint256 stakedAmount;
        uint256 lastUpdateTime;
        uint256 timeWeightedScore;
        uint256 rewardsEarned;
        uint256 currentTier;
        bool hasStaked;
    }
    
    // Mapping from staker address to their info
    mapping(address => StakerInfo) public stakerInfo;
    
    // Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardsHarvested(address indexed user, uint256 amount);
    event TierAchieved(address indexed user, uint256 tier);
    event LPTokenMinted(address indexed user, uint256 tokenId);
    event AchievementBadgeMinted(address indexed user, uint256 tokenId, uint256 tier);
    
    constructor(address _stakingToken) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        lpToken = new LPToken();
        achievementBadge = new AchievementBadge();
    }
    
    // User stakes tokens
    function stake(uint256 amount) external {
        require(amount > 0, "Cannot stake 0");
        
        // Update rewards first
        _updateRewards(msg.sender);
        
        // Transfer tokens to this contract
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Update staked amount
        stakerInfo[msg.sender].stakedAmount += amount;
        
        // If first time staking, mint LP NFT
        if (!stakerInfo[msg.sender].hasStaked) {
            stakerInfo[msg.sender].hasStaked = true;
            uint256 tokenId = lpToken.mint(msg.sender);
            emit LPTokenMinted(msg.sender, tokenId);
        }
        
        // Update LP token metadata
        _updateLPTokenMetadata(msg.sender);
        
        emit Staked(msg.sender, amount);
    }
    
    // User withdraws tokens
    function withdraw(uint256 amount) external {
        StakerInfo storage staker = stakerInfo[msg.sender];
        require(staker.hasStaked, "No stake found");
        require(amount > 0 && amount <= staker.stakedAmount, "Invalid withdraw amount");
        
        // Update rewards first
        _updateRewards(msg.sender);
        
        // Update staked amount
        staker.stakedAmount -= amount;
        
        // Transfer tokens back to user
        stakingToken.safeTransfer(msg.sender, amount);
        
        // Update LP token metadata
        _updateLPTokenMetadata(msg.sender);
        
        emit Withdrawn(msg.sender, amount);
    }
    
    // Harvest rewards (calculated but not transferred yet)
    function harvestRewards() external {
        // Update rewards first
        _updateRewards(msg.sender);
        
        StakerInfo storage staker = stakerInfo[msg.sender];
        uint256 rewards = _calculatePendingRewards(msg.sender);
        require(rewards > 0, "No rewards to harvest");
        
        // Reset last update time to now
        staker.lastUpdateTime = block.timestamp;
        
        // Add to total rewards earned (for tier tracking)
        staker.rewardsEarned += rewards;
        
        // Check if user crossed a tier threshold
        _checkAndUpdateTier(msg.sender);
        
        // Update LP token metadata
        _updateLPTokenMetadata(msg.sender);
        
        // For simplicity, let's say rewards are the same token
        // In a real implementation, you'd have a separate reward token
        stakingToken.safeTransfer(msg.sender, rewards);
        
        emit RewardsHarvested(msg.sender, rewards);
    }
    
    // Calculate pending rewards for a user
    function pendingRewards(address user) public view returns (uint256) {
        return _calculatePendingRewards(user);
    }
    
    // Internal function to calculate pending rewards
    function _calculatePendingRewards(address user) internal view returns (uint256) {
        StakerInfo storage staker = stakerInfo[user];
        if (staker.stakedAmount == 0) return 0;
        
        uint256 timeElapsed = block.timestamp - staker.lastUpdateTime;
        return (staker.stakedAmount * REWARD_RATE * timeElapsed) / (REWARD_RATE_DENOMINATOR * SECONDS_IN_YEAR);
    }
    
    // Internal function to update rewards
    function _updateRewards(address user) internal {
        StakerInfo storage staker = stakerInfo[user];
        
        // If first stake, initialize time
        if (!staker.hasStaked) {
            staker.lastUpdateTime = block.timestamp;
            return;
        }
        
        uint256 timeElapsed = block.timestamp - staker.lastUpdateTime;
        
        // Update time-weighted score: stakedAmount * timeElapsed
        if (staker.stakedAmount > 0 && timeElapsed > 0) {
            staker.timeWeightedScore += staker.stakedAmount * timeElapsed;
        }
        
        // Update last interaction time
        staker.lastUpdateTime = block.timestamp;
    }
    
    // Check and update tier, minting achievement NFT if needed
    function _checkAndUpdateTier(address user) internal {
        StakerInfo storage staker = stakerInfo[user];
        
        // Check if user crossed a tier threshold
        for (uint256 i = 0; i < tiers.length; i++) {
            if (staker.rewardsEarned >= tiers[i] && staker.currentTier <= i) {
                // User reached a new tier
                staker.currentTier = i + 1;
                
                // Mint achievement badge NFT
                uint256 badgeId = achievementBadge.mint(user, i);
                
                emit TierAchieved(user, i + 1);
                emit AchievementBadgeMinted(user, badgeId, i + 1);
            }
        }
    }
    
    // Update LP token metadata
    function _updateLPTokenMetadata(address user) internal {
        StakerInfo storage staker = stakerInfo[user];
        if (!staker.hasStaked) return;
        
        // Find the LP token ID for this user (assuming 1 LP token per user)
        uint256 tokenId = lpToken.tokenOfOwnerByIndex(user, 0);
        
        // Generate new metadata
        string memory metadata = _generateLPTokenMetadata(user);
        
        // Update the token URI
        lpToken.setTokenURI(tokenId, metadata);
    }
    
    // Generate LP token metadata as base64-encoded JSON
    function _generateLPTokenMetadata(address user) internal view returns (string memory) {
        StakerInfo storage staker = stakerInfo[user];
        
        string memory currentTierName = staker.currentTier > 0 && staker.currentTier <= tierNames.length 
            ? tierNames[staker.currentTier - 1] 
            : "None";
        
        string memory json = string(abi.encodePacked(
            '{"name": "Staking LP Token", "description": "Represents your stake in the pool", ',
            '"attributes": [',
            '{"trait_type": "Staked Amount", "value": "', staker.stakedAmount.toString(), '"},',
            '{"trait_type": "Time-Weighted Score", "value": "', staker.timeWeightedScore.toString(), '"},',
            '{"trait_type": "Rewards Earned", "value": "', staker.rewardsEarned.toString(), '"},',
            '{"trait_type": "Current Tier", "value": "', currentTierName, '"}',
            ']}'
        ));
        
        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }
    
    // Get user staking information
    function getUserInfo(address user) external view returns (
        uint256 stakedAmount,
        uint256 timeWeightedScore,
        uint256 rewardsEarned,
        uint256 currentTier,
        bool hasStaked,
        uint256 pendingRewardsAmount
    ) {
        StakerInfo storage staker = stakerInfo[user];
        return (
            staker.stakedAmount,
            staker.timeWeightedScore,
            staker.rewardsEarned,
            staker.currentTier,
            staker.hasStaked,
            _calculatePendingRewards(user)
        );
    }
}

// LP Token as NFT
contract LPToken is ERC721URIStorage {
    using Strings for uint256;

    uint256 private _tokenIdCounter;
    address public stakingContract;
    
    // Mapping to track tokens owned by each address
    mapping(address => uint256[]) private _tokensOfOwner;
    
    constructor() ERC721("Staking LP Token", "SLPT") {
        stakingContract = msg.sender;
    }
    
    modifier onlyStakingContract() {
        require(msg.sender == stakingContract, "Only staking contract");
        _;
    }
    
    function mint(address to) external onlyStakingContract returns (uint256) {
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _safeMint(to, tokenId);
        _tokensOfOwner[to].push(tokenId);
        
        return tokenId;
    }
    
    function setTokenURI(uint256 tokenId, string memory uri) external onlyStakingContract {
        _setTokenURI(tokenId, uri);
    }
    
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        require(index < _tokensOfOwner[owner].length, "Index out of bounds");
        return _tokensOfOwner[owner][index];
    }
    
    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        return _tokensOfOwner[owner];
    }
    
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = super._update(to, tokenId, auth);
        
        // Update the tokens of owner mapping
        if (from != address(0)) {
            _removeTokenFromOwnerEnumeration(from, tokenId);
        }
        
        if (to != address(0)) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }
        
        return from;
    }
    
    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        _tokensOfOwner[to].push(tokenId);
    }
    
    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        uint256[] storage tokenList = _tokensOfOwner[from];
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == tokenId) {
                tokenList[i] = tokenList[tokenList.length - 1];
                tokenList.pop();
                break;
            }
        }
    }
}

// Achievement Badge NFT
contract AchievementBadge is ERC721URIStorage {
    using Strings for uint256;
    using Base64 for bytes;

    uint256 private _tokenIdCounter;
    address public stakingContract;
    
    // Store tier for each badge
    mapping(uint256 => uint256) public badgeTier;
    
    // Tier names
    string[] public tierNames = ["Bronze", "Silver", "Gold"];
    
    constructor() ERC721("Staking Achievement Badge", "SAB") {
        stakingContract = msg.sender;
    }
    
    modifier onlyStakingContract() {
        require(msg.sender == stakingContract, "Only staking contract");
        _;
    }
    
    function mint(address to, uint256 tier) external onlyStakingContract returns (uint256) {
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _safeMint(to, tokenId);
        badgeTier[tokenId] = tier;
        
        // Generate and set token URI
        string memory uri = _generateBadgeMetadata(tokenId, tier);
        _setTokenURI(tokenId, uri);
        
        return tokenId;
    }
    
    function _generateBadgeMetadata(uint256 tokenId, uint256 tier) internal view returns (string memory) {
        string memory tierName = tier < tierNames.length ? tierNames[tier] : "Unknown";
        
        string memory json = string(abi.encodePacked(
            '{"name": "', tierName, ' Achievement Badge", ',
            '"description": "This badge certifies achievement of the ', tierName, ' tier.", ',
            '"attributes": [{"trait_type": "Tier", "value": "', tierName, '"}]}'
        ));
        
        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }
}