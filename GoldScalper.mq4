//+------------------------------------------------------------------+
//|                                              GoldScalper.mq4     |
//|                 MT4 Gold (XAUUSD) Scalping EA  — Version 2.0     |
//|                                                                    |
//|  Strategy: Multi-Confirmation Mean Reversion + Trend Filter       |
//|  Timeframe: M5 entries / H1 trend direction                       |
//|                                                                    |
//|  Entry checklist (ALL must pass):                                  |
//|    1. H1 trend direction  — price above/below H1 EMA 50           |
//|    2. Bollinger Band touch — price at outer band on M5            |
//|    3. RSI extreme         — oversold < 35 / overbought > 65       |
//|    4. Candle confirmation — last M5 bar closes in entry direction  |
//|    5. Spread guard        — spread must be within limit            |
//|    6. Session filter      — London / NY hours only                 |
//|                                                                    |
//|  Exit logic:                                                       |
//|    - TP1 (50% position): 1.0 × ATR  → SL moves to breakeven      |
//|    - TP2 (50% position): 2.0 × ATR                                |
//|    - SL : 1.0 × ATR                                               |
//|    - Trailing stop on remaining position after TP1 hit            |
//+------------------------------------------------------------------+
#property copyright "GoldScalperEA v2.0"
#property version   "2.00"
#property strict

//--- Input parameters
input double RiskPercent      = 1.0;    // Risk per trade (% of balance)
input int    BB_Period        = 20;     // Bollinger Bands period
input double BB_Deviation     = 2.0;   // Bollinger Bands deviation
input int    RSI_Period       = 14;    // RSI period
input double RSI_OB           = 65.0;  // RSI overbought (sell signal)
input double RSI_OS           = 35.0;  // RSI oversold  (buy signal)
input int    H1_EMA_Period    = 50;    // H1 trend EMA period
input double ATR_SL           = 1.0;   // SL distance (ATR units)
input double ATR_TP1          = 1.0;   // TP1 distance (ATR units) — closes 50%
input double ATR_TP2          = 2.0;   // TP2 distance (ATR units) — closes rest
input int    MaxSpreadPoints  = 25;    // Max allowed spread (points)
input int    SessionStartHour = 7;     // Session open  (server time)
input int    SessionEndHour   = 20;    // Session close (server time)
input int    MaxTradesPerDay  = 3;     // Max new trades per day
input int    MinBarsBetween   = 3;     // Min M5 bars between trades
input int    MagicNumber      = 202402;// EA identifier

//--- Global state
int    lastTradeBar   = -99;
int    tradesToday    = 0;
datetime lastTradeDay = 0;
int    Slippage       = 3;

//+------------------------------------------------------------------+
//| Initialisation                                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("GoldScalper v2.0 initialised on ", Symbol(), " TF:", Period());
   if(Symbol() != "XAUUSD" && Symbol() != "GOLD")
      Print("WARNING: Optimised for XAUUSD. Current: ", Symbol());
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Main tick                                                         |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Act only on new M5 bar
   static datetime lastBar = 0;
   if(Time[0] == lastBar) return;
   lastBar = Time[0];

   // Reset daily trade counter
   if(TimeDay(TimeCurrent()) != TimeDay(lastTradeDay))
     {
      tradesToday  = 0;
      lastTradeDay = TimeCurrent();
     }

   // Manage open trades (breakeven + trail)
   ManageOpenTrades();

   // Session filter
   int hour = TimeHour(TimeCurrent());
   if(hour < SessionStartHour || hour >= SessionEndHour) return;

   // Daily trade limit
   if(tradesToday >= MaxTradesPerDay) return;

   // Spread filter
   double spread = MarketInfo(Symbol(), MODE_SPREAD);
   if(spread > MaxSpreadPoints) return;

   // Cooldown between trades
   if(Bars - lastTradeBar < MinBarsBetween) return;

   // No stacking — one position at a time
   if(TotalOpenOrders() > 0) return;

   // Gather indicators
   double atr     = iATR(NULL, 0, 14, 1);
   double rsi     = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);

   double bbUpper = iBands(NULL, 0, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double bbLower = iBands(NULL, 0, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double bbMid   = iBands(NULL, 0, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_MAIN,  1);

   // H1 trend: price vs EMA50 on H1
   double h1ema   = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1close = iClose(Symbol(), PERIOD_H1, 0);

   bool h1Bullish = (h1close > h1ema);
   bool h1Bearish = (h1close < h1ema);

   // Candle direction confirmation
   double candleOpen  = Open[1];
   double candleClose = Close[1];
   bool bullCandle = (candleClose > candleOpen);
   bool bearCandle = (candleClose < candleOpen);

   // Price touching bands
   bool atLowerBand = (Low[1] <= bbLower);
   bool atUpperBand = (High[1] >= bbUpper);

   //--- BUY setup: all 4 conditions must align ---
   if(h1Bullish && atLowerBand && rsi < RSI_OS && bullCandle)
     {
      OpenTrade(OP_BUY, atr);
      return;
     }

   //--- SELL setup: all 4 conditions must align ---
   if(h1Bearish && atUpperBand && rsi > RSI_OB && bearCandle)
     {
      OpenTrade(OP_SELL, atr);
      return;
     }
  }

//+------------------------------------------------------------------+
//| Open split position: 2 orders (TP1 + TP2)                        |
//+------------------------------------------------------------------+
void OpenTrade(int orderType, double atr)
  {
   double slDist  = atr * ATR_SL;
   double tp1Dist = atr * ATR_TP1;
   double tp2Dist = atr * ATR_TP2;
   double halfLot = CalculateLotSize(slDist);
   if(halfLot <= 0) return;

   double price, sl, tp1, tp2;
   if(orderType == OP_BUY)
     {
      price = Ask;
      sl    = price - slDist;
      tp1   = price + tp1Dist;
      tp2   = price + tp2Dist;
     }
   else
     {
      price = Bid;
      sl    = price + slDist;
      tp1   = price - tp1Dist;
      tp2   = price - tp2Dist;
     }

   color clr = (orderType == OP_BUY) ? clrDodgerBlue : clrOrangeRed;

   // Order 1 — closes at TP1
   int t1 = OrderSend(Symbol(), orderType, halfLot, price, Slippage, sl, tp1,
                      "GS-TP1", MagicNumber, 0, clr);
   // Order 2 — closes at TP2
   int t2 = OrderSend(Symbol(), orderType, halfLot, price, Slippage, sl, tp2,
                      "GS-TP2", MagicNumber, 0, clr);

   if(t1 < 0 || t2 < 0)
      Print("OrderSend error: ", GetLastError());
   else
     {
      Print("Trade opened | ", (orderType==OP_BUY?"BUY":"SELL"),
            " | Lot:", halfLot, "x2 | SL:", sl, " TP1:", tp1, " TP2:", tp2);
      lastTradeBar = Bars;
      tradesToday++;
     }
  }

//+------------------------------------------------------------------+
//| Move SL to breakeven once TP1 order is closed; trail TP2 order   |
//+------------------------------------------------------------------+
void ManageOpenTrades()
  {
   bool tp1Hit = true;
   bool hasTP2 = false;

   // Check if any TP1 order is still open
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(StringFind(OrderComment(), "GS-TP1") >= 0) { tp1Hit = false; }
      if(StringFind(OrderComment(), "GS-TP2") >= 0) { hasTP2 = true;  }
     }

   // TP1 has been hit — move TP2 SL to breakeven + trail
   if(tp1Hit && hasTP2)
     {
      double atr = iATR(NULL, 0, 14, 1);
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
         if(StringFind(OrderComment(), "GS-TP2") < 0) continue;

         double openPrice  = OrderOpenPrice();
         double currentSL  = OrderStopLoss();
         double trailDist  = atr * 0.8;
         double newSL;

         if(OrderType() == OP_BUY)
           {
            newSL = MathMax(openPrice, Bid - trailDist); // at least breakeven
            if(newSL > currentSL + Point)
               OrderModify(OrderTicket(), openPrice, newSL, OrderTakeProfit(), 0, clrGreen);
           }
         else
           {
            newSL = MathMin(openPrice, Ask + trailDist);
            if(newSL < currentSL - Point || currentSL == 0)
               OrderModify(OrderTicket(), openPrice, newSL, OrderTakeProfit(), 0, clrGreen);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Lot size from risk % and SL distance                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
  {
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   double minLot    = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot    = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep   = MarketInfo(Symbol(), MODE_LOTSTEP);
   double balance   = AccountBalance();
   double riskAmt   = balance * (RiskPercent / 100.0);

   if(tickSize == 0 || tickValue == 0) return 0;

   double slPoints = slDistance / tickSize;
   double lots     = riskAmt / (slPoints * tickValue);
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
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
//| Deinitialisation                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("GoldScalper v2.0 removed. Reason: ", reason);
  }
//+------------------------------------------------------------------+
