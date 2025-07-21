// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "./SafeMath.sol";
import {HeartBankCoinInterface as Kiitos} from "./HeartBankCoinInterface.sol";
import {BoxOfficeMovie as Movie} from "./BoxOfficeMovie.sol";

/** @title Box Office factory that creates ERC20 movie tickets */
contract BoxOffice { 
    
    using SafeMath for uint;
    using SafeMath for uint8;
    
    address public admin;
    bool private emergency;
    
    Kiitos public kiitos;
    uint public heartbank;
    uint public charity;
    uint public listingFee;
    uint8 public withdrawFee;
    
    address[] public films;
    
    event FilmCreated(
        address movie,
        uint salesEndDate,
        uint availableTickets,
        uint price,
        uint ticketSupply, 
        string movieName, 
        string ticketSymbol,
        string logline,
        string poster,
        string trailer
    );
    
    event TicketsBought(
        address movie, 
        address buyer,
        uint price,
        uint quantity
    );
    
    event ExcessPaid(
        uint indexed date,
        address indexed movie,
        address indexed buyer,
        uint excess
    );
    
    event FundWithdrawn(
        uint indexed date,
        address indexed movie, 
        address recipient, 
        uint amount, 
        string expense
    );
    
    event CharityDonated(
        uint indexed date,
        address indexed recipient, 
        uint amount
    );
    
    event ExcessReturned(
        address recipient, 
        uint amount
    );
    
    event FeesUpdated(
        uint listingFee,
        uint withdrawFee
    );
    
    event FallbackTriggered(
        uint indexed date,
        address indexed sender,
        uint value
    );

    // Restricting Access
    
    modifier onlyAdmin {
        require(msg.sender == admin);
        _;
    }
    
    // Restructing access
    modifier onlyFilmmaker(address movie) {
        require(msg.sender == Movie(movie).filmmaker());
        _;
    }

    //fail early & fail aloud
    
    modifier chargeListingFee {
        require(kiitos.balanceOf(msg.sender) >= listingFee);
        kiitos.transferToAdmin(msg.sender, listingFee);
        _;
    }
    
    modifier chargeWithdrawFee(uint amount) {
        uint fee = withdrawFee.mul(amount).div(100);
        heartbank = heartbank.add(fee);
        charity = charity.add(fee);
        _;
    }
    
    //circuit breaker
    modifier stopInEmergency { 
        require(!emergency); 
        _; 
    }
    
    modifier onlyInEmergency { 
        require(emergency); 
        _;
    }
    
    /** @dev Instantiates a Box Office factory with initial values
     * @param token Contract address of the HeartBank coin called Kiitos
     */
    constructor(address token) public {
        kiitos = Kiitos(token);
        admin = msg.sender;
        emergency = false;
        
        heartbank = 0;
        charity = 0;
        listingFee = 2;
        withdrawFee = 1;
    }
    
    /** @dev Catches payment mistakes for admin to refund */
    function() public payable {
        emit FallbackTriggered(now, msg.sender, msg.value);
    }
    
    /** @dev Creates ERC20 token per movie 
     * @param salesEndDate End date of ticket sales
     * @param availableTickets Quantity of tickets available during sales period
     * @param price Price of each ticket
     * @param ticketSupply Total supply of tickets 
     * @param movieName Title of movie
     * @param ticketSymbol Token symbol of ticket
     * @param logline Logline of movie
     * @param poster IPFS hash of movie poster
     * @param trailer YouTube id of video trailer
     * @return Boolean for testing in solidity
     */
    function makeFilm(
        uint salesEndDate,
        uint availableTickets,
        uint price,
        uint ticketSupply, 
        string movieName, 
        string ticketSymbol,
        string logline,
        string poster,
        string trailer
    ) 
        public 
        stopInEmergency
        chargeListingFee
        returns (bool)
    {
        require(salesEndDate > now);
        require(availableTickets <= ticketSupply);
        require(price > 0);
        require(ticketSupply > 0);
        require(bytes(movieName).length > 0);
        require(bytes(ticketSymbol).length > 0);
        require(bytes(logline).length > 0);
        require(bytes(poster).length > 0);
        require(bytes(trailer).length > 0);
        
        Movie film = new Movie(msg.sender, salesEndDate, availableTickets, price, ticketSupply, movieName, ticketSymbol, logline, poster, trailer);
        films.push(film);
        
        emit FilmCreated(
            film,
            salesEndDate,
            availableTickets,
            price,
            ticketSupply,
            movieName,
            ticketSymbol,
            logline,
            poster,
            trailer    
        );
        return true;
    }
    
    /** @dev Purchases movie tickets
     * @param movie Address of movie token
     * @param quantity Number of tikcets to purchase
     * @return Boolean for testing in solidity 
     */
    function buyTickets(address movie, uint quantity) 
        public 
        payable
        stopInEmergency
        returns (bool)
    {
        require(quantity > 0);
        Movie film = Movie(movie);
        uint price = film.price();
        
        // only during sales period
        require(now < film.salesEndDate());
        
        // check available tickets
        require(quantity <= film.availableTickets());
        
        // check payment amount
        require(msg.value >= quantity.mul(price));
        
        // check excess payment
        uint excess = msg.value.sub(quantity.mul(price));
        if (excess > 0) emit ExcessPaid(now, movie, msg.sender, excess);
        
        film.buyTickets(msg.sender, quantity);
        emit TicketsBought(movie, msg.sender, price, quantity);
        return true;
    }
    
    /** @dev Withdraws from fund to pay expense
     * @param movie Address of movie token
     * @param recipient Address of recipient to be paid
     * @param amount Amount in wei to pay
     * @param expense Description of expense
     * @return Boolean for testing in solidity
     */
    function withdrawFund(address movie, address recipient, uint amount, string expense) 
        public 
        stopInEmergency
        onlyFilmmaker(movie)
        chargeWithdrawFee(amount)
        returns (bool)
    {
        require(recipient != address(0));
        require(amount > 0);
        require(bytes(expense).length > 0);
        Movie(movie).withdrawFund(amount.add(withdrawFee.mul(amount).div(100)));
        
        emit FundWithdrawn(now, movie, recipient, amount, expense);
        recipient.transfer(amount);
        return true;
    }
    
    /** @dev Returns array of movie token addresses
     * @return Movie token addresses
     */
    function getFilms() public view returns (address[]) {
        return films;
    }
    
    /** @dev Lets admin update listing fee and withdraw fee
     * @param listing Listing fee in Kiitos for creating a movie token
     * @param withdraw Fee as percentage of amount for withdrawing from fund
     * @return Boolean for testing in solidity
     */
    function updateFees(uint listing, uint8 withdraw)
        public
        stopInEmergency
        onlyAdmin
        returns (bool)
    {
        listingFee = listing;
        withdrawFee = withdraw;
        emit FeesUpdated(listingFee, withdrawFee);
        return true;
    }
    
    /** @dev Gives admin the ability to donate widthdraw fees to any charity
     * @param recipient Address of charity
     * @param amount Amount in wei to donate
     * @return Boolean for testing in solidity
     */
    function donateToCharity(address recipient, uint amount) public onlyAdmin returns (bool) {
        require(amount <= heartbank);
        heartbank = heartbank.sub(amount);
        emit CharityDonated(now, recipient, amount);
        recipient.transfer(amount);
        return true;
    }
    
    /** @dev Gives admin the ability to return payment in excess or mistake 
     * @param recipient Address of recipient to refund
     * @param amount Amount in wei to refund 
     * @return Boolean for testing in solidity
     */
    function returnExcessPayment(address recipient, uint amount) public onlyAdmin returns (bool) {
        require(amount <= address(this).balance);
        emit ExcessReturned(recipient, amount);
        recipient.transfer(amount);
        return true;
    }
    
    /** @dev Returns stats collected
     * @return listingFee The listing fee
     * @return withdrawFee The withdraw fee
     * @return heartbank Balance of withdraw fees withdrawn for charity 
     * @return charity Total withdraw fees collected
     */
    function getBoxOfficeStats() public view returns (uint, uint, uint, uint) {
        return (listingFee, withdrawFee, heartbank, charity); 
    }
    
    /** @dev Lets admin toggle the state of emergency 
     * @return Boolean for testing in solidity
     */
    function toggleEmergency() public onlyAdmin returns (bool) {
        emergency = !emergency;
        return true;
    }
    

    //mortal 
    /** @dev Lets admin destroy this contract and send excess balance to self
     */
    function shutDownBoxOffice() public onlyInEmergency onlyAdmin {
        selfdestruct(admin);
    }
    
    
}
// BoxOfficeMovie.sol
pragma solidity ^0.4.24;

import "./StandardToken.sol";

/** @title A Box Office Movie that inherits ERC20 */
contract BoxOfficeMovie is StandardToken {

    uint8 public constant decimals = 0;
    string public name;
    string public symbol;
    
    address public boxOffice;
    address public filmmaker;
    address[] public audienceMembers;
    
    uint public createdTime;
    uint public salesEndDate;
    uint public availableTickets;
    uint public price;
    uint public sales;
    uint public fund;
    string public logline; 
    string public poster; 
    string public trailer;
    
    event FilmUpdated(
        uint salesEndDate,
        uint availableTickets,
        uint price,
        string movieName,
        string ticketSymbol,
        string logline,
        string poster,
        string trailer
    );
    
    event TicketSpent(
        address indexed holder
    );
    
    modifier onlyBoxOffice {
        require(msg.sender == boxOffice);
        _;
    }
    
    modifier onlyFilmmaker {
        require(msg.sender == filmmaker);
        _;
    }
    
    modifier onlyTicketHolder {
        require(balanceOf(msg.sender) > 0);
        _;
    }

    /** @dev Instantiates a ERC20 token per movie 
     * @param _filmmaker Address of filmmaker 
     * @param _salesEndDate End date of ticket sales
     * @param _availableTickets Quantity of tickets available during sales period
     * @param _price Price of each ticket
     * @param _ticketSupply Total supply of tickets 
     * @param _movieName Title of movie
     * @param _ticketSymbol Token symbol of ticket
     * @param _logline Logline of movie
     * @param _poster IPFS hash of movie poster
     * @param _trailer YouTube id of video trailer
     */
    constructor(
        address _filmmaker,
        uint _salesEndDate,
        uint _availableTickets,
        uint _price,
        uint _ticketSupply, 
        string _movieName, 
        string _ticketSymbol,
        string _logline,
        string _poster,
        string _trailer
    ) 
        public 
    {
        boxOffice = msg.sender;
        filmmaker = _filmmaker;
        
        createdTime = now;
        sales = 0;
        fund = 0;
        
        salesEndDate = _salesEndDate;
        availableTickets = _availableTickets;
        price = _price;
        totalSupply_ = _ticketSupply;
        name = _movieName;
        symbol = _ticketSymbol;
        logline = _logline;
        poster = _poster;
        trailer = _trailer;
        
        balances[filmmaker] = totalSupply_;
        allowed[filmmaker][boxOffice] = totalSupply_;
    }
    
    /** @dev Updates movie and token details
     * @param _salesEndDate End date of ticket sales
     * @param _availableTickets Quantity of tickets available during sales period
     * @param _price Price of each ticket
     * @param _movieName Title of movie
     * @param _ticketSymbol Token symbol of ticket
     * @param _logline Logline of movie
     * @param _poster IPFS hash of movie poster
     * @param _trailer YouTube id of video trailer
     * @return Boolean for testing in solidity
     */
    function updateFilm(
        uint _salesEndDate,
        uint _availableTickets,
        uint _price,
        string _movieName,
        string _ticketSymbol,
        string _logline,
        string _poster,
        string _trailer
    ) 
        public 
        onlyFilmmaker
        returns (bool)
    {
        if (_salesEndDate > now) salesEndDate = _salesEndDate;
        if (_availableTickets <= totalSupply_) availableTickets = _availableTickets;
        if (_price > 0) price = _price;
        if (bytes(_movieName).length > 0) name = _movieName;
        if (bytes(_ticketSymbol).length > 0) symbol = _ticketSymbol;
        if (bytes(_logline).length > 0) logline = _logline;
        if (bytes(_poster).length > 0) poster = _poster;
        if (bytes(_trailer).length > 0) trailer = _trailer;
        
        emit FilmUpdated(
            salesEndDate,
            availableTickets,
            price,
            name,
            symbol,
            logline,
            poster,
            trailer    
        );
        return true;
    } 
    
    /** @dev Spends a movie ticket 
     * @return Boolean for testing in solidity
     */
    function spendTicket() 
        public 
        onlyTicketHolder 
        returns (bool)
    {
        require(balances[msg.sender] >= 1);
        balances[msg.sender] = balances[msg.sender].sub(1);
        balances[boxOffice] = balances[boxOffice].add(1);
        audienceMembers.push(msg.sender);

        emit TicketSpent(msg.sender);
        emit Transfer(msg.sender, boxOffice, 1);
        return true;
    }
    
    /** @dev Purchases movie tickets
     * @param buyer Address of buyer
     * @param quantity Number of tikcets to purchase
     * @return Boolean for testing in solidity 
     */
    function buyTickets(address buyer, uint quantity) external onlyBoxOffice returns (bool) {
        require(balances[filmmaker] >= quantity);
        balances[filmmaker] = balances[filmmaker].sub(quantity);
        balances[buyer] = balances[buyer].add(quantity);
        
        availableTickets = availableTickets.sub(quantity);
        sales = sales.add(quantity.mul(price));
        fund = fund.add(quantity.mul(price));
        
        emit Transfer(filmmaker, buyer, quantity);
        return true;
    }
    

    // pull over push payments
    /** @dev Withdraws from fund to pay expense
     * @param amount Amount in wei to pay
     * @return Boolean for testing in solidity
     */
    function withdrawFund(uint amount) external onlyBoxOffice returns (bool) {
        require(fund >= amount);
        fund = fund.sub(amount);
        return true;
    }
    
    /** @dev Retrieves movie and token details 
     * @return _filmmaker Address of filmmaker 
     * @return _salesEndDate End date of ticket sales
     * @return _availableTickets Quantity of tickets available during sales period
     * @return _price Price of each ticket
     * @return _movieName Title of movie
     * @return _ticketSymbol Token symbol of ticket
     * @return _logline Logline of movie
     * @return _poster IPFS hash of movie poster
     * @return _trailer YouTube id of video trailer
     */
    function getFilmSummary() public view returns (
        address _filmmaker,
        uint _createdTime,
        uint _salesEndDate,
        uint _availableTickets,
        uint _price,
        string _movieName,
        string _ticketSymbol,
        string _logline,
        string _poster,
        string _trailer
    ) {
        _filmmaker = filmmaker;
        _createdTime = createdTime;
        _salesEndDate = salesEndDate;
        _availableTickets = availableTickets;
        _price = price;
        _movieName = name;
        _ticketSymbol = symbol;
        _logline = logline;
        _poster = poster;
        _trailer = trailer;
    }
    
    /** @dev Retrieves movie statistics 
     * @return Total ticket sales
     * @return Balance from ticket sales and withdrawals
     * @return Total tickets spent
     * @return Total tickets available 
     * @return Total supply of tickets  
     */
    function getFilmStats() public view returns (uint, uint, uint, uint, uint) {
        return (sales, fund, balanceOf(boxOffice), balanceOf(filmmaker), totalSupply_);
    }
    
    /** @dev Retrieves audience members 
     * @return Addresses of audience members
     */
    function getAudienceMembers() public view returns (address[]) {
        return audienceMembers;
    }

}
HeartBankCoin.sol
pragma solidity ^0.4.24;

import "./StandardToken.sol";

contract HeartBankCoin is StandardToken {

    string public constant name = "HeartBank";
    string public constant symbol = "Kiitos";
    uint8 public constant decimals = 0;
    
    bool private airdrop;
    address private owner;
    mapping (address => bool) private admins;

    
    // Restricting Access
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }
    
    modifier onlyAdmin {
        require(admins[msg.sender]);
        _;
    }
    
    modifier onlyDuringAirDrop {
        require(airdrop);
        _;
    }

    constructor() public {
        airdrop = true;
        owner = msg.sender;
        totalSupply_ = 1 ether;
        balances[owner] = totalSupply_;
    }
    
    function addAdmin(address admin) public onlyOwner returns (bool) {
        admins[admin] = true;
        return true;
    }
    
    function transferToAdmin(address holder, uint kiitos) external onlyAdmin returns (bool) {
        require(balances[holder] >= kiitos);
        balances[holder] = balances[holder].sub(kiitos);
        balances[msg.sender] = balances[msg.sender].add(kiitos);
        emit Transfer(holder, msg.sender, kiitos);
        return true;
    }
    
    function toggleAirDrop() public onlyOwner returns (bool) {
        airdrop = !airdrop;
        return true;
    }
    
    function airDrop() public onlyDuringAirDrop returns (bool) {
        balances[owner] = balances[owner].sub(100);
        balances[msg.sender] = balances[msg.sender].add(100);
        emit Transfer(owner, msg.sender, 100);
        return true;
    }

}
// HeartBankCoinInterface.sol
pragma solidity ^0.4.24;

interface HeartBankCoinInterface {

    function transferToAdmin(address holder, uint kiitos) external returns (bool);
    
    function balanceOf(address _who) external view returns (uint256);
    
}
Oracle.sol
pragma solidity ^0.4.24;

import {OracleLibrary as Library} from "./OracleLibrary.sol";

contract Oracle {
    
    using Library for address;
    
    address public owner;
    address public oracle;
    
    event GetPrice();
    event PriceUpdated(uint price);
    
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }
    
    constructor(address oracleStorage) public {
        owner = msg.sender;
        oracle = oracleStorage;
    }
    
    function updatePrice() public onlyOwner returns (bool) {
        emit GetPrice();
        return true;
    }
    
    function setPrice(uint price) public onlyOwner returns (bool) {
        oracle.usdPriceOfEth(price);
        emit PriceUpdated(price);
        return true;
    }
    
    function usdPriceOfEth() public view returns (uint) {
        return oracle.usdPriceOfEth();
    }
    
    function convertToUsd(uint amountInWei) public view returns (uint) {
        return usdPriceOfEth() * amountInWei / 1 ether;
    }
    
    function kill() public onlyOwner {
        selfdestruct(owner);
    }
    
}
// OracleLibrary.sol
pragma solidity ^0.4.24;

import {OracleStorage as Storage} from "./OracleStorage.sol";

library OracleLibrary {
    
    function usdPriceOfEth(address oracle) public view returns (uint) {
        return Storage(oracle).usdPriceOfEth();
    }
    
    function usdPriceOfEth(address oracle, uint price) public returns (bool) {
        return Storage(oracle).usdPriceOfEth(price);
    }
    
}
// OracleRegistry.sol
pragma solidity ^0.4.24;

contract OracleRegistry {
    
    address public owner;
    address public currentOracle;
    address[] public previousOracles;
    
    event OracleUpgraded(address newOracle);
    
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    constructor(address oracle) public {
        owner = msg.sender;
        currentOracle = oracle;
    }

    function upgradeOracle(address newOracle) public onlyOwner returns (bool) {
        if(newOracle != currentOracle) {
            previousOracles.push(currentOracle);
            currentOracle = newOracle;
            emit OracleUpgraded(newOracle);
            return true;
        }
        return false;
    }
    
    function kill() public onlyOwner {
        selfdestruct(owner);
    }
    
}
// OracleStorage.sol
pragma solidity ^0.4.24;

contract OracleStorage {
    
    address public owner;
    mapping (address => bool) private admins;
    
    uint public usdPriceOfEth;
    
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }
    
    modifier onlyAdmin {
        require(admins[msg.sender]);
        _;
    }
    
    constructor() public {
        owner = msg.sender;
        usdPriceOfEth = 1;
    }
    
    function addAdmin(address admin) public onlyOwner returns (bool) {
        admins[admin] = true;
        return true;
    }
    
    function usdPriceOfEth(uint price) public onlyAdmin returns (bool) {
        usdPriceOfEth = price;
        return true;
    }
    
    function kill() public onlyOwner {
        selfdestruct(owner);
    }
    
}
// SafeMath.sol
pragma solidity ^0.4.24;


/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  */
  function mul(uint256 _a, uint256 _b) internal pure returns (uint256 c) {
    // Gas optimization: this is cheaper than asserting 'a' not being zero, but the
    // benefit is lost if 'b' is also tested.
    // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
    if (_a == 0) {
      return 0;
    }

    c = _a * _b;
    assert(c / _a == _b);
    return c;
  }

  /**
  * @dev Integer division of two numbers, truncating the quotient.
  */
  function div(uint256 _a, uint256 _b) internal pure returns (uint256) {
    // assert(_b > 0); // Solidity automatically throws when dividing by 0
    // uint256 c = _a / _b;
    // assert(_a == _b * c + _a % _b); // There is no case in which this doesn't hold
    return _a / _b;
  }

  /**
  * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 _a, uint256 _b) internal pure returns (uint256) {
    assert(_b <= _a);
    return _a - _b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint256 _a, uint256 _b) internal pure returns (uint256 c) {
    c = _a + _b;
    assert(c >= _a);
    return c;
  }
}
// StandardToken.sol
pragma solidity ^0.4.24;

import "./SafeMath.sol";


/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 {
  function totalSupply() public view returns (uint256);

  function balanceOf(address _who) public view returns (uint256);

  function allowance(address _owner, address _spender)
    public view returns (uint256);

  function transfer(address _to, uint256 _value) public returns (bool);

  function approve(address _spender, uint256 _value)
    public returns (bool);

  function transferFrom(address _from, address _to, uint256 _value)
    public returns (bool);

  event Transfer(
    address indexed from,
    address indexed to,
    uint256 value
  );

  event Approval(
    address indexed owner,
    address indexed spender,
    uint256 value
  );
}



/**
 * @title Standard ERC20 token
 *
 * @dev Implementation of the basic standard token.
 * https://github.com/ethereum/EIPs/issues/20
 * Based on code by FirstBlood: https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
 */
contract StandardToken is ERC20 {
  using SafeMath for uint256;

  mapping(address => uint256) balances;

  mapping (address => mapping (address => uint256)) internal allowed;

  uint256 totalSupply_;

  /**
  * @dev Total number of tokens in existence
  */
  function totalSupply() public view returns (uint256) {
    return totalSupply_;
  }

  /**
  * @dev Gets the balance of the specified address.
  * @param _owner The address to query the the balance of.
  * @return An uint256 representing the amount owned by the passed address.
  */
  function balanceOf(address _owner) public view returns (uint256) {
    return balances[_owner];
  }

  /**
   * @dev Function to check the amount of tokens that an owner allowed to a spender.
   * @param _owner address The address which owns the funds.
   * @param _spender address The address which will spend the funds.
   * @return A uint256 specifying the amount of tokens still available for the spender.
   */
  function allowance(
    address _owner,
    address _spender
   )
    public
    view
    returns (uint256)
  {
    return allowed[_owner][_spender];
  }

  /**
  * @dev Transfer token for a specified address
  * @param _to The address to transfer to.
  * @param _value The amount to be transferred.
  */
  function transfer(address _to, uint256 _value) public returns (bool) {
    require(_value <= balances[msg.sender]);
    require(_to != address(0));

    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
    emit Transfer(msg.sender, _to, _value);
    return true;
  }

  /**
   * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
   * Beware that changing an allowance with this method brings the risk that someone may use both the old
   * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
   * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   * @param _spender The address which will spend the funds.
   * @param _value The amount of tokens to be spent.
   */
  function approve(address _spender, uint256 _value) public returns (bool) {
    allowed[msg.sender][_spender] = _value;
    emit Approval(msg.sender, _spender, _value);
    return true;
  }

  /**
   * @dev Transfer tokens from one address to another
   * @param _from address The address which you want to send tokens from
   * @param _to address The address which you want to transfer to
   * @param _value uint256 the amount of tokens to be transferred
   */
  function transferFrom(
    address _from,
    address _to,
    uint256 _value
  )
    public
    returns (bool)
  {
    require(_value <= balances[_from]);
    require(_value <= allowed[_from][msg.sender]);
    require(_to != address(0));

    balances[_from] = balances[_from].sub(_value);
    balances[_to] = balances[_to].add(_value);
    allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
    emit Transfer(_from, _to, _value);
    return true;
  }

  /**
   * @dev Increase the amount of tokens that an owner allowed to a spender.
   * approve should be called when allowed[_spender] == 0. To increment
   * allowed value is better to use this function to avoid 2 calls (and wait until
   * the first transaction is mined)
   * From MonolithDAO Token.sol
   * @param _spender The address which will spend the funds.
   * @param _addedValue The amount of tokens to increase the allowance by.
   */
  function increaseApproval(
    address _spender,
    uint256 _addedValue
  )
    public
    returns (bool)
  {
    allowed[msg.sender][_spender] = (
      allowed[msg.sender][_spender].add(_addedValue));
    emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
    return true;
  }

  /**
   * @dev Decrease the amount of tokens that an owner allowed to a spender.
   * approve should be called when allowed[_spender] == 0. To decrement
   * allowed value is better to use this function to avoid 2 calls (and wait until
   * the first transaction is mined)
   * From MonolithDAO Token.sol
   * @param _spender The address which will spend the funds.
   * @param _subtractedValue The amount of tokens to decrease the allowance by.
   */
  function decreaseApproval(
    address _spender,
    uint256 _subtractedValue
  )
    public
    returns (bool)
  {
    uint256 oldValue = allowed[msg.sender][_spender];
    if (_subtractedValue >= oldValue) {
      allowed[msg.sender][_spender] = 0;
    } else {
      allowed[msg.sender][_spender] = oldValue.sub(_subtractedValue);
    }
    emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
    return true;
  }

}

