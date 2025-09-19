//+------------------------------------------------------------------+
//|                                            MultiSymbolVWAP_EA.mq5 |
//|                        Multi-Symbol VWAP + Volume Profile EA       |
//|                        Copyright 2025, xAI                         |
//+------------------------------------------------------------------+
#property copyright "xAI"
#property link      "https://x.ai"
#property version   "1.01"
#property strict

#include <Trade\Trade.mqh>
#include <Arrays\ArrayDouble.mqh>
#include <Arrays\ArrayInt.mqh>
#include <Arrays\ArrayLong.mqh>

//--- Input Parameters
input group "General Settings"
input string Symbols = "EURUSD,GBPUSD,AUDUSD,US500"; // Symbols to trade (comma-separated)
input double RiskPerTrade = 1.0;                    // Risk per trade (% of equity)
input double MaxDailyDrawdown = 10.0;               // Max daily drawdown (% of equity)
input int ADR_Period = 14;                          // ADR lookback period (days)
input int TradeBarLookback = 5;                     // Bars to wait before new trade on same symbol
input bool EnableTimeFilter = true;                 // Enable time filter
input string TradingDays = "2,3,4";                 // Trading days of week (1=Mon,2=Tue,...,5=Fri, comma-separated)
input int StartHourUTC = 13;                        // Start trading hour (UTC)
input int EndHourUTC = 17;                          // End trading hour (UTC)
input bool EnableNewsFilter = true;                 // Enable news filter
input bool EnableVWAPCrossoverExit = false;         // Exit on VWAP crossover

input group "Volume Profile Settings"
input int VolumeProfileBins = 10;                   // Number of price bins

//--- Global Variables
CTrade trade;
string symbol_list[];
datetime monday_start;
double vwap_values[];
double adr_values[];
double equity_high;
datetime drawdown_reset_time;
bool trading_halted;
int allowed_days[];

//--- Symbol Data Structure
struct SymbolData {
   string symbol;
   double vwap;
   double adr;
   double poc;
   double hvn_lower, hvn_upper;
   double lvn_lower, lvn_upper;
   bool has_open_trade;
   datetime last_trade_time;
};

//--- Structures for dynamic 2D arrays
struct VolumePriceRow {
   double prices[];
};

struct VolumeVolumeRow {
   long volumes[];
};

//--- Global Arrays
SymbolData symbol_data[];
VolumePriceRow volume_price_rows[];
VolumeVolumeRow volume_volume_rows[];

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit() {
   // Parse trading days
   string days_str[];
   StringSplit(TradingDays, ',', days_str);
   int day_count = ArraySize(days_str);
   ArrayResize(allowed_days, day_count);
   for(int i = 0; i < day_count; i++) {
      allowed_days[i] = (int)StringToInteger(days_str[i]);
   }

   // Split symbols into array
   StringSplit(Symbols, ',', symbol_list);
   int symbol_count = ArraySize(symbol_list);
   ArrayResize(symbol_data, symbol_count);
   ArrayResize(vwap_values, symbol_count);
   ArrayResize(adr_values, symbol_count);
   ArrayResize(volume_price_rows, symbol_count);
   ArrayResize(volume_volume_rows, symbol_count);

   // Initialize and validate symbols
   for(int i = 0; i < symbol_count; i++) {
      symbol_data[i].symbol = symbol_list[i];
      symbol_data[i].vwap = 0.0;
      symbol_data[i].adr = 0.0;
      symbol_data[i].poc = 0.0;
      symbol_data[i].hvn_lower = 0.0;
      symbol_data[i].hvn_upper = 0.0;
      symbol_data[i].lvn_lower = 0.0;
      symbol_data[i].lvn_upper = 0.0;
      symbol_data[i].has_open_trade = false;
      symbol_data[i].last_trade_time = 0;
      if(!SymbolSelect(symbol_data[i].symbol, true)) {
         Print("Error: Cannot select symbol ", symbol_data[i].symbol, " in Market Watch");
         return(INIT_FAILED);
      }
      if(SymbolInfoDouble(symbol_data[i].symbol, SYMBOL_TRADE_TICK_VALUE) == 0) {
         Print("Error: Invalid tick value for ", symbol_data[i].symbol);
         return(INIT_FAILED);
      }
      // Initialize volume profile arrays
      ArrayResize(volume_price_rows[i].prices, VolumeProfileBins);
      ArrayResize(volume_volume_rows[i].volumes, VolumeProfileBins);
   }

   // Find Monday 00:00 UTC
   monday_start = GetMondayStartTime();

   // Initialize drawdown tracking
   equity_high = AccountInfoDouble(ACCOUNT_EQUITY);
   drawdown_reset_time = TimeCurrent();
   trading_halted = false;

   // Calculate initial VWAP, ADR, and volume profiles
   for(int i = 0; i < symbol_count; i++) {
      symbol_data[i].vwap = CalculateVWAP(symbol_data[i].symbol);
      symbol_data[i].adr = CalculateADR(symbol_data[i].symbol, ADR_Period);
      CalculateVolumeProfile(i);
      if(symbol_data[i].vwap == 0.0 || symbol_data[i].adr == 0.0) {
         Print("Error: Failed to calculate VWAP or ADR for ", symbol_data[i].symbol);
         return(INIT_FAILED);
      }
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
   // Reset drawdown daily
   if(TimeCurrent() >= drawdown_reset_time + 86400) {
      equity_high = AccountInfoDouble(ACCOUNT_EQUITY);
      drawdown_reset_time = TimeCurrent();
      trading_halted = false;
   }

   // Check daily drawdown
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = (equity_high - current_equity) / equity_high * 100.0;
   if(drawdown > MaxDailyDrawdown) {
      trading_halted = true;
      Print("Trading halted: Max daily drawdown exceeded (", drawdown, "%)");
      return;
   }

   // Update on new M30 bar
   static datetime last_bar;
   datetime current_bar = iTime(symbol_data[0].symbol, PERIOD_M30, 0);
   if(last_bar != current_bar && !trading_halted) {
      last_bar = current_bar;

      // Update VWAP, ADR, and volume profiles
      for(int i = 0; i < ArraySize(symbol_data); i++) {
         symbol_data[i].vwap = CalculateVWAP(symbol_data[i].symbol);
         symbol_data[i].adr = CalculateADR(symbol_data[i].symbol, ADR_Period);
         CalculateVolumeProfile(i);
         if(symbol_data[i].vwap == 0.0 || symbol_data[i].adr == 0.0) {
            Print("Warning: Failed to update VWAP or ADR for ", symbol_data[i].symbol);
         }
      }

      // Check trading conditions for each symbol
      for(int i = 0; i < ArraySize(symbol_data); i++) {
         CheckTradeConditions(i);
      }
   }

   // Manage open trades
   ManageTrades();
}

//+------------------------------------------------------------------+
//| Calculate Monday 00:00 UTC                                        |
//+------------------------------------------------------------------+
datetime GetMondayStartTime() {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int days_to_subtract = (dt.day_of_week == 0) ? 6 : dt.day_of_week - 1;
   datetime monday = now - days_to_subtract * 86400;
   TimeToStruct(monday, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Calculate VWAP for a symbol                                       |
//+------------------------------------------------------------------+
double CalculateVWAP(string symbol) {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, PERIOD_M30, monday_start, TimeCurrent(), rates);
   if(copied <= 0) {
      Print("Error: Cannot copy rates for ", symbol, ", Error: ", GetLastError());
      return 0.0;
   }

   double sum_price_volume = 0.0;
   double sum_volume = 0.0;
   for(int i = 0; i < copied; i++) {
      double typical_price = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      sum_price_volume += typical_price * (double)rates[i].tick_volume;
      sum_volume += (double)rates[i].tick_volume;
   }

   double vwap = (sum_volume > 0) ? sum_price_volume / sum_volume : 0.0;
   return NormalizeDouble(vwap, SymbolInfoInteger(symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
//| Calculate ADR for a symbol                                        |
//+------------------------------------------------------------------+
double CalculateADR(string symbol, int period) {
   double sum_range = 0.0;
   int valid_days = 0;
   for(int i = 1; i <= period; i++) {
      MqlRates daily_rates[];
      ArraySetAsSeries(daily_rates, true);
      if(CopyRates(symbol, PERIOD_D1, i, 1, daily_rates) > 0) {
         sum_range += daily_rates[0].high - daily_rates[0].low;
         valid_days++;
      }
   }
   double adr = (valid_days > 0) ? sum_range / valid_days : 0.0;
   return NormalizeDouble(adr / SymbolInfoDouble(symbol, SYMBOL_POINT), 2);
}

//+------------------------------------------------------------------+
//| Calculate Volume Profile for a symbol                              |
//+------------------------------------------------------------------+
void CalculateVolumeProfile(int symbol_index) {
   string symbol = symbol_data[symbol_index].symbol;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, PERIOD_M30, monday_start, TimeCurrent(), rates);
   if(copied <= 0) {
      Print("Error: Cannot copy rates for volume profile for ", symbol, ", Error: ", GetLastError());
      return;
   }

   // Find price range
   double min_price = rates[0].low;
   double max_price = rates[0].high;
   for(int i = 1; i < copied; i++) {
      min_price = MathMin(min_price, rates[i].low);
      max_price = MathMax(max_price, rates[i].high);
   }

   // Initialize bins with fixed number
   double bin_size = (max_price - min_price) / VolumeProfileBins;
   if(bin_size <= 0) {
      Print("Error: Invalid bin size for volume profile for ", symbol);
      return;
   }

   int bin_count = VolumeProfileBins;
   ArrayResize(volume_price_rows[symbol_index].prices, bin_count);
   ArrayResize(volume_volume_rows[symbol_index].volumes, bin_count);
   for(int j = 0; j < bin_count; j++) {
      volume_price_rows[symbol_index].prices[j] = min_price + j * bin_size;
      volume_volume_rows[symbol_index].volumes[j] = 0;
   }

   // Populate volume profile
   for(int i = 0; i < copied; i++) {
      double price = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      int bin_index = (int)MathFloor((price - min_price) / bin_size);
      if(bin_index >= 0 && bin_index < bin_count) {
         volume_volume_rows[symbol_index].volumes[bin_index] += rates[i].tick_volume;
      }
   }

   // Find POC, HVN, LVN
   long max_volume = 0;
   double total_volume = 0.0;
   int poc_index = 0;
   for(int i = 0; i < bin_count; i++) {
      total_volume += (double)volume_volume_rows[symbol_index].volumes[i];
      if(volume_volume_rows[symbol_index].volumes[i] > max_volume) {
         max_volume = volume_volume_rows[symbol_index].volumes[i];
         poc_index = i;
      }
   }

   if(total_volume == 0) {
      Print("Error: No volume data for ", symbol);
      return;
   }

   symbol_data[symbol_index].poc = volume_price_rows[symbol_index].prices[poc_index];
   double threshold = total_volume / bin_count;
   symbol_data[symbol_index].hvn_lower = symbol_data[symbol_index].poc;
   symbol_data[symbol_index].hvn_upper = symbol_data[symbol_index].poc;
   symbol_data[symbol_index].lvn_lower = min_price;
   symbol_data[symbol_index].lvn_upper = max_price;

   for(int i = 0; i < bin_count; i++) {
      if(volume_volume_rows[symbol_index].volumes[i] > threshold) {
         symbol_data[symbol_index].hvn_lower = MathMin(symbol_data[symbol_index].hvn_lower, volume_price_rows[symbol_index].prices[i]);
         symbol_data[symbol_index].hvn_upper = MathMax(symbol_data[symbol_index].hvn_upper, volume_price_rows[symbol_index].prices[i]);
      } else {
         symbol_data[symbol_index].lvn_lower = MathMin(symbol_data[symbol_index].lvn_lower, volume_price_rows[symbol_index].prices[i]);
         symbol_data[symbol_index].lvn_upper = MathMax(symbol_data[symbol_index].lvn_upper, volume_price_rows[symbol_index].prices[i]);
      }
   }

   // Normalize values to symbol's digits
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   symbol_data[symbol_index].poc = NormalizeDouble(symbol_data[symbol_index].poc, digits);
   symbol_data[symbol_index].hvn_lower = NormalizeDouble(symbol_data[symbol_index].hvn_lower, digits);
   symbol_data[symbol_index].hvn_upper = NormalizeDouble(symbol_data[symbol_index].hvn_upper, digits);
   symbol_data[symbol_index].lvn_lower = NormalizeDouble(symbol_data[symbol_index].lvn_lower, digits);
   symbol_data[symbol_index].lvn_upper = NormalizeDouble(symbol_data[symbol_index].lvn_upper, digits);
}

//+------------------------------------------------------------------+
//| Check if trading is allowed based on time filter                   |
//+------------------------------------------------------------------+
bool IsTradingTime() {
   if(!EnableTimeFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   int day = dt.day_of_week;
   bool day_allowed = false;
   for(int i = 0; i < ArraySize(allowed_days); i++) {
      if(allowed_days[i] == day) {
         day_allowed = true;
         break;
      }
   }
   return day_allowed && hour >= StartHourUTC && hour < EndHourUTC;
}

//+------------------------------------------------------------------+
//| Check news filter using MT5 economic calendar                      |
//+------------------------------------------------------------------+
bool IsNewsFilterPassed(string symbol) {
   if(!EnableNewsFilter) return true;
   string base = StringSubstr(symbol, 0, 3);
   string quote = StringSubstr(symbol, 3, 3);
   MqlCalendarValue values[];
   datetime from = TimeCurrent() - 3600; // 1 hour before
   datetime to = TimeCurrent() + 3600;   // 1 hour after
   bool has_impact = false;
   int base_count = CalendarValueHistory(values, from, to, ULONG_MAX, base);
   if(base_count > 0) {
      for(int i = 0; i < ArraySize(values); i++) {
         MqlCalendarValue value = values[i];
         MqlCalendarEvent event;
         if(CalendarEventById(value.event_id, event) && event.importance >= CALENDAR_IMPORTANCE_MODERATE) {
            has_impact = true;
            break;
         }
      }
   }
   if(has_impact) {
      Print("Impact news detected for ", symbol, " (base currency)");
      return false;
   }
   int quote_count = CalendarValueHistory(values, from, to, ULONG_MAX, quote);
   if(quote_count > 0) {
      for(int i = 0; i < ArraySize(values); i++) {
         MqlCalendarValue value = values[i];
         MqlCalendarEvent event;
         if(CalendarEventById(value.event_id, event) && event.importance >= CALENDAR_IMPORTANCE_MODERATE) {
            has_impact = true;
            break;
         }
      }
   }
   if(has_impact) {
      Print("Impact news detected for ", symbol, " (quote currency)");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check bar lookback to prevent whipsaws                            |
//+------------------------------------------------------------------+
bool IsBarLookbackPassed(int symbol_index) {
   if(symbol_data[symbol_index].last_trade_time == 0) return true;
   datetime current_bar = iTime(symbol_data[symbol_index].symbol, PERIOD_M30, 0);
   int bars_since_last_trade = iBarShift(symbol_data[symbol_index].symbol, PERIOD_M30, symbol_data[symbol_index].last_trade_time);
   return bars_since_last_trade >= TradeBarLookback;
}

//+------------------------------------------------------------------+
//| Check trading conditions and place trades                          |
//+------------------------------------------------------------------+
void CheckTradeConditions(int symbol_index) {
   if(symbol_data[symbol_index].has_open_trade) return;
   string symbol = symbol_data[symbol_index].symbol;
   double vwap = symbol_data[symbol_index].vwap;
   double adr = symbol_data[symbol_index].adr;
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double sl_pips = adr * 0.1; // 10% of ADR for stop loss
   double tp_pips = adr * 0.5; // 50% of ADR for take profit
   double stops_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

   // Check time, news, and bar lookback filters
   if(!IsTradingTime() || !IsNewsFilterPassed(symbol) || !IsBarLookbackPassed(symbol_index)) {
      return;
   }

   // Validate VWAP and ADR
   if(vwap == 0.0 || adr == 0.0) {
      Print("Trade skipped for ", symbol, ": Invalid VWAP or ADR");
      return;
   }

   // Volume profile conditions
   bool is_above_hvn = bid > symbol_data[symbol_index].hvn_upper;
   bool is_below_hvn = ask < symbol_data[symbol_index].hvn_lower;
   bool is_above_lvn = bid > symbol_data[symbol_index].lvn_upper;
   bool is_below_lvn = ask < symbol_data[symbol_index].lvn_lower;

   // Long entry
   if(ask > vwap && (is_above_hvn || is_above_lvn)) {
      double sl = bid - sl_pips * point;
      double tp = bid + tp_pips * point;
      // Ensure SL and TP meet minimum stops level
      if(sl >= ask - stops_level || tp <= ask + stops_level) {
         Print("Trade skipped for ", symbol, ": SL/TP too close to market price");
         return;
      }
      double lot_size = CalculateLotSize(symbol, sl_pips, RiskPerTrade);
      ResetLastError();
      if(trade.Buy(lot_size, symbol, ask, sl, tp, "VWAP Long")) {
         symbol_data[symbol_index].has_open_trade = true;
         symbol_data[symbol_index].last_trade_time = iTime(symbol, PERIOD_M30, 0);
         Print("Buy order placed for ", symbol, ", Lot: ", lot_size, ", SL: ", sl, ", TP: ", tp);
      } else {
         Print("Buy order failed for ", symbol, ", Error: ", GetLastError());
      }
   }
   // Short entry
   else if(bid < vwap && (is_below_hvn || is_below_lvn)) {
      double sl = bid + sl_pips * point;
      double tp = bid - tp_pips * point;
      // Ensure SL and TP meet minimum stops level
      if(sl <= bid + stops_level || tp >= bid - stops_level) {
         Print("Trade skipped for ", symbol, ": SL/TP too close to market price");
         return;
      }
      double lot_size = CalculateLotSize(symbol, sl_pips, RiskPerTrade);
      ResetLastError();
      if(trade.Sell(lot_size, symbol, bid, sl, tp, "VWAP Short")) {
         symbol_data[symbol_index].has_open_trade = true;
         symbol_data[symbol_index].last_trade_time = iTime(symbol, PERIOD_M30, 0);
         Print("Sell order placed for ", symbol, ", Lot: ", lot_size, ", SL: ", sl, ", TP: ", tp);
      } else {
         Print("Sell order failed for ", symbol, ", Error: ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                   |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double sl_pips, double risk_percent) {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_amount = equity * (risk_percent / 100.0);
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_value == 0) {
      Print("Error: Invalid tick value for ", symbol);
      return 0.0;
   }
   double lot_size = risk_amount / (sl_pips * tick_value);
   
   // Get symbol volume constraints
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   // Normalize lot size to meet step requirements
   lot_size = MathRound(lot_size / lot_step) * lot_step;
   
   // Ensure lot size is within min/max limits
   lot_size = MathMin(MathMax(lot_size, min_lot), max_lot);
   
   return NormalizeDouble(lot_size, 2);
}

//+------------------------------------------------------------------+
//| Manage open trades (trailing stop, VWAP crossover exit)           |
//+------------------------------------------------------------------+
void ManageTrades() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         string symbol = PositionGetString(POSITION_SYMBOL);
         int symbol_index = -1;
         for(int j = 0; j < ArraySize(symbol_data); j++) {
            if(symbol_data[j].symbol == symbol) {
               symbol_index = j;
               break;
            }
         }
         if(symbol_index == -1) continue;
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
         double sl_pips = symbol_data[symbol_index].adr * 0.1; // 1R = 10% of ADR
         double stops_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         double profit_pips = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                            ? (current_price - open_price) / point
                            : (open_price - current_price) / point;

         // Trailing stop
         double new_sl = sl;
         if(profit_pips >= sl_pips) { // +1R
            new_sl = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                   ? open_price // Breakeven
                   : open_price;
         }
         if(profit_pips >= sl_pips * 2) { // +2R
            new_sl = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                   ? open_price + sl_pips * point // Lock +1R
                   : open_price - sl_pips * point;
         }
         if(profit_pips >= sl_pips * 3) { // +3R
            new_sl = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                   ? open_price + 2 * sl_pips * point // Lock +2R
                   : open_price - 2 * sl_pips * point;
         }
         if(profit_pips >= sl_pips * 4) { // +4R
            new_sl = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                   ? open_price + 3 * sl_pips * point // Lock +3R
                   : open_price - 3 * sl_pips * point;
         }

         // Normalize new SL and ensure it meets stops level requirement
         new_sl = NormalizeDouble(new_sl, digits);
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
            if(new_sl >= current_price - stops_level) new_sl = sl; // Prevent invalid stops
         } else {
            if(new_sl <= current_price + stops_level) new_sl = sl; // Prevent invalid stops
         }

         // Only modify if SL has changed
         if(new_sl != sl && MathAbs(new_sl - sl) >= tick_size) {
            if(trade.PositionModify(ticket, new_sl, tp)) {
               Print("Trailing stop updated for ", symbol, ", Ticket: ", ticket, ", New SL: ", new_sl);
            } else {
               Print("Failed to update trailing stop for ", symbol, ", Ticket: ", ticket, ", Error: ", GetLastError());
            }
         }

         // VWAP crossover exit
         if(EnableVWAPCrossoverExit) {
            double vwap = symbol_data[symbol_index].vwap;
            if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && current_price < vwap) ||
               (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && current_price > vwap)) {
               if(trade.PositionClose(ticket)) {
                  Print("Position closed on VWAP crossover for ", symbol, ", Ticket: ", ticket);
                  symbol_data[symbol_index].has_open_trade = false;
               }
            }
         }

         // Update has_open_trade status
         if(!PositionSelectByTicket(ticket)) {
            symbol_data[symbol_index].has_open_trade = false;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Clean up
   ArrayFree(symbol_list);
   ArrayFree(symbol_data);
   ArrayFree(vwap_values);
   ArrayFree(adr_values);
   for(int i = 0; i < ArraySize(volume_price_rows); i++) {
      ArrayFree(volume_price_rows[i].prices);
      ArrayFree(volume_volume_rows[i].volumes);
   }
   ArrayFree(volume_price_rows);
   ArrayFree(volume_volume_rows);
   ArrayFree(allowed_days);
}