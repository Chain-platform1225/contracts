/*
    @dev: Logan (Nam) Nguyen
    @Course: SUNY Oswego - CSC 495 - Capstone
    @Instructor: Professor Bastian Tenbergen
    @Version: 1.0
    @Honor: OpenZeppelin
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

//  ==========  External imports    ==========
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

import "@thirdweb-dev/contracts/openzeppelin-presets/metatx/ERC2771ContextUpgradeable.sol";
import "@thirdweb-dev/contracts/lib/CurrencyTransferLib.sol";

//  ==========  Internal imports    ==========
import { ISwylClub } from "../../interfaces/v1/ISwylClub.sol";

contract SwylClub is
    Initializable,
    ISwylClub,
    ERC2771ContextUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlEnumerableUpgradeable
{
     /*///////////////////////////////////////////////////////////////
                            State variables
    //////////////////////////////////////////////////////////////*/

    /// @notice module level info
    bytes32 private constant MODULE_TYPE = bytes32("Swyl-Club");
    uint256 private constant VERSION = 1;

    /// @dev Contract level metadata.
    string public contractURI;

    /// @dev Only lister role holders can create listings, when listings are restricted by lister address.
    bytes32 public constant CLUB_OWNER_ROLE = keccak256("CLUB_OWNER_ROLE");

    /// @dev The address of the native token wrapper contract i.e. 0xeee.
    address private immutable nativeTokenWrapper;

    /// @dev The total clubs have ever been created
    uint256 public totalNumberClubs;

    
    /*///////////////////////////////////////////////////////////////
                                Mappings
    //////////////////////////////////////////////////////////////*/

    /// @dev Mapping from an address of a clubId => Club.
    mapping(uint256 => Club) private totalClubs;

    /// @dev Mapping from a clubId => Tier[]
    mapping(uint256 => Tier[]) private totalTiers;

    /// @dev Mapping from a clubId => (tierId => Subscription[])
    mapping(uint256 => mapping(uint256 => Subscription[])) private totalSubscriptions;


    /*///////////////////////////////////////////////////////////////
                                Modifiers
    //////////////////////////////////////////////////////////////*/

    /// @dev Checks where the caller is a Club's onwer
    modifier onlyClubOwnerRole() {
        require(hasRole(CLUB_OWNER_ROLE, _msgSender()), "!CLUB_OWNER");
        _; // move on
    }

    /// @dev Checks where the caller is the owner of the Club
    modifier onlyClubOwner(uint256 _clubId) {
        require(totalClubs[_clubId].clubOwner == _msgSender() , "!CLUB_OWNER");
        _; // move on
    }


    /// @dev Checks where a Club exists
    modifier onlyExistingClub(uint256 _clubId) {
        require(totalClubs[_clubId].clubOwner != address(0), "DNE");
        _;
    }


    /*///////////////////////////////////////////////////////////////
                    Constructor + initializer logic
    //////////////////////////////////////////////////////////////*/


    /** 
    * @dev This contract utilizes the @openzeppelin/upgradeable pluggin and then will be deployed behind a proxy.
    *       A proxied contract doesn't make use of a constructor and the logic in a constructor got moved into 
    *       an external initializer function.
    *
    * @notice deploying to a proxy, constructor won't be in use.
    */ 
    constructor (address _nativeTokenWrapper) initializer {
        // Initialize inherited contracts
        __ReentrancyGuard_init(); // block malicious reentrant/nested calls

        // set nativeTokenWrapper
        nativeTokenWrapper = _nativeTokenWrapper;


         // grant roles
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender()); // grant DEFAULT_ADMIN_ROLE to deployer, i.e. Swyl Service account
        _setupRole(CLUB_OWNER_ROLE, address(0));
    }

    /**
    * @dev This function acts like a constructor on deploying to proxy.
    *       initializer modifier is marked to make sure this function can ever be called once in this contract's lifetime
    * NOTE  from EIP7221: Secure Protocol for Native Meta Transactions (https://eips.ethereum.org/EIPS/eip-2771)
    *           - Transaction Signer - entity that signs & sends to request to Gas Relay
    *           - Gas Relay - receives a signed request off-chain from Transaction Signer and pays gas to turn it into a valid transaction that goes through Trusted Forwarder
    *           - Trusted Forwarder - a contract that is trusted by the Recipient to correctly verify the signature and nonce before forwarding the request from Transaction Signer
    *           - Recipient - a contract that can securely accept meta-transactions through a Trusted Forwarder by being compliant with this standard.
    */
    function initialize(
        address _defaultAdmin, // original deployer i.e. Swyl Service account
        string memory _contrtactURI, // contract level URI
        address[] memory _trustedForwarders
    ) external initializer {
        // Initialize inherited contracts
        __ReentrancyGuard_init(); // block malicious reentrant/nested calls
        __ERC2771Context_init(_trustedForwarders); // init trusted forwarders

        // set platform admin/contract's state info
        contractURI = _contrtactURI;

        // grant roles
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin); // grant DEFAULT_ADMIN_ROLE to deployer, i.e. Swyl Service account in this case
        _setupRole(CLUB_OWNER_ROLE, address(0)); // grant LISTER_ROLE to address 0x000
    }


    /*///////////////////////////////////////////////////////////////
                        Generic contract logic
    //////////////////////////////////////////////////////////////*/
    
    /**
    * @notice receive() is a special function and only one can be defined in a smart contract.
    *       It executes on calls to the contract with no data(calldata), e.g. calls made via send() or transfer()
    *
    * @dev Lets the contract receives native tokens from `nativeTokenWrapper` withdraw
    */ 
    receive() external payable {}

    /// @dev Returns the module type of the contract
    function contractType() external pure returns (bytes32) {
        return MODULE_TYPE;
    }

    /// @dev Returns the version of the contract
    function contractVersion() external pure returns (uint8) {
        return uint8(VERSION);
    }



     /*///////////////////////////////////////////////////////////////
                Club (create-update-cancel) logic
    //////////////////////////////////////////////////////////////*/


    /** 
    * @notice Lets an account start a new Club
    *
    * @dev Start a new Club struct
    */
    function startClub(address _currency) external override {
        // stop a club's owner to create a second club
        require(!hasRole(CLUB_OWNER_ROLE, _msgSender()), "!NOT ALOOWED - account already has a club");

        // grant CLUB_OWNER_ROLE to the caller
        _setupRole(CLUB_OWNER_ROLE, _msgSender());

        // handle clubId and `totalNumberClubs`
        uint256 currentId = totalNumberClubs;

        // start a new Club
        // Tier[] memory tiers;
        Club memory newClub = Club({
            clubId: currentId,
            clubOwner: _msgSender(),
            date: block.timestamp,
            currency: _currency,
            totalMembers: 0
        });

        // update global `toalClubs`
        totalClubs[currentId] = newClub;

        // update global `totalNumberClubs`
        totalNumberClubs++;

        // emit ClubCreated event
        emit ClubCreated(_msgSender(), newClub);
    }

    /** 
    * @notice Lets a Club's owner add a Tier
    *
    * @dev Create a new Tier struct and add it to corresponding Club
    *
    * @param _param     TierAPIParam - the parameter that governs the tier to be created.
    *                                  See struct `TierAPIParam` for more info.
    */
    function addTier(AddTierParam memory _param) external override onlyClubOwner(_param.clubId) onlyClubOwnerRole() onlyExistingClub(_param.clubId){
        // param checks
        require(_param.tierFee > 0, "!TIER_FEE - fee must be greater than 0");
        require(_param.sizeLimit > 0, "!SIZE_LIMIT - tier size must be greater than 0");

        // get currentTierId
        Tier[] storage tiers = totalTiers[_param.clubId];
        uint256 currentTierId = tiers.length;


        // initialize newTier struct
        Tier memory newTier = Tier({
            tierId: currentTierId,
            tierFee: _param.tierFee,
            totalMembers: 0,
            sizeLimit: _param.sizeLimit,
            tierData: _param.tierData
        });


        // add newTier to global `totalClubs` array
        tiers.push(newTier);
        totalTiers[_param.clubId] = tiers;

        // emit TierAdded event
        emit TierAdded(currentTierId, _msgSender(), newTier);
    }



    /** 
    * @notice Lets a Club's owner update a Tier
    *
    * @param _param     TierAPIParam - the parameter that governs the tier to be created.
    *                                  See struct `TierAPIParam` for more details.
    */
    function updateTier(UpdateTierParam memory _param) external override onlyClubOwner(_param.clubId) onlyClubOwnerRole() onlyExistingClub(_param.clubId) {
        // param checks
        require(_param.tierFee > 0, "!TIER_FEE - fee must be greater than 0");
        require(_param.sizeLimit > 0, "!SIZE_LIMIT - tier size must be greater than 0");

        // get target Tier array
        Tier[] memory targetClubTiers = totalTiers[_param.clubId];

        // validate if `_param.tierId` points to a valid Tier
        require(_param.tierId < targetClubTiers.length, "!TIER_ID - invalid tierId parameter");

        // get target Tier
        Tier memory targetTier = targetClubTiers[_param.tierId];

        // revert transaction if desired parameters are not any different than targetTier's attributes to save gas
        bool isUpdatable = _param.tierFee != targetTier.tierFee ||
                           _param.sizeLimit != targetTier.sizeLimit ||
                           keccak256(abi.encodePacked(_param.tierData)) != keccak256(abi.encodePacked(targetTier.tierData));
        require(isUpdatable, "!UPDATABLE - nothing new to update");

        // update Tier 
        targetTier.tierFee = _param.tierFee;
        targetTier.sizeLimit = _param.sizeLimit;
        targetTier.tierData = _param.tierData;

        // update global totalClubs
        totalTiers[_param.clubId][_param.tierId] = targetTier;

        // emit the TierUpdated event
        emit TierUpdated(_param.tierId, _msgSender(), targetTier);
    }


    /** 
    * @notice Lets a Club's owner delete a Tier
    *
    * @param _tierId    uint256 - the uid of the tier to be deleted
    */
    function deleteTier(uint256 _clubId, uint256 _tierId) external override onlyClubOwner(_clubId) onlyClubOwnerRole() onlyExistingClub(_clubId) {
         // get target Tier array
        Tier[] storage targetTiers = totalTiers[_clubId];

        // validate if `_param.tierId` points to a valid Tier
        require(_tierId < targetTiers.length, "!TIER_ID - invalid _param.tierId");

        // shift items toward to cover the target deleted tier => eventually create duplicating last item
        for (uint256 i = _tierId; i < targetTiers.length - 1; i++) {
            targetTiers[i] = targetTiers[i+1];
        }

        // remove the last item
        targetTiers.pop();

        // updated global `totalClubs` state
        totalTiers[_clubId] = targetTiers;

        // emit TierDeleted event
        emit TierDeleted(_tierId, _msgSender(), targetTiers);
    }


    /** 
    * @notice Lets an account subscribe to a Tier
    *
    * @param _param     SubscriotionAPIParam - the parameter that governs a subscription to be made.
    *                                          See struct `SubscriptionAPIParam` for more details.
    */
    function subsribe(SubscribeParam memory _param) external payable override {
        
    }


    /** 
    * @notice Lets a subscriber unsubscribe a Tier 
    *
    * @param _clubId     uint256 - the uid of the club holding the tier to be unsubscribed.
    *
    * @param _tierId     uint256 - the uid of the tier to be unsubscribed.
    */
    function unsubscribe(uint256 _clubId, uint256 _tierId) external override {}




    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    
    /*///////////////////////////////////////////////////////////////
                            Getter functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns a Club by `_clubOwner`
    function getClubAt(uint256 _clubId) public view returns (Club memory) {
        return totalClubs[_clubId];
    }


    /// @dev Returns an array of Tier that a `_clubOwner` has
    function getTiersAt(uint256 _clubId) public view returns (Tier[] memory) {
        return totalTiers[_clubId];
    }

    /// @dev Returns an array of Tier that a `_clubOwner` has
    function getTier(uint256 _clubId, uint256 _tierId) public view returns (Tier memory) {
        return totalTiers[_clubId][_tierId];
    }


    /*///////////////////////////////////////////////////////////////
                            Utilities
    //////////////////////////////////////////////////////////////*/
    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }
}