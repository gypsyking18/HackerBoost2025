## Sample Presentation Of Medical Crowdfunding Smart Contract.

### Leveraging Blockchain for Transparent Healthcare Funding

### Presenter: Yussif Baba Akologo

### Introduction
- What is Medical Crowdfunding?
A platform that connects donors with patients in need of medical support.

- Why Blockchain?
For Transparency: Every donation is recorded on the blockchain.
Security: Immutable records prevent fraud.
Decentralization: Trustless environment—no central authority required.

### Overview of the Contract
- Contract Name: MedicalCrowdfunding
Purpose: Facilitate secure, transparent fundraising for medical campaigns.
Ensure funds reach verified patients for their healthcare needs.

### Core Functionalities:
- Managing campaigns and donations.
- Releasing funds upon successful fundraising.
- Issuing refunds when necessary.

### External Integrations
    - Chainlink Price Feed: Provides real-time conversion rates (e.g., USD to token amounts).
USDC Token Integration:
    - ERC20 Compliance: Uses OpenZeppelin’s SafeERC20 library to manage stablecoin transfers securely.
    - Price Conversion Utility: Utilizes the PriceConverter library to seamlessly convert donation amounts.

### Key Components – Enums & Structs
- Enums: 
An enum lets you create a list of named options.
  - CampaignStatus: Active, Successful, Failed
  - CampaignCategory: Surgery, Cancer, Emergency, Others
- Structs:
A struct in Solidity is like a custom container that lets you group different pieces of related information together
  - Description:
    - imageURL: Visual representation (e.g., patient or hospital image).
hospital, hospitalNumber, doctorName: Key details for validation.
  - Campaign:
    - Patient (address payable).
    - goalAmountInUSD.
    - raisedAmountInUSD.
    - platformFee.
    - Metadata: metadataURI for off-chain data (e.g., IPFS).
    - Donors Allay
    - Deadlines: Tracks campaign duration.
    - campaignStatus. 
    - campaignCategory: For easy filtering and management.
    - Description : Nested struct.

### Data Management with Mappings
In Solidity, a mapping is like a simple dictionary or phone book. Here’s what that means in plain language. Think of it as a list where every item (a value) is connected to a unique label (a key). For example, in a phone book, you look up a name (key) to find a phone number (value).
- Mappings Explained:
  - campaigns: Links campaign IDs to its corresponding campaign.
  - donorCampaigns: Tracks all campaigns a donor has contributed to. Allays of campaignIDs.
  - s_addressToAmountDonated: Records total donated amount per address.
  - verifiedPatients: Ensures only authorized patients can access funds.

- Campaign Counter:
  - s_campaignIdCounter keeps a unique identifier for each campaign.

### Modifiers:
    - zeroFund: Ensures donations are non-zero.
    - onlyPatient: Restricts fund withdrawal to the campaign’s patient.
    - onlyVerifiedPatient: Allows only verified patients to create a campaign.
    - onlyOwner: Restricts certain actions to the contract owner (e.g., configuration changes).

### Events for Transparency
In Solidity, events are like simple announcements or notifications that your smart contract makes when something important happens.
- Events Emitted:
  - DonationReceived: Emitted each time a donor contributes.
  - FundsReleased: Logged when funds are disbursed to the patient.
  - RefundIssued: Recorded when a donor is refunded.
- Significance: These events help auditors and users trace every step of the fundraising process.




   