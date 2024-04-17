// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

import "@nation3/nationcred-contracts/INationCred.sol";
import "@nation3/nationcred-contracts/utils/IPassportUtils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

/**
 *        ---------::::
 *     ---------:---::::::
 *   -----------::---:::::::
 *  ------------:.:--::::::::
 * -------------: .:--::::::::
 * -------------:   .:::::::::
 * -------------:.......::::::
 * -----:..    .:-------::::::
 * --------:.. .:-------::::::
 * ----------:..:--------:::::
 *  -----------.:--------::::
 *   ----------::--------:::
 *     -------------------
 *        -------------
 *
 *         Nation3 DAO
 *     https://nation3.org
 */
contract BasicIncomeDistributor {
    string public constant VERSION = "0.4.0";

    address public owner;

    /// The smart contract used for checking if a citizen holds a valid passport.
    IPassportUtils public passportUtils;

    /// The smart contract used for checking if a Nation3 citizen is active.
    INationCred public nationCred;

    /// The Basic Income amount a citizen can claim per yearly enrollment.
    uint256 public amountPerEnrollment;

    /// The total amount enrolled, accumulated over time.
    uint256 public amountEnrolled;

    /// The timestamp of each citizen's most recent enrollment.
    mapping(address => uint256) public enrollmentTimestamps;
    mapping(address => uint256) public latestClaimTimestamps;

    event Enrolled(address citizen);
    event IncomeClaimed(address citizen, uint256 amount);
    event AmountPerEnrollmentUpdated(uint256 newAmount);

    IERC20 public token;

    error NotEligibleError(address citizen);
    error CurrentlyEnrolledError(address citizen, uint256 enrollmentTimestamp);
    error NotEnoughFunding(uint256 amountAvailable, uint256 amountRequested);

    constructor(
        address passportUtilsAddress,
        address nationCredAddress,
        address rewardToken,
        uint256 amountPerEnrollment_
    ) {
        console.log("Deploying BasicIncomeDistributor");
        console.log("passportUtilsAddress:", passportUtilsAddress);
        console.log("nationCredAddress:", nationCredAddress);
        console.log("amountPerEnrollment_:", amountPerEnrollment_);
        owner = address(msg.sender);
        passportUtils = IPassportUtils(passportUtilsAddress);
        nationCred = INationCred(nationCredAddress);
        token = IERC20(rewardToken);
        amountPerEnrollment = amountPerEnrollment_;
    }

    receive() external payable {}

    function setOwner(address ownerAddress) public {
        require(msg.sender == owner, "You are not the owner");
        owner = ownerAddress;
    }

    function setPassportUtils(address passportUtilsAddress) public {
        require(msg.sender == owner, "You are not the owner");
        passportUtils = IPassportUtils(passportUtilsAddress);
    }

    function setNationCred(address nationCredAddress) public {
        require(msg.sender == owner, "You are not the owner");
        nationCred = INationCred(nationCredAddress);
    }

    function setAmountPerEnrollment(uint256 amount) public {
        require(msg.sender == owner, "You are not the owner");
        amountPerEnrollment = amount;
        emit AmountPerEnrollmentUpdated(amountPerEnrollment);
    }

    /// Checks if a Nation3 citizen is eligible to enroll for Basic Income.
    function isEligibleToEnroll(address citizen) public view returns (bool) {
        console.log("isEligibleToEnroll");

        // The account owns the passport NFT
        if (!passportUtils.isOwner(citizen)) {
            return false;
        }
        console.log(unicode"✅ The account owns the passport NFT");

        // The passport has not yet expired
        if (passportUtils.isExpired(citizen)) {
            return false;
        }
        console.log(unicode"✅ The passport has not yet expired");

        // The passport is not about to expire within the next year
        uint256 expirationTimestamp = passportUtils.getExpirationTimestamp(
            citizen
        );
        console.log("expirationTimestamp:", expirationTimestamp);
        uint256 oneYearFromNow = block.timestamp + 365 days;
        console.log("oneYearFromNow:", oneYearFromNow);
        if (expirationTimestamp < oneYearFromNow) {
            return false;
        }
        console.log(
            unicode"✅ The passport is not about to expire within the next year"
        );

        // The citizen is active
        if (!nationCred.isActiveAddress(citizen)) {
            return false;
        }
        console.log(unicode"✅ The citizen is active");

        return true;
    }

    /// Once eligible, the citizen can enroll for Basic Income, as long as the smart contract contains enough funding for covering one additional citizen's Basic Income for the duration of 1 year.
    function enroll() public {
        console.log("enroll");

        if (!isEligibleToEnroll(msg.sender)) {
            revert NotEligibleError(msg.sender);
        }
        console.log(unicode"✅ The citizen is eligible for enrollment");

        uint256 oneYearAgo = block.timestamp - 365 days;
        console.log("oneYearAgo:", oneYearAgo);
        if (enrollmentTimestamps[msg.sender] > oneYearAgo) {
            revert CurrentlyEnrolledError(
                msg.sender,
                enrollmentTimestamps[msg.sender]
            );
        }

        uint256 amountAvailable = address(this).balance - amountEnrolled;
        console.log("amountAvailable:", amountAvailable);
        if (amountAvailable < amountPerEnrollment) {
            revert NotEnoughFunding(amountAvailable, amountPerEnrollment);
        }

        amountEnrolled += amountPerEnrollment;
        enrollmentTimestamps[msg.sender] = block.timestamp;
        emit Enrolled(msg.sender);
    }

    /// Checks if a Nation3 citizen is eligible to claim Basic Income.
    function isEligibleToClaim(address citizen) public view returns (bool) {
        console.log("isEligibleToClaim");

        // The account owns the passport NFT
        if (!passportUtils.isOwner(citizen)) {
            return false;
        }
        console.log(unicode"✅ The account owns the passport NFT");

        // The passport has not yet expired
        if (passportUtils.isExpired(citizen)) {
            return false;
        }
        console.log(unicode"✅ The passport has not yet expired");

        return true;
    }

    /// Once enrolled, citizens can claim their earned Basic Income at any time.
    function claim() public {
        console.log("claim");

        if (!isEligibleToClaim(msg.sender)) {
            revert NotEligibleError(msg.sender);
        }
        console.log(unicode"✅ The citizen is eligible for claiming");

        uint256 claimableAmount = getClaimableAmount(msg.sender);
        require(claimableAmount > 0, "There is no reward to claim.");
        console.log("claimableAmount:", claimableAmount);

        //Update latest claim timestamp
        latestClaimTimestamps[msg.sender] = block.timestamp;
        emit IncomeClaimed(msg.sender, claimableAmount);

        // Transfer token to recipient
        bool success = token.transfer(msg.sender, claimableAmount);
        require(success, "transfer failed");
    }

    function getClaimableAmount(address citizen) public view returns (uint256) {
        uint256 latestClaimTimestamp = latestClaimTimestamps[citizen];
        uint256 enrollmentDuration = latestClaimTimestamp == 0
            ? block.timestamp - enrollmentTimestamps[citizen]
            : block.timestamp - latestClaimTimestamp;

        uint256 daysSinceLastClaim = enrollmentDuration / 365 days;
        return daysSinceLastClaim * amountPerEnrollment;
    }
}
