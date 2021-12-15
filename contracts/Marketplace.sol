// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./interfaces/IERC721Verifiable.sol";

contract Marketplace is Context, Ownable, Initializable, IERC721Receiver {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant MAX_AUCTION_DURATION = 182 days; // 182 days - 26 weeks - 6 months
    uint256 public constant MIN_AUCTION_DURATION = 1 minutes;
    uint256 public constant ONE_MILLION = 1000000;
    bytes4 public constant ERC721_Interface = 0x80ac58cd;

    struct Offer {
        bool isListing;
        address seller;
        uint256 price;
    }

    struct Auction {
        bool isListing;
        address seller;
        uint256 minPrice;
        uint256 startTime;
        uint256 endTime;
    }

    struct Transaction {
        address seller;
        address bider;
        uint256 price;
        uint256 time;
    }

    /// @notice token address => token id => offer info
    mapping(address => mapping(uint256 => Offer)) public offers;

    /// @notice token address => token id => auction info
    mapping(address => mapping(uint256 => Auction)) public auctions;

    /// @notice token address => token id => bider => amount
    mapping(address => mapping(uint256 => mapping(address => uint256))) public bids;

    /// @notice token address => token id => last bider
    mapping(address => mapping(uint256 => address)) public lastBider;

    /// @notice token address => token id => list bider
    mapping(address => mapping(uint256 => address[])) public biders;

    /// @notice token address => token id => transaction history
    mapping(address => mapping(uint256 => Transaction[])) public transactions;

    /// @notice coin to be used to trade or bids
    IERC20 public acceptedToken;

    /// @notice transaction fee
    uint256 public transactionFee;

    /// @notice fee balance
    uint256 public feeBalance;

    /* ========== INITTIALIZE =============== */

    function initialize(address _acceptedToken) external initializer {
        require(_acceptedToken != address(0), "Invalid address!");
        acceptedToken = IERC20(_acceptedToken);
    }

    /* ========== VIEWS FUNCTIONS ========== */

    function getAuctionBidsPagination(
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _cursor,
        uint256 _size
    ) external view returns (address[] memory, uint256) {
        uint256 length = _size;
        if (length > biders[_tokenAddress][_tokenId].length - _cursor) {
            length = biders[_tokenAddress][_tokenId].length - _cursor;
        }
        address[] memory values = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            values[i] = biders[_tokenAddress][_tokenId][_cursor + i];
        }
        return (values, _cursor + length);
    }

    function getTransactionPagination(
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _cursor,
        uint256 _size
    ) external view returns (Transaction[] memory, uint256) {
        uint256 length = _size;
        if (length > transactions[_tokenAddress][_tokenId].length - _cursor) {
            length = transactions[_tokenAddress][_tokenId].length - _cursor;
        }
        Transaction[] memory values = new Transaction[](length);
        for (uint256 i = 0; i < length; i++) {
            values[i] = transactions[_tokenAddress][_tokenId][_cursor + i];
        }
        return (values, _cursor + length);
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    /**
     * @dev Listing ERC721 token for sell in market.
     * @param _tokenAddress - address of the ERC721 token
     * @param _tokenId - uint256 of the token id
     * @param _price - uint256 of the price for the bid
     */
    function listingForSell(
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _price
    ) external {
        _requireERC721(_tokenAddress);
        require(!offers[_tokenAddress][_tokenId].isListing, "Offer already exists");
        require(_price > 0, "Required price larger than zero");
        offers[_tokenAddress][_tokenId] = Offer(true, _msgSender(), _price);
        IERC721(_tokenAddress).safeTransferFrom(_msgSender(), address(this), _tokenId);
        emit ListingForSell(_msgSender(), _tokenAddress, _tokenId, _price);
    }

    /**
     * @dev Cancel listing ERC721 token in market.
     * @param _tokenAddress - address of the ERC721 token
     * @param _tokenId - uint256 of the token id
     */
    function cancelListing(address _tokenAddress, uint256 _tokenId) external {
        Offer memory _offer = offers[_tokenAddress][_tokenId];
        require(_offer.isListing, "Offer is not available");
        require(_offer.seller == _msgSender(), "Only seller can cancel offer");
        delete offers[_tokenAddress][_tokenId];
        IERC721(_tokenAddress).safeTransferFrom(address(this), _msgSender(), _tokenId);
        emit CancelListing(_msgSender(), _tokenAddress, _tokenId);
    }

    /**
     * @dev Purchase with accepted token to earn ERC721 token
     * @param _tokenAddress - address of the ERC721 token
     * @param _tokenId - uint256 of the token id
     */
    function purchase(address _tokenAddress, uint256 _tokenId) external {
        Offer memory _offer = offers[_tokenAddress][_tokenId];
        require(_offer.isListing, "Offer is not available");
        require(_offer.seller != _msgSender(), "Seller can not purchase");
        transactions[_tokenAddress][_tokenId].push(
            Transaction(_offer.seller, _msgSender(), _offer.price, block.timestamp)
        );
        delete offers[_tokenAddress][_tokenId];
        acceptedToken.safeTransferFrom(_msgSender(), address(this), _offer.price);
        uint256 _feeAmount = 0;
        if (transactionFee > 0) {
            _feeAmount = _offer.price.mul(transactionFee).div(ONE_MILLION);
            feeBalance = feeBalance.add(_feeAmount);
            acceptedToken.safeTransfer(_offer.seller, _offer.price.sub(_feeAmount));
        } else {
            acceptedToken.safeTransfer(_offer.seller, _offer.price);
        }
        IERC721(_tokenAddress).safeTransferFrom(address(this), _msgSender(), _tokenId);
        emit Purchase(_msgSender(), _tokenAddress, _tokenId, _feeAmount);
    }

    /**
     * @dev Create auction with ERC721 token
     * @param _tokenAddress - address of the ERC721 token
     * @param _tokenId - uint256 of the token id
     * @param _minPrice - uint256 of the price for the auction
     * @param _startTime - uint256 of the start time
     * @param _duration - uint256 of the duration in seconds for the bid
     */
    function createAuction(
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _minPrice,
        uint256 _startTime,
        uint256 _duration
    ) external {
        _requireERC721(_tokenAddress);
        if(_startTime < block.timestamp) {
            _startTime = block.timestamp;
        }
        require(_duration >= MIN_AUCTION_DURATION, "The auction should be last longer than a min auction duration");
        require(_duration <= MAX_AUCTION_DURATION, "The auction can not last longer than max auction duration");
        require(!auctions[_tokenAddress][_tokenId].isListing, "Auction already exists");
        uint256 _endTime = _startTime.add(_duration);
        auctions[_tokenAddress][_tokenId] = Auction(true, _msgSender(), _minPrice, _startTime, _endTime);
        IERC721(_tokenAddress).safeTransferFrom(_msgSender(), address(this), _tokenId);
        emit AuctionCreated(_msgSender(), _tokenAddress, _tokenId, _minPrice, _startTime, _endTime);
    }

    /**
     * @dev Cancel auction with ERC721 token
     * @param _tokenAddress - address of the ERC721 token
     * @param _tokenId - uint256 of the token id
     */
    function cancelAuction(address _tokenAddress, uint256 _tokenId) external {
        Auction memory _auction = auctions[_tokenAddress][_tokenId];
        address _lastBider = lastBider[_tokenAddress][_tokenId];
        require(_auction.isListing, "Auction is not available");
        require(_auction.seller == _msgSender(), "Only seller can cancel auction");
        require(_auction.endTime > block.timestamp, "Can not cancel auction when auction closed");
        if (_lastBider != address(0)) {
            uint256 _lastBidPrice = bids[_tokenAddress][_tokenId][_lastBider];
            if (_lastBidPrice > 0) {
                acceptedToken.safeTransfer(_lastBider, _lastBidPrice);
            }
        }
        deleteAuctionState(_tokenAddress, _tokenId);
        IERC721(_tokenAddress).safeTransferFrom(address(this), _auction.seller, _tokenId);
        emit CancelAuction(_msgSender(), _tokenAddress, _tokenId);
    }

    /**
     * @dev Place a bid for an ERC721 token
     * @param _tokenAddress - address of the ERC721 token
     * @param _tokenId - uint256 of the token id
     * @param _price - uint256 of the price for the bid
     */
    function placeBid(
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _price
    ) external {
        Auction memory _auction = auctions[_tokenAddress][_tokenId];
        address _lastBider = lastBider[_tokenAddress][_tokenId];
        uint256 _lastBidPrice = bids[_tokenAddress][_tokenId][_lastBider];
        require(_auction.isListing, "Auction is not available");
        require(_auction.seller != _msgSender(), "The auction should have an seller different from the sender");
        require(_auction.startTime < block.timestamp && block.timestamp < _auction.endTime, "Auction not active yet");
        require(_price >= _auction.minPrice, "Required new bid price large than min price");
        require(_price > _lastBidPrice, "Required new bid price large than last bid price");
        bids[_tokenAddress][_tokenId][_msgSender()] = _price;
        lastBider[_tokenAddress][_tokenId] = _msgSender();
        biders[_tokenAddress][_tokenId].push(_msgSender());
        transactions[_tokenAddress][_tokenId].push(
            Transaction(_auction.seller, _lastBider, _lastBidPrice, block.timestamp)
        );
        acceptedToken.safeTransferFrom(_msgSender(), address(this), _price);
        if (_lastBider != address(0)) {
            acceptedToken.safeTransfer(_lastBider, _lastBidPrice);
        }
        emit BidPlaced(_msgSender(), _tokenAddress, _tokenId, _price);
    }

    /**
     * @dev Claim nft and token before auction ended
     * @param _tokenAddress - address of the ERC721 token
     * @param _tokenId - uint256 of the token id
     */
    function claimAfterAuction(address _tokenAddress, uint256 _tokenId) external {
        Auction memory _auction = auctions[_tokenAddress][_tokenId];
        address _lastBider = lastBider[_tokenAddress][_tokenId];
        address seller = _auction.seller;
        uint256 _feeAmount = 0;
        require(_auction.isListing, "Auction is not available");
        require(_auction.endTime < block.timestamp, "Auction is not over yet");
        require(_msgSender() == seller || _msgSender() == _lastBider, "Only seller or last bider can claim");
        if (_lastBider == address(0)) {
            require(_msgSender() == seller, "Only seller can claim");
            deleteAuctionState(_tokenAddress, _tokenId);
            IERC721(_tokenAddress).safeTransferFrom(address(this), seller, _tokenId);
        } else {
            uint256 _lastBidPrice = bids[_tokenAddress][_tokenId][_lastBider];
            if (transactionFee > 0) {
                _feeAmount = _lastBidPrice.mul(transactionFee).div(ONE_MILLION);
                feeBalance = feeBalance.add(_feeAmount);
                acceptedToken.safeTransfer(seller, _lastBidPrice.sub(_feeAmount));
            } else {
                acceptedToken.safeTransfer(seller, _lastBidPrice);
            }
            deleteAuctionState(_tokenAddress, _tokenId);
            IERC721(_tokenAddress).safeTransferFrom(address(this), _lastBider, _tokenId);
        }
        emit ClaimAfterAuction(_msgSender(), _tokenAddress, _tokenId, _feeAmount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Sets the share cut for the owner of the contract that's
     * charged to the seller on a successful sale
     * @param _transactionFee - from 0 to 999,999
     */
    function setTransactionFee(uint256 _transactionFee) external onlyOwner {
        require(_transactionFee < ONE_MILLION, "The owner cut should be between 0 and 999,999");
        transactionFee = _transactionFee;
        emit ChangedTransactionFee(transactionFee);
    }

    /**
     * @dev Withdraw fee in contract
     * @param _to - receiver
     */
    function withdrawFee(address _to) external onlyOwner {
        uint256 _feeBalance = feeBalance;
        require(_to != address(0), "Invalid address");
        require(_feeBalance > 0, "Required fee balance larger than zero");
        feeBalance = 0;
        acceptedToken.safeTransfer(_to, _feeBalance);
        emit WithdrawFee(_feeBalance, _to);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Delete auction state before cancel or complete
     * @param _tokenAddress - address of the token
     * @param _tokenId - uint256 of the token id
     */
    function deleteAuctionState(address _tokenAddress, uint256 _tokenId) internal {
        address[] memory _biders = biders[_tokenAddress][_tokenId];
        for (uint256 i; i < _biders.length; i++) {
            delete bids[_tokenAddress][_tokenId][_biders[i]];
        }
        delete auctions[_tokenAddress][_tokenId];
        delete lastBider[_tokenAddress][_tokenId];
        delete biders[_tokenAddress][_tokenId];
    }

    /**
     * @dev Check if the token has a valid ERC721 implementation
     * @param _tokenAddress - address of the token
     */
    function _requireERC721(address _tokenAddress) internal view {
        IERC721 token = IERC721(_tokenAddress);
        require(token.supportsInterface(ERC721_Interface), "Token has an invalid ERC721 implementation");
    }

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /* =============== EVENTS ==================== */
    event AuctionCreated(
        address indexed _user,
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _minPrice,
        uint256 _tartTime,
        uint256 _endTime
    );
    event CancelAuction(address indexed _user, address _tokenAddress, uint256 _tokenId);
    event BidPlaced(address indexed _user, address _tokenAddress, uint256 _tokenId, uint256 _price);
    event ClaimAfterAuction(address indexed _user, address _tokenAddress, uint256 _tokenId, uint256 _feeAmount);
    event ListingForSell(address indexed _user, address _tokenAddress, uint256 _tokenId, uint256 _price);
    event CancelListing(address indexed _user, address _tokenAddress, uint256 _tokenId);
    event Purchase(address indexed _user, address _tokenAddress, uint256 _tokenId, uint256 _feeAmount);
    event ChangedTransactionFee(uint256 _transactionFee);
    event WithdrawFee(uint256 _fee, address _to);
}
