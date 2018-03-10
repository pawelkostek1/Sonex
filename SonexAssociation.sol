pragma solidity ^0.4.18;

/**
 * @dev SafeMath library - solves the overflow vulnerability problem.
 *          Taken from: 'https://github.com/OpenZeppelin/'.
 */
library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  * 
  * @param a -
  * @param b -
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
  * @param a -
  * @param b -
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
  * @param a -
  * @param b -
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  * 
  * @param a -
  * @param b -
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
 * @dev tokenRecipient contract interface to support ERC20 Standard, in particular the functionality of receiving approval for spending tokens.
 */
contract tokenRecipient {
    event receivedEther(address sender, uint amount);
    event receivedTokens(address _from, uint256 _value, address _token, bytes _extraData);
    
    function receiveApporval(address _from, uint256 _value, address _token, bytes _extraData) external {
        Token t = Token(_token);
        emit receivedTokens(_from, _value, _token, _extraData);
        require(t.transferFrom(_from, this, _value));
    }
    
    function () payable public {
        emit receivedEther(msg.sender, msg.value);
    }
}

/**
 * @dev token contract interface to support ERC20 Standard.
 */
contract Token {
    mapping (address => uint256) public balanceOf;
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success); //This only supports ERC20, what about ERC223?
}

/**
 * @dev SonexAssociation contract - implements the founders association (mostly based on reference implementation).
 */
contract SonexAssociation is owned, tokenRecipient {
    uint private minimumQuorum;
    uint private debatingPeriodInMinutes;
    Proposal[] private allProposals;
    uint private numProposals;
    Token private sharesTokenAddress;
    
    event ProposalAdded(uint proposalID, address recipient, uint amount, string description);
    event Voted(uint proposalID, bool position, address voter);
    event ProposalTallied(uint proposalID, uint result, uint quorum, bool active);
    event ChangeOfRules(uint newMinimumQuorum, uint newDebatingPeriodInMinutes, address newSharesTokenAddress);
    
    struct Proposal {
        address recipient;
        uint amount;
        string description;
        uint votingDeadline;
        bool executed;
        bool proposalPassed;
        uint numberOfVotes;
        bytes32 proposalHash;
        Vote[] votes;
        mapping (address => bool) voted;
    }
    
    struct Vote {
        bool inSupport;
        address voter;
    }
    
    /**
     * @dev Modifier that allows only shareholders to vote and create new proposals.
     */
    modifier onlyShareholders {
        require(sharesTokenAddress.balanceOf(msg.sender) > 0);
        _;
    }
    
    /**
     * @dev Constructor function - sets up basic parameters for running the proposals in the association.
     * 
     * @param sharesAddress - 
     * @param minimumSharesToPassAVote - 
     * @param minutesForDebate -
     */
    function Association(Token sharesAddress, uint minimumSharesToPassAVote, uint minutesForDebate) payable public { //Why this is payable?
        changeVotingRules(sharesAddress, minimumSharesToPassAVote, minutesForDebate);
    }
    
    /**
     * @dev Change voting rules - make so that proposals need to be discussed for at least 'minutesForDebate/60' hours
     *      and all voters combines must own more than 'minimumSharesToPassAVote' shares of token 'sharesAddress' to be executes.
     * 
     * @param sharesAddress - token address
     * @param minimumSharesToPassAVote - proposal can vote only if the sum of shares held by all voters excees this numberOfVotes
     * @param minutesForDebate - the minimum amount of delay between when a proposal is made and when it can be executed
     */
    
    function changeVotingRules(Token sharesAddress, uint minimumSharesToPassAVote, uint minutesForDebate) onlyOwner public {
        sharesTokenAddress = Token(sharesAddress);
        if (minimumSharesToPassAVote == 0) minimumSharesToPassAVote = 1;
        minimumQuorum = minimumSharesToPassAVote;
        debatingPeriodInMinutes = minutesForDebate;
        emit ChangeOfRules(minimumQuorum, debatingPeriodInMinutes, sharesTokenAddress);
    }
    
    /**
     * @dev Add Proposal - propose to send 'weiAmount / 1e18' ether to 'beneficiary' for 'jobDescription' . 'transactionBytecode ? Contains : Doeas not contain'.
     * 
     * @param beneficiary - who to send the ether to
     * @param weiAmount - amount of ether to send, in wei
     * @param jobDescription - description of jobDescription
     * @param transactionBytecode - bytecode of transaction
     */
    function newProposal(
        address beneficiary,
        uint weiAmount,
        string jobDescription,
        bytes transactionBytecode
    )
        onlyShareholders
        public
        returns (uint proposalID)
    {
        proposalID = allProposals.length++;
        Proposal storage p = allProposals[proposalID];
        p.recipient = beneficiary;
        p.amount = weiAmount;
        p.description = jobDescription;
        p.proposalHash = keccak256(beneficiary, weiAmount, transactionBytecode);
        p.votingDeadline = now + debatingPeriodInMinutes * 1 minutes;
        p.executed = false;
        p.proposalPassed = false;
        p.numberOfVotes = 0;
        emit ProposalAdded(proposalID, beneficiary, weiAmount, jobDescription);
        numProposals = proposalID + 1;
        
        return proposalID;
    }
    
    /**
     * @dev Add proposal in Ether - propose to send 'etherAmount' ether to 'benficiary' for 'jobDescription'. 'transactionBytecode ? Contains : Does not contain' code.
     *      This is a convinience function to use if the amount to be given is in round number of ether uints.
     * 
     * @param beneficiary - who to send the ether to
     * @param etherAmount - amount of ether to send
     * @param jobDescription - decription of job
     * @param transactionBytecode - bytecode of transaction
     */
    function newProposalInEther(
        address beneficiary,
        uint etherAmount,
        string jobDescription,
        bytes transactionBytecode
    )
        onlyShareholders
        public
        returns (uint proposalID)
    {
        return newProposal(beneficiary, etherAmount * 1 ether, jobDescription, transactionBytecode);
    }
    
    /**
     * @dev Check if a proposal code matches.
     * 
     * @param proposalNumber - ID number of the proposal to query
     * @param beneficiary - who to send the ether to
     * @param weiAmount - amount of ether to send
     * @param transactionBytecode - bytecode of transaction
     */
    function checkProposalCode(
        uint proposalNumber,
        address beneficiary,
        uint weiAmount,
        bytes transactionBytecode
    )
        public
        constant
        returns (bool codeChecksOut)
    {
        Proposal storage p = allProposals[proposalNumber];
        return p.proposalHash == keccak256(beneficiary, weiAmount, transactionBytecode);
    }
    
    /**
     * @dev Log a vote for a proposalNumber - vote 'supportsProposal? in support of: against' proposal #'proposalNumber'.
     * 
     * @param proposalNumber - number of proposal
     * @param supportsProposal - either in favor or against it
     */
    function vote(
        uint proposalNumber,
        bool supportsProposal
    )
        onlyShareholders
        public
        returns (uint voteID)
    {
        Proposal storage p = allProposals[proposalNumber];
        require(p.voted[msg.sender] != true);
        
        voteID = p.votes.length++;
        p.votes[voteID] = Vote({inSupport: supportsProposal, voter: msg.sender});
        p.voted[msg.sender] = true;
        p.numberOfVotes = voteID + 1;
        emit Voted(proposalNumber, supportsProposal, msg.sender);
        return voteID;
    }
    
    /**
     * @dev Finish vote - Count the votes proposal #'proposalNumber' and execute it if approved
     * 
     * @param proposalNumber - proposal number
     * @param transactionBytecode - option: if the transaction contained a bytecode, you need to send it
     */
    function executeProposal(uint proposalNumber, bytes transactionBytecode) public { //Do we want it to be public?
        Proposal storage p = allProposals[proposalNumber];
        
        require(now > p.votingDeadline
                && !p.executed
                && p.proposalHash == keccak256(p.recipient, p.amount, transactionBytecode));
        
        uint quorum = 0;
        uint yea = 0;
        uint nay = 0;
        
        for (uint i = 0; i < p.votes.length; ++i) {
            Vote storage v = p.votes[i];
            uint voteWeight = sharesTokenAddress.balanceOf(v.voter);
            quorum += voteWeight;
            if (v.inSupport) {
                yea += voteWeight;
            } else {
                nay += voteWeight;
            }
        }
        
        require(quorum >= minimumQuorum);
        
        if(yea > nay){
            p.executed = true;
            require(p.recipient.call.value(p.amount)(transactionBytecode));
            
            p.proposalPassed = true;
        } else {
            p.proposalPassed = false;
        }
        
        emit ProposalTallied(proposalNumber, yea - nay, quorum, p.proposalPassed);
    }
}


