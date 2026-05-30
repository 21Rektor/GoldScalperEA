//+------------------------------------------------------------------+
//|                                              GoldScalper.mq4     |
//|                          MT4 Gold (XAUUSD) Scalping Expert Advisor|
//|                                                                    |
//|  Strategy:                                                         |
//|    - EMA crossover (fast 8 / slow 21) for trend direction          |
//|    - RSI filter to avoid chasing momentum extremes                 |
//|    - ATR-based dynamic Stop Loss & Take Profit                     |
//|    - Spread guard so we never trade in wide-spread conditions       |
//|    - Session filter (London + NY overlap only)                     |
//+------------------------------------------------------------------+
#property copyright "GoldScalperEA"
#property version   "1.00"
#property strict

//--- Input parameters
input double RiskPercent      = 1.0;   // Risk per trade (% of balance)
input int    FastEMA          = 8;     // Fast EMA period
input int    SlowEMA          = 21;    // Slow EMA period
input int    RSI_Period       = 14;    // RSI period
input double RSI_OB           = 70.0;  // RSI overbought level
input double RSI_OS           = 30.0;  // RSI oversold level
input double ATR_Multiplier   = 1.5;   // ATR multiplier for SL
input double RR_Ratio         = 2.0;   // Risk:Reward ratio for TP
input int    MaxSpreadPoints  = 30;    // Max allowed spread (points)
input int    SessionStartHour = 7;     // Session open hour (server time)
input int    SessionEndHour   = 20;    // Session close hour (server time)
input int    MagicNumber      = 202401;// Unique EA identifier
input bool   UseTrailingStop  = true;  // Enable trailing stop
input double TrailATR         = 1.0;   // Trailing stop distance (ATR units)

//--- Global variables
double FastEMAVal, SlowEMAVal, PrevFastEMA, PrevSlowEMA;
double RSIVal, ATRVal;
int    Slippage = 3;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("GoldScalper EA initialised on ", Symbol(), " | TF: ", Period());
   if(Symbol() != "XAUUSD" && Symbol() != "GOLD")
      Print("WARNING: This EA is optimised for XAUUSD. Current symbol: ", Symbol());
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Only act on a new bar to avoid re-entries within the same candle
   static datetime lastBarTime = 0;
   if(Time[0] == lastBarTime) return;
   lastBarTime = Time[0];

   // --- Session filter ---
   int hour = TimeHour(TimeCurrent());
   if(hour < SessionStartHour || hour >= SessionEndHour) return;

   // --- Spread filter ---
   double spread = MarketInfo(Symbol(), MODE_SPREAD);
   if(spread > MaxSpreadPoints)
     {
      Print("Spread too wide (", spread, " pts) — skipping bar.");
      return;
     }

   // --- Indicator values (shift 1 = last closed bar) ---
   FastEMAVal   = iMA(NULL, 0, FastEMA,  0, MODE_EMA, PRICE_CLOSE, 1);
   SlowEMAVal   = iMA(NULL, 0, SlowEMA,  0, MODE_EMA, PRICE_CLOSE, 1);
   PrevFastEMA  = iMA(NULL, 0, FastEMA,  0, MODE_EMA, PRICE_CLOSE, 2);
   PrevSlowEMA  = iMA(NULL, 0, SlowEMA,  0, MODE_EMA, PRICE_CLOSE, 2);
   RSIVal       = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   ATRVal       = iATR(NULL, 0, 14, 1);

   // --- Crossover signals ---
   bool bullCross = (PrevFastEMA <= PrevSlowEMA) && (FastEMAVal > SlowEMAVal);
   bool bearCross = (PrevFastEMA >= PrevSlowEMA) && (FastEMAVal < SlowEMAVal);

   // --- RSI filter ---
   bool rsiBuyOK  = (RSIVal > RSI_OS && RSIVal < RSI_OB); // not overbought
   bool rsiSellOK = (RSIVal < RSI_OB && RSIVal > RSI_OS); // not oversold

   // --- Trailing stop management ---
   if(UseTrailingStop) ManageTrailingStop();

   // --- No trade if already in position ---
   if(TotalOpenOrders() > 0) return;

   // --- Entry logic ---
   if(bullCross && rsiBuyOK)
      OpenTrade(OP_BUY);
   else if(bearCross && rsiSellOK)
      OpenTrade(OP_SELL);
  }

//+------------------------------------------------------------------+
//| Open a trade with ATR-based SL / TP                              |
//+------------------------------------------------------------------+
void OpenTrade(int orderType)
  {
   double sl, tp, price;
   double slDistance = ATRVal * ATR_Multiplier;
   double tpDistance = slDistance * RR_Ratio;
   double lotSize    = CalculateLotSize(slDistance);

   if(lotSize <= 0) return;

   if(orderType == OP_BUY)
     {
      price = Ask;
      sl    = price - slDistance;
      tp    = price + tpDistance;
     }
   else
     {
      price = Bid;
      sl    = price + slDistance;
      tp    = price - tpDistance;
     }

   int ticket = OrderSend(
      Symbol(), orderType, lotSize, price,
      Slippage, sl, tp,
      "GoldScalper", MagicNumber, 0,
      orderType == OP_BUY ? clrDodgerBlue : clrOrangeRed
   );

   if(ticket < 0)
      Print("OrderSend failed — Error: ", GetLastError());
   else
      Print("Trade opened | Type: ", (orderType == OP_BUY ? "BUY" : "SELL"),
            " | Lots: ", lotSize,
            " | SL: ", sl, " | TP: ", tp);
  }

//+------------------------------------------------------------------+
//| Calculate lot size based on risk % and SL distance               |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
  {
   double tickValue  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize   = MarketInfo(Symbol(), MODE_TICKSIZE);
   double minLot     = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot     = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep    = MarketInfo(Symbol(), MODE_LOTSTEP);
   double balance    = AccountBalance();
   double riskAmount = balance * (RiskPercent / 100.0);

   if(tickSize == 0 || tickValue == 0) return 0;

   double slPoints = slDistance / tickSize;
   double lots     = riskAmount / (slPoints * tickValue);

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return lots;
  }

//+------------------------------------------------------------------+
//| Move SL to lock in profit as price moves in our favour           |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   double trailDistance = ATRVal * TrailATR;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;

      double newSL = 0;

      if(OrderType() == OP_BUY)
        {
         newSL = Bid - trailDistance;
         if(newSL > OrderStopLoss() + Point)
            OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrDodgerBlue);
        }
      else if(OrderType() == OP_SELL)
        {
         newSL = Ask + trailDistance;
         if(newSL < OrderStopLoss() - Point || OrderStopLoss() == 0)
            OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrOrangeRed);
        }
     }
  }

//+------------------------------------------------------------------+
//| Count open orders for this EA                                    |
//+------------------------------------------------------------------+
int TotalOpenOrders()
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("GoldScalper EA removed. Reason code: ", reason);
  }
//+------------------------------------------------------------------+
