//+------------------------------------------------------------------+
//|                                              MainACAlgorithm.mq5 |
//|                      DEPRECATED-OLD VERSION                      |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.25"
#property strict
#property description "Main trading EA with Asymmetrical Compounding Risk Management"

// Include necessary libraries
#include <Trade/Trade.mqh>
#include "C:/Users/marth/AppData/Roaming/MetaQuotes/Terminal/E62C655ED163FFC555DD40DBEA67E6BB/MQL5/Experts/MainACAlgo/Include/ACFunctions.mqh"      // Position sizing and risk management
#include "C:/Users/marth/AppData/Roaming/MetaQuotes/Terminal/E62C655ED163FFC555DD40DBEA67E6BB/MQL5/Experts/MainACAlgo/Include/ATRtrailing.mqh"      // Trailing stop functionality
// Include indicators as direct calculation libraries
#include "C:/Users/marth/AppData/Roaming/MetaQuotes/Terminal/E62C655ED163FFC555DD40DBEA67E6BB/MQL5/Experts/MainACAlgo/Indicators/T3.mqh"             // T3 indicator calculations
#include "C:/Users/marth/AppData/Roaming/MetaQuotes/Terminal/E62C655ED163FFC555DD40DBEA67E6BB/MQL5/Experts/MainACAlgo/Indicators/vwap_lite.mqh"         // VWAP indicator calculations

//--- Performance Optimization Settings
input group "==== Performance Settings ===="
input bool     OptimizationMode = true;  // Enable optimization mode for faster backtesting
input int      UpdateFrequency = 5;      // Update indicators every X ticks in backtest mode

//--- Input Parameters for Trading
input group "==== Trading Settings ===="
input double   DefaultLot = 0.01;       // Default lot size if risk calculation fails
input int      Slippage = 20;           // Allowed slippage in points
input int      MagicNumber = 12345;     // Magic number for this EA
input string   TradeComment = "AC";     // Comment for trades

//--- Risk Management Settings
input group "==== Risk Management Settings ===="
input bool     UseACRiskManagement = true; // Enable AC risk management (false = use fixed lot size)

// Note: AC risk parameters are defined in ACFunctions.mqh
// They will appear in the inputs dialog automatically
// AC_BaseRisk, AC_BaseReward, AC_CompoundingWins, ATRPeriod, ATRMultiplier, MaxStopLossDistance

//--- Button Settings
input group "==== Button Settings ===="
input int      BuyButtonX = 100;        // X position for Buy button
input int      BuyButtonY = 40;         // Y position for Buy button
input int      SellButtonX = 100;       // X position for Sell button
input int      SellButtonY = 80;        // Y position for Sell button
input color    BuyButtonColor = clrDodgerBlue;  // Color for Buy button
input color    SellButtonColor = clrCrimson;    // Color for Sell button

//--- T3 Indicator Settings
input group "==== T3 Indicator Settings ===="
input bool     UseT3Indicator = true;   // Use T3 indicator for entry signals
input int      T3_Length = 12;          // Period length for T3 calculation
input double   T3_Factor = 0.7;         // Volume factor for T3 calculation
input ENUM_APPLIED_PRICE T3_Applied_Price = PRICE_CLOSE; // Price type for T3
input bool     T3_UseTickPrecision = false; // Use tick-level precision for T3 (slower but more accurate)

//--- VWAP Indicator Settings
input group "==== VWAP Indicator Settings ===="
input bool     UseVWAPIndicator = true; // Use VWAP indicator for entry signals
input bool     Enable_Daily_VWAP = true;     // Enable Daily VWAP
input ENUM_TIMEFRAMES VWAP_Timeframe1 = PERIOD_M15;  // VWAP Timeframe 1
input ENUM_TIMEFRAMES VWAP_Timeframe2 = PERIOD_H1;   // VWAP Timeframe 2
input ENUM_TIMEFRAMES VWAP_Timeframe3 = PERIOD_H4;   // VWAP Timeframe 3
input ENUM_TIMEFRAMES VWAP_Timeframe4 = PERIOD_CURRENT; // VWAP Timeframe 4 (PERIOD_CURRENT = disabled)
input ENUM_APPLIED_PRICE VWAP_Price_Type = PRICE_CLOSE; // Price type for VWAP
input bool     VWAP_UseTickPrecision = false; // Use tick-level precision for VWAP (slower but more accurate)

//--- Entry Signal Settings
input group "==== Entry Signal Settings ===="
input bool     UseAutomaticTrading = false; // Enable automatic trading based on indicators
input int      SignalConfirmationBars = 2;  // Number of bars to confirm signal

//--- Global Variables
CTrade trade;                      // Trade object for executing trades
string BuyButtonName = "BuyButton";  // Name for Buy button
string SellButtonName = "SellButton"; // Name for Sell button

// Indicator instances
CT3Indicator T3;                // T3 indicator instance
CVWAPIndicator VWAP;            // VWAP indicator instance

// Indicator buffers
double T3Buffer[];                 // Buffer for T3 indicator values
double VWAPDailyBuffer[];          // Buffer for VWAP Daily values
double VWAPTF1Buffer[];            // Buffer for VWAP Timeframe 1 values
double VWAPTF2Buffer[];            // Buffer for VWAP Timeframe 2 values
double VWAPTF3Buffer[];            // Buffer for VWAP Timeframe 3 values
double VWAPTF4Buffer[];            // Buffer for VWAP Timeframe 4 values

// Price arrays for indicators
double priceDataT3[];
double priceDataVWAP[];
MqlRates priceRates[];  // Renamed from 'rates' to avoid conflicts

// Previous indicator values for signal detection
double prevT3 = 0;
double currT3 = 0;
double prevVWAPDaily = 0;
double currVWAPDaily = 0;
double prevVWAPTF1 = 0;
double currVWAPTF1 = 0;
double prevVWAPTF2 = 0;
double currVWAPTF2 = 0;
double prevVWAPTF3 = 0;
double currVWAPTF3 = 0;
double prevVWAPTF4 = 0;
double currVWAPTF4 = 0;

// Optimization variables
datetime lastBarTime = 0;           // Time of the last processed bar
int tickCounter = 0;                // Counter for updating on specific ticks
bool isInBacktest = false;          // Flag for backtest mode

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Check if we're in optimization/backtesting mode
   isInBacktest = MQLInfoInteger(MQL_OPTIMIZATION) || MQLInfoInteger(MQL_TESTER);
   
   // Clear existing objects from the chart first (except indicators)
   if(!OptimizationMode || !isInBacktest)
   {
      Print("Clearing chart objects before initializing EA...");
      
      // Delete objects by their specific type using manual iteration
      // Delete all buttons
      for(int i = ObjectsTotal(0, 0, OBJ_BUTTON) - 1; i >= 0; i--)
      {
          ObjectDelete(0, ObjectName(0, i, 0, OBJ_BUTTON));
      }
      
      // Delete all labels
      for(int i = ObjectsTotal(0, 0, OBJ_LABEL) - 1; i >= 0; i--)
      {
          ObjectDelete(0, ObjectName(0, i, 0, OBJ_LABEL));
      }
      
      // Delete all horizontal lines
      for(int i = ObjectsTotal(0, 0, OBJ_HLINE) - 1; i >= 0; i--)
      {
          ObjectDelete(0, ObjectName(0, i, 0, OBJ_HLINE));
      }
      
      // Delete objects by pattern that could be left from previous runs
      int totalObjects = ObjectsTotal(0);
      for(int i = totalObjects - 1; i >= 0; i--)
      {
          string objName = ObjectName(0, i);
          
          // Check if this is one of our objects by specific patterns
          if(StringFind(objName, "ATR") >= 0 || 
             StringFind(objName, "Trail") >= 0 || 
             StringFind(objName, "Button") >= 0 ||
             StringFind(objName, "Test") >= 0 || 
             StringFind(objName, "Buy") >= 0 || 
             StringFind(objName, "Sell") >= 0 || 
             StringFind(objName, "SL") >= 0 || 
             StringFind(objName, "Close") >= 0 || 
             StringFind(objName, "Level") >= 0 || 
             StringFind(objName, "Label") >= 0)
          {
              ObjectDelete(0, objName);
          }
      }
      
      // Force a chart redraw to ensure all objects are removed visually
      ChartRedraw();
   }
   
   // Initialize the trade object
   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Initialize risk management system
   InitializeACRiskManagement();
   
   if(!OptimizationMode || !isInBacktest)
      Print("Asymmetrical Compounding Risk Management initialized with base risk: ", AC_BaseRisk, "%");
   
   // Initialize ATR trailing stop system
   InitDEMAATR();
   
   if(!OptimizationMode || !isInBacktest)
      Print("DEMA-ATR trailing system initialized without visual indicators");
   
   // Initialize T3 indicator
   if(UseT3Indicator)
   {
      // Initialize price arrays for T3
      ArraySetAsSeries(priceDataT3, true);
      ArrayResize(priceDataT3, isInBacktest && OptimizationMode ? 200 : 1000);
      
      // Initialize the T3 indicator class
      T3.Init(T3_Length, T3_Factor, T3_Applied_Price, T3_UseTickPrecision);
      
      // Allocate memory for T3 buffer
      ArraySetAsSeries(T3Buffer, true);
      ArrayResize(T3Buffer, isInBacktest && OptimizationMode ? 10 : 100);
      
      if(!OptimizationMode || !isInBacktest)
         Print("T3 indicator initialized successfully");
   }
   
   // Initialize VWAP indicator
   if(UseVWAPIndicator)
   {
      // Map ENUM_APPLIED_PRICE to PRICE_TYPE for VWAP
      PRICE_TYPE priceType;
      switch(VWAP_Price_Type)
      {
         case PRICE_OPEN:  priceType = OPEN; break;
         case PRICE_CLOSE: priceType = CLOSE; break;
         case PRICE_HIGH:  priceType = HIGH; break;
         case PRICE_LOW:   priceType = LOW; break;
         case PRICE_MEDIAN: priceType = HIGH_LOW; break;
         case PRICE_TYPICAL: priceType = CLOSE_HIGH_LOW; break;
         case PRICE_WEIGHTED: priceType = OPEN_CLOSE_HIGH_LOW; break;
         default: priceType = CLOSE; break;
      }
      
      // In backtest mode, force disable tick precision for VWAP to improve performance
      bool useTickPrecision = isInBacktest && OptimizationMode ? false : VWAP_UseTickPrecision;
      
      // Initialize the VWAP indicator class
      VWAP.Init(priceType, Enable_Daily_VWAP, VWAP_Timeframe1, VWAP_Timeframe2, 
               VWAP_Timeframe3, VWAP_Timeframe4, useTickPrecision);
      
      // Initialize price arrays for VWAP and prepare MqlRates for bar data
      ArraySetAsSeries(priceRates, true);
      
      // Allocate memory for VWAP buffers
      ArraySetAsSeries(VWAPDailyBuffer, true);
      ArraySetAsSeries(VWAPTF1Buffer, true);
      ArraySetAsSeries(VWAPTF2Buffer, true);
      ArraySetAsSeries(VWAPTF3Buffer, true);
      ArraySetAsSeries(VWAPTF4Buffer, true);
      
      int bufferSize = isInBacktest && OptimizationMode ? 10 : 100;
      
      ArrayResize(VWAPDailyBuffer, bufferSize);
      ArrayResize(VWAPTF1Buffer, bufferSize);
      ArrayResize(VWAPTF2Buffer, bufferSize);
      ArrayResize(VWAPTF3Buffer, bufferSize);
      ArrayResize(VWAPTF4Buffer, bufferSize);
      
      if(!OptimizationMode || !isInBacktest)
         Print("VWAP indicator initialized successfully");
   }
   
   // Create buttons for manual trading only when not in backtest mode
   if(!isInBacktest)
   {
      CreateButton(BuyButtonName, "BUY", BuyButtonX, BuyButtonY, BuyButtonColor);
      CreateButton(SellButtonName, "SELL", SellButtonX, SellButtonY, SellButtonColor);
   }
   
   if(!OptimizationMode || !isInBacktest)
   {
      Print("=================================");
      Print("✓ MainACAlgorithm EA initialized successfully");
      Print("✓ Current risk setting: ", currentRisk, "%");
      Print("✓ Base risk: ", AC_BaseRisk, "%", " | Base reward: ", AC_BaseReward);
      Print("✓ ATR Period: ", ATRPeriod, " | ATR Multiplier: ", ATRMultiplier);
      Print("✓ Risk Management Mode: ", UseACRiskManagement ? "Dynamic (AC)" : "Fixed lot");
      Print("✓ T3 indicator: ", UseT3Indicator ? "Enabled" : "Disabled");
      Print("✓ VWAP indicator: ", UseVWAPIndicator ? "Enabled" : "Disabled");
      Print("✓ Automatic trading: ", UseAutomaticTrading ? "Enabled" : "Disabled");
      Print("✓ Optimization Mode: ", OptimizationMode ? "Enabled" : "Disabled");
      Print("=================================");
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // More aggressive cleanup of ALL objects to ensure no leftovers
   Print("Performing complete cleanup of all EA objects...");
   
   // Clean up specific named buttons
   ObjectDelete(0, BuyButtonName);
   ObjectDelete(0, SellButtonName);
   ObjectDelete(0, ButtonName); // ATR trailing button
   
   // Clean up ALL buttons on the chart
   for(int i = ObjectsTotal(0, 0, OBJ_BUTTON) - 1; i >= 0; i--)
   {
       ObjectDelete(0, ObjectName(0, i, 0, OBJ_BUTTON));
   }
   
   // Clean up ALL labels and lines
   for(int i = ObjectsTotal(0, 0, OBJ_LABEL) - 1; i >= 0; i--)
   {
       ObjectDelete(0, ObjectName(0, i, 0, OBJ_LABEL));
   }
   
   for(int i = ObjectsTotal(0, 0, OBJ_HLINE) - 1; i >= 0; i--)
   {
       ObjectDelete(0, ObjectName(0, i, 0, OBJ_HLINE));
   }
   
   // Clean up ATR trailing objects
   CleanupATRTrailing();
   
   // Force chart redraw to ensure all objects are cleared visually
   ChartRedraw();
   
   Print("MainACAlgorithm EA removed - all objects cleaned up");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only update trailing stops when necessary
   if(isInBacktest && OptimizationMode)
   {
      tickCounter++;
      // Only update on specific ticks to reduce processing load during backtesting
      if(tickCounter < UpdateFrequency)
         return;
         
      tickCounter = 0;
   }
   
   // Get the current bar time
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // Check if we have a new bar or if we should process this tick
   bool newBar = currentBarTime != lastBarTime;
   
   // Update trailing stops for all open positions
   UpdateAllTrailingStops();
   
   // Update indicators only on new bars or when not in optimization mode
   if(newBar || !OptimizationMode || !isInBacktest)
   {
      lastBarTime = currentBarTime;
      UpdateIndicators();
   
      // Check for trading signals if automatic trading is enabled
      if(UseAutomaticTrading)
         CheckForTradingSignals();
   }
}

//+------------------------------------------------------------------+
//| Update indicator values                                          |
//+------------------------------------------------------------------+
void UpdateIndicators()
{
   // Get current price data - optimized to use smaller buffer in backtest mode
   int barsToRequest = isInBacktest && OptimizationMode ? 20 : 100;
   
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, barsToRequest, priceRates) <= 0)
   {
      if(!OptimizationMode || !isInBacktest)
         Print("Error copying rates data: ", GetLastError());
      return;
   }
   
   // Update T3 indicator values if enabled
   if(UseT3Indicator)
   {
      // Prepare price array based on selected price type - only resize if absolutely necessary
      int ratesSize = ArraySize(priceRates);
      if(ArraySize(priceDataT3) < ratesSize)
         ArrayResize(priceDataT3, ratesSize);
      
      for(int i = 0; i < ratesSize; i++)
      {
         switch(T3_Applied_Price)
         {
            case PRICE_CLOSE:  priceDataT3[i] = priceRates[i].close; break;
            case PRICE_OPEN:   priceDataT3[i] = priceRates[i].open; break;
            case PRICE_HIGH:   priceDataT3[i] = priceRates[i].high; break;
            case PRICE_LOW:    priceDataT3[i] = priceRates[i].low; break;
            case PRICE_MEDIAN: priceDataT3[i] = (priceRates[i].high + priceRates[i].low) / 2; break;
            case PRICE_TYPICAL: priceDataT3[i] = (priceRates[i].high + priceRates[i].low + priceRates[i].close) / 3; break;
            case PRICE_WEIGHTED: priceDataT3[i] = (priceRates[i].high + priceRates[i].low + priceRates[i].close + priceRates[i].open) / 4; break;
            default: priceDataT3[i] = priceRates[i].close;
         }
      }
      
      // Calculate T3 values for positions we need (at least current and previous)
      double t3Value = T3.Calculate(priceDataT3, 0); // Current value
      double prevT3Value = T3.Calculate(priceDataT3, 1); // Previous value
      
      // Store for signal detection
      prevT3 = currT3;
      currT3 = prevT3Value; // Use previous bar for signal confirmation
      
      // Store in buffer (though we're not really using this anymore)
      T3Buffer[0] = t3Value;
      T3Buffer[1] = prevT3Value;
   }
   
   // Update VWAP indicator values if enabled
   if(UseVWAPIndicator)
   {
      // In backtest/optimization mode, always use bar precision for better performance
      bool useTickPrecision = isInBacktest && OptimizationMode ? false : VWAP_UseTickPrecision;
      
      if(useTickPrecision)
      {
         // For tick precision mode, we need to simulate ticks from bar data
         datetime tickTimes[];
         double tickPrices[];
         long tickVolumes[];
         
         int ratesSize = ArraySize(priceRates);
         ArrayResize(tickTimes, ratesSize);
         ArrayResize(tickPrices, ratesSize);
         ArrayResize(tickVolumes, ratesSize);
         
         for(int i = 0; i < ratesSize; i++)
         {
            tickTimes[i] = priceRates[i].time;
            
            // Calculate price based on the selected price type
            switch(VWAP_Price_Type)
            {
               case PRICE_CLOSE:  tickPrices[i] = priceRates[i].close; break;
               case PRICE_OPEN:   tickPrices[i] = priceRates[i].open; break;
               case PRICE_HIGH:   tickPrices[i] = priceRates[i].high; break;
               case PRICE_LOW:    tickPrices[i] = priceRates[i].low; break;
               case PRICE_MEDIAN: tickPrices[i] = (priceRates[i].high + priceRates[i].low) / 2; break;
               case PRICE_TYPICAL: tickPrices[i] = (priceRates[i].high + priceRates[i].low + priceRates[i].close) / 3; break;
               case PRICE_WEIGHTED: tickPrices[i] = (priceRates[i].high + priceRates[i].low + priceRates[i].close + priceRates[i].open) / 4; break;
               default: tickPrices[i] = (priceRates[i].high + priceRates[i].low + priceRates[i].close) / 3;
            }
            
            tickVolumes[i] = priceRates[i].tick_volume > 0 ? priceRates[i].tick_volume : 1;
         }
         
         // Calculate VWAP using tick-level precision with safety check
         SafeCalculateVWAP(tickTimes, tickPrices, tickVolumes, ratesSize);
      }
      else
      {
         // Calculate VWAP using bar-level precision - much faster
         SafeCalculateVWAPOnBar(priceRates, ArraySize(priceRates));
      }
      
      // Update VWAP values for signal detection
      prevVWAPDaily = currVWAPDaily;
      currVWAPDaily = VWAPDailyBuffer[1]; // Use previous bar for signal confirmation
      
      if(VWAP_Timeframe1 != PERIOD_CURRENT)
      {
         prevVWAPTF1 = currVWAPTF1;
         currVWAPTF1 = VWAPTF1Buffer[1];
      }
      
      if(VWAP_Timeframe2 != PERIOD_CURRENT)
      {
         prevVWAPTF2 = currVWAPTF2;
         currVWAPTF2 = VWAPTF2Buffer[1];
      }
      
      if(VWAP_Timeframe3 != PERIOD_CURRENT)
      {
         prevVWAPTF3 = currVWAPTF3;
         currVWAPTF3 = VWAPTF3Buffer[1];
      }
      
      if(VWAP_Timeframe4 != PERIOD_CURRENT)
      {
         prevVWAPTF4 = currVWAPTF4;
         currVWAPTF4 = VWAPTF4Buffer[1];
      }
   }
   
   // We've disabled visualization, but keeping this for compatibility
   // The condition will always be false since we set ShowATRLevels=false in OnInit
   if(ShowATRLevels && !isInBacktest)
      UpdateVisualization();
}

//+------------------------------------------------------------------+
//| Safe wrapper for VWAP calculation to avoid array out of bounds   |
//+------------------------------------------------------------------+
void SafeCalculateVWAP(const datetime &time[], const double &price[], 
                      long &volume[], int data_count)
{
   // First verify the buffer sizes are sufficient
   int bufferSize = ArraySize(VWAPDailyBuffer);
   
   // Ensure all buffers are properly sized
   if(bufferSize < data_count)
   {
      bufferSize = MathMax(bufferSize, data_count);
      ArrayResize(VWAPDailyBuffer, bufferSize);
      ArrayResize(VWAPTF1Buffer, bufferSize);
      ArrayResize(VWAPTF2Buffer, bufferSize);
      ArrayResize(VWAPTF3Buffer, bufferSize);
      ArrayResize(VWAPTF4Buffer, bufferSize);
   }
   
   // For safety during optimization, limit data_count to buffer size
   int safe_count = MathMin(data_count, bufferSize);
   
   // Call the actual VWAP calculation with the safe count
   VWAP.CalculateOnTick(time, price, volume, safe_count,
                       VWAPDailyBuffer, VWAPTF1Buffer, VWAPTF2Buffer, 
                       VWAPTF3Buffer, VWAPTF4Buffer);
}

//+------------------------------------------------------------------+
//| Safe wrapper for VWAP bar calculation to avoid array out of bounds|
//+------------------------------------------------------------------+
void SafeCalculateVWAPOnBar(const MqlRates &rates[], int rates_count)
{
   // First verify the buffer sizes are sufficient
   int bufferSize = ArraySize(VWAPDailyBuffer);
   
   // Ensure all buffers are properly sized
   if(bufferSize < rates_count)
   {
      bufferSize = MathMax(bufferSize, rates_count);
      ArrayResize(VWAPDailyBuffer, bufferSize);
      ArrayResize(VWAPTF1Buffer, bufferSize);
      ArrayResize(VWAPTF2Buffer, bufferSize);
      ArrayResize(VWAPTF3Buffer, bufferSize);
      ArrayResize(VWAPTF4Buffer, bufferSize);
   }
   
   // For safety during optimization, limit rates_count to buffer size
   int safe_count = MathMin(rates_count, bufferSize);
   
   // Call the actual VWAP calculation with the safe count
   VWAP.CalculateOnBar(rates, safe_count, VWAPDailyBuffer, VWAPTF1Buffer, 
                      VWAPTF2Buffer, VWAPTF3Buffer, VWAPTF4Buffer);
}

//+------------------------------------------------------------------+
//| Check for trading signals based on indicators                    |
//+------------------------------------------------------------------+
void CheckForTradingSignals()
{
   // Only check for signals if automatic trading is enabled
   if(!UseAutomaticTrading) return;
   
   // Get current price data
   MqlRates signalRates[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, SignalConfirmationBars + 2, signalRates) <= 0)
   {
      Print("Error copying price data for signal check. Error code: ", GetLastError());
      return;
   }
   ArraySetAsSeries(signalRates, true);
   
   // Initialize signal variables
   bool buySignal = false;
   bool sellSignal = false;
   
   // Check if we're already in a position with this magic number
   bool hasOpenPosition = false;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetTicket(i) > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            hasOpenPosition = true;
            break;
         }
      }
   }
   
   // Only check for signals if we don't have an open position
   if(!hasOpenPosition)
   {
      // T3 crossing VWAP signal
      if(UseT3Indicator && UseVWAPIndicator)
      {
         // Check for bullish crossing (T3 crosses above VWAP)
         if(prevT3 < prevVWAPDaily && currT3 > currVWAPDaily)
         {
            // Confirm with price action
            if(signalRates[1].close > signalRates[1].open && signalRates[2].close > signalRates[2].open)
            {
               buySignal = true;
               Print("BUY Signal: T3 crossed above VWAP with bullish confirmation");
               
               // Apply additional VWAP timeframe filters if enabled
               if(VWAP_Timeframe1 != PERIOD_CURRENT && signalRates[1].close < currVWAPTF1)
                  buySignal = false;
                  
               if(VWAP_Timeframe2 != PERIOD_CURRENT && signalRates[1].close < currVWAPTF2)
                  buySignal = false;
                  
               if(VWAP_Timeframe3 != PERIOD_CURRENT && signalRates[1].close < currVWAPTF3)
                  buySignal = false;
                  
               if(VWAP_Timeframe4 != PERIOD_CURRENT && signalRates[1].close < currVWAPTF4)
                  buySignal = false;
            }
         }
         
         // Check for bearish crossing (T3 crosses below VWAP)
         else if(prevT3 > prevVWAPDaily && currT3 < currVWAPDaily)
         {
            // Confirm with price action
            if(signalRates[1].close < signalRates[1].open && signalRates[2].close < signalRates[2].open)
            {
               sellSignal = true;
               Print("SELL Signal: T3 crossed below VWAP with bearish confirmation");
               
               // Apply additional VWAP timeframe filters if enabled
               if(VWAP_Timeframe1 != PERIOD_CURRENT && signalRates[1].close > currVWAPTF1)
                  sellSignal = false;
                  
               if(VWAP_Timeframe2 != PERIOD_CURRENT && signalRates[1].close > currVWAPTF2)
                  sellSignal = false;
                  
               if(VWAP_Timeframe3 != PERIOD_CURRENT && signalRates[1].close > currVWAPTF3)
                  sellSignal = false;
                  
               if(VWAP_Timeframe4 != PERIOD_CURRENT && signalRates[1].close > currVWAPTF4)
                  sellSignal = false;
            }
         }
      }
      
      // Execute trade if signal is confirmed
      if(buySignal)
      {
         Print("Executing BUY trade based on indicator signals");
         ExecuteTrade(ORDER_TYPE_BUY);
      }
      else if(sellSignal)
      {
         Print("Executing SELL trade based on indicator signals");
         ExecuteTrade(ORDER_TYPE_SELL);
      }
   }
}

//+------------------------------------------------------------------+
//| ChartEvent function - Handle button clicks                       |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Check if this is a button click event
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      Print("Button clicked: ", sparam);
      
      // Check which button was clicked
      if(sparam == BuyButtonName)
      {
         Print("Buy button clicked - executing BUY trade...");
         // Reset button state immediately to avoid double-clicks
         ObjectSetInteger(0, BuyButtonName, OBJPROP_STATE, false);
         ChartRedraw();
         
         // Execute BUY trade
         ExecuteTrade(ORDER_TYPE_BUY);
      }
      else if(sparam == SellButtonName)
      {
         Print("Sell button clicked - executing SELL trade...");
         // Reset button state immediately to avoid double-clicks
         ObjectSetInteger(0, SellButtonName, OBJPROP_STATE, false);
         ChartRedraw();
         
         // Execute SELL trade
         ExecuteTrade(ORDER_TYPE_SELL);
      }
      else if(sparam == ButtonName) // ATR trailing activation button
      {
         Print("ATR trailing button clicked");
         
         // Toggle manual trailing activation
         ManualTrailingActivated = !ManualTrailingActivated;
         
         // Update button color and text based on state
         ObjectSetInteger(0, ButtonName, OBJPROP_COLOR, 
                         ManualTrailingActivated ? ButtonColorActive : ButtonColorInactive);
         ObjectSetString(0, ButtonName, OBJPROP_TEXT, 
                        ManualTrailingActivated ? "Trailing Active" : "Start Trailing");
         
         // Print status message
         Print(ManualTrailingActivated ? "Manual trailing activation enabled" : "Manual trailing activation disabled");
         
         ChartRedraw();
      }
   }
}

//+------------------------------------------------------------------+
//| Create a button on the chart                                     |
//+------------------------------------------------------------------+
void CreateButton(string name, string text, int x, int y, color buttonColor)
{
   // Delete any existing button with the same name to avoid conflicts
   ObjectDelete(0, name);
   
   // Create the button
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
   {
      Print("Error: failed to create button ", name, ". Error code: ", GetLastError());
      return;
   }
   
   // Configure button properties
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 80);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 30);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, buttonColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);  // Make buttons not selectable
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);      // Make buttons visible
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1);          // Put buttons on top
   ObjectSetInteger(0, name, OBJPROP_BACK, false);        // Not in the background
   
   // Log successful button creation
   Print("Button ", name, " created successfully");
   
   // Force chart redraw to ensure button appears
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Execute a trade with proper risk management                       |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
   if(!OptimizationMode || !isInBacktest)
      Print("Starting trade execution for ", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL", " order...");
   
   // Calculate stop loss distance based on ATR
   double stopLossDistance = GetStopLossDistance();
   if(stopLossDistance <= 0)
   {
      if(!OptimizationMode || !isInBacktest)
         Print("ERROR: Could not calculate stop loss distance. Trade aborted.");
      return;
   }
   
   double stopLossPoints = stopLossDistance / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(!OptimizationMode || !isInBacktest)
      Print("Stop loss distance calculated: ", stopLossDistance, " (", stopLossPoints, " points)");
   
   // Get account equity and risk amount in account currency
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (currentRisk / 100.0);
   
   if(!OptimizationMode || !isInBacktest)
      Print("Account equity: $", equity, ", Risk amount ($): ", riskAmount);
   
   // Get current price for order
   double price = SymbolInfoDouble(_Symbol, orderType == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
   
   // Calculate stop loss level based on order type
   double stopLossLevel = (orderType == ORDER_TYPE_BUY) ? 
                          price - stopLossDistance : 
                          price + stopLossDistance;
   
   // Get the minimum allowed stop distance from the broker
   double minStopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   
   // Ensure our stop is at least the minimum distance required by broker
   if(stopLossPoints < minStopLevel)
   {
      stopLossDistance = minStopLevel * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      stopLossPoints = stopLossDistance / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      
      if(orderType == ORDER_TYPE_BUY)
         stopLossLevel = price - stopLossDistance;
      else
         stopLossLevel = price + stopLossDistance;
      
      if(!OptimizationMode || !isInBacktest)
         Print("WARNING: Stop distance adjusted to broker minimum: ", stopLossPoints, " points");
   }
   
   if(!OptimizationMode || !isInBacktest)
      Print("Entry price: ", price, ", Stop loss level: ", stopLossLevel, " (", stopLossPoints, " points)");
   
   // DETERMINE ACCURATE POINT VALUE AND LOT SIZE
   // ---------------------------------------------
   double lotSize = DefaultLot; // Start with default
   
   if(UseACRiskManagement)
   {
      // DETERMINE TRUE FINANCIAL VALUE OF POINTS FOR THIS SYMBOL
      // We use a practical approach: calculate the exact money value of a 1-lot position with 1-point stop
      double testLot = 1.0; // Use 1.0 lot for calculation
      double testPointDistance = 1.0; // 1 point distance
      double testPriceMovement = testPointDistance * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      
      // Get contract specifications
      double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      
      // Calculate how many ticks are in one point
      double ticksPerPoint = pointSize / tickSize;
      
      // Calculate money value of one point for 1.0 lot
      double onePointValue = tickValue * ticksPerPoint;
      
      // Calculate money value of one point for our desired lot size
      double onePointPerLotValue = onePointValue; // Value of one point for 1.0 lot
      
      if(!OptimizationMode || !isInBacktest)
      {
         Print("SYMBOL SPECIFICATIONS:");
         Print("- Contract Size: ", contractSize);
         Print("- Tick Value: ", tickValue);
         Print("- Tick Size: ", tickSize);
         Print("- Point Size: ", pointSize);
         Print("- Ticks per Point: ", ticksPerPoint);
         Print("- Value of ONE POINT for 1.0 lot: $", onePointPerLotValue);
      }
      
      // Calculate lot size to achieve desired risk
      // Formula: lotSize = riskAmount / (stopLossPoints * onePointPerLotValue)
      lotSize = riskAmount / (stopLossPoints * onePointPerLotValue);
      
      if(!OptimizationMode || !isInBacktest)
         Print("LOT SIZE CALCULATION: Risk $ ", riskAmount, 
              " / (", stopLossPoints, " points * $", onePointPerLotValue, " per point per 1.0 lot) = ", lotSize, " lots");
      
      // Get symbol volume constraints for validation
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      
      if(!OptimizationMode || !isInBacktest)
         Print("Symbol volume constraints - Min: ", minLot, ", Max: ", maxLot, ", Step: ", lotStep);
      
      // Round to the nearest lot step and apply constraints
      lotSize = MathFloor(lotSize / lotStep) * lotStep;
      if(lotSize < minLot) lotSize = minLot;
      if(lotSize > maxLot) lotSize = maxLot;
      
      // Re-verify risk with the adjusted lot size
      double actualRiskAmount = lotSize * stopLossPoints * onePointPerLotValue;
      double actualRiskPercent = (actualRiskAmount / equity) * 100.0;
      
      if(!OptimizationMode || !isInBacktest)
      {
         Print("Final lot size after adjustments: ", lotSize);
         Print("Actual risk with this lot size: $", actualRiskAmount, " (", actualRiskPercent, "% of account)");
      }
   }
   else
   {
      if(!OptimizationMode || !isInBacktest)
         Print("Using fixed lot size: ", lotSize, " (AC Risk Management disabled)");
   }
   
   // Calculate take profit based on reward target
   double takeProfitDistance = 0.0;
   double takeProfitLevel = 0.0;
   
   // Calculate take profit based on risk-to-reward ratio and the stop loss distance
   if(UseACRiskManagement)
   {
      double riskToRewardRatio = currentReward / currentRisk;
      // Calculate take profit points based on the R:R ratio
      double takeProfitPoints = stopLossPoints * riskToRewardRatio;
      takeProfitDistance = takeProfitPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      
      if(!OptimizationMode || !isInBacktest)
      {
         Print("TAKE PROFIT CALCULATION:");
         Print("  Stop loss distance: ", stopLossPoints, " points");
         Print("  Risk: ", currentRisk, "%, Reward: ", currentReward, "%");
         Print("  Risk:Reward ratio: 1:", riskToRewardRatio);
         Print("  Take profit distance: ", takeProfitPoints, " points");
      }
   }
   else
   {
      // Use a fixed R:R based on stop loss (default 3:1)
      double takeProfitPoints = stopLossPoints * AC_BaseReward;
      takeProfitDistance = takeProfitPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(!OptimizationMode || !isInBacktest)
         Print("Using fixed R:R ratio of 1:", AC_BaseReward);
   }
   
   if(orderType == ORDER_TYPE_BUY)
      takeProfitLevel = price + takeProfitDistance;
   else
      takeProfitLevel = price - takeProfitDistance;
   
   if(!OptimizationMode || !isInBacktest)
      Print("Take profit level: ", takeProfitLevel);
   
   // Set takeProfitLevel to 0 to disable automatic take profit
   takeProfitLevel = 0;
   if(!OptimizationMode || !isInBacktest)
      Print("Take profit disabled - manual close required");
   
   // Execute the trade
   if(!OptimizationMode || !isInBacktest)
      Print("Executing trade: ", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL", " ", lotSize, " lots @ ", price);
      
   trade.PositionOpen(_Symbol, orderType, lotSize, price, stopLossLevel, takeProfitLevel, TradeComment);
   
   if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      ulong ticket = trade.ResultOrder();
      if(!OptimizationMode || !isInBacktest)
      {
         Print("==== TRADE EXECUTED SUCCESSFULLY ====");
         Print("Order Type: ", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL");
         Print("Lot Size: ", lotSize);
         Print("Entry Price: ", price);
         Print("Stop Loss: ", stopLossLevel, " (", stopLossPoints, " points)");
         Print("Take Profit: DISABLED - close manually when desired");
         if(UseACRiskManagement)
            Print("Risk: ", currentRisk, "%, Target Reward: ", currentReward, "%");
         Print("Ticket #: ", ticket);
         Print("====================================");
      }
      
      // DO NOT force enable trailing as requested by user
      if(!OptimizationMode || !isInBacktest)
         Print("NOTE: Trailing stops are NOT automatically enabled - click the button to activate");
   }
   else
   {
      if(!OptimizationMode || !isInBacktest)
         Print("ERROR: Trade execution failed. Error code: ", trade.ResultRetcode(),
               ", Description: ", trade.ResultComment());
   }
}

//+------------------------------------------------------------------+
//| Update trailing stops for all positions                          |
//+------------------------------------------------------------------+
void UpdateAllTrailingStops()
{
   // In optimization mode, only update trailing stops periodically
   if(isInBacktest && OptimizationMode && lastBarTime != iTime(_Symbol, PERIOD_CURRENT, 0))
      return;
      
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionSelectByTicket(ticket))
      {
         // Only update trailing stops for positions opened by this EA
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            string orderType = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
            double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            
            // Update trailing stop for this position
            UpdateTrailingStop(ticket, entryPrice, orderType);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTester function - required for strategy tester optimization     |
//+------------------------------------------------------------------+
double OnTester()
{
   // Get account statistics
   double profit = TesterStatistics(STAT_PROFIT);
   double drawdown = TesterStatistics(STAT_EQUITYDD_PERCENT);
   double trades = TesterStatistics(STAT_TRADES);
   double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);
   double sharpeRatio = TesterStatistics(STAT_SHARPE_RATIO);
   double recoveryFactor = TesterStatistics(STAT_RECOVERY_FACTOR);
   
   // Skip if no trades were made
   if(trades < 1)
      return 0;
   
   // Return a custom metric for optimization
   // Using a combination of profit factor and recovery factor
   // with penalties for high drawdown
   double metric = profitFactor;
   
   // Apply penalties for high drawdowns
   if(drawdown > 20)
      metric *= 0.8;
   if(drawdown > 30)
      metric *= 0.5;
   
   // Bonus for good recovery factor
   if(recoveryFactor > 2)
      metric *= 1.2;
   
   return metric;
}
