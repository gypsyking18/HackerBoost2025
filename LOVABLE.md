IN THE ``` Start a Donation ``` BUTTON IS WHERE DONORS CLICK TO MAKE DONATIONS. WHEN THE DONOR CLICKS THE BUTTON, HE/SHE WILL HAVE TO SELECT A CAMPAIGN FROM A LIST OF ACTIVE CAMPAIGNS THAT HE/SHE INTEND TO DONATE TO. THEY MUST ALSO HAVE AN INPUT FIELD WHERE THEY CAN INPUT THE CAMPAIGN ID OF THE CAMPAIGN THEY INTEND TO DONATE TO. BELOW IS THE FUNCTION FOR THE DONATION BUTTON:

```solidity
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

```

donateToCampaign:
This is the core function for receiving donations:

Checks:

Confirms that the campaign is Active and that donations are still accepted (before the deadline).
Uses the zeroFund modifier to ensure a nonzero donation.
Fee Calculation:

A service fee is deducted from the donation based on the current serviceFeePercentage.
The remaining amount (net donation) is sent to the patient’s address.
The donation amount is also converted to USD using the PriceConverter (relying on the Chainlink price feed) to update the campaign’s raised amount.
Fee Distribution:

The fee is split into two portions:
35% to the contract owner.
65% divided equally among all DAO members who voted during the campaign verification process.
If no DAO voters participated, the transaction reverts.

mapping(uint256 => Campaign) public campaigns; 


Wire up the existing donateToCampaign function to the ```Start a Donation``` button. When a user clicks the button, the system should:

Retrieve the required campaign ID and donation amount from the UI.
Call the donateToCampaign function with the provided campaign ID by the donor or provide a list of active campaigns for the donor to select and pass the donation amount as the payable value.
Handle errors if the campaign is inactive, past its deadline, or if any fund transfer fails.
Update the UI to reflect a successful donation or display appropriate error messages.
Reject transactions is not an ethereum network address
Initializes this function to the button click event.



THIS IS THE CREATECAMPAIGN FUNCTION. THIS FUNCTION SHOULD BE INITIALIZED WHEN THE ```Start a Campaign``` button is clicked:
```solidity
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
```
Campaign Creation
createCampaign:
Patients call this function to ```Start a Campaign```. They provide:
Their Ethereum address.
The funding goal in USD.
A detailed description and relevant documents.
Optionally, a custom campaign duration (if not provided, a default duration is used).
The campaign is initially set to PendingVerification and awaits DAO member voting.

Connect the existing createCampaign function from our smart contract to the ```Start a Campaign``` button. When the user clicks the button, the system should:

Collect all required inputs from the UI, including:
Patient Ethereum Address (the recipient of the campaign funds),
Goal Amount in USD,
Description details (patient name, hospital name, hospital number, doctor's name),
Custom Campaign Duration (if provided, otherwise use a default duration),
Campaign Category (one of: Surgery, Cancer, Emergency, Others),
Documents details (diagnosis report URI, treatment plan cost estimate URI, hospital doctor letter URI, patient ID URI, identity proof URI, and medical bills URI).
Validate that the patient address is valid (not zero) and that all necessary fields are filled.
Invoke the createCampaign function with these inputs.
Handle any errors that might occur (such as an invalid address).
Upon a successful transaction, update the UI to notify the user that the campaign has been created and display any relevant confirmation details.

NOTE: THE MEDICAL BILLS URI AND THE IDENTITY PROOF URI FROM THE DOCUMENTS DETAILS ARE OPTIONAL, BUT IF A PERSON IS STARTING A CAMPAIGN ON BEHAVE OF SOMEONE, THE IDENTITY PROOF URI SHOULD ENFORCE FOR THE PERSON TO PROVIDE THE IDENTITY PROOF URI.

USE THIS PROJECT ID:
 d3c50f8ba5840af2e45fc19efa35f7d2 TO INITIALIZE/integrate  ```Connect Wallet``` BUTTON

THIS IS THE PROJECT ID: d3c50f8ba5840af2e45fc19efa35f7d2

ALSO, ADD ```Become a DAO``` AT NAVIGATION MENU BAR



THIS IS THE FUNCTION THAT PROPOSE FEE FOR THE SERVICE FEE. INITIALIZE THIS FUNCTION TO THE ```Proposals``` AT THE FOOTER SECTION.

```solidity

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

        uint256 public feeProposalCounter = 0;

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
```

proposeFeeChange:
A DAO member can propose a new fee percentage (with an upper limit of 5%). A new fee proposal is recorded with its own voting period.

Prompt:

"Integrate the proposeFeeChange function from our smart contract with a ```Proposals``` button in the UI. When a DAO member inputs a new fee value and clicks the button, the system should:

Retrieve the new fee value from an input field.
(Optionally) Check that the new fee is at or below the maximum allowed value of 5 before calling the function.
Call the proposeFeeChange function with the provided new fee.
Handle any errors, such as if the fee exceeds the maximum or if the caller is not a DAO member.
Update the UI to confirm the successful proposal or to display an appropriate error message.

ALSO, IN THE ```Proposals``` BUTTON THERE SHOULD BE PLACE WHERE USERS CAN CLICK AND ALL PASSED PROPOSALS.



THESE ARE THE FUNCTIONS THAT VOTES FOR THE SERVICE FEE AND CAMPAIGN VERIFICATION. INITIALIZE THIS FUNCTION TO THE ```Vote``` button AT THE FOOTER SECTION. IN THIS SECTION, IT SHOULD BE TWO SEPARATE SECTIONS. ONE SHOULD ```Vote a Proposal``` and the other should ```Vote a Campaign ```. 
IN THE VOTE A PROPOSAL SECTION, THIS IS THE FUNCTION:

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
mapping(uint256 => mapping(address => bool)) public hasVotedOnFeeProposal;

Prompt:

"Integrate the existing fee proposal voting and execution functionalities into our web interface. Specifically, when a DAO member interacts with the UI, the system should allow them to:

Vote on a Fee Proposal:

Provide UI options (e.g., 'Yes' and 'No' buttons) for voting on a specific fee proposal.
Retrieve the proposal ID from the interface.
Call the voteOnFeeProposal function with the selected proposal ID and a boolean indicating support (true for yes, false for no).
Ensure that before voting, the system checks that the voting period is still active, that the proposal hasn’t already been executed, and that the user hasn’t already voted.
Display success or error messages based on the outcome.
Execute a Fee Proposal:

Provide a button for executing a fee proposal after the voting period is over.
Retrieve the proposal ID from the UI.
Call the executeFeeProposal function with the proposal ID.
The function should verify that the voting period has ended and that the proposal has not already been executed.
If the total votes meet the quorum and the yes votes outnumber the no votes, the service fee is updated; otherwise, the proposal is marked as failed.
Update the UI with a confirmation or error message accordingly.

🔹 Breakdown of Key Functionalities
1️⃣ Voting on a Fee Proposal
Objective: Allow users to vote Yes (✅) or No (❌) on a fee proposal via the web interface.

✅ Required Steps:
UI Components

Display active fee proposals.
Show 'Yes' and 'No' buttons for each proposal.
Retrieve the Proposal ID

When a user selects a proposal, the proposal ID is fetched from the UI.
Call the Smart Contract Function

The front-end calls the voteOnFeeProposal(uint256 proposalId, bool support) function with:
proposalId (from UI)
support (true for Yes, false for No)
Pre-Vote Validations (before calling the function)

Ensure voting period is active.
Check that the proposal hasn’t already been executed.
Verify that the user hasn’t already voted.
Show Feedback to the User

Display success message if voting is successful.
Show error messages if the vote fails (e.g., voting closed, already voted, etc.).
2️⃣ Executing a Fee Proposal
Objective: Allow DAO members to execute a fee proposal once the voting period has ended.

✅ Required Steps:
UI Components

Provide an "Execute Proposal" button (only visible after voting ends).
Retrieve the Proposal ID

When the user clicks the button, fetch the proposal ID from the UI.
Call the Smart Contract Function

Call executeFeeProposal(uint256 proposalId) in the smart contract.
Pre-Execution Validations

Ensure the voting period is over.
Confirm the proposal hasn’t already been executed.
Proposal Approval Conditions

Check if the proposal meets quorum (minimum required votes).
Ensure that 'Yes' votes outnumber 'No' votes.
Update Fee or Mark Proposal as Failed

If conditions are met, update the service fee.
If not, mark the proposal as failed.
Show Feedback to the User

Display success message if execution is successful.
Show an error message if execution fails (e.g., quorum not met, already executed, etc.).

THERE SHOULD BE AN OPTIONAL INPUT FIELD FOR USERS TO INPUT THEIR REASONS. AND THERE SHOULD BE A COMMENT SECTION.


AND IN THE VOTE CAMPAIGN SECTION, THIS IS THE FUNCTIONS:

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

    These functions manage the voting, finalization, and evaluation of crowdfunding campaigns in a DAO-governed medical crowdfunding system. Each function enforces the DAO's governance rules to ensure fair and transparent decision-making.

🔹 1️⃣ voteOnCampaign(uint256 campaignId, bool approve)
Purpose: Allows DAO members to vote on whether a crowdfunding campaign should be approved.

✅ Key Steps:
Retrieve the Campaign

Fetches the campaign data using campaigns[campaignId].
Check if the Campaign is in Pending Verification

If it's not pending verification, revert with MedicalCrowdfunding__NoPendingCampaign().
Check if the Voting Period is Still Active

Calculate the voting deadline:
solidity
Copy
Edit
uint256 effectiveVotingDeadline = campaignCreationTime[campaignId] + votingDuration;
If the current time (block.timestamp) is past the deadline, revert with MedicalCrowdfunding__VotingPeriodIsOver().
Ensure the Voter Hasn’t Already Voted

If the voter has already voted (s_hasVoted[campaignId][msg.sender] is true), revert with MedicalCrowdfunding__HasAlreadyVoted().
Record the Vote

If the vote is Yes (approve == true), increment s_campaignYesVotes[campaignId].
If the vote is No (approve == false), increment s_campaignNoVotes[campaignId].
Mark the voter as having voted:
solidity
Copy
Edit
s_hasVoted[campaignId][msg.sender] = true;
Store the voter's address in campaignVoters[campaignId].
Emit the Voted event.
Increment the total vote count for this campaign.
🔹 2️⃣ finalizeCampaign(uint256 campaignId)
Purpose: After the voting period ends, this function finalizes the voting results and determines whether a campaign gets approved or rejected.

✅ Key Steps:
Retrieve the Campaign

Fetches the campaign data using campaigns[campaignId].
Check if the Campaign is Pending Verification

If it's not pending verification, revert with MedicalCrowdfunding__NoPendingCampaign().
Check if the Voting Period Has Ended

Calculate the voting deadline:
solidity
Copy
Edit
uint256 effectiveVotingDeadline = campaignCreationTime[campaignId] + votingDuration;
If current time (block.timestamp) is before the deadline, revert with MedicalCrowdfunding__VotingPeriodIsNotOver().
Check if Quorum is Reached

Fetch the total number of DAO members:
solidity
Copy
Edit
uint256 totalDAOMembers = i_memberDAO.getTotalMembers();
Calculate the quorum (60% of DAO members):
solidity
Copy
Edit
uint256 quorum = (totalDAOMembers * 60) / 100;
If the total votes are less than quorum, the campaign fails (CampaignStatus.Failed), and CampaignRejected is emitted.
Check if More than 50% of Votes are "Yes"

If Yes votes ≥ 50%, the campaign is approved and set to CampaignStatus.Active, allowing donations.
If not, the campaign fails (CampaignStatus.Failed).
Emit CampaignVerified (if approved) or CampaignRejected (if failed).
🔹 3️⃣ checkCampaignResult(uint256 campaignId)
Purpose: After the campaign's donation period ends, checks if the campaign met its fundraising goal and updates its status accordingly.

✅ Key Steps:
Retrieve the Campaign

Fetch the campaign data using campaigns[campaignId].
Ensure the Campaign Deadline Has Passed

If block.timestamp is before campaign.deadline, revert with MedicalCrowdfunding__DeadlineNotPassed().
Check if the Campaign is Active

If campaign.status != CampaignStatus.Active, revert with MedicalCrowdfunding__CampaignNotActive().
Check if the Goal Amount Was Reached

If campaign.raisedAmountInUSD >= campaign.goalAmountInUSD, mark the campaign as CampaignStatus.Successful.
Otherwise, set the status to CampaignStatus.GoalAmountNotReached.
Emit the Campaign Status Update Event

Emit CampaignStatusUpdated(campaignId, campaign.status).

Prompt:

"Integrate the following DAO governance functions into our medical crowdfunding web interface:

Vote on Campaign

Function: voteOnCampaign(uint256 campaignId, bool approve)
Purpose: Allows DAO members to vote on whether a campaign in 'Pending Verification' should be approved.
Steps:
Retrieve the campaign details using the provided campaign ID.
Check that the campaign is in the Pending Verification state.
Verify that the current time is within the voting period by calculating campaignCreationTime[campaignId] + votingDuration.
Ensure the voter has not already voted on this campaign.
Record the vote: increment yes or no votes based on the approve flag, mark the voter as having voted, store the voter’s address, and increment the total vote count.
Emit the Voted event.
Finalize Campaign

Function: finalizeCampaign(uint256 campaignId)
Purpose: Finalizes the DAO vote after the voting period ends, approving or rejecting the campaign.
Steps:
Retrieve the campaign using the campaign ID.
Confirm that the campaign is still pending verification and that the voting period (calculated using campaignCreationTime[campaignId] + votingDuration) has ended.
Check if the total votes meet a quorum (60% of total DAO members).
If quorum is met and at least 50% of the votes are "Yes", change the campaign status to Active (allowing donations); otherwise, mark it as Failed.
Emit either the CampaignVerified or CampaignRejected event.
Check Campaign Result

Function: checkCampaignResult(uint256 campaignId)
Purpose: After the campaign’s donation period ends, verifies if the fundraising goal was met and updates the campaign status accordingly.
Steps:
Retrieve the campaign data using the campaign ID.
Ensure that the campaign’s deadline has passed and that the campaign is currently Active.
Compare the raised amount with the goal amount; if met, set the status to Successful, otherwise set it to GoalAmountNotReached.
Emit the CampaignStatusUpdated event with the updated status.
For each function, bind the corresponding action (e.g., vote, finalize, check result) to UI elements (such as buttons) using a web3 library (for example, ethers.js). Make sure to handle errors appropriately and update the UI with the results or error messages."

NOTE: THERE SHOULD BE AN OPTIONAL INPUT FIELD FOR VOTERS TO INPUT THEIR REASONS. AND THERE SHOULD BE A COMMENT SECTION.



























