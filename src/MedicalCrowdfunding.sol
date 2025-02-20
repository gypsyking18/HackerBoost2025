// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {MedicalDAO} from "./MedicalDAO.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

error MedicalCrowdfunding__NoFund();
error MedicalCrowdfunding__NotOwner();
error MedicalCrowdfunding__NotDAOMember();
error MedicalCrowdfunding__NotPending();
error MedicalCrowdfunding__VotingPeriodIsOver();
error MedicalCrowdfunding__VotingNotEnded();
error MedicalCrowdfunding__CampaignDeadlinePass();
error MedicalCrowdfunding__FeeExceeds100();
error MedicalCrowdfunding__VotingPeriodOver();
error MedicalCrowdfunding__AlreadyVoted();
error MedicalCrowdfunding__ProposalExecuted();
error MedicalCrowdfunding__NotActive();
error MedicalCrowdfunding__TransferFailed();
error MedicalCrowdfunding__HasAlreadyVoted();
error MedicalCrowdfunding__NoUSDCFees();
error MedicalCrowdfunding__NotPatient();
error MedicalCrowdfunding__CampaignNotSuccessful();
error MedicalCrowdfunding__FundAlreadyReleased();
error MedicalCrowdfunding__NoETHFees();
error MedicalCrowdfunding__InvalidAddress();
error MedicalCrowdfunding__VotingPeriodIsNotOver();
error MedicalCrowdfunding__DeadlineNotPassed();
error MedicalCrowdfunding__CampaignNotActive();

contract MedicalCrowdfunding is ReentrancyGuard {
    using PriceConverter for uint256;
    using SafeERC20 for IERC20; // Prevent sending tokens to recipients who can’t receive

    MedicalDAO private immutable i_memberDAO;
    uint256 private votingDuration;
    uint256 public serviceFeePercentage = 2; // Initial service fee 2%
    uint256 public totalEthFees;
    uint256 public totalUsdcFees;

    enum CampaignStatus {
        PendingVerification,
        Active,
        Successful,
        Failed
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

    struct Patient {
        address payable ethAddress;
        address payable usdcAddress;
    }

    struct Campaign {
        Patient patient;
        uint256 goalAmountInUSD;
        uint256 raisedAmountInUSD;
        uint256 ethBalance;
        uint256 usdcBalance;
        bool fundsReleased;
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
    mapping(uint256 => uint256) private s_campaignYesVotes;
    mapping(uint256 => uint256) private s_campaignNoVotes;
    mapping(uint256 => uint256) private s_campaignTotalVotes;
    mapping(uint256 => mapping(address => bool)) private s_hasVoted; // Tracks whether a DAO member has already voted on a given campaign.
    mapping(uint256 => uint256) public campaignCreationTime;

    /// Storage Variables
    uint256 public s_campaignIdCounter = 0;
    address private immutable i_owner;
    AggregatorV3Interface private s_priceFeed;
    IERC20 public usdcToken;
    address payable public ethPoolAddress;
    address public usdcPoolAddress;
    uint256 public feeProposalCounter = 0;
    uint256 public campaignDuration;

    event CampaignCreated(uint256 campaignId, Patient patient);
    event CampaignVerified(uint256 campaignId);
    event CampaignRejected(uint256 campaignId);
    event UsdcDonationReceived(uint256 campaignId, address donor, uint256 amount);
    event FundsReleased(uint256 campaignId, uint256 amount);
    event Voted(uint256 campaignId, address voter, bool approved);
    event FeeProposalCreated(uint256 feeProposalCounter, uint256 newFee);
    event FeeProposalVoted(uint256 proposalId, address voter, bool support);
    event FeeProposalFailed(uint256 proposalId);
    event FeeChanged(uint256 proposalId, uint256 proposedFee);
    event CampaignStatusUpdated(uint256 campaignId, CampaignStatus status);
    event EthDonationReceived(
        uint256 campaignId,
        address donor,
        uint256 originalAmount,
        uint256 feeAmount,
        uint256 netAmount,
        uint256 donationInUSD
    );
    event EthPoolAddressUpdated(address EthPoolAddress);
    event UsdcPoolAddressUpdated(address UsdcPoolAddress);
    event EthWithdrawal(address indexed patient, uint256 amount);
    event UsdcWithdrawal(address indexed patient, uint256 amount);

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
        address usdcAddress,
        uint256 campaignIdCounter,
        uint256 initialVotingDuration,
        address payable _ethPoolAddress,
        address _usdcPoolAddress,
        uint256 _campaignDuration,
        address daoAddress
    ) {
        require(priceFeed != address(0), "Invalid price feed address");
        require(usdcAddress != address(0), "Invalid USDC token address");
        require(_ethPoolAddress != address(0), "Invalid ETH pool address");
        require(_usdcPoolAddress != address(0), "Invalid USDC pool address");
        require(daoAddress != address(0), "Invalid DAO address");

        s_priceFeed = AggregatorV3Interface(priceFeed);
        usdcToken = IERC20(usdcAddress);
        s_campaignIdCounter = campaignIdCounter;
        i_owner = msg.sender;
        i_memberDAO = MedicalDAO(daoAddress);
        votingDuration = initialVotingDuration;
        ethPoolAddress = _ethPoolAddress;
        usdcPoolAddress = _usdcPoolAddress;
        campaignDuration = _campaignDuration;
    } //  Initializes the contract’s state.

    function setVotingDuration(uint256 _votingDuration) external onlyOwner {
        votingDuration = _votingDuration;
    }

    // @notice Enables DAO members to propose a change in the service fee.
    function proposeFeeChange(uint256 newFee) external onlyDAOMember {
        if (newFee > 100) {
            revert MedicalCrowdfunding__FeeExceeds100();
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
        Patient calldata patient,
        uint256 goalAmountInUSD,
        Description calldata description,
        uint256 customCampaignDuration,
        CampaignCategory category,
        Documents calldata documents
    ) external {
        Campaign storage newCampaign = campaigns[s_campaignIdCounter];
        campaignCreationTime[s_campaignIdCounter] = block.timestamp;

        if (patient.ethAddress == address(0) || patient.usdcAddress == address(0)) {
            revert MedicalCrowdfunding__InvalidAddress();
        }

        newCampaign.patient = patient;
        newCampaign.goalAmountInUSD = goalAmountInUSD;
        newCampaign.raisedAmountInUSD = 0;
        newCampaign.fundsReleased = false;
        newCampaign.description = description;
        uint256 duration = customCampaignDuration > 0 ? customCampaignDuration : campaignDuration; // Use customCampaignDuration if provided; otherwise, fallback to the global campaignDuration
        newCampaign.deadline = block.timestamp + duration;
        newCampaign.status = CampaignStatus.PendingVerification;
        newCampaign.category = category;
        newCampaign.documents = documents;

        emit CampaignCreated(s_campaignIdCounter, newCampaign.patient);

        s_campaignIdCounter++;
    }

    function voteOnCampaign(uint256 campaignId, bool approve) external onlyDAOMember {
        Campaign storage campaign = campaigns[campaignId];
        if (campaign.status != CampaignStatus.PendingVerification) {
            revert MedicalCrowdfunding__NotPending();
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
            revert MedicalCrowdfunding__NotPending();
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

    /**
     * @dev Emitted when a donation is received.
     * @param campaignId The ID of the campaign receiving the donation.
     */
    function donateWithETH(uint256 campaignId) public payable zeroFund {
        Campaign storage campaign = campaigns[campaignId];

        if (campaign.status != CampaignStatus.Active) {
            revert MedicalCrowdfunding__NotActive();
        }
        if (block.timestamp >= campaign.deadline) {
            revert MedicalCrowdfunding__CampaignDeadlinePass();
        }

        uint256 fee = (msg.value * serviceFeePercentage) / 100;
        uint256 netAmount = msg.value - fee;
        totalEthFees += fee;

        campaign.ethBalance += netAmount;
        uint256 ethToUsd = netAmount.getConversionRate(s_priceFeed);
        campaign.raisedAmountInUSD += ethToUsd;
        campaign.donors.push(msg.sender);
        s_addressToAmountDonated[msg.sender] += ethToUsd; // TRACKS ADDRESS TO AMOUNT
        donorCampaigns[msg.sender].push(campaignId);

        emit EthDonationReceived(campaignId, msg.sender, msg.value, fee, netAmount, ethToUsd);
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
            campaign.status = CampaignStatus.Failed;
        }
        emit CampaignStatusUpdated(campaignId, campaign.status);
    }

    /**
     * @notice Donate to a campaign using USDC.
     * @param campaignId The ID of the campaign.
     * @param amount The donation amount in USDC's smallest unit (6 decimals).
     */
    function donateWithUSDC(uint256 campaignId, uint256 amount) public {
        Campaign storage campaign = campaigns[campaignId];

        if (campaign.status != CampaignStatus.Active) {
            revert MedicalCrowdfunding__NotActive();
        }
        if (block.timestamp >= campaign.deadline) {
            revert MedicalCrowdfunding__CampaignDeadlinePass();
        }

        uint256 fee = (amount * serviceFeePercentage) / 100;
        uint256 netAmount = amount - fee;
        totalUsdcFees += fee;

        usdcToken.safeTransferFrom(msg.sender, address(this), netAmount);
        campaign.usdcBalance += netAmount;

        campaign.raisedAmountInUSD += netAmount * 1e12; // Convert USDC 6 decimals to 18
        campaign.donors.push(msg.sender);
        donorCampaigns[msg.sender].push(campaignId);

        emit UsdcDonationReceived(campaignId, msg.sender, netAmount);
    }

    function setEthPoolAddress(address payable _ethPoolAddress) external onlyOwner {
        if (_ethPoolAddress == address(0)) {
            revert MedicalCrowdfunding__InvalidAddress();
        }
        ethPoolAddress = _ethPoolAddress;
        emit EthPoolAddressUpdated(_ethPoolAddress);
    }

    function setUsdcPoolAddress(address _usdcPoolAddress) external onlyOwner {
        if (_usdcPoolAddress == address(0)) {
            revert MedicalCrowdfunding__InvalidAddress();
        }
        usdcPoolAddress = _usdcPoolAddress;
        emit UsdcPoolAddressUpdated(_usdcPoolAddress);
    }

    function withdrawServiceFeesETH() external onlyOwner nonReentrant {
        uint256 fees = totalEthFees;
        if (fees == 0) {
            revert MedicalCrowdfunding__NoETHFees();
        }
        totalEthFees = 0;
        (bool success,) = ethPoolAddress.call{value: fees}("");
        if (!success) {
            revert MedicalCrowdfunding__TransferFailed();
        }
    }

    function withdrawServiceFeesUSDC() external onlyOwner nonReentrant {
        uint256 fees = totalUsdcFees;
        if (fees == 0) {
            revert MedicalCrowdfunding__NoUSDCFees();
        }
        totalUsdcFees = 0;
        usdcToken.safeTransfer(usdcPoolAddress, fees);
    }

    function patientWithdraw(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = campaigns[campaignId];

        if (block.timestamp >= campaign.deadline && campaign.status == CampaignStatus.Active) {
            if (campaign.raisedAmountInUSD >= campaign.goalAmountInUSD) {
                campaign.status = CampaignStatus.Successful;
            } else {
                campaign.status = CampaignStatus.Failed;
            }
        } // Update campaign status if the deadline has passed

        if (!(msg.sender == campaign.patient.ethAddress || msg.sender == campaign.patient.usdcAddress)) {
            revert MedicalCrowdfunding__NotPatient();
        } // Verify that the caller is one of the patient's addresses

        if (campaign.status != CampaignStatus.Successful) {
            revert MedicalCrowdfunding__CampaignNotSuccessful();
        }

        if (campaign.fundsReleased) {
            revert MedicalCrowdfunding__FundAlreadyReleased();
        }

        campaign.fundsReleased = true;

        _withdrawEth(campaign);

        _withdrawUsdc(campaign);

        emit FundsReleased(campaignId, campaign.ethBalance + campaign.usdcBalance);
    }

    /// @notice Internal function to handle ETH withdrawal.
    function _withdrawEth(Campaign storage campaign) internal {
        uint256 ethAmount = campaign.ethBalance;
        if (ethAmount > 0) {
            campaign.ethBalance = 0;
            (bool sent,) = campaign.patient.ethAddress.call{value: ethAmount}("");
            if (!sent) {
                revert MedicalCrowdfunding__TransferFailed();
            }
            emit EthWithdrawal(campaign.patient.ethAddress, ethAmount);
        }
    }

    /// @notice Internal function to handle USDC withdrawal.
    function _withdrawUsdc(Campaign storage campaign) internal {
        uint256 usdcAmount = campaign.usdcBalance;
        if (usdcAmount > 0) {
            campaign.usdcBalance = 0;
            usdcToken.safeTransfer(campaign.patient.usdcAddress, usdcAmount);
            emit UsdcWithdrawal(campaign.patient.usdcAddress, usdcAmount);
        }
    }
}
