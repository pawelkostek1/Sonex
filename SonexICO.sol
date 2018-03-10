pragma solidity ^0.4.18;

  /**
  * @dev SafeMath library - solves the overflow vulnerability problem.
  *          Taken from: 'https://github.com/OpenZeppelin/'.
  */
library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  */
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
      return 0;
    }
    uint256 c = a * b;
    assert(c / a == b);
    return c;
  }

  /**
  * @dev Integer division of two numbers, truncating the quotient.
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  /**
  * @dev Substracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}

/**
 * @dev Contract that implements the ownership. The right to call the function designated by onlyOwner modifier.
 */
contract owned {
    address public owner;
    
    function owned() public {
        owner = msg.sender;
    }
    
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }
    
    function transferOwnership(address newOwner) onlyOwner public {
        owner = newOwner;
    }
}

/**
 * @dev Common interfaces to integrate with the ERC223 Standard.
 */
interface Token {function transfer(address receiver, uint256 amount) external; }
interface ERC223ReceivingContract {function tokenFallback(address _from, uint256 _value, bytes _data) external; }

/**
 * @dev Custom crowsale implementation (mostly based on reference implementation).
 */
contract SonexICO is owned, ERC223ReceivingContract {
    
    using SafeMath for uint256;
    
    address private _association;
    uint256 private _fundingGoal;
    uint256 private _amountRaised;
    uint256 private _deadline;
    uint256 private _limit;
    uint256 private _price;
    uint256 private _shareBalance;
    Token private _tokenShares;
    
    mapping (address => uint256) private _balanceOf;
    mapping (address => uint256) private _shareLimitOf;
    
    bool _fundingGoalReached = false;
    bool _crowdsaleClosed = false;
    
    modifier afterDeadline() { if (now >= _deadline) _;}
    modifier availableShare( uint256 _value) {
        uint amount = _value.div(_price);
        require(!_crowdsaleClosed);
        require(_shareBalance.sub(_value) > 0);
        _;
    }
    modifier withinLimit(address _addr, uint256 _value) {
        uint256 amount = _value.div(_price);
        require(_shareLimitOf[_addr].add(amount) <= _limit);
        _;
    }
    
    event GoalReached(address recipient, uint256 totalAmountRaised);
    event FundTransfer(address indexed backer, uint256 indexed amount, bool indexed isContribution);
    
    /**
     * @dev Constructor function - sets up basic parameters and Crowdsale ownership.
     * 
     * @param ifSuccessfulSendTo - 
     * @param fundingGoalInEthers - 
     * @param durationInMinutes -
     * @param etherCostOfEachShare - 
     * @param addressShares - 
     * @param shareLimit - 
     */
    function SonexICO (
        address ifSuccessfulSendTo,
        uint256 fundingGoalInEthers,
        uint256 durationInMinutes,
        uint256 etherCostOfEachShare,
        address addressShares,
        uint256 shareLimit
    ) onlyOwner public { //Not sure whether onlyOwner modifier is needed here. Do we want this to be public?
    
        require(etherCostOfEachShare > 0);
        require(ifSuccessfulSendTo != address(0));
        require(addressShares != address(0));
        
        _association = ifSuccessfulSendTo;
        _fundingGoal = fundingGoalInEthers.mul(1 ether);
        _deadline = now.add(durationInMinutes.mul(1 minutes));//'now' does not refer to the current time, it is a Block.timestamp.
        _price = etherCostOfEachShare.mul(1 ether);
        _limit = shareLimit;
        _tokenShares = Token(addressShares);
    }
    
    /**
     * @dev Getter function - returns the amount of shares left to be sold.
     */
    function availableShares() public view returns (uint256) {
        return _shareBalance;
    }
    
    /**
     * @dev Fallback function - usualy used to accept upcoming ether, however, in this case it reverts all transactions due to not sufficient gas.
     */
    function () payable public {//Is it necessary to have this function at all?
        revert();
    }
    
    /**
     * @dev Buy function - allows transaction sender to purchase shares.
     */
    function buy() payable public {
        buyFor(msg.sender);
    }
    
    /**
     * @dev BuyFor function - allows transaction sender to purchase shares on behalf of other person.
     * 
     * @param _addr - 
     */
    function buyFor(address _addr) availableShare(msg.value) withinLimit(_addr, msg.value) payable public {
        uint256 amount = msg.value.div(_price);
        _balanceOf[_addr] = _balanceOf[_addr].add(msg.value);
        _shareLimitOf[_addr] = _shareLimitOf[_addr].add(amount);
        _shareBalance = _shareBalance.sub(amount);
        _amountRaised = _amountRaised.add(msg.value);
        emit FundTransfer(_addr, msg.value, true);
        _tokenShares.transfer(_addr, amount);
    }
    
    /**
     * @dev Token fallback function - registers all the shares to be sold in the Crowdsale. It can be executed only by the association. 
     * 
     * @param _from - 
     * @param _value -
     * @param _data - 
     */
    function tokenFallback(address _from, uint256 _value, bytes _data) onlyOwner external { //what to do with data
        require(_from == owner);
        _shareBalance = _shareBalance.add(_value);
        _data; // Inefficiency!!!
    } 
    
    /**
     * @dev Crowdsale closing function - in case of deadline passed allows to close the crowdsale. However, it will not execute before the deadline.
     */
    function closeCrowdsale() afterDeadline onlyOwner public { //do we onlyOwner only to be able to call this function
        if (_amountRaised >= _fundingGoal){
            _fundingGoalReached = true;
            emit GoalReached(_association, _amountRaised);
        }
        _crowdsaleClosed = true;
    }
    
    /**
     * @dev Ether withdrawal function - in case of funding goal reached allows the association to Withdraw the funds. Alternativly, the right to Withdraw ether goes to contributors.
     */
    function safeWithdrawal() afterDeadline public {
        /*
        if (!_fundingGoalReached) {
            uint256 amount = _balanceOf[msg.sender];
            _balanceOf[msg.sender] = 0;
            if(amount > 0){
                if(msg.sender.send(amount)){
                    emit FundTransfer(msg.sender, amount, false);
                } else {
                    _balanceOf[msg.sender] = amount;
                }
            }
        }
        
        if (_fundingGoalReached && _association == msg.sender) {
            if (_association.send(_amountRaised)){
                emit FundTransfer(_association, _amountRaised, false);
            } else {
                _fundingGoalReached = false;
            }
        }
        */
        
        //Alternative implmentation
        if (!_fundingGoalReached) {
            uint256 amount = _balanceOf[msg.sender];
            _balanceOf[msg.sender] = 0;
            if(amount > 0){
                emit FundTransfer(msg.sender, amount, false);
                msg.sender.transfer(amount);
            }
        }
        else if(_fundingGoalReached && _association == msg.sender) {
            //emit FundTransfer(_association, _amountRaised, false); //This triggers a warning for some reason...
            _association.transfer(_amountRaised);
        }
        
    }
}
