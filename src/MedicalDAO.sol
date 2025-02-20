// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

error MedicalDAO__InitialMemberLimitReached();
error MedicalDAO__AlreadyDAOMember();

contract MedicalDAO is ERC721Enumerable, Ownable {
    uint256 public constant MAX_INITIAL_MEMBERS = 50;
    uint256 public constant MIN_DIFFERENT_CAMPAIGN_DEPOSITS_FOR_MEMBERSHIP = 60;
    uint256 public constant MIN_DONATION_AMOUNT = 30; //Minimum donation (in USD units) required per campaign for membership qualification.

    uint256 private _tokenIdCounter;
    address[] public daoMembers;

    mapping(address => bool) public isMember;
    mapping(address => uint256) public daoRewards;
    mapping(address => mapping(uint256 => bool)) public campaignDeposits; // Tracks unique campaign deposits
    mapping(address => uint256) public uniqueCampaignDepositsCount;
    mapping(address => mapping(uint256 => uint256)) public donorCampaignDonationTotal; //Keeps track of how much a donor has donated to each campaign.

    event MemberAdded(address indexed member, uint256 tokenId);
    event DepositRecorded(address indexed donor, uint256 campaignId);

    constructor() ERC721("MedicalDAO Membership", "MDAO") Ownable(msg.sender) {}

    function registerMember(address member) external {
        if (totalSupply() > MAX_INITIAL_MEMBERS) {
            revert MedicalDAO__InitialMemberLimitReached();
        }
        if (isMember[member]) {
            revert MedicalDAO__AlreadyDAOMember();
        }
        daoMembers.push(member);
        _mintMember(member);
    }

    /**
     * @notice Records a donation for a given campaign.
     * @param donor The address of the donor.
     * @param campaignId The unique campaign identifier.
     * @param donationAmount The donation amount (in USD units) for this deposit.
     *
     * The donor’s cumulative donation for the campaign is updated.
     * Once the cumulative donation equals or exceeds $10 and if not already counted,
     * the campaign is marked as qualified, and the donor’s unique campaign count is incremented.
     */
    function recordDeposit(address donor, uint256 campaignId, uint256 donationAmount) external onlyOwner {
        // Update the cumulative donation amount for this donor and campaign.
        donorCampaignDonationTotal[donor][campaignId] += donationAmount;

        // Only mark this campaign as "qualified" if the donor hasn’t already been credited
        // and their cumulative donation is at least $10.
        if (
            !campaignDeposits[donor][campaignId] && donorCampaignDonationTotal[donor][campaignId] >= MIN_DONATION_AMOUNT
        ) {
            campaignDeposits[donor][campaignId] = true;
            uniqueCampaignDepositsCount[donor] += 1;
        }
        emit DepositRecorded(donor, campaignId);
    }

    /**
     * @notice Allows a donor to claim DAO membership.
     * To qualify, the donor must have contributed at least $10 (cumulatively) in 60 or more unique campaigns.
     */
    function claimMembership() external {
        if (isMember[msg.sender]) {
            revert MedicalDAO__AlreadyDAOMember();
        }
        if (uniqueCampaignDepositsCount[msg.sender] >= MIN_DIFFERENT_CAMPAIGN_DEPOSITS_FOR_MEMBERSHIP) {
            _mintMember(msg.sender);
            return;
        }
    }

    function _mintMember(address member) internal {
        _tokenIdCounter++;
        _safeMint(member, _tokenIdCounter);
        isMember[member] = true;
        emit MemberAdded(member, _tokenIdCounter);
    }

    function isDaoMember(address account) external view returns (bool) {
        return isMember[account];
    }

    function getTotalMembers() external view returns (uint256) {
        return totalSupply();
    }
}
