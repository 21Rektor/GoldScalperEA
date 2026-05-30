# GoldScalper EA — MT4 Expert Advisor for XAUUSD

A MetaTrader 4 Expert Advisor designed for scalping Gold (XAUUSD) on the M5 timeframe.

## Strategy Overview

| Component | Details |
|-----------|---------|
| Trend filter | EMA crossover (fast 8 / slow 21) |
| Momentum filter | RSI (14) — avoids overbought/oversold entries |
| Stop Loss | ATR × 1.5 (dynamic, adapts to volatility) |
| Take Profit | SL × 2.0 (2:1 risk-reward ratio) |
| Session | London + NY overlap (07:00–20:00 server time) |
| Spread guard | Skips bars when spread > 30 points |

## Installation

1. Copy `GoldScalper.mq4` to your MT4 `Experts` folder:
   ```
   C:\Program Files (x86)\MetaTrader 4\MQL4\Experts\
   ```
2. Open MetaEditor and compile the file (press **F7**)
3. In MT4, open an **XAUUSD M5** chart
4. Drag the EA from the Navigator panel onto the chart
5. Enable **"Allow automated trading"** in EA settings
6. Click **OK**

## Input Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| RiskPercent | 1.0 | % of account balance risked per trade |
| FastEMA | 8 | Fast EMA period |
| SlowEMA | 21 | Slow EMA period |
| RSI_Period | 14 | RSI lookback period |
| RSI_OB | 70 | RSI overbought threshold |
| RSI_OS | 30 | RSI oversold threshold |
| ATR_Multiplier | 1.5 | Stop loss distance in ATR units |
| RR_Ratio | 2.0 | Take profit = SL × RR_Ratio |
| MaxSpreadPoints | 30 | Maximum spread to allow a trade |
| SessionStartHour | 7 | Trading session start (server time) |
| SessionEndHour | 20 | Trading session end (server time) |
| MagicNumber | 202401 | Unique ID to identify this EA's orders |

## Risk Warning

> **Trading foreign exchange and commodities carries significant risk.
> Past performance is not indicative of future results.
> Always test on a demo account before going live.**

## Backtest Tips

- Use **Every Tick** mode for the most accurate results
- Recommended history: minimum 1 year of XAUUSD M5 data
- Optimise `ATR_Multiplier` and `RR_Ratio` per market condition
