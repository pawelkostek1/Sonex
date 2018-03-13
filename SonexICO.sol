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
    address private owner;

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
    uint256 private _durationPrivateICO;
    uint256 private _minimumInvestmentInPrivateICO
    uint256 private _limit;
    uint256 private _minimumInvestment;
    uint256 private _price;
    uint256 private _coinBalance;
    Token private _tokenCoins;

    mapping (address => uint256) private _balanceOf;
    mapping (address => uint256) private _coinLimitOf;
    mapping (address => bool) private _supportsToken;

    bool _fundingGoalReached = false;
    bool _crowdsaleClosed = false;

    modifier afterDeadline() { require(now >= _deadline); _;}
    modifier availableCoin( uint256 _value) {
        uint amount = _value.div(_price);
        require(!_crowdsaleClosed);
        require(_coinBalance.sub(amount) > 0);
        _;
    }
    modifier withinLimit(address _addr, uint256 _value) {
        uint256 amount = _value.div(_price);
        require(_coinLimitOf[_addr].add(amount) <= _limit);
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
     * @param etherCostOfEachCoin -
     * @param addressCoins -
     * @param shareLimit -
     */
    function SonexICO (
        address ifSuccessfulSendTo,
        uint256 fundingGoalInEthers,
        uint256 durationInMinutes,
        uint256 durationInMinutesOfPrivateICO,
        uint256 minimumInvestmentInPrivateICO,
        uint256 etherCostOfEachCoin,
        address addressCoins,
        uint256 coinLimit
    ) onlyOwner public { //Not sure whether onlyOwner modifier is needed here. Do we want this to be public?

        require(etherCostOfEachCoin > 0);
        require(ifSuccessfulSendTo != address(0));
        require(addressCoins != address(0));

        _association = ifSuccessfulSendTo;
        _fundingGoal = fundingGoalInEthers.mul(1 ether);
        _deadline = now.add(durationInMinutes.mul(1 minutes));//'now' does not refer to the current time, it is a Block.timestamp.
        _durationPrivateICO = durationInMinutesOfPrivateICO.mul(1 minutes);
        _minimumInvestmentInPrivateICO = minimumInvestmentInPrivateICO;
        _price = etherCostOfEachCoin.mul(1 ether);
        _limit = coinLimit;
        _tokenCoins = Token(addressCoins);
        _supportsToken[addressCoins] = true;
    }

    /**
     * @dev Getter function - returns the amount of coins left to be sold.
     */
    function availableCoins() public view returns (uint256) {
        return _coinBalance;
    }

    /**
     * @dev Getter function - returns the price of coins left to be sold.
     */
    function price() public view returns (uint256) {
        return _price;
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
    function buyFor(address _addr) availableCoin(msg.value) withinLimit(_addr, msg.value) payable public {
        uint256 amount = msg.value.div(_price);
        /*
        if(now<=_durationPrivateICO.div(20 minutes)){//first week private ICO
          require(_minimumInvestmentInPrivateICO);
          _balanceOf[_addr] = _balanceOf[_addr].add(msg.value);
          _coinLimitOf[_addr] = _coinLimitOf[_addr].add(amount);
          _coinBalance = _coinBalance.sub(amount);
          _amountRaised = _amountRaised.add(msg.value);
          emit FundTransfer(_addr, msg.value, true);
          _tokenCoins.transfer(_addr, amount.mul(1.5));
        }else if(now<=_deadline.sub(10 minutes)&&now>_deadline.sub(20 minutes)){//second week private ICO
          require(_minimumInvestmentInPrivateICO);
          _balanceOf[_addr] = _balanceOf[_addr].add(msg.value);
          _coinLimitOf[_addr] = _coinLimitOf[_addr].add(amount);
          _coinBalance = _coinBalance.sub(amount);
          _amountRaised = _amountRaised.add(msg.value);
          emit FundTransfer(_addr, msg.value, true);
          _tokenCoins.transfer(_addr, amount);
        }else{//public ICC
          */
            _balanceOf[_addr] = _balanceOf[_addr].add(msg.value);
            _coinLimitOf[_addr] = _coinLimitOf[_addr].add(amount);
            _coinBalance = _coinBalance.sub(amount);
            _amountRaised = _amountRaised.add(msg.value);
            emit FundTransfer(_addr, msg.value, true);
            _tokenCoins.transfer(_addr, amount);
        //}
    }

    /**
     * @dev Token fallback function - registers all the shares to be sold in the Crowdsale. It can be executed only by the association.
     *
     * @param _from -
     * @param _value -
     * @param _data -
     */
    function tokenFallback(address _from, uint256 _value, address token) external { //what to do with data
        if(_supportsToken[token]) {
        _coinBalance = _coinBalance.add(_value);
        _data; // Inefficiency!!!
        }
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
