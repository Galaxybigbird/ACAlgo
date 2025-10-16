//+------------------------------------------------------------------+
//|                                   ParameterOptimizationTest.mq5 |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.06"
#property strict

// This script is designed to be used in the MT5 Strategy Tester for optimization
// of T3 and VWAP indicator parameters through backtesting

// Include necessary libraries
#include <Trade/Trade.mqh>
#include "C://Users//marth//AppData//Roaming//MetaQuotes//Terminal//E62C655ED163FFC555DD40DBEA67E6BB//MQL5//Experts//MainACAlgo//Indicators//T3.mqh"
#include "C://Users//marth//AppData//Roaming//MetaQuotes//Terminal//E62C655ED163FFC555DD40DBEA67E6BB//MQL5//Experts//MainACAlgo//Indicators//vwap_lite.mqh"

// Define optimization parameters
input group "==== Optimization Settings ===="
input bool     OptimizeT3 = true;            // Optimize T3 parameters
input bool     OptimizeVWAP = true;          // Optimize VWAP parameters
input int      MinProfit = 10;               // Minimum profit in points for successful trade
input int      MaxLoss = 30;                 // Maximum loss in points before exit

// Position sizing settings
input group "==== Position Settings ===="
input double   LotSize = 0.1;                // Fixed lot size for testing
input int      MaxPositions = 1;             // Maximum number of concurrent positions

// T3 Indicator Settings for Optimization
input group "==== T3 Indicator Settings ===="
input bool     UseT3Indicator = true;        // Use T3 indicator for entry signals
input int      T3_Length = 12;               // Period length for T3 calculation (to optimize)
input double   T3_Factor = 0.7;              // Volume factor for T3 calculation (to optimize)
input ENUM_APPLIED_PRICE T3_Applied_Price = PRICE_CLOSE; // Price type for T3
input bool     T3_UseTickPrecision = false;  // Use tick-level precision for T3 calculations

// VWAP Indicator Settings
input group "==== VWAP Indicator Settings ===="
input bool     UseVWAPIndicator = true;    // Use VWAP indicator for entry signals
input bool     Enable_Daily_VWAP = true;   // Enable Daily VWAP
input ENUM_TIMEFRAMES VWAP_Timeframe1 = PERIOD_M15;   // VWAP Timeframe 1
input ENUM_TIMEFRAMES VWAP_Timeframe2 = PERIOD_H1;    // VWAP Timeframe 2
input ENUM_TIMEFRAMES VWAP_Timeframe3 = PERIOD_H4;    // VWAP Timeframe 3
input ENUM_TIMEFRAMES VWAP_Timeframe4 = PERIOD_D1;    // VWAP Timeframe 4
input ENUM_APPLIED_PRICE VWAP_Price_Type = PRICE_CLOSE; // Price type for VWAP
input bool     VWAP_UseTickPrecision = false; // Enable tick-level precision for VWAP

// Signal Settings
input group "==== Signal Settings ===="
input int      SignalConfirmationBars = 2;   // Number of bars to confirm signal (to optimize)
input bool     RequirePriceConfirmation = true; // Require bullish/bearish candles for confirmation

// Exit Settings
input group "==== Exit Settings ===="
input bool     UseFixedTP = true;            // Use fixed take profit
input int      TakeProfit = 50;              // Fixed take profit in points
input bool     UseFixedSL = true;            // Use fixed stop loss
input int      StopLoss = 30;                // Fixed stop loss in points
input bool     UseTrailingStop = false;      // Use trailing stop
input int      TrailingStop = 20;            // Trailing stop distance in points
input int      MaxBarsInTrade = 20;          // Maximum bars to hold a position

// Test Settings
input group "==== Test Settings ===="
input int      TestBars = 11000;          // Number of historical bars to analyze

// Global variables
CTrade trade;                       // Trade object for executing trades

// Indicator instances
CT3Indicator t3;                    // T3 indicator instance
CVWAPIndicator vwap;                // VWAP indicator instance

// Indicator buffers
double T3Buffer[];                  // Buffer for T3 indicator values
double VWAPDailyBuffer[];           // Buffer for VWAP Daily values
double VWAPTF1Buffer[];              // Buffer for VWAP Timeframe 1 values
double VWAPTF2Buffer[];              // Buffer for VWAP Timeframe 2 values
double VWAPTF3Buffer[];              // Buffer for VWAP Timeframe 3 values
double VWAPTF4Buffer[];              // Buffer for VWAP Timeframe 4 values

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

// Trade tracking variables
int totalTrades = 0;
int winningTrades = 0;
int losingTrades = 0;
double totalProfit = 0;
double totalLoss = 0;
int activePositions = 0;
datetime positionOpenTime[];        // Track when positions were opened
int positionBars[];                 // Track how many bars positions have been open

// Add a flag to track if backtest is completed
bool backtestCompleted = false;

// Add screen display functions and variables
string infoPrefix = "OptTestInfo_";
int labelCounter = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== ParameterOptimizationTest OnInit starting ===");
   
   // Initialize trade object
   trade.SetExpertMagicNumber(12345);
   
   // Initialize T3 indicator
   if(UseT3Indicator)
   {
      // Initialize T3 indicator directly using the class
      t3.Init(T3_Length, T3_Factor, T3_Applied_Price, T3_UseTickPrecision);
      
      // Allocate memory for T3 buffer
      ArraySetAsSeries(T3Buffer, true);
      ArrayResize(T3Buffer, 100);
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
      
      // Initialize VWAP indicator directly using the class
      vwap.Init(priceType, Enable_Daily_VWAP, VWAP_Timeframe1, VWAP_Timeframe2, 
               VWAP_Timeframe3, VWAP_Timeframe4, VWAP_UseTickPrecision);
      
      // Allocate memory for VWAP buffers
      ArraySetAsSeries(VWAPDailyBuffer, true);
      ArraySetAsSeries(VWAPTF1Buffer, true);
      ArraySetAsSeries(VWAPTF2Buffer, true);
      ArraySetAsSeries(VWAPTF3Buffer, true);
      ArraySetAsSeries(VWAPTF4Buffer, true);
      
      ArrayResize(VWAPDailyBuffer, 100);
      ArrayResize(VWAPTF1Buffer, 100);
      ArrayResize(VWAPTF2Buffer, 100);
      ArrayResize(VWAPTF3Buffer, 100);
      ArrayResize(VWAPTF4Buffer, 100);
   }
   
   // Initialize position tracking arrays
   ArrayResize(positionOpenTime, MaxPositions);
   ArrayResize(positionBars, MaxPositions);
   ArrayInitialize(positionOpenTime, 0);
   ArrayInitialize(positionBars, 0);
   
   // Clear the chart of any existing objects
   CleanupObjects();
   
   // Create initial info label
   CreateLabel(infoPrefix + IntegerToString(labelCounter++), 
              "Parameter Optimization Test RUNNING...", 20, 20, clrWhite, 12);
   
   // Run backtest immediately with user-defined number of bars
   RunBacktest(TestBars);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Run backtest on historical data                                 |
//+------------------------------------------------------------------+
void RunBacktest(int testBars)
{
   Print("==========================================");
   Print("BEGINNING PARAMETER OPTIMIZATION BACKTEST");
   Print("T3 Length: ", T3_Length, ", Factor: ", T3_Factor);
   Print("VWAP: Daily=", Enable_Daily_VWAP, 
         ", TF1=", EnumToString(VWAP_Timeframe1), 
         ", TF2=", EnumToString(VWAP_Timeframe2),
         ", TF3=", EnumToString(VWAP_Timeframe3),
         ", TF4=", EnumToString(VWAP_Timeframe4));
   Print("==========================================");
   
   // Get historical data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, testBars, rates) <= 0)
   {
      Print("ERROR: Failed to copy historical data for backtest");
      return;
   }
   
   Print("Processing ", ArraySize(rates), " bars of historical data...");
   
   // Calculate indicators for all bars first
   double t3Values[];
   double vwapDailyValues[];
   double vwapTF1Values[];
   double vwapTF2Values[];
   double vwapTF3Values[];
   double vwapTF4Values[];
   
   ArrayResize(t3Values, ArraySize(rates));
   ArrayResize(vwapDailyValues, ArraySize(rates));
   ArrayResize(vwapTF1Values, ArraySize(rates));
   ArrayResize(vwapTF2Values, ArraySize(rates));
   ArrayResize(vwapTF3Values, ArraySize(rates));
   ArrayResize(vwapTF4Values, ArraySize(rates));
   
   ArraySetAsSeries(t3Values, true);
   ArraySetAsSeries(vwapDailyValues, true);
   ArraySetAsSeries(vwapTF1Values, true);
   ArraySetAsSeries(vwapTF2Values, true);
   ArraySetAsSeries(vwapTF3Values, true);
   ArraySetAsSeries(vwapTF4Values, true);
   
   // Calculate indicators
   if(UseT3Indicator)
   {
      Print("Calculating T3 indicator values...");
      
      // Prepare price array
      double priceArray[];
      ArrayResize(priceArray, ArraySize(rates));
      ArraySetAsSeries(priceArray, true);
      
      // Fill price array
      for(int i = 0; i < ArraySize(rates); i++)
      {
         switch(T3_Applied_Price)
         {
            case PRICE_CLOSE:  priceArray[i] = rates[i].close; break;
            case PRICE_OPEN:   priceArray[i] = rates[i].open; break;
            case PRICE_HIGH:   priceArray[i] = rates[i].high; break;
            case PRICE_LOW:    priceArray[i] = rates[i].low; break;
            case PRICE_MEDIAN: priceArray[i] = (rates[i].high + rates[i].low) / 2; break;
            case PRICE_TYPICAL: priceArray[i] = (rates[i].high + rates[i].low + rates[i].close) / 3; break;
            case PRICE_WEIGHTED: priceArray[i] = (rates[i].high + rates[i].low + rates[i].close + rates[i].open) / 4; break;
            default: priceArray[i] = rates[i].close;
         }
      }
      
      // Calculate T3 values
      for(int i = 0; i < ArraySize(rates) - T3_Length; i++)
      {
         t3Values[i] = t3.Calculate(priceArray, i);
         
         // Print progress occasionally
         if(i % 100 == 0 || i == ArraySize(rates) - T3_Length - 1)
         {
            Print("T3 calculation progress: ", i + 1, " of ", ArraySize(rates) - T3_Length);
         }
      }
   }
   
   if(UseVWAPIndicator)
   {
      Print("Calculating VWAP indicator values...");
      
      // Calculate VWAP values
      if(VWAP_UseTickPrecision)
      {
         // For tick precision, prepare arrays
         datetime timeArray[];
         double priceArray[];
         long volumeArray[];
         
         ArrayResize(timeArray, ArraySize(rates));
         ArrayResize(priceArray, ArraySize(rates));
         ArrayResize(volumeArray, ArraySize(rates));
         
         ArraySetAsSeries(timeArray, true);
         ArraySetAsSeries(priceArray, true);
         ArraySetAsSeries(volumeArray, true);
         
         // Fill arrays
         for(int i = 0; i < ArraySize(rates); i++)
         {
            timeArray[i] = rates[i].time;
            
            // Get price based on selected type
            switch(VWAP_Price_Type)
            {
               case PRICE_CLOSE:  priceArray[i] = rates[i].close; break;
               case PRICE_OPEN:   priceArray[i] = rates[i].open; break;
               case PRICE_HIGH:   priceArray[i] = rates[i].high; break;
               case PRICE_LOW:    priceArray[i] = rates[i].low; break;
               case PRICE_MEDIAN: priceArray[i] = (rates[i].high + rates[i].low) / 2; break;
               case PRICE_TYPICAL: priceArray[i] = (rates[i].high + rates[i].low + rates[i].close) / 3; break;
               case PRICE_WEIGHTED: priceArray[i] = (rates[i].high + rates[i].low + rates[i].close + rates[i].open) / 4; break;
               default: priceArray[i] = rates[i].close;
            }
            
            volumeArray[i] = rates[i].tick_volume;
         }
         
         // Calculate with tick precision
         vwap.CalculateOnTick(timeArray, priceArray, volumeArray, ArraySize(rates),
                             vwapDailyValues, vwapTF1Values, vwapTF2Values, vwapTF3Values, 
                             vwapTF4Values);
      }
      else
      {
         // Calculate with bar precision
         vwap.CalculateOnBar(rates, ArraySize(rates), 
                           vwapDailyValues, vwapTF1Values, vwapTF2Values, vwapTF3Values, 
                           vwapTF4Values);
      }
      
      Print("VWAP calculation complete");
   }
   
   // Now scan for signals
   Print("Scanning for trading signals...");
   
   // Reset statistics
   totalTrades = 0;
   winningTrades = 0;
   losingTrades = 0;
   totalProfit = 0;
   totalLoss = 0;
   
   // Process each bar to find signals
   for(int i = SignalConfirmationBars + 3; i < ArraySize(rates) - 1; i++)
   {
      // Get indicator values for this bar
      double currT3Value = t3Values[i];
      double prevT3Value = t3Values[i+1];
      double currVwapDaily = vwapDailyValues[i];
      double prevVwapDaily = vwapDailyValues[i+1];
      double currVwapTF1 = vwapTF1Values[i];
      double prevVwapTF1 = vwapTF1Values[i+1];
      double currVwapTF2 = vwapTF2Values[i];
      double prevVwapTF2 = vwapTF2Values[i+1];
      double currVwapTF3 = vwapTF3Values[i];
      double prevVwapTF3 = vwapTF3Values[i+1];
      double currVwapTF4 = vwapTF4Values[i];
      double prevVwapTF4 = vwapTF4Values[i+1];
      
      // Check for signals
      bool buySignal = false;
      bool sellSignal = false;
      
      // T3 crossing VWAP upward (buy signal)
      if(prevT3Value < prevVwapDaily && currT3Value > currVwapDaily)
      {
         // Confirm with price action if required
         if(!RequirePriceConfirmation || 
            (rates[i].close > rates[i].open && rates[i+1].close > rates[i+1].open))
         {
            buySignal = true;
         }
      }
      
      // T3 crossing VWAP downward (sell signal)
      else if(prevT3Value > prevVwapDaily && currT3Value < currVwapDaily)
      {
         // Confirm with price action if required
         if(!RequirePriceConfirmation || 
            (rates[i].close < rates[i].open && rates[i+1].close < rates[i+1].open))
         {
            sellSignal = false;
         }
      }
      
      // Additional filter: Check Timeframe 1 VWAP if enabled
      if(VWAP_Timeframe1 != PERIOD_CURRENT)
      {
         // For buy signals, ensure price is above Timeframe 1 VWAP
         if(buySignal && rates[i].close < currVwapTF1)
            buySignal = false;
            
         // For sell signals, ensure price is below Timeframe 1 VWAP
         if(sellSignal && rates[i].close > currVwapTF1)
            sellSignal = false;
      }
      
      // Additional filter: Check Timeframe 2 VWAP if enabled
      if(VWAP_Timeframe2 != PERIOD_CURRENT)
      {
         // For buy signals, ensure price is above Timeframe 2 VWAP
         if(buySignal && rates[i].close < currVwapTF2)
            buySignal = false;
            
         // For sell signals, ensure price is below Timeframe 2 VWAP
         if(sellSignal && rates[i].close > currVwapTF2)
            sellSignal = false;
      }
      
      // Additional filter: Check Timeframe 3 VWAP if enabled
      if(VWAP_Timeframe3 != PERIOD_CURRENT)
      {
         // For buy signals, ensure price is above Timeframe 3 VWAP
         if(buySignal && rates[i].close < currVwapTF3)
            buySignal = false;
            
         // For sell signals, ensure price is below Timeframe 3 VWAP
         if(sellSignal && rates[i].close > currVwapTF3)
            sellSignal = false;
      }
      
      // Additional filter: Check Timeframe 4 VWAP if enabled
      if(VWAP_Timeframe4 != PERIOD_CURRENT)
      {
         // For buy signals, ensure price is above Timeframe 4 VWAP
         if(buySignal && rates[i].close < currVwapTF4)
            buySignal = false;
            
         // For sell signals, ensure price is below Timeframe 4 VWAP
         if(sellSignal && rates[i].close > currVwapTF4)
            sellSignal = false;
      }
      
      // Process signals
      if(buySignal)
      {
         totalTrades++;
         
         // Simulate trade outcome (look ahead a few bars)
         double entryPrice = rates[i].close;
         double maxProfit = 0;
         double maxLoss = 0;
         bool isWinning = false;
         
         // Scan forward bars to see outcome
         for(int j = 1; j <= MaxBarsInTrade && (i-j) >= 0; j++)
         {
            double highPrice = rates[i-j].high;
            double lowPrice = rates[i-j].low;
            
            // Calculate potential profit/loss in points
            double profit = (highPrice - entryPrice) / _Point;
            double loss = (entryPrice - lowPrice) / _Point;
            
            // Update maximum values
            if(profit > maxProfit) maxProfit = profit;
            if(loss > maxLoss) maxLoss = loss;
            
            // Check if take profit would have been hit
            if(UseFixedTP && maxProfit >= TakeProfit)
            {
               isWinning = true;
               break;
            }
            
            // Check if stop loss would have been hit
            if(UseFixedSL && maxLoss >= StopLoss)
            {
               isWinning = false;
               break;
            }
            
            // Alternative success criteria - if price moved in our favor by MinProfit
            if(maxProfit >= MinProfit)
            {
               isWinning = true;
            }
         }
         
         // Update statistics
         if(isWinning)
         {
            winningTrades++;
            totalProfit += maxProfit;
         }
         else
         {
            losingTrades++;
            totalLoss += maxLoss;
         }
      }
      else if(sellSignal)
      {
         totalTrades++;
         
         // Simulate trade outcome (look ahead a few bars)
         double entryPrice = rates[i].close;
         double maxProfit = 0;
         double maxLoss = 0;
         bool isWinning = false;
         
         // Scan forward bars to see outcome
         for(int j = 1; j <= MaxBarsInTrade && (i-j) >= 0; j++)
         {
            double highPrice = rates[i-j].high;
            double lowPrice = rates[i-j].low;
            
            // For sell trades, profit when price goes down
            double profit = (entryPrice - lowPrice) / _Point;
            double loss = (highPrice - entryPrice) / _Point;
            
            // Update maximum values
            if(profit > maxProfit) maxProfit = profit;
            if(loss > maxLoss) maxLoss = loss;
            
            // Check if take profit would have been hit
            if(UseFixedTP && maxProfit >= TakeProfit)
            {
               isWinning = true;
               break;
            }
            
            // Check if stop loss would have been hit
            if(UseFixedSL && maxLoss >= StopLoss)
            {
               isWinning = false;
               break;
            }
            
            // Alternative success criteria - if price moved in our favor by MinProfit
            if(maxProfit >= MinProfit)
            {
               isWinning = true;
            }
         }
         
         // Update statistics
         if(isWinning)
         {
            winningTrades++;
            totalProfit += maxProfit;
         }
         else
         {
            losingTrades++;
            totalLoss += maxLoss;
         }
      }
      
      // Print progress occasionally
      if(i % 100 == 0 || i == ArraySize(rates) - 2)
      {
         Print("Signal scan progress: ", i - SignalConfirmationBars - 3 + 1, " of ", 
               ArraySize(rates) - SignalConfirmationBars - 4);
      }
   }
   
   // Mark backtest as completed
   backtestCompleted = true;
   
   // Display results
   double winRatio = totalTrades > 0 ? ((double)winningTrades / totalTrades) * 100.0 : 0;
   double profitFactor = totalLoss > 0 ? totalProfit / totalLoss : totalProfit;
   
   Print("==========================================");
   Print("PARAMETER OPTIMIZATION BACKTEST RESULTS:");
   Print("==========================================");
   Print("Total Trades: ", totalTrades);
   Print("Winning Trades: ", winningTrades, " (", DoubleToString(winRatio, 1), "%)");
   Print("Losing Trades: ", losingTrades);
   Print("Total Profit: ", DoubleToString(totalProfit, 1), " points");
   Print("Total Loss: ", DoubleToString(totalLoss, 1), " points");
   Print("Profit Factor: ", DoubleToString(profitFactor, 2));
   Print("T3 Parameters: Length=", T3_Length, ", Factor=", T3_Factor);
   Print("VWAP Configuration: Daily=", Enable_Daily_VWAP, 
         ", TF1=", EnumToString(VWAP_Timeframe1), 
         ", TF2=", EnumToString(VWAP_Timeframe2),
         ", TF3=", EnumToString(VWAP_Timeframe3),
         ", TF4=", EnumToString(VWAP_Timeframe4));
   Print("==========================================");
   
   // Update display with results
   UpdateResultsDisplay();
}

//+------------------------------------------------------------------+
//| Clean up objects                                                |
//+------------------------------------------------------------------+
void CleanupObjects()
{
   // Delete all existing objects with our prefix
   for(int i = ObjectsTotal(0, 0, OBJ_LABEL) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_LABEL);
      if(StringFind(name, infoPrefix) == 0)
      {
         ObjectDelete(0, name);
      }
   }
   
   // Reset label counter
   labelCounter = 0;
}

//+------------------------------------------------------------------+
//| Create text label                                               |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int fontSize = 10)
{
   // Delete if already exists
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
      
   // Create label
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Update display with results                                     |
//+------------------------------------------------------------------+
void UpdateResultsDisplay()
{
   // Clean up existing labels
   CleanupObjects();
   
   // Create header
   CreateLabel(infoPrefix + IntegerToString(labelCounter++), 
              "PARAMETER OPTIMIZATION RESULTS", 20, 20, clrWhite, 12);
   
   int yPos = 50;
   
   // T3 settings
   CreateLabel(infoPrefix + IntegerToString(labelCounter++), 
              "T3 Settings: Length=" + IntegerToString(T3_Length) + 
              ", Factor=" + DoubleToString(T3_Factor, 2),
              20, yPos, clrYellow, 10);
   yPos += 20;
   
   // VWAP settings
   string vwapSettings = "VWAP: ";
   if(Enable_Daily_VWAP) vwapSettings += "Daily ";
   
   vwapSettings += EnumToString(VWAP_Timeframe1) + " " +
                  EnumToString(VWAP_Timeframe2) + " " +
                  EnumToString(VWAP_Timeframe3) + " " +
                  EnumToString(VWAP_Timeframe4);
   
   CreateLabel(infoPrefix + IntegerToString(labelCounter++), 
              vwapSettings, 20, yPos, clrYellow, 10);
   yPos += 30;
   
   // Trade statistics
   double winRatio = totalTrades > 0 ? ((double)winningTrades / totalTrades) * 100.0 : 0;
   
   CreateLabel(infoPrefix + IntegerToString(labelCounter++), 
              "Total Trades: " + IntegerToString(totalTrades), 20, yPos, clrWhite, 10);
   yPos += 20;
   
   CreateLabel(infoPrefix + IntegerToString(labelCounter++), 
              "Winning Trades: " + IntegerToString(winningTrades) + 
              " (" + DoubleToString(winRatio, 1) + "%)", 
              20, yPos, clrLime, 10);
   yPos += 20;
   
   CreateLabel(infoPrefix + IntegerToString(labelCounter++), 
              "Losing Trades: " + IntegerToString(losingTrades),
              20, yPos, clrRed, 10);
   yPos += 30;
   
   // Profit metrics
   double profitFactor = totalLoss > 0 ? totalProfit / totalLoss : totalProfit;
   
   CreateLabel(infoPrefix + IntegerToString(labelCounter++), 
              "Total Profit: " + DoubleToString(totalProfit, 1) + " points",
              20, yPos, clrLime, 10);
   yPos += 20;
   
   CreateLabel(infoPrefix + IntegerToString(labelCounter++), 
              "Total Loss: " + DoubleToString(totalLoss, 1) + " points",
              20, yPos, clrRed, 10);
   yPos += 20;
   
   CreateLabel(infoPrefix + IntegerToString(labelCounter++), 
              "Profit Factor: " + DoubleToString(profitFactor, 2),
              20, yPos, clrYellow, 10);
   
   // Force chart redraw
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // If backtest is completed, we don't need to do anything in OnTick
   if(backtestCompleted)
      return;
      
   // If not completed, just run the normal EA logic
   // Update indicator values
   UpdateIndicators();
   
   // Manage existing positions
   ManagePositions();
   
   // Check for and process new trading signals if we have room for positions
   if(activePositions < MaxPositions)
   {
      CheckForTradingSignals();
   }
}

//+------------------------------------------------------------------+
//| Update indicator values                                          |
//+------------------------------------------------------------------+
void UpdateIndicators()
{
   // Get price data for calculations
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 100, rates) <= 0)
   {
      Print("Error copying rates data for indicators. Error: ", GetLastError());
      return;
   }
   
   // Update T3 indicator values if enabled
   if(UseT3Indicator)
   {
      // Prepare price array based on selected price type
      double priceArray[];
      ArraySetAsSeries(priceArray, true);
      ArrayResize(priceArray, ArraySize(rates));
      
      // Fill price array with selected price
      for(int i = 0; i < ArraySize(rates); i++)
      {
         switch(T3_Applied_Price)
         {
            case PRICE_CLOSE:  priceArray[i] = rates[i].close; break;
            case PRICE_OPEN:   priceArray[i] = rates[i].open; break;
            case PRICE_HIGH:   priceArray[i] = rates[i].high; break;
            case PRICE_LOW:    priceArray[i] = rates[i].low; break;
            case PRICE_MEDIAN: priceArray[i] = (rates[i].high + rates[i].low) / 2; break;
            case PRICE_TYPICAL: priceArray[i] = (rates[i].high + rates[i].low + rates[i].close) / 3; break;
            case PRICE_WEIGHTED: priceArray[i] = (rates[i].high + rates[i].low + rates[i].close + rates[i].open) / 4; break;
            default: priceArray[i] = rates[i].close;
         }
      }
      
      // Calculate T3 values
      for(int i = 0; i < 3; i++)
      {
         T3Buffer[i] = t3.Calculate(priceArray, i);
      }
      
      // Update T3 values for signal detection
      prevT3 = currT3;
      currT3 = T3Buffer[1]; // Use previous bar for signal confirmation
   }
   
   // Update VWAP indicator values if enabled
   if(UseVWAPIndicator)
   {
      // Calculate VWAP values - we'll use the class methods directly
      if(VWAP_UseTickPrecision)
      {
         // For tick precision, we need to convert rates to separate arrays
         datetime timeArray[];
         double priceArray[];
         long volumeArray[];
         
         ArraySetAsSeries(timeArray, true);
         ArraySetAsSeries(priceArray, true);
         ArraySetAsSeries(volumeArray, true);
         
         ArrayResize(timeArray, ArraySize(rates));
         ArrayResize(priceArray, ArraySize(rates));
         ArrayResize(volumeArray, ArraySize(rates));
         
         // Convert rates to price/volume arrays
         for(int i = 0; i < ArraySize(rates); i++)
         {
            timeArray[i] = rates[i].time;
            
            // Get price based on selected price type
            switch(VWAP_Price_Type)
            {
               case PRICE_CLOSE:  priceArray[i] = rates[i].close; break;
               case PRICE_OPEN:   priceArray[i] = rates[i].open; break;
               case PRICE_HIGH:   priceArray[i] = rates[i].high; break;
               case PRICE_LOW:    priceArray[i] = rates[i].low; break;
               case PRICE_MEDIAN: priceArray[i] = (rates[i].high + rates[i].low) / 2; break;
               case PRICE_TYPICAL: priceArray[i] = (rates[i].high + rates[i].low + rates[i].close) / 3; break;
               case PRICE_WEIGHTED: priceArray[i] = (rates[i].high + rates[i].low + rates[i].close + rates[i].open) / 4; break;
               default: priceArray[i] = rates[i].close;
            }
            
            volumeArray[i] = rates[i].tick_volume;
         }
         
         // Calculate VWAP with tick precision
         vwap.CalculateOnTick(timeArray, priceArray, volumeArray, ArraySize(rates), 
                             VWAPDailyBuffer, VWAPTF1Buffer, VWAPTF2Buffer, VWAPTF3Buffer, 
                             VWAPTF4Buffer);
      }
      else
      {
         // Calculate with bar precision
         vwap.CalculateOnBar(rates, ArraySize(rates), VWAPDailyBuffer, VWAPTF1Buffer, 
                           VWAPTF2Buffer, VWAPTF3Buffer, VWAPTF4Buffer);
      }
      
      // Update VWAP values for signal detection
      if(Enable_Daily_VWAP)
      {
         prevVWAPDaily = currVWAPDaily;
         currVWAPDaily = VWAPDailyBuffer[1]; // Use previous bar for signal confirmation
      }
      
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
}

//+------------------------------------------------------------------+
//| Check for trading signals based on indicators                    |
//+------------------------------------------------------------------+
void CheckForTradingSignals()
{
   // Get current price data
   MqlRates rates[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, SignalConfirmationBars + 2, rates) <= 0)
   {
      Print("Error copying price data. Error code: ", GetLastError());
      return;
   }
   ArraySetAsSeries(rates, true);
   
   // Initialize signal variables
   bool buySignal = false;
   bool sellSignal = false;
   
   // T3 crossing VWAP signal
   if(UseT3Indicator && UseVWAPIndicator)
   {
      // Check for bullish crossing (T3 crosses above VWAP)
      if(prevT3 < prevVWAPDaily && currT3 > currVWAPDaily)
      {
         // Confirm with price action if required
         if(!RequirePriceConfirmation || 
            (rates[1].close > rates[1].open && rates[2].close > rates[2].open))
         {
            buySignal = true;
         }
      }
      
      // Check for bearish crossing (T3 crosses below VWAP)
      else if(prevT3 > prevVWAPDaily && currT3 < currVWAPDaily)
      {
         // Confirm with price action if required
         if(!RequirePriceConfirmation || 
            (rates[1].close < rates[1].open && rates[2].close < rates[2].open))
         {
            sellSignal = true;
         }
      }
      
      // Additional filter: Check Timeframe 1 VWAP if enabled
      if(VWAP_Timeframe1 != PERIOD_CURRENT)
      {
         // For buy signals, ensure price is above Timeframe 1 VWAP
         if(buySignal && rates[1].close < currVWAPTF1)
            buySignal = false;
            
         // For sell signals, ensure price is below Timeframe 1 VWAP
         if(sellSignal && rates[1].close > currVWAPTF1)
            sellSignal = false;
      }
      
      // Additional filter: Check Timeframe 2 VWAP if enabled
      if(VWAP_Timeframe2 != PERIOD_CURRENT)
      {
         // For buy signals, ensure price is above Timeframe 2 VWAP
         if(buySignal && rates[1].close < currVWAPTF2)
            buySignal = false;
            
         // For sell signals, ensure price is below Timeframe 2 VWAP
         if(sellSignal && rates[1].close > currVWAPTF2)
            sellSignal = false;
      }
      
      // Additional filter: Check Timeframe 3 VWAP if enabled
      if(VWAP_Timeframe3 != PERIOD_CURRENT)
      {
         // For buy signals, ensure price is above Timeframe 3 VWAP
         if(buySignal && rates[1].close < currVWAPTF3)
            buySignal = false;
            
         // For sell signals, ensure price is below Timeframe 3 VWAP
         if(sellSignal && rates[1].close > currVWAPTF3)
            sellSignal = false;
      }
      
      // Additional filter: Check Timeframe 4 VWAP if enabled
      if(VWAP_Timeframe4 != PERIOD_CURRENT)
      {
         // For buy signals, ensure price is above Timeframe 4 VWAP
         if(buySignal && rates[1].close < currVWAPTF4)
            buySignal = false;
            
         // For sell signals, ensure price is below Timeframe 4 VWAP
         if(sellSignal && rates[1].close > currVWAPTF4)
            sellSignal = false;
      }
   }
   
   // Execute trades based on signals
   if(buySignal)
   {
      ExecuteTrade(ORDER_TYPE_BUY);
   }
   else if(sellSignal)
   {
      ExecuteTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Execute a trade                                                  |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
   // Get current price for order
   double price = SymbolInfoDouble(_Symbol, orderType == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
   
   // Calculate stop loss and take profit levels
   double stopLossLevel = 0, takeProfitLevel = 0;
   
   if(UseFixedSL)
   {
      if(orderType == ORDER_TYPE_BUY)
         stopLossLevel = price - (StopLoss * _Point);
      else
         stopLossLevel = price + (StopLoss * _Point);
   }
   
   if(UseFixedTP)
   {
      if(orderType == ORDER_TYPE_BUY)
         takeProfitLevel = price + (TakeProfit * _Point);
      else
         takeProfitLevel = price - (TakeProfit * _Point);
   }
   
   // Open the position
   if(trade.PositionOpen(_Symbol, orderType, LotSize, price, stopLossLevel, takeProfitLevel, "Optimization Test"))
   {
      // Position opened successfully
      Print("Position opened: ", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL", " at ", price);
      
      // Track the position
      positionOpenTime[activePositions] = TimeCurrent();
      positionBars[activePositions] = 0;
      activePositions++;
      
      // Increment total trades count
      totalTrades++;
   }
   else
   {
      // Failed to open position
      Print("Failed to open position. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Manage existing positions (trail stops, check exit conditions)   |
//+------------------------------------------------------------------+
void ManagePositions()
{
   // If no positions, nothing to do
   if(activePositions <= 0) return;
   
   // Get current candle data
   MqlRates rates[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 2, rates) <= 0)
   {
      Print("Error copying rates data for position management. Error: ", GetLastError());
      return;
   }
   ArraySetAsSeries(rates, true);
   
   // Loop through all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      // Select the position
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         // Only manage positions with our magic number
         if(PositionGetInteger(POSITION_MAGIC) == trade.RequestMagic())
         {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double stopLoss = PositionGetDouble(POSITION_SL);
            double takeProfit = PositionGetDouble(POSITION_TP);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            
            // Calculate position age in bars
            int posIndex = FindPositionIndex(openTime);
            if(posIndex >= 0)
            {
               positionBars[posIndex]++;
               
               // Check if position has reached maximum age
               if(positionBars[posIndex] >= MaxBarsInTrade)
               {
                  // Close position due to maximum age
                  if(trade.PositionClose(ticket))
                  {
                     Print("Position closed due to reaching maximum bars: ", MaxBarsInTrade);
                     
                     // Update statistics
                     double profit = PositionGetDouble(POSITION_PROFIT);
                     if(profit >= 0)
                     {
                        winningTrades++;
                        totalProfit += profit;
                     }
                     else
                     {
                        losingTrades++;
                        totalLoss += MathAbs(profit);
                     }
                     
                     // Update position tracking
                     RemovePosition(posIndex);
                     continue;
                  }
               }
            }
            
            // Apply trailing stop if enabled
            if(UseTrailingStop)
            {
               double newStopLoss = 0;
               bool modifyStop = false;
               
               if(posType == POSITION_TYPE_BUY && currentPrice > openPrice)
               {
                  // Calculate new stop loss for buy positions
                  newStopLoss = currentPrice - (TrailingStop * _Point);
                  
                  // Only move stop loss if it's higher than current stop loss
                  if(newStopLoss > stopLoss && stopLoss != 0)
                  {
                     modifyStop = true;
                  }
                  else if(stopLoss == 0) // If no stop loss is set
                  {
                     modifyStop = true;
                  }
               }
               else if(posType == POSITION_TYPE_SELL && currentPrice < openPrice)
               {
                  // Calculate new stop loss for sell positions
                  newStopLoss = currentPrice + (TrailingStop * _Point);
                  
                  // Only move stop loss if it's lower than current stop loss
                  if((newStopLoss < stopLoss || stopLoss == 0) && stopLoss != 0)
                  {
                     modifyStop = true;
                  }
                  else if(stopLoss == 0) // If no stop loss is set
                  {
                     modifyStop = true;
                  }
               }
               
               // Modify stop loss if needed
               if(modifyStop)
               {
                  if(trade.PositionModify(ticket, newStopLoss, takeProfit))
                  {
                     Print("Trailing stop updated for position #", ticket, " to ", newStopLoss);
                  }
               }
            }
         }
      }
   }
   
   // Update activePositions based on actual positions count
   int actualPositions = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) == trade.RequestMagic())
         {
            actualPositions++;
         }
      }
   }
   
   // Reconcile our tracking with actual positions
   if(actualPositions != activePositions)
   {
      // Some positions were closed externally (SL/TP hit)
      activePositions = actualPositions;
   }
}

//+------------------------------------------------------------------+
//| Find the index of a position in our tracking arrays              |
//+------------------------------------------------------------------+
int FindPositionIndex(datetime openTime)
{
   for(int i = 0; i < MaxPositions; i++)
   {
      if(positionOpenTime[i] == openTime)
         return i;
   }
   return -1;  // Not found
}

//+------------------------------------------------------------------+
//| Remove a position from tracking                                  |
//+------------------------------------------------------------------+
void RemovePosition(int index)
{
   if(index >= 0 && index < MaxPositions)
   {
      // Shift all elements after index up by one
      for(int i = index; i < MaxPositions - 1; i++)
      {
         positionOpenTime[i] = positionOpenTime[i+1];
         positionBars[i] = positionBars[i+1];
      }
      
      // Clear the last element
      positionOpenTime[MaxPositions-1] = 0;
      positionBars[MaxPositions-1] = 0;
      
      // Decrement active positions count
      activePositions--;
   }
}

//+------------------------------------------------------------------+
//| Custom optimization criterion                                    |
//| The MT5 strategy tester will use this to rank parameter sets     |
//+------------------------------------------------------------------+
double OnTester()
{
   // Calculate win ratio
   double winRatio = totalTrades > 0 ? ((double)winningTrades / totalTrades) : 0;
   
   // Calculate profit factor
   double profitFactor = totalLoss > 0 ? (totalProfit / totalLoss) : totalProfit;
   
   // Calculate custom score (weighting win ratio and profit factor)
   // You can adjust the weights to prioritize different aspects
   double score = (winRatio * 0.4) + (profitFactor * 0.6);
   
   return score;
} 