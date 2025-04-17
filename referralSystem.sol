// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ReferralRewards is Ownable {
    // Custom ERC20 token for rewards
    RewardToken public rewardToken;
    
    // Address authorized to trigger referral rewards (backend wallet)
    address public authorizedAddress;
    
    // Referral rewards in tokens (configurable)
    uint256 public referrerReward = 50 * 10**18; // 50 tokens
    uint256 public refereeReward = 25 * 10**18; // 25 tokens
    
    // Mapping to track if an address has already been referred
    mapping(address => bool) public hasBeenReferred;
    
    // Mapping to track referrer of each user
    mapping(address => address) public referrerOf;
    
    // Mapping to track all referees for a given referrer
    mapping(address => address[]) public refereesOf;
    
    // Events
    event ReferralRegistered(address indexed referrer, address indexed referee, uint256 timestamp);
    event RewardsDistributed(address indexed referrer, address indexed referee, uint256 referrerAmount, uint256 refereeAmount);
    event AuthorizedBackendChanged(address indexed previousBackend, address indexed newBackend);
    event RewardAmountsChanged(uint256 newReferrerReward, uint256 newRefereeReward);
    
    
    constructor() Ownable(msg.sender) {
        rewardToken = new RewardToken();
        authorizedAddress = msg.sender; // Initially set the deployer as the authorized backend
    }
    
  
    modifier onlyAuthorizedAddress() {
        require(msg.sender == authorizedAddress, "Not authorized");
        _;
    }
    

    function setAuthorizedAddres(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Invalid address");
        emit AuthorizedBackendChanged(authorizedAddress, _newAddress);
        authorizedAddress = _newAddress;
    }
    
    
    function setRewardAmounts(uint256 _referrerReward, uint256 _refereeReward) external onlyOwner {
        referrerReward = _referrerReward;
        refereeReward = _refereeReward;
        emit RewardAmountsChanged(_referrerReward, _refereeReward);
    }
    

    function processReferral(address _referee, address _referrer) external onlyAuthorizedAddress {
        // Validate addresses
        require(_referee != address(0) && _referrer != address(0), "Invalid address");
        
        // Prevent self-referrals
        require(_referee != _referrer, "Self-referral not allowed");
        
        // Ensure the referee has not been referred before
        require(!hasBeenReferred[_referee], "User already referred");
        
        // Prevent circular referrals (A → B → A)
        address currentReferrer = _referrer;
        while (currentReferrer != address(0)) {
            require(currentReferrer != _referee, "Circular referral detected");
            currentReferrer = referrerOf[currentReferrer];
        }
        
        // Register the referral
        hasBeenReferred[_referee] = true;
        referrerOf[_referee] = _referrer;
        refereesOf[_referrer].push(_referee);
        
        emit ReferralRegistered(_referrer, _referee, block.timestamp);
        
        // Distribute rewards
        rewardToken.mint(_referrer, referrerReward);
        rewardToken.mint(_referee, refereeReward);
        
        emit RewardsDistributed(_referrer, _referee, referrerReward, refereeReward);
    }
   
    function getReferees(address _referrer) external view returns (address[] memory) {
        return refereesOf[_referrer];
    }
    

    function getRefereeCount(address _referrer) external view returns (uint256) {
        return refereesOf[_referrer].length;
    }
}


contract RewardToken is ERC20, Ownable {
    // The ReferralRewards contract that is authorized to mint tokens
    address public minter;
    
    
    constructor() ERC20("Referral Reward", "RFR") Ownable(msg.sender) {
        minter = msg.sender; // Initially set to the deployer (will be the ReferralRewards contract)
    }
  
    modifier onlyMinter() {
        require(msg.sender == minter, "Not authorized to mint");
        _;
    }
    

    function setMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "Invalid minter address");
        minter = _minter;
    }
   
    function mint(address _to, uint256 _amount) external onlyMinter {
        _mint(_to, _amount);
    }
}