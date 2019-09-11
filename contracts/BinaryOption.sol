pragma solidity 0.5.10;

import { usingBandProtocol } from "band-solidity/contracts/Band.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import { Ownable } from "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract BinaryOption is usingBandProtocol, Ownable {
  using SafeMath for uint256;

  enum Status { INVALID, OPENED, RESOLVED }

  struct Order {
    address payable owner;
    uint resolveTime;
    bool isCall;
    uint strikePrice;
    uint value;
    Status status;
  }

  mapping(uint => Order) public orders;
  mapping(address => bool) public hasOpenOrder;

  uint public orderCount = 0;

  event OrderPlaced(uint orderId, address indexed owner, uint resolveTime, bool isCall, uint strikePrice, uint value);
  event OrderResolved(uint orderId, bool isCorrect, uint settlementPrice);

  string constant QUERY_KEY = "BTC-USDT";
  uint public orderFee = 0.005 ether;
  uint public minDuration = 90 seconds;
  uint public maxOrderValue = 1 ether;

  function () external payable {}

  function buy(uint resolveTime, bool isCall, bytes calldata data) external payable {
    require(resolveTime.sub(now) >= minDuration, "RESOLVE_TIME_TOO_EARLY");
    require(msg.value >= orderFee, "ETH_INSUFFICIENT_FOR_ORDER_FEE");
    require(msg.value.sub(orderFee) <= maxOrderValue, "TOO_MUCH_BUY_AMOUNT");
    require(!hasOpenOrder[msg.sender], "ALREADY_HAS_OPEN_ORDER");

    uint currentPrice = reportToOracle(data);
    orderCount = orderCount + 1;
    uint stake = msg.value.sub(orderFee);
    orders[orderCount] = Order({
      owner: msg.sender,
      resolveTime: resolveTime,
      isCall: isCall,
      strikePrice: currentPrice,
      value: stake,
      status: Status.OPENED
    });

    hasOpenOrder[msg.sender] = true;

    emit OrderPlaced(orderCount, msg.sender, resolveTime, isCall, currentPrice, stake);
  }

  function resolve(uint orderId, bytes calldata data) external {
    uint currentPrice = reportToOracle(data);
    Order storage order = orders[orderId];
    require(order.status == Status.OPENED, "INVALID_ORDER_STATUS");
    require(order.resolveTime <= now, "TOO_EARLY_TO_RESOLVE");

    bool isCorrect;
    if (order.isCall) {
      isCorrect = currentPrice >= order.strikePrice;
    } else {
      isCorrect = currentPrice <= order.strikePrice;
    }

    order.status = Status.RESOLVED;
    if (isCorrect) {
      order.owner.transfer(order.value.mul(2));
    }

    hasOpenOrder[order.owner] = false;
    emit OrderResolved(orderId, isCorrect, currentPrice);
  }

  function reportToOracle(bytes memory data) internal returns (uint256) {
    address(FINANCIAL).call(data);
    return FINANCIAL.querySpotPriceWithExpiry(QUERY_KEY, 30 seconds);
  }

  // Admin function
  function _withdraw(uint value) external onlyOwner {
    msg.sender.transfer(value);
  }

  function _setOrderFee(uint _orderFee) external onlyOwner {
    orderFee = _orderFee;
  }

  function _setMinDuration(uint _minDuration) external onlyOwner {
    minDuration = _minDuration;
  }

  function _setMaxOrderValue(uint _maxOrderValue) external onlyOwner {
    maxOrderValue = _maxOrderValue;
  }
}
