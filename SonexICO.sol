pragma solidity ^0.4.18;

  /**
  * @dev SafeMath library - solves the overflow vulnerability problem.
  *          Taken from: 'https://github.com/OpenZeppelin/'.
  */
library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  *
  * @param a - first integer nuber
  * @param b - second integer number
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
  *
  * @param a - first integer nuber
  * @param b - second integer number
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  /**
  * @dev Substracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  *
  * @param a - first integer nuber
  * @param b - second integer number
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  *
  * @param a - first integer nuber
  * @param b - second integer number
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
interface ERC20ReceivingContract {function tokenFallback(address _from, uint256 _value, address token) external; }

/**
 * @dev Custom crowsale implementation (mostly based on reference implementation).
 */
contract SonexIco is owned, ERC20ReceivingContract {

    using SafeMath for uint256;

    //Define the internal parameters of the contract
    address private _association;
    uint256 private _fundingGoal;
    uint256 private _amountRaised;
    uint256 private _deadline;
    uint256 private _deadlinePrivateICO;
    uint256 private _durationPrivateICO;
    uint256 private _minimumInvestmentInPrivateICO;
    uint256 private _limit;
    uint256 private _minimumInvestment;
    uint256 private _price;
    uint256 private _coinBalance;
    Token private _tokenCoins;
    address[] _contributorsAddress;

    mapping (address => uint256) private _balanceOf;
    mapping (address => uint256) private _coinLimitOf;
    mapping (address => bool) private _supportsToken;
    mapping (address => bool) private _contributors;

    bool _fundingGoalReached = false;
    bool _crowdsaleClosed = false;

    modifier afterDeadline() { require(now >= _deadline); _;}

    modifier closedCrowdsale() {require(_crowdsaleClosed == true); _;}

    modifier availableCoin( uint256 _value) {
        uint amount = _value.div(_price); //price
        require(!_crowdsaleClosed);
        require(_coinBalance.sub(amount) > 0); // ico contracts needs money in its account and shoudlent be closed
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
     * @param ifSuccessfulSendTo - the address where the raised funds will be send in case of succesful ICO
     * @param fundingGoalInEthers - the goal to be achived during ICO
     * @param durationInMinutesOfICO - the duration of the ICO in minutes
     * @param durationInMinutesOfPrivateICO - the duration of the private ICO (part of the whole ICO)
     * @param minimumInvestmentInPrivateICO - the minimum investment that is required to participate in the private ICO
     * @param costOfEachCoinInWei - cost of each coin in wei
     * @param addressOfCoinContract - the address of the token contract
     * @param limitOnTheNumberOfCoinsPersonCanBuy - the limit of how many coins can a single person buy
     */
    function SonexIco (
        address ifSuccessfulSendTo,
        uint256 fundingGoalInEthers,
        uint256 durationInMinutesOfICO,
        uint256 durationInMinutesOfPrivateICO,
        uint256 minimumInvestmentInPrivateICO,
        uint256 costOfEachCoinInWei,
        address addressOfCoinContract,
        uint256 limitOnTheNumberOfCoinsPersonCanBuy
    ) onlyOwner public { //Not sure whether onlyOwner modifier is needed here. Do we want this to be public?

        require(costOfEachCoinInWei > 0);
        require(ifSuccessfulSendTo != address(0));
        require(addressOfCoinContract != address(0));

        _association = ifSuccessfulSendTo;
        _fundingGoal = fundingGoalInEthers.mul(1 ether);
        _deadline = now.add(durationInMinutesOfICO.mul(1 minutes));//'now' does not refer to the current time, it is a Block.timestamp.
        _durationPrivateICO = durationInMinutesOfPrivateICO.mul(1 minutes);
        _deadlinePrivateICO = now.add(_durationPrivateICO);
        _minimumInvestmentInPrivateICO = minimumInvestmentInPrivateICO.mul(1 ether);
        _price = costOfEachCoinInWei;
        _limit = limitOnTheNumberOfCoinsPersonCanBuy;
        _tokenCoins = Token(addressOfCoinContract);
        _supportsToken[addressOfCoinContract] = true;
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
     * @dev Buy convinience function - allows transaction sender to purchase shares.
     */
    function _buy(address _addr, uint256 _value, uint256 amount) internal {//do we have to make it payable??


      uint256 five_percent = _value.sub(_value.div(20));
      uint256 nine_five_percent =  _value.sub(five_percent);

      if(!_contributors[_addr]){
        _contributors[_addr] = true;
        _contributorsAddress.push(_addr);
      }
      _balanceOf[_addr] = _balanceOf[_addr].add(nine_five_percent);
      _coinLimitOf[_addr] = _coinLimitOf[_addr].add(amount);
      _coinBalance = _coinBalance.sub(amount);
      _amountRaised = _amountRaised.add(_value);
      FundTransfer(_addr, _value, true);
      FundTransfer(_association, five_percent, false);

      _tokenCoins.transfer(_addr, amount);
      _association.transfer(five_percent);
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
     * @param _addr - address of the person for whom the tokens are purchased
     */
    function buyFor(address _addr) availableCoin(msg.value) withinLimit(_addr, msg.value) payable public {
        uint256 amount = msg.value.div(_price);
        //amount = amount.mul(10 ** uint256(18));



        if(now <= _deadlinePrivateICO.sub(_durationPrivateICO.div(2))){//first week private ICO
          require(msg.value >= _minimumInvestmentInPrivateICO);
          _buy(_addr, msg.value, amount.add(amount.div(2)));
        }else if(now <=_deadlinePrivateICO){//second week private ICO
          require(msg.value >= _minimumInvestmentInPrivateICO);
          _buy(_addr, msg.value, amount);
        }else{//public ICC
          _buy(_addr, msg.value, amount);
        }
    }

    /**
     * @dev Token fallback function - registers all the shares to be sold in the Crowdsale. It can be executed only by the association.
     *
     * @param _from - address of the person or contract transfering the money to the ICO
     * @param _value - the value of how much was transfered
     * @param token - the address of the token that was transfered in the transaction
     */
    function tokenFallback(address _from, uint256 _value, address token) external { //what to do with data
        if(_supportsToken[token]){
        _coinBalance = _coinBalance.add(_value);
        }
        _from;
    }

    /**
     * @dev Crowdsale closing function - in case of deadline passed allows to close the crowdsale. However, it will not execute before the deadline.
     */
    function closeCrowdsale() afterDeadline onlyOwner public { //do we onlyOwner only to be able to call this function
        if (_amountRaised >= _fundingGoal){
            _fundingGoalReached = true;
            GoalReached(_association, _amountRaised);
        }
        _crowdsaleClosed = true;
    }

    /**
     * @dev Ether withdrawal function - in case of funding goal reached allows the association to Withdraw the funds. Alternativly, the right to Withdraw ether goes to contributors.
     */
    function safeWithdrawal() afterDeadline closedCrowdsale onlyOwner public { //Must revise this part of the code!!!
        /*
        if (!_fundingGoalReached) {
            uint256 amount = _balanceOf[msg.sender];
            _balanceOf[msg.sender] = 0;
            if(amount > 0){
                if(msg.sender.send(amount)){
                    FundTransfer(msg.sender, amount, false);
                } else {
                    _balanceOf[msg.sender] = amount;
                }
            }
        }

        if (_fundingGoalReached && _association == msg.sender) {
            if (_association.send(_amountRaised)){
                FundTransfer(_association, _amountRaised, false);
            } else {
                _fundingGoalReached = false;
            }
        }
        */

        //Alternative implmentation
        if (!_fundingGoalReached) {
            for(uint i=0; i< _contributorsAddress.length; i++){
              uint256 amount = _balanceOf[_contributorsAddress[i]];
              _balanceOf[_contributorsAddress[0]] = 0;
              if(amount > 0){
                  FundTransfer(_contributorsAddress[0], amount, false);
                  _contributorsAddress[0].transfer(amount);
              }
            }
        }
        else if(_fundingGoalReached && _association == msg.sender) {
            FundTransfer(_association, _amountRaised, false); //This triggers a warning for some reason...
            _association.transfer(_amountRaised);
        }

    }
}
