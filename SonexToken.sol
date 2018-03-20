pragma solidity ^0.4.18;

/**
 * @dev SafeMath library - solves the overflow vulnerability problem.
 *          Taken from: 'https://github.com/OpenZeppelin/'
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
 * @dev Contract that implements the ownership. The right to call the function designated by onlyOwner modifier
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
 * @dev Common interfaces to integrate with the ERC20 Standard.
 */
interface tokenRecipient {function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) external; }

interface ERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approve(address indexed from, address indexed to, uint256 value);

    function transfer(address _to, uint256 _value) external;
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool success);
    function approve(address _spender, uint256 _value) external returns (bool success);
    function approveAndCall(address _spender, uint256 _value, bytes _extraData) external returns (bool success);
}

//A custom version of the Receiving Contract interface to comply with ERC20
interface ERC20ReceivingContract {function tokenFallback(address _from, uint256 _value, address token) external; }

/**
 * @dev Implementation of the custom token - the Sonex shares (mostly based on reference implementation). Ownership of the Sonex Contract will be assigned to the association.
 */
contract SonexCoin is owned, ERC20 {

    using SafeMath for uint256;

    //Define internal parameters of the Token
    string private _name;
    string private _symbol;
    uint8 private _decimals = 18;
    uint256 private _totalSupply;

    mapping (address => uint256) private _balanceOf;
    mapping (address => mapping (address => uint256)) private _allowance;

    /**
     * @dev Constructor function - sets up basic parameters.
     *
     * @param initialSupply - initial supply of the token
     * @param tokenName - name of the token
     * @param tokenSymbol - symbol of the token
     */
    function SonexCoin(
        uint256 initialSupply,
        string tokenName,
        string tokenSymbol
    ) onlyOwner public {

        _totalSupply = initialSupply * (10 ** uint256(_decimals));
        _balanceOf[msg.sender] = _totalSupply;
        _name = tokenName;
        _symbol = tokenSymbol;
    }

    /**
     * @dev Getter function - returns name of the token.
     */
    function name() public view returns (string){
        return _name;
    }

    /**
     * @dev Getter function - returns symbol of the token.
     */
    function symbol() public view returns (string){
        return _symbol;
    //uint256 public sellPrice;
    //uint256 public buyPrice;
    }

    /**
     * @dev Getter function - returns number of decimal places of the token.
     */
    function decimals() public view returns (uint8){
        return _decimals;
    }

    /**
     * @dev Getter function - returns total supply of the token.
     */
    function totalSupply() public view returns (uint256){
        return _totalSupply;
    }

    /**
     * @dev Getter function - returns token balance of a msg.sender
     */
    function balanceOf(address _addr) public view returns (uint256){ //This is required so that Ethereneum wallet detect the coin balance
        return _balanceOf[_addr];
    }

    /**
     * @dev Getter function - returns token allowance of a particular address
     */
    function allowanceOf(address _addr) public view returns (uint256){
        return _allowance[msg.sender][_addr];
    }

    /**
     * @dev isContract function - returns whether given address is a contract. Currently, only inline assemly implementation is possible.
     *
     * @param _target - an address of the destination for the transaction, will be evaluated whether it is a contract.
     */
    function _isContract(address _target) internal view returns (bool){ //warning that it is constant?

        uint codeLength;
        assembly {
            // Retrieve the size of the code on target address, this needs assembly .
            codeLength := extcodesize(_target)
        }

        return codeLength > 0;
    }

    /**
     * @dev Convinience transfer function - implements the basic transfer functionality. Performs various checks, uses SafeMath to avoid overflow.
     *
     * @param _from - an address from which the balance will be deduced
     * @param _to - an address to which the balance will be added
     * @param _value - the value to be transfered between addresses
     */
    function _transfer(address _from, address _to, uint256 _value) internal {
        //Prevents from sending to address 0x0.
        require(_to != 0x0);
        //Ensures there is sufficient amount of funds for the given account.
        require(_balanceOf[_from] >= _value);
        //Checks for overflow condition. Possibly not necessary due to usage of SafeMath library.
        require(_balanceOf[_to].add(_value) > _balanceOf[_to]);
        uint256 previousBalances = _balanceOf[_from].add(_balanceOf[_to]);
        _balanceOf[_from] = _balanceOf[_from].sub(_value);
        _balanceOf[_to] = _balanceOf[_to].add(_value);
        assert(_balanceOf[_from].add(_balanceOf[_to]) == previousBalances);
    }

    /**
     * @dev ERC20 compatible transfer function - implements transfer of Sonex token beetwen transaction sender and taget account.
     *
     * @param _to - an address to which the balance will be added
     * @param _value - the value to be transfered between addresses
     */
    function transfer(address _to, uint256 _value) external {
        Transfer(msg.sender, _to, _value);
        if(_isContract(_to)){
            ERC20ReceivingContract _contract  = ERC20ReceivingContract(_to);
            _contract.tokenFallback(msg.sender, _value, this);
        }
        _transfer(msg.sender, _to, _value);
    }

    /**
     * @dev ERC20 compatible transfer from function - implements the transfer from functionality. Performs various checks, uses SafeMath to avoid overflow.
     *basic
     * @param _from - an address from which the balance will be deduced
     * @param _to - an address to which the balance will be added
     * @param _value - the value to be transfered between addresses
     */
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool success) {
        require(_value <= _allowance[_from][msg.sender]);
        _allowance[_from][msg.sender] =  _allowance[_from][msg.sender].sub(_value);
        Transfer(msg.sender, _to, _value);
        if(_isContract(_to)){
             ERC20ReceivingContract _contract  = ERC20ReceivingContract(_to);
             _contract.tokenFallback(msg.sender, _value, this);
         }
        _transfer(_from, _to, _value);
        return true;
    }

    /**
     * @dev ERC20 compatible approveAndCall function - implements the apporval of the allowance and the corresponding call to contracts receiving the token.
     *
     * @param _spender - an address of a person that will be allowed to spend the money
     * @param _value - the value of how much a person is allowed to spend
     */
    function approve(address _spender, uint256 _value) external returns (bool success) {
        Approve(msg.sender, _spender, _value);
        _allowance[msg.sender][_spender] = _value;
        return true;
    }

    /**
     * @dev ERC20 compatible approveAndCall function - implements the apporval of the allowance and the corresponding call to contracts receiving the token.
     *
     * @param _spender - an address of a person that will be allowed to spend the money
     * @param _value - the value of how much a person is allowed to spend
     */
    function approveAndCall(address _spender, uint256 _value, bytes _extraData) external returns (bool success) {
        Approve(msg.sender, _spender, _value);
        tokenRecipient spender = tokenRecipient(_spender);
        _allowance[msg.sender][_spender] = _value;
        spender.receiveApproval(msg.sender, _value, this, _extraData);
        return true;
    }
}
