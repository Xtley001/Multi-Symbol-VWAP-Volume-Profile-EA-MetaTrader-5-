# Multi-Symbol VWAP + Volume Profile EA (MetaTrader 5)

## 📌 Overview

**MultiSymbolVWAP\_EA** is a professional-grade MetaTrader 5 Expert Advisor (EA) that combines **VWAP (Volume Weighted Average Price)**, **Volume Profile analysis**, and **ADR (Average Daily Range)** to execute trades across multiple symbols with institutional-style precision.

This EA is designed for **multi-asset trading**, robust **risk management**, and advanced **trade execution logic**. It automatically manages entries, exits, and trailing stops while incorporating **time filters**, **news filters**, and **drawdown protection**.

---

## ✨ Key Features

* **🔄 Multi-Symbol Support**
  Trade multiple assets simultaneously (Forex pairs, indices, commodities, etc.) by listing symbols in the settings.

* **📊 Institutional Indicators**

  * **VWAP (Volume Weighted Average Price)** for directional bias.
  * **Volume Profile (POC, HVN, LVN)** to detect high- and low-volume price areas.
  * **ADR (Average Daily Range)** for adaptive SL/TP levels.

* **⚡ Risk Management**

  * Risk per trade (% of equity).
  * Automatic lot size calculation based on SL distance.
  * Daily equity drawdown limits.

* **🕒 Trade Filters**

  * Time-based trading sessions (configurable by day/hour UTC).
  * Economic calendar integration to avoid high-impact news events.
  * Bar lookback filter to reduce whipsaws.

* **📈 Trade Management**

  * Dynamic trailing stop based on **R-multiples (1R, 2R, 3R, 4R)**.
  * Optional **VWAP crossover exit**.
  * Automatic breakeven protection.

* **⚙️ Robust Engineering**

  * Optimized for MQL5 with `CTrade` and dynamic arrays.
  * Detailed error handling for symbol validation.
  * Modular functions for VWAP, ADR, and Volume Profile calculations.

---

## ⚡ How It Works

1. **Market Analysis**

   * On each new **M30 bar**, the EA updates VWAP, ADR, and Volume Profile for all configured symbols.

2. **Trade Entry Conditions**

   * Long: Price above VWAP **and** above HVN/LVN zones.
   * Short: Price below VWAP **and** below HVN/LVN zones.
   * SL = 10% of ADR, TP = 50% of ADR.

3. **Risk & Position Sizing**

   * Position size is calculated from account equity, risk %, and stop-loss distance.

4. **Trade Management**

   * Automated trailing stop logic using **R-multiples**.
   * Optional VWAP crossover exit for early trade closure.

5. **Protections**

   * Stops trading when daily drawdown exceeds limit.
   * Avoids trading around high-impact news.
   * Only trades during specified UTC hours and weekdays.

---

## 🔧 Input Parameters

### General Settings

| Parameter                 | Description                                                           |
| ------------------------- | --------------------------------------------------------------------- |
| `Symbols`                 | Comma-separated symbols to trade (e.g. `EURUSD,GBPUSD,AUDUSD,US500`). |
| `RiskPerTrade`            | Risk per trade (% of equity).                                         |
| `MaxDailyDrawdown`        | Maximum daily drawdown (% of equity) before halting trading.          |
| `ADR_Period`              | ADR lookback period in days.                                          |
| `TradeBarLookback`        | Minimum bars between trades on the same symbol.                       |
| `EnableTimeFilter`        | Restrict trading to specified days/hours.                             |
| `TradingDays`             | Days of week allowed (1=Mon … 5=Fri).                                 |
| `StartHourUTC`            | Start trading hour (UTC).                                             |
| `EndHourUTC`              | End trading hour (UTC).                                               |
| `EnableNewsFilter`        | Avoid trading around economic news.                                   |
| `EnableVWAPCrossoverExit` | Exit trades when price crosses VWAP.                                  |

### Volume Profile Settings

| Parameter           | Description                                     |
| ------------------- | ----------------------------------------------- |
| `VolumeProfileBins` | Number of bins for volume profile distribution. |

---

## 📂 Project Structure

```
MultiSymbolVWAP_EA.mq5    # Main Expert Advisor file
```

---

## 🚀 Installation & Usage

1. Copy `MultiSymbolVWAP_EA.mq5` into:

   ```
   MQL5/Experts/
   ```

2. Restart MetaTrader 5 or refresh the Navigator.

3. Attach the EA to any chart (it manages multiple symbols automatically).

4. Configure input parameters under the EA’s **Properties → Inputs** tab.

---

## 📊 Example Configuration

* Symbols: `EURUSD,GBPUSD,AUDUSD,US500`
* Risk: `1% per trade`
* Daily Drawdown Limit: `10%`
* Trading Days: `Tuesday–Thursday`
* Trading Hours: `13:00 – 17:00 UTC`
* Volume Profile Bins: `10`

---

## ⚠️ Risk Disclaimer

This EA is provided **for educational and research purposes only**. Trading leveraged products like Forex, indices, and commodities involves significant risk of loss. Past performance does not guarantee future results. Always test on a **demo account** before live trading.

---

## 🧠 Author

**Christley Olubela(2025)**
🔗 https://www.linkedin.com/in/christley-olubela/

---

Would you like me to also create a **workflow diagram** (mermaid or image-based) to visually show how the EA processes signals → executes trades → manages risk? It would make your README even more professional.
