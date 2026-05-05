// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract Payment is ReentrancyGuard, Ownable, Pausable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    struct PaymentParams {
        bytes32 paymentId;
        string vendorId;
        address token;
        uint256 amount;
        uint256 deadline;
        bytes backendSignature;
    }

    struct PaymentRecord {
        bytes32 paymentId;
        address vendor;
        address customer;
        uint256 totalAmount;
        uint256 vendorAmount;
        uint256 feeAmount;
        address token;
        uint256 createdAt;
        bool exists;
    }

    struct Vendor {
        address walletAddress;
        string businessName;
        bool isActive;
        uint256 totalPayments;
        uint256 totalVolume;
        bool exists;
    }

    mapping(bytes32 => PaymentRecord) public payments;
    mapping(string => Vendor) public vendors;
    mapping(address => bool) public supportedTokens;

    uint256 public platformFee = 50;
    uint256 public constant BASIS_POINTS = 10000;

    address public feeRecipient;

    event PaymentCompleted(
        bytes32 indexed paymentId,
        string indexed vendorId,
        address indexed vendor,
        address customer,
        uint256 totalAmount,
        uint256 vendorAmount,
        uint256 feeAmount,
        address token,
        uint256 timestamp
    );

    event VendorRegistered(string indexed vendorId, address walletAddress, string businessName);
    event VendorUpdated(string indexed vendorId, address newWalletAddress);
    event VendorStatusChanged(string indexed vendorId, bool isActive);

    constructor() Ownable(msg.sender) {
        feeRecipient = msg.sender;
        supportedTokens[address(0)] = true;
    }

    modifier vendorExists(string memory vendorId) {
        require(vendors[vendorId].exists, "Vendor does not exist");
        _;
    }

    // Vendor management 
    function registerVendorByOwner(
        string memory vendorId,
        address walletAddress,
        string memory businessName
    ) external onlyOwner {
        require(bytes(vendorId).length > 0, "Invalid vendor ID");
        require(!vendors[vendorId].exists, "Vendor exists");
        require(walletAddress != address(0), "Invalid wallet");

        vendors[vendorId] = Vendor({
            walletAddress: walletAddress,
            businessName: businessName,
            isActive: true,
            totalPayments: 0,
            totalVolume: 0,
            exists: true
        });

        emit VendorRegistered(vendorId, walletAddress, businessName);
    }

    function batchRegisterVendors(
        string[] memory vendorIds,
        address[] memory walletAddresses,
        string[] memory businessNames
    ) external onlyOwner {
        require(
            vendorIds.length == walletAddresses.length &&
            vendorIds.length == businessNames.length,
            "Array length mismatch"
        );
        require(vendorIds.length <= 100, "Batch too large");

        for (uint256 i = 0; i < vendorIds.length; i++) {
            if (!vendors[vendorIds[i]].exists && walletAddresses[i] != address(0)) {
                vendors[vendorIds[i]] = Vendor({
                    walletAddress: walletAddresses[i],
                    businessName: businessNames[i],
                    isActive: true,
                    totalPayments: 0,
                    totalVolume: 0,
                    exists: true
                });
                emit VendorRegistered(vendorIds[i], walletAddresses[i], businessNames[i]);
            }
        }
    }

    function updateVendorWallet(
        string memory vendorId,
        address newWallet
    ) external vendorExists(vendorId) {
        require(
            vendors[vendorId].walletAddress == msg.sender || msg.sender == owner(),
            "Unauthorized"
        );
        require(newWallet != address(0), "Invalid wallet");
        vendors[vendorId].walletAddress = newWallet;
        emit VendorUpdated(vendorId, newWallet);
    }

    function updateVendorWalletByOwner(
        string memory vendorId,
        address newWallet
    ) external onlyOwner vendorExists(vendorId) {
        require(newWallet != address(0), "Invalid wallet");
        vendors[vendorId].walletAddress = newWallet;
        emit VendorUpdated(vendorId, newWallet);
    }

    function setVendorStatus(
        string memory vendorId,
        bool isActive
    ) external onlyOwner vendorExists(vendorId) {
        vendors[vendorId].isActive = isActive;
        emit VendorStatusChanged(vendorId, isActive);
    }

    //  Internal helpers 

    function _buildHash(
        bytes32 paymentId,
        string memory vendorId,
        address token,
        uint256 amount,
        uint256 deadline
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            paymentId,
            vendorId,
            token,
            amount,
            deadline,
            block.chainid,
            address(this)
        ));
    }

    function _transferFunds(
        address token,
        address vendorWallet,
        uint256 vendorAmount,
        uint256 feeAmount
    ) internal {
        if (token == address(0)) {
            require(msg.value == vendorAmount + feeAmount, "Incorrect ETH amount");

            (bool successVendor, ) = payable(vendorWallet).call{value: vendorAmount}("");
            require(successVendor, "Vendor transfer failed");

            if (feeAmount > 0) {
                (bool successFee, ) = payable(feeRecipient).call{value: feeAmount}("");
                require(successFee, "Fee transfer failed");
            }
        } else {
            require(msg.value == 0, "No ETH for token payment");

            require(
                IERC20(token).transferFrom(msg.sender, address(this), vendorAmount + feeAmount),
                "Token transfer failed"
            );
            require(
                IERC20(token).transfer(vendorWallet, vendorAmount),
                "Vendor transfer failed"
            );
            if (feeAmount > 0) {
                require(
                    IERC20(token).transfer(feeRecipient, feeAmount),
                    "Fee transfer failed"
                );
            }
        }
    }

    //run all checks and verify the backend signature.
    function _validatePayment(PaymentParams calldata p) internal view {
        require(block.timestamp <= p.deadline, "Signature expired");
        require(!payments[p.paymentId].exists, "Payment exists");
        require(vendors[p.vendorId].exists, "Vendor does not exist");
        require(vendors[p.vendorId].isActive, "Vendor inactive");
        require(supportedTokens[p.token], "Token unsupported");
        require(p.amount > 0, "Invalid amount");

        bytes32 hash = _buildHash(p.paymentId, p.vendorId, p.token, p.amount, p.deadline);
        address signer = ECDSA.recover(
            MessageHashUtils.toEthSignedMessageHash(hash),
            p.backendSignature
        );
        require(signer == owner(), "Invalid backend signature");
    }


    function _processPayment(PaymentParams calldata p) internal returns (uint256 feeAmount) {
        feeAmount = (p.amount * platformFee) / BASIS_POINTS;
        _transferFunds(p.token, vendors[p.vendorId].walletAddress, p.amount, feeAmount);
    }


    function _recordPayment(PaymentParams calldata p, uint256 feeAmount) internal {
        payments[p.paymentId] = PaymentRecord({
            paymentId:    p.paymentId,
            vendor:       vendors[p.vendorId].walletAddress,
            customer:     msg.sender,
            totalAmount:  p.amount + feeAmount,
            vendorAmount: p.amount,
            feeAmount:    feeAmount,
            token:        p.token,
            createdAt:    block.timestamp,
            exists:       true
        });

        vendors[p.vendorId].totalPayments++;
        vendors[p.vendorId].totalVolume += p.amount;

        emit PaymentCompleted(
            p.paymentId,
            p.vendorId,
            vendors[p.vendorId].walletAddress,
            msg.sender,
            p.amount + feeAmount,
            p.amount,
            feeAmount,
            p.token,
            block.timestamp
        );
    }

   

    function createPayment(PaymentParams calldata p)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        _validatePayment(p);
        _recordPayment(p, _processPayment(p));
    }


    function getPayment(bytes32 paymentId)
        external
        view
        returns (
            address vendor,
            address customer,
            uint256 totalAmount,
            uint256 vendorAmount,
            uint256 feeAmount,
            address token,
            uint256 createdAt
        )
    {
        require(payments[paymentId].exists, "Payment does not exist");
        PaymentRecord storage p = payments[paymentId];
        return (
            p.vendor,
            p.customer,
            p.totalAmount,
            p.vendorAmount,
            p.feeAmount,
            p.token,
            p.createdAt
        );
    }

    function getVendor(string memory vendorId)
        external
        view
        returns (
            address walletAddress,
            string memory businessName,
            bool isActive,
            uint256 totalPayments,
            uint256 totalVolume
        )
    {
        require(vendors[vendorId].exists, "Vendor does not exist");
        Vendor storage v = vendors[vendorId];
        return (
            v.walletAddress,
            v.businessName,
            v.isActive,
            v.totalPayments,
            v.totalVolume
        );
    }

    function isVendorActive(string memory vendorId) external view returns (bool) {
        return vendors[vendorId].exists && vendors[vendorId].isActive;
    }



    function setPlatformFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee too high (max 10%)");
        platformFee = newFee;
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid address");
        feeRecipient = newRecipient;
    }

    function setSupportedToken(address token, bool supported) external onlyOwner {
        supportedTokens[token] = supported;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function emergencyWithdraw(address token) external onlyOwner {
        if (token == address(0)) {
            uint256 balance = address(this).balance;
            if (balance > 0) {
                (bool success, ) = owner().call{value: balance}("");
                require(success, "Withdrawal failed");
            }
        } else {
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                require(IERC20(token).transfer(owner(), balance), "Token withdrawal failed");
            }
        }
    }
}
