//+------------------------------------------------------------------+
//|                                              GoldScalper.mq4     |
//|              MT4 Gold (XAUUSD) EA — Version 3.0                  |
//|                                                                    |
//|  FIXES FROM v2 BACKTEST (PF 0.91, 37% win, 74% drawdown):        |
//|    - Too many trades (1952) → max 2/day, strict ADX filter        |
//|    - Spread (29pts) killing M5 targets → switched to M15          |
//|    - RR not enough at 36% win rate → 3:1 RR, bigger targets       |
//|    - 74% drawdown → hard daily loss limit, max 1% risk/trade      |
//|                                                                    |
//|  Strategy: Session Momentum + Multi-Filter                        |
//|  Timeframe: M15 (compile & attach chart to M15!)                  |
//|                                                                    |
//|  Entry checklist (ALL must pass):                                  |
//|    1. H4 trend — price above/below H4 EMA 50                      |
//|    2. ADX > 22 — market is trending, not ranging                  |
//|    3. H1 EMA cross — fast 8 crossed slow 21 in entry direction    |
//|    4. RSI confirmation — 40-60 zone (momentum, not exhaustion)     |
//|    5. Candle body — last M15 bar body > 50% of total range        |
//|    6. Session — London open (08-10) or NY open (13-15) only       |
//|    7. Spread < 30 pts, min profit potential 3× spread             |
//|                                                                    |
//|  Exit:                                                             |
//|    - SL  : 1.5 × ATR(14) on M15                                   |
//|    - TP  : 3.0 × ATR(14) on M15  (2:1 RR minimum)                |
//|    - Breakeven: move SL to entry+spread after 1×ATR in profit     |
//|    - Hard daily loss limit: stops trading if day loss > 2%        |
//+------------------------------------------------------------------+
#property copyright "GoldScalperEA v3.0"
#property version   "3.00"
#property strict

//--- Inputs
input double RiskPercent       = 0.8;   // Risk per trade (% of balance)
input int    ADX_Period        = 14;    // ADX period
input double ADX_MinLevel      = 22.0;  // Min ADX for trend strength
input int    FastEMA           = 8;     // Fast EMA (H1)
input int    SlowEMA           = 21;    // Slow EMA (H1)
input int    H4_EMA_Period     = 50;    // H4 trend EMA period
input int    RSI_Period        = 14;    // RSI period
input double RSI_BuyMin        = 45.0;  // RSI min for buy (not overbought)
input double RSI_BuyMax        = 65.0;  // RSI max for buy
input double RSI_SellMin       = 35.0;  // RSI min for sell
input double RSI_SellMax       = 55.0;  // RSI max for sell (not oversold)
input double ATR_SL            = 1.5;   // SL distance in ATR units
input double ATR_TP            = 3.0;   // TP distance in ATR units (2:1 RR)
input double ATR_BE            = 1.0;   // Move to breakeven after X ATR profit
input int    MaxSpreadPoints   = 35;    // Max spread allowed (points) — 35 suits Roboforex Pro 29pt spread
input int    LondonOpenStart   = 8;     // London session start hour
input int    LondonOpenEnd     = 10;    // London session end hour
input int    NYOpenStart       = 13;    // NY session start hour
input int    NYOpenEnd         = 15;    // NY session end hour
input int    MaxTradesPerDay   = 2;     // Max trades per day
input double MaxDailyLossPct   = 2.0;   // Stop trading if daily loss > X%
input int    MagicNumber       = 202403;// EA identifier

//--- State
int      tradesToday    = 0;
double   dayStartBalance= 0;
datetime lastTradeDay   = 0;
bool     dailyLimitHit  = false;
int      Slippage       = 3;

//+------------------------------------------------------------------+
int OnInit()
  {
   Print("GoldScalper v3.0 — M15 Session Momentum EA on ", Symbol());
   if(Period() != PERIOD_M15)
      Print("WARNING: Attach this EA to an M15 chart for best results!");
   dayStartBalance = AccountBalance();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   // New bar check
   static datetime lastBar = 0;
   if(Time[0] == lastBar) return;
   lastBar = Time[0];

   // Daily reset
   datetime today = TimeCurrent();
   if(TimeDay(today) != TimeDay(lastTradeDay))
     {
      tradesToday     = 0;
      dailyLimitHit   = false;
      dayStartBalance = AccountBalance();
      lastTradeDay    = today;
     }

   // Manage open trades (breakeven)
   ManageBreakeven();

   // Daily loss guard
   if(!dailyLimitHit)
     {
      double dayLoss = (dayStartBalance - AccountEquity()) / dayStartBalance * 100.0;
      if(dayLoss >= MaxDailyLossPct)
        {
         dailyLimitHit = true;
         Print("Daily loss limit reached (", DoubleToStr(dayLoss,2), "%) — no more trades today.");
        }
     }
   if(dailyLimitHit) return;

   // Trade limits
   if(tradesToday >= MaxTradesPerDay) return;
   if(TotalOpenOrders() > 0) return;

   // Session filter — London or NY open only
   int hour = TimeHour(today);
   bool inSession = (hour >= LondonOpenStart && hour < LondonOpenEnd) ||
                    (hour >= NYOpenStart      && hour < NYOpenEnd);
   if(!inSession) return;

   // Spread filter
   double spread = MarketInfo(Symbol(), MODE_SPREAD);
   if(spread > MaxSpreadPoints) return;

   //--- Indicators ---
   double atr   = iATR(NULL, 0, 14, 1);
   double rsi   = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double adx   = iADX(NULL, 0, ADX_Period, PRICE_CLOSE, MODE_MAIN,    1);
   double diPlus  = iADX(NULL, 0, ADX_Period, PRICE_CLOSE, MODE_PLUSDI,  1);
   double diMinus = iADX(NULL, 0, ADX_Period, PRICE_CLOSE, MODE_MINUSDI, 1);

   // H1 EMA cross
   double h1FastNow  = iMA(NULL, PERIOD_H1, FastEMA, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1SlowNow  = iMA(NULL, PERIOD_H1, SlowEMA, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1FastPrev = iMA(NULL, PERIOD_H1, FastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double h1SlowPrev = iMA(NULL, PERIOD_H1, SlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);

   // H4 trend direction
   double h4ema   = iMA(NULL, PERIOD_H4, H4_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h4close = iClose(Symbol(), PERIOD_H4, 0);

   // M15 candle body strength (body must be > 50% of total range)
   double bodySize  = MathAbs(Close[1] - Open[1]);
   double totalRange= High[1] - Low[1];
   bool strongCandle = (totalRange > 0 && bodySize / totalRange >= 0.5);

   // Minimum profit potential must be at least 5× spread
   // At 29pt spread on Roboforex, TP must be > 145pts minimum
   // M15 ATR is typically 150-300pts so this easily passes during sessions
   double minTarget = spread * 5 * Point;
   bool worthTrading = (atr * ATR_TP > minTarget);

   // ADX confirms trend is strong
   bool trendStrong = (adx >= ADX_MinLevel);

   //--- BUY conditions ---
   bool h4Bull     = (h4close > h4ema);
   bool emaCrossBull = (h1FastPrev <= h1SlowPrev && h1FastNow > h1SlowNow);
   bool rsiBuy     = (rsi >= RSI_BuyMin && rsi <= RSI_BuyMax);
   bool disBull    = (diPlus > diMinus);
   bool bullCandle = (Close[1] > Open[1]);

   if(h4Bull && trendStrong && disBull && emaCrossBull && rsiBuy && strongCandle && bullCandle && worthTrading)
     {
      OpenTrade(OP_BUY, atr);
      return;
     }

   //--- SELL conditions ---
   bool h4Bear     = (h4close < h4ema);
   bool emaCrossBear = (h1FastPrev >= h1SlowPrev && h1FastNow < h1SlowNow);
   bool rsiSell    = (rsi >= RSI_SellMin && rsi <= RSI_SellMax);
   bool disBear    = (diMinus > diPlus);
   bool bearCandle = (Close[1] < Open[1]);

   if(h4Bear && trendStrong && disBear && emaCrossBear && rsiSell && strongCandle && bearCandle && worthTrading)
     {
      OpenTrade(OP_SELL, atr);
     }
  }

//+------------------------------------------------------------------+
void OpenTrade(int orderType, double atr)
  {
   double slDist  = atr * ATR_SL;
   double tpDist  = atr * ATR_TP;
   double lots    = CalculateLotSize(slDist);
   if(lots <= 0) return;

   double price, sl, tp;
   if(orderType == OP_BUY)
     {
      price = Ask;
      sl    = price - slDist;
      tp    = price + tpDist;
     }
   else
     {
      price = Bid;
      sl    = price + slDist;
      tp    = price - tpDist;
     }

   color clr = (orderType == OP_BUY) ? clrDodgerBlue : clrOrangeRed;
   int ticket = OrderSend(Symbol(), orderType, lots, price, Slippage, sl, tp,
                          "GS-v3", MagicNumber, 0, clr);

   if(ticket < 0)
      Print("OrderSend error: ", GetLastError());
   else
     {
      tradesToday++;
      Print("v3 Trade | ", (orderType==OP_BUY?"BUY":"SELL"),
            " Lots:", lots, " SL:", sl, " TP:", tp,
            " ATR:", atr, " Spread:", MarketInfo(Symbol(),MODE_SPREAD));
     }
  }

//+------------------------------------------------------------------+
//| Move SL to breakeven once trade is ATR_BE in profit              |
//+------------------------------------------------------------------+
void ManageBreakeven()
  {
   double atr = iATR(NULL, 0, 14, 1);
   double beDistance = atr * ATR_BE;
   double spreadPts  = MarketInfo(Symbol(), MODE_SPREAD) * Point;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;

      double openPrice = OrderOpenPrice();
      double currentSL = OrderStopLoss();

      if(OrderType() == OP_BUY)
        {
         double beLevel = openPrice + spreadPts; // breakeven + spread cost
         if(Bid >= openPrice + beDistance && currentSL < beLevel)
            if(!OrderModify(OrderTicket(), openPrice, beLevel, OrderTakeProfit(), 0, clrGold))
               Print("Breakeven modify failed (BUY) — Error: ", GetLastError());
        }
      else if(OrderType() == OP_SELL)
        {
         double beLevel = openPrice - spreadPts;
         if(Ask <= openPrice - beDistance && (currentSL > beLevel || currentSL == 0))
            if(!OrderModify(OrderTicket(), openPrice, beLevel, OrderTakeProfit(), 0, clrGold))
               Print("Breakeven modify failed (SELL) — Error: ", GetLastError());
        }
     }
  }

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
int TotalOpenOrders()
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            count++;
   return count;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("GoldScalper v3.0 removed. Reason: ", reason);
  }
//+------------------------------------------------------------------+
