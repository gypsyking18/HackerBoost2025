// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {MedicalDAO} from "./MedicalDAO.sol";

error MedicalCrowdfunding__NoFund();
error MedicalCrowdfunding__NotOwner();
error MedicalCrowdfunding__NotDAOMember();
error MedicalCrowdfunding__NoPendingCampaign();
error MedicalCrowdfunding__VotingPeriodIsOver();
error MedicalCrowdfunding__VotingNotEnded();
error MedicalCrowdfunding__CampaignDeadlinePass();
error MedicalCrowdfunding__FeeExceedsMaximum();
error MedicalCrowdfunding__VotingPeriodOver();
error MedicalCrowdfunding__AlreadyVoted();
error MedicalCrowdfunding__ProposalExecuted();
error MedicalCrowdfunding__NotActive();
error MedicalCrowdfunding__TransferFailed();
error MedicalCrowdfunding__HasAlreadyVoted();
error MedicalCrowdfunding__NotPatient();
error MedicalCrowdfunding__CampaignNotSuccessful();
error MedicalCrowdfunding__InvalidAddress();
error MedicalCrowdfunding__VotingPeriodIsNotOver();
error MedicalCrowdfunding__DeadlineNotPassed();
error MedicalCrowdfunding__CampaignNotActive();
error MedicalCrowdfunding__NoDAOVotersParticipation();

contract MedicalCrowdfunding is ReentrancyGuard {
    using PriceConverter for uint256;
    using Math for uint256;
    using SafeERC20 for IERC20; // Prevent sending tokens to recipients who can’t receive

    MedicalDAO private immutable i_memberDAO;
    uint256 private votingDuration;
    uint256 public serviceFeePercentage; // Initial service fee
    uint256 public totalFees;

    enum CampaignStatus {
        PendingVerification,
        Active,
        Successful,
        Failed,
        GoalAmountNotreached
    }

    enum CampaignCategory {
        Surgery,
        Cancer,
        Emergency,
        Others
    }

    struct Description {
        string patientname;
        string hospital;
        string hospitalNumber;
        string doctorName;
    }

    struct Documents {
        string diagnosisReportURI;
        string treatmentPlanCostEstimateURI;
        string hospitalDoctorLetterURI;
        string patientId;
        string identityProofURI; // IPFS hash/URI for Proof of Identity & Relationship(Optional)
        string medicalBillsURI;
    } // IPFS hash/URI for the documents.

    struct Campaign {
        address payable patientEthAddress;
        uint256 goalAmountInUSD;
        uint256 raisedAmountInUSD;
        Description description;
        address[] donors;
        uint256 deadline;
        CampaignStatus status;
        CampaignCategory category;
        Documents documents; // Holds all the document URIs provided by the patient
    }

    struct FeeProposal {
        uint256 proposedFee;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 startTime; // When the proposal becomes active for voting
        uint256 endTime; // The timestamp when the voting period ends.
        bool executed; // Indicating whether the proposal has been finalized (executed) or not.
        uint256 totalMembersAtCreation;
    }

    // ==== Mapping for FeeProposal =====
    mapping(uint256 => FeeProposal) public feeProposals;
    mapping(uint256 => mapping(address => bool)) public hasVotedOnFeeProposal;
    mapping(uint256 => Campaign) public campaigns;
    mapping(address => uint256[]) public donorCampaigns;
    mapping(address => uint256) private s_addressToAmountDonated;
    mapping(uint256 => bool) public verifiedCampaigns;

    // ===== Mapping for Voting =====
    mapping(uint256 => address[]) public campaignVoters; // NEW mapping for tracking campaign verification voters
    mapping(uint256 => uint256) private s_campaignYesVotes;
    mapping(uint256 => uint256) private s_campaignNoVotes;
    mapping(uint256 => uint256) private s_campaignTotalVotes;
    mapping(uint256 => mapping(address => bool)) private s_hasVoted; // Tracks whether a DAO member has already voted on a given campaign.
    mapping(uint256 => uint256) public campaignCreationTime;

    /// Storage Variables
    uint256 public s_campaignIdCounter = 0;
    address private immutable i_owner;
    AggregatorV3Interface private s_priceFeed;
    uint256 public feeProposalCounter = 0;
    uint256 public campaignDuration;

    event CampaignCreated(uint256 campaignId, address patientEthAddress);
    event CampaignVerified(uint256 campaignId);
    event CampaignRejected(uint256 campaignId);
    event FundsReleased(uint256 campaignId, uint256 amount);
    event Voted(uint256 campaignId, address voter, bool approved);
    event FeeProposalCreated(uint256 feeProposalCounter, uint256 newFee);
    event FeeProposalVoted(uint256 proposalId, address voter, bool support);
    event FeeProposalFailed(uint256 proposalId);
    event FeeChanged(uint256 proposalId, uint256 proposedFee);
    event CampaignStatusUpdated(uint256 campaignId, CampaignStatus status);
    event DonationReceived(uint256 campaignId, address donor, uint256 amount, uint256 fee, uint256 netAmount);

    modifier zeroFund() {
        if (msg.value == 0) {
            revert MedicalCrowdfunding__NoFund();
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != i_owner) {
            revert MedicalCrowdfunding__NotOwner();
        }
        _;
    }

    modifier onlyDAOMember() {
        if (!i_memberDAO.isDaoMember(msg.sender)) {
            revert MedicalCrowdfunding__NotDAOMember();
        }
        _;
    }

    /// @notice Initializes the contract’s state.
    /// @dev Added input validations (e.g., ensuring non-zero addresses for critical parameters).
    constructor(
        address priceFeed,
        uint256 campaignIdCounter,
        uint256 initialVotingDuration,
        uint256 _campaignDuration,
        address daoAddress
    ) {
        require(priceFeed != address(0), "Invalid price feed address");
        require(daoAddress != address(0), "Invalid DAO address");

        s_priceFeed = AggregatorV3Interface(priceFeed);
        s_campaignIdCounter = campaignIdCounter;
        i_owner = msg.sender;
        i_memberDAO = MedicalDAO(daoAddress);
        votingDuration = initialVotingDuration;
        campaignDuration = _campaignDuration;
    } //  Initializes the contract’s state.

    function setVotingDuration(uint256 _votingDuration) external onlyOwner {
        votingDuration = _votingDuration;
    }

    // @notice Enables DAO members to propose a change in the service fee.
    function proposeFeeChange(uint256 newFee) external onlyDAOMember {
        if (newFee > 5) {
            revert MedicalCrowdfunding__FeeExceedsMaximum();
        }
        feeProposalCounter++;
        feeProposals[feeProposalCounter] = FeeProposal({
            proposedFee: newFee,
            yesVotes: 0,
            noVotes: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + votingDuration,
            executed: false,
            totalMembersAtCreation: i_memberDAO.getTotalMembers()
        });
        emit FeeProposalCreated(feeProposalCounter, newFee);
    }

    function voteOnFeeProposal(uint256 proposalId, bool support) external onlyDAOMember {
        FeeProposal storage proposal = feeProposals[proposalId];

        if (block.timestamp > proposal.endTime) {
            revert MedicalCrowdfunding__VotingPeriodOver();
        }
        if (proposal.executed) {
            revert MedicalCrowdfunding__ProposalExecuted();
        }
        if (hasVotedOnFeeProposal[proposalId][msg.sender]) {
            revert MedicalCrowdfunding__AlreadyVoted();
        }

        if (support) {
            proposal.yesVotes += 1;
        } else {
            proposal.noVotes += 1;
        }
        hasVotedOnFeeProposal[proposalId][msg.sender] = true;
        emit FeeProposalVoted(proposalId, msg.sender, support);
    }

    // Checks that the voting period is over and that the proposal hasn’t already been executed.
    function executeFeeProposal(uint256 proposalId) external {
        FeeProposal storage proposal = feeProposals[proposalId];
        if (block.timestamp <= proposal.endTime) {
            revert MedicalCrowdfunding__VotingNotEnded();
        }
        if (proposal.executed) {
            revert MedicalCrowdfunding__ProposalExecuted();
        }
        proposal.executed = true;

        uint256 totalVotes = proposal.yesVotes + proposal.noVotes;
        uint256 quorum = (proposal.totalMembersAtCreation * 60) / 100;

        if (totalVotes >= quorum && proposal.yesVotes > proposal.noVotes) {
            serviceFeePercentage = proposal.proposedFee;
            emit FeeChanged(proposalId, proposal.proposedFee);
        } else {
            emit FeeProposalFailed(proposalId);
        }
    }

    // ===== Campaign Creation =====
    /// @notice Called by a patient to create a new campaign.
    /// @param goalAmountInUSD The funding goal expressed in USD.
    /// @param description Medical/hospital details.
    /// @param category The category of the campaign.
    /// @param documents URI for additional metadata (e.g. stored on IPFS).
    function createCampaign(
        address payable patientEthAddress,
        uint256 goalAmountInUSD,
        Description calldata description,
        uint256 customCampaignDuration,
        CampaignCategory category,
        Documents calldata documents
    ) external {
        Campaign storage newCampaign = campaigns[s_campaignIdCounter];
        campaignCreationTime[s_campaignIdCounter] = block.timestamp;

        if (newCampaign.patientEthAddress == address(0)) {
            revert MedicalCrowdfunding__InvalidAddress();
        }

        newCampaign.patientEthAddress = patientEthAddress;
        newCampaign.goalAmountInUSD = goalAmountInUSD;
        newCampaign.raisedAmountInUSD = 0;
        newCampaign.description = description;
        uint256 duration = customCampaignDuration > 0 ? customCampaignDuration : campaignDuration; // Use customCampaignDuration if provided; otherwise, fallback to the global campaignDuration
        newCampaign.deadline = block.timestamp + duration;
        newCampaign.status = CampaignStatus.PendingVerification;
        newCampaign.category = category;
        newCampaign.documents = documents;

        emit CampaignCreated(s_campaignIdCounter, newCampaign.patientEthAddress);
        s_campaignIdCounter++;
    }

    function voteOnCampaign(uint256 campaignId, bool approve) external onlyDAOMember {
        Campaign storage campaign = campaigns[campaignId];
        if (campaign.status != CampaignStatus.PendingVerification) {
            revert MedicalCrowdfunding__NoPendingCampaign();
        }

        uint256 effectiveVotingDeadline = campaignCreationTime[campaignId] + votingDuration;
        if (block.timestamp > effectiveVotingDeadline) {
            revert MedicalCrowdfunding__VotingPeriodIsOver();
        }

        if (s_hasVoted[campaignId][msg.sender]) {
            revert MedicalCrowdfunding__HasAlreadyVoted();
        }

        if (approve) {
            s_campaignYesVotes[campaignId]++;
        } else {
            s_campaignNoVotes[campaignId]++;
        }
        s_hasVoted[campaignId][msg.sender] = true;
        campaignVoters[campaignId].push(msg.sender); // Record the voter.
        emit Voted(campaignId, msg.sender, approve);
        s_campaignTotalVotes[campaignId]++;
    }

    /// @notice Finalizes the DAO vote on a campaign.
    /// @dev Anyone may call this after the voting period.
    /// @param campaignId The ID of the campaign to finalize.
    function finalizeCampaign(uint256 campaignId) external {
        Campaign storage campaign = campaigns[campaignId];
        uint256 effectiveVotingDeadline = campaignCreationTime[campaignId] + votingDuration;
        if (campaign.status != CampaignStatus.PendingVerification) {
            revert MedicalCrowdfunding__NoPendingCampaign();
        }

        if (block.timestamp < effectiveVotingDeadline) {
            revert MedicalCrowdfunding__VotingPeriodIsNotOver();
        }
        uint256 totalDAOMembers = i_memberDAO.getTotalMembers();
        uint256 quorum = (totalDAOMembers * 60) / 100; // 60% of DAO members

        if (s_campaignTotalVotes[campaignId] < quorum) {
            campaign.status = CampaignStatus.Failed;
            emit CampaignRejected(campaignId);
            return;
        }

        if ((s_campaignYesVotes[campaignId] * 100) / s_campaignTotalVotes[campaignId] >= 50) {
            campaign.status = CampaignStatus.Active; // Now open for donations.
            emit CampaignVerified(campaignId);
        } else {
            campaign.status = CampaignStatus.Failed;
            emit CampaignRejected(campaignId);
        }
    }

    // ===== Donation Function with Fee Allocation =====
    /// @notice Accepts ETH donations for an active campaign.
    ///Automatically deducts the service fee from the donation, allocates 35% of that fee to the owner,
    /// and distributes 65% equally among the DAO members who voted on that campaign's verification.
    /// @param campaignId The ID of the campaign to donate to.
    function donateToCampaign(uint256 campaignId) public payable nonReentrant zeroFund {
        Campaign storage campaign = campaigns[campaignId];

        if (campaign.status != CampaignStatus.Active) {
            revert MedicalCrowdfunding__NotActive();
        }
        if (block.timestamp >= campaign.deadline) {
            revert MedicalCrowdfunding__CampaignDeadlinePass();
        }

        uint256 fee = (msg.value * serviceFeePercentage) / 100;
        uint256 netAmount = msg.value - fee;

        (bool patientSent,) = campaign.patientEthAddress.call{value: netAmount}("");
        if (!patientSent) {
            revert MedicalCrowdfunding__TransferFailed();
        }

        campaign.raisedAmountInUSD += msg.value.getConversionRate(s_priceFeed);
        campaign.donors.push(msg.sender);

        // Calculate fee allocations: 35% to owner, 65% to DAO voters
        uint256 ownerShare = (fee * 35) / 100;
        uint256 daoShareTotal = fee - ownerShare; // equals (feeAmount * 65)/100
        uint256 daoVotersCount = campaignVoters[campaignId].length;

        if (daoVotersCount <= 0) {
            revert MedicalCrowdfunding__NoDAOVotersParticipation();
        }

        uint256 sharePerVoter = daoShareTotal / daoVotersCount;

        // Transfer the owner’s share
        (bool ownerSent,) = i_owner.call{value: ownerShare}("");
        if (!ownerSent) {
            revert MedicalCrowdfunding__TransferFailed();
        }

        // Transfer the DAO share equally among the voters
        for (uint256 i = 0; i < daoVotersCount; i++) {
            (bool voterSent,) = campaignVoters[campaignId][i].call{value: sharePerVoter}("");
            if (!voterSent) {
                revert MedicalCrowdfunding__TransferFailed();
            }
        }

        totalFees += fee;
        emit DonationReceived(campaignId, msg.sender, msg.value, fee, netAmount);
    }

    function checkCampaignResult(uint256 campaignId) external {
        Campaign storage campaign = campaigns[campaignId];
        if (block.timestamp < campaign.deadline) {
            revert MedicalCrowdfunding__DeadlineNotPassed();
        }
        if (campaign.status != CampaignStatus.Active) {
            revert MedicalCrowdfunding__CampaignNotActive();
        }

        if (campaign.raisedAmountInUSD >= campaign.goalAmountInUSD) {
            campaign.status = CampaignStatus.Successful;
        } else {
            campaign.status = CampaignStatus.GoalAmountNotreached;
        }
        emit CampaignStatusUpdated(campaignId, campaign.status);
    }

    /**
     * @notice Returns campaign details by campaign ID
     */
    function getCampaign(uint256 campaignId)
        external
        view
        returns (
            address payable patientEthAddress,
            uint256 goalAmountInUSD,
            uint256 raisedAmountInUSD,
            Description memory description,
            uint256 deadline,
            CampaignStatus status,
            CampaignCategory category,
            Documents memory documents
        )
    {
        Campaign storage campaign = campaigns[campaignId];
        return (
            campaign.patientEthAddress,
            campaign.goalAmountInUSD,
            campaign.raisedAmountInUSD,
            campaign.description,
            campaign.deadline,
            campaign.status,
            campaign.category,
            campaign.documents
        );
    }

    /**
     * @notice Returns the total number of campaigns created
     */
    function getTotalCampaigns() external view returns (uint256) {
        return s_campaignIdCounter;
    }

    /**
     * @notice Returns donor's total donated amount
     */
    function getTotalDonatedByAddress(address donor) external view returns (uint256) {
        return s_addressToAmountDonated[donor];
    }

    /**
     * @notice Returns the campaign IDs a donor has contributed to
     */
    function getDonorCampaigns(address donor) external view returns (uint256[] memory) {
        return donorCampaigns[donor];
    }

    /**
     * @notice Returns the number of yes, no, and total votes for a campaign
     */
    function getCampaignVotes(uint256 campaignId)
        external
        view
        returns (uint256 yesVotes, uint256 noVotes, uint256 totalVotes)
    {
        return (s_campaignYesVotes[campaignId], s_campaignNoVotes[campaignId], s_campaignTotalVotes[campaignId]);
    }

    /**
     * @notice Checks if an address has voted on a campaign
     */
    function hasVotedOnCampaign(uint256 campaignId, address voter) external view returns (bool) {
        return s_hasVoted[campaignId][voter];
    }

    /**
     * @notice Returns details of a fee proposal
     */
    function getFeeProposal(uint256 proposalId)
        external
        view
        returns (
            uint256 proposedFee,
            uint256 yesVotes,
            uint256 noVotes,
            uint256 startTime,
            uint256 endTime,
            bool executed,
            uint256 totalMembersAtCreation
        )
    {
        FeeProposal storage proposal = feeProposals[proposalId];
        return (
            proposal.proposedFee,
            proposal.yesVotes,
            proposal.noVotes,
            proposal.startTime,
            proposal.endTime,
            proposal.executed,
            proposal.totalMembersAtCreation
        );
    }

    /**
     * @notice Returns the total number of fee proposals created
     */
    function getTotalFeeProposals() external view returns (uint256) {
        return feeProposalCounter;
    }


    /**
     * @notice Returns the current service fee percentage
     */
    function getServiceFeePercentage() external view returns (uint256) {
        return serviceFeePercentage;
    }

    /**
     * @notice Returns the contract owner
     */
    function getOwner() external view returns (address) {
        return i_owner;
    }
}
