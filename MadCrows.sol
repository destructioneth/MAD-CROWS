// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IERC20.sol";
import "./ERC721.sol";
import "./Ownable.sol";
import "./ERC721Enumerable.sol";
import "./Context.sol";

contract MADCROW is
    Context,
    Ownable,
    ERC721Enumerable
{
    //ERRORS
    error SaleNotEnded();
    error NoBalance();
    error NoAllowance();
    error SoldOut();
    error AlreadyClaimed();
    error URIFrozen();
    error CrowNotOwned();
    error SaleNotStarted();
    error NotEnoughCrows();
    error ZeroMint();
    error TimeLocked();
    error BadPrice();

    //METADATA
    bool public tokenURIFrozen = false;
    string private baseTokenURI;
    
    //MINT
    uint256 constant public MAX_SUPPLY = 3333;
    uint256 public idTracker;

    //DUTCH
    uint256 public startDate;
    uint256 public endDate;
    uint256 public startPrice = 100 ether;
    uint256 public endPrice = 10 ether;
    uint256 constant public SEGMENTS = 24;
    uint256 public lastPrice;
    bool public soldOut;

    //TEAM CUT
    bool public rewardsClaimed;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    //REFUND
    mapping(uint256 => uint256) public purchasePrices;

    //AIRDROP
    mapping(uint256 => bool) public airdropClaimed;

    //CONTRACT
    IERC721Enumerable public crocrow;
    IERC20 public mad;

    event MintEvent(address indexed buyer, uint256 currentSupply, uint256 amount, uint256 time, uint256 price); 

    constructor(
        string memory name,
        string memory symbol,
        string memory uri,
        address _crocrow,
        address _mad,
        uint256 _startDate
    ) ERC721(name, symbol) {
        baseTokenURI = uri;
        startDate = _startDate;
        endDate = startDate + (60 * 60 * 2);
        crocrow = IERC721Enumerable(_crocrow);
        mad = IERC20(_mad);
        _safeMint(_msgSender(), 0);
    }

    function mint(uint256 amount) external {
        uint256 price = getCurrentPrice();
        uint256 totalPrice = price * amount;
        if(amount == 0) revert ZeroMint();
        if((idTracker + amount) > MAX_SUPPLY) revert SoldOut();
        if(block.timestamp < startDate) revert SaleNotStarted();
        if(totalPrice > mad.allowance(_msgSender(),address(this))) revert NoAllowance();
        if(mad.balanceOf(_msgSender()) < totalPrice) revert NoBalance();
        if(crocrow.balanceOf(_msgSender()) < 2) revert NotEnoughCrows();
        
        for (uint256 i = 1; i <= amount;) {
            purchasePrices[idTracker + i] = price;
            _safeMint(_msgSender(), idTracker + i);
            unchecked{
                ++i;
            }
        }
        idTracker += amount;

        if(idTracker == MAX_SUPPLY){
            purchasePrices[0] = price;
            lastPrice = price;
            soldOut = true;
        }

        mad.transferFrom(_msgSender(),address(this),totalPrice);
        emit MintEvent(_msgSender(),idTracker,amount,block.timestamp,price);
    }

    //ADMIN CONTROLS

    function changeStartPrice(uint256 price) external onlyOwner{
        if(block.timestamp >= startDate - (60*60*24) ) revert TimeLocked();
        if(price <= endPrice) revert BadPrice();
        startPrice = price;
    }

    function changeEndPrice(uint256 price) external onlyOwner{
        if(block.timestamp >= startDate - (60*60*24) ) revert TimeLocked();
        if(price >= startPrice) revert BadPrice();
        endPrice = price;
    }

    function changeStartDate(uint256 stamp) public onlyOwner{
        if(block.timestamp >= startDate - (60*60*24) ) revert TimeLocked();
        startDate = stamp;
        endDate = stamp + (60 * 60 * 2);
    }

    function setBaseTokenURI(string memory uri) public onlyOwner {
        if(tokenURIFrozen) revert URIFrozen();
        baseTokenURI = uri;
    }
    
    function freezeBaseURI() public onlyOwner {
        tokenURIFrozen = true;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function walletOfOwner(address add) external view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(add);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(add, i);
        }
        return tokenIds;
    }

    //TEAM FUNDS

    function withdraw() public onlyOwner{
        if(!soldOut) revert SaleNotEnded();
        if(rewardsClaimed) revert AlreadyClaimed();
        rewardsClaimed = true;
        uint256 teamAmount = lastPrice * MAX_SUPPLY / 4;
        mad.transfer(_msgSender(),teamAmount);
        uint256 burnAmount = lastPrice * MAX_SUPPLY / 2;
        mad.transfer(DEAD,burnAmount);
    }

    //REFUNDS

    function refund(uint256 madCrow) external{
        if(!soldOut) revert SaleNotEnded();
        if(_msgSender() != ownerOf(madCrow)) revert CrowNotOwned();
        uint256 amount = purchasePrices[madCrow] - lastPrice;
        if(amount == 0) revert NoBalance();
        purchasePrices[madCrow] = lastPrice;
        mad.transfer(_msgSender(),amount);
    }

    function refundAll() public{
        if(!soldOut) revert SaleNotEnded();
        uint256 ownerTokenCount = balanceOf(_msgSender());
        uint256 toSend;
        uint256 tokenId;
        for (uint256 i; i < ownerTokenCount;) {
            unchecked{
                tokenId = tokenOfOwnerByIndex(_msgSender(),i);
                uint256 amount = purchasePrices[tokenId] - lastPrice;
                purchasePrices[tokenId] = lastPrice;
                toSend+= amount;
                ++i;
            }
        }
        if(toSend == 0) revert NoBalance();
        mad.transfer(_msgSender(),toSend);
    }

    function refundCheck(uint256 madCrow) external view returns(uint256){
        if(!soldOut) revert SaleNotEnded();
        return purchasePrices[madCrow] - lastPrice;
    }

    function refundMulticheck(address add) external view returns (uint256) {
        if(!soldOut) revert SaleNotEnded();
        uint256 ownerTokenCount = balanceOf(add);
        uint256 toSend;
        uint256 tokenId;
        for (uint256 i; i < ownerTokenCount;) {
            unchecked{
                tokenId = tokenOfOwnerByIndex(add,i);
                uint256 amount = purchasePrices[tokenId] - lastPrice;
                toSend+= amount;
                ++i;
            }
        }
        return (toSend);
    }
    
    //AIRDROPS

    function claimAirdrop(uint256 crow) external{
        if(!soldOut) revert SaleNotEnded();
        if(_msgSender() != crocrow.ownerOf(crow)) revert CrowNotOwned();
        if(airdropClaimed[crow]) revert AlreadyClaimed();
        uint256 airdropAmount = lastPrice * MAX_SUPPLY / 4 / 7777;
        airdropClaimed[crow] = true;
        mad.transfer(_msgSender(),airdropAmount);
    }

    function claimAirdropAll() public{
        if(!soldOut) revert SaleNotEnded();
        uint256 airdropAmount = lastPrice * MAX_SUPPLY / 4 / 7777;
        uint256 ownerTokenCount = crocrow.balanceOf(_msgSender());
        uint256 toSend;
        uint256 tokenId;
        for (uint256 i; i < ownerTokenCount;) {
            tokenId = crocrow.tokenOfOwnerByIndex(_msgSender(), i);
            unchecked{
                if(!airdropClaimed[tokenId]){
                    toSend += airdropAmount;
                    airdropClaimed[tokenId] = true;
                }
                ++i;
            }
        }
        if(toSend == 0) revert NoBalance();
        mad.transfer(_msgSender(),toSend);
    }

    //Function for mass claiming for the whales with 200+ CRO CROWs.
    function claimAirdrop100(uint256 index) external{
        if(!soldOut) revert SaleNotEnded();
        uint256 airdropAmount = lastPrice * MAX_SUPPLY / 4 / 7777;
        uint256 ownerTokenCount = crocrow.balanceOf(_msgSender());
        uint256 toSend;
        uint256 tokenId;
        if(ownerTokenCount < 100 * (index+1)) revert NotEnoughCrows();
        for (uint256 i = 100 * index; i < 100 * (index+1);) {
            tokenId = crocrow.tokenOfOwnerByIndex(_msgSender(), i);
            unchecked{
                if(!airdropClaimed[tokenId]){
                    toSend += airdropAmount;
                    airdropClaimed[tokenId] = true;
                }
                ++i;
            }
        }
        if(toSend == 0) revert NoBalance();
        mad.transfer(_msgSender(),toSend);
    }

    function airdropCheck(uint256 crow) external view returns(bool){
        if(!soldOut) revert SaleNotEnded();
        return airdropClaimed[crow];
    }

    function airdropMulticheck(address add) external view returns (uint256) {
        if(!soldOut) revert SaleNotEnded();
        uint256 airdropAmount = lastPrice * MAX_SUPPLY / 4 / 7777;
        uint256 ownerTokenCount = crocrow.balanceOf(add);
        uint256 toSend;
        uint256 tokenId;
        for (uint256 i; i < ownerTokenCount;) {
            tokenId = crocrow.tokenOfOwnerByIndex(add, i);
            unchecked{
                if(!airdropClaimed[tokenId]){
                    toSend += airdropAmount;
                }
                ++i;
            }
        }
        return toSend;
    }

    //TIME

    function currentSegment() public view returns(uint256){
        if(block.timestamp < startDate){
            return 0;
        }else{
            uint256 passed = block.timestamp - startDate;
            uint256 segmentSize = (endDate-startDate) / SEGMENTS;
            uint256 current = ((passed - (passed % segmentSize)) / segmentSize) + 1;
            if(current > SEGMENTS){
                current = SEGMENTS+1;
            }
            return current;
        }
    }

    function getCurrentPrice() public view returns(uint256){
        uint256 segment = currentSegment();
        if(segment == 0){
            return startPrice;
        }
        return endPrice+((SEGMENTS - (segment-1)) * (startPrice-endPrice) /SEGMENTS);
    }
}
