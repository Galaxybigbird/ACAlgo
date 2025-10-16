//+------------------------------------------------------------------+
//|                                       T3_VWAP_TesterScript.mq5 |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.13"
#property strict

// Include necessary libraries
#include <Trade/Trade.mqh>
#include "../Indicators/T3.mqh"
#include "../Indicators/vwap_lite.mqh"

// Define test parameters
input group "==== Test Settings ===="
input int      TestDurationBars = 1000;   // Number of bars to test
input bool     UseTickPrecision = false;  // Enable tick-level precision (more accurate but slower)
input int      TicksPerBar = 100;         // Estimated number of ticks per bar (for tick precision mode)
input bool     VisualMode = true;         // Enable visual testing
input double   InitialDeposit = 10000.0;  // Initial deposit for testing
input bool     EnableDetailedLogs = false;// Enable detailed logs for debug

// T3 Indicator Settings
input group "==== T3 Indicator Settings ===="
input bool     UseT3Indicator = true;      // Use T3 indicator for entry signals
input int      T3Length = 12;              // Period length for T3 calculation
input double   T3Factor = 0.7;             // Volume factor for T3 calculation
input ENUM_APPLIED_PRICE T3_Applied_Price = PRICE_CLOSE; // Price type for T3

// VWAP Indicator Settings
input group "==== VWAP Indicator Settings ===="
input bool     UseVWAPIndicator = true;    // Use VWAP indicator for entry signals
input bool     Enable_Daily_VWAP = true;   // Enable Daily VWAP
input ENUM_TIMEFRAMES VWAP_Timeframe1 = PERIOD_M15;  // Additional VWAP timeframe 1
input ENUM_TIMEFRAMES VWAP_Timeframe2 = PERIOD_H1;   // Additional VWAP timeframe 2
input ENUM_TIMEFRAMES VWAP_Timeframe3 = PERIOD_H4;   // Additional VWAP timeframe 3
input ENUM_TIMEFRAMES VWAP_Timeframe4 = PERIOD_CURRENT; // Additional VWAP timeframe 4
input ENUM_APPLIED_PRICE VWAP_Price_Type = PRICE_CLOSE; // Price type for VWAP

// Signal Settings
input group "==== Signal Settings ===="
input int      SignalConfirmationBars = 2;  // Number of bars to confirm signal
input bool     DrawSignals = true;          // Draw signal arrows on chart

// Global variables
int T3Handle = INVALID_HANDLE;     // Handle for T3 indicator

// Indicator objects
CT3Indicator T3;                   // T3 indicator object
CVWAPIndicator VWAP;               // VWAP indicator object

// Indicator buffers
double T3BufferValues[];           // Buffer for T3 values
double VWAPDailyBuffer[];          // Buffer for VWAP Daily values
double VWAPTF1Buffer[];            // Buffer for VWAP TF1 values
double VWAPTF2Buffer[];            // Buffer for VWAP TF2 values
double VWAPTF3Buffer[];            // Buffer for VWAP TF3 values
double VWAPTF4Buffer[];            // Buffer for VWAP TF4 values

// Test statistics
int totalBuySignals = 0;
int totalSellSignals = 0;
int successfulBuySignals = 0;
int successfulSellSignals = 0;
bool testCompleted = false;

// Price movement statistics
double totalBuyPriceMovement = 0;      // Total price movement in points for buy signals
double totalSellPriceMovement = 0;     // Total price movement in points for sell signals
double maxBuyPriceMovement = 0;        // Maximum price movement in points for buy signals
double maxSellPriceMovement = 0;       // Maximum price movement in points for sell signals
double avgBuyPriceMovement = 0;        // Average price movement in points for buy signals
double avgSellPriceMovement = 0;       // Average price movement in points for sell signals

// Tick-level testing variables
struct TickData {
   datetime time;    // Time of tick
   double price;     // Price of tick
   double volume;    // Volume of tick
   double t3;        // T3 value at this tick
   double vwap;      // VWAP value at this tick
};
TickData tickBuffer[];  // Buffer to store tick data
int totalTicks = 0;     // Total number of ticks processed

// Arrow IDs for visualization
int buyArrowCounter = 0;
int sellArrowCounter = 0;
string buyArrowPrefix = "BuySignal_";
string sellArrowPrefix = "SellSignal_";

// T3 calculation variables (embedded from T3.mq5)
double ema1[], ema2[], ema3[], ema4[], ema5[], ema6[];

// Helper function to get error description
string ErrorDescription(int error_code)
{
   string error_string;
   
   switch(error_code)
   {
      case 4802: return "Custom indicator cannot be created (4802)";
      case 4804: return "Not enough memory for copying indicator string (4804)";
      case 4806: return "Cannot load custom indicator (4806)";
      case 4807: return "Indicator buffer invalid array type (4807)";
      case 4808: return "Wrong index in CopyBuffer function (4808)";
      case 4809: return "Different indicator and buffer dimensions (4809)";
      default: error_string = "Error code " + IntegerToString(error_code);
   }
   
   return error_string;
}

//+------------------------------------------------------------------+
//| Calculate embedded T3 value                                      |
//+------------------------------------------------------------------+
double CalculateT3(double &prices[], int length, double factor, int shift)
{
   // Make sure prices array is set as time-descending
   ArraySetAsSeries(prices, true);
   
   // Allocate memory for EMA arrays if needed
   if(ArraySize(ema1) < length + shift + 10) {
      ArrayResize(ema1, length + shift + 10);
      ArrayResize(ema2, length + shift + 10);
      ArrayResize(ema3, length + shift + 10);
      ArrayResize(ema4, length + shift + 10);
      ArrayResize(ema5, length + shift + 10);
      ArrayResize(ema6, length + shift + 10);
      
      // Set all arrays as time-descending
      ArraySetAsSeries(ema1, true);
      ArraySetAsSeries(ema2, true);
      ArraySetAsSeries(ema3, true);
      ArraySetAsSeries(ema4, true);
      ArraySetAsSeries(ema5, true);
      ArraySetAsSeries(ema6, true);
   }
   
   // Check for valid input data
   if(ArraySize(prices) < length + shift) {
      Print("WARNING: Not enough price data for T3 calculation. Need ", length + shift, " bars, have ", ArraySize(prices));
      return 0.0;
   }
   
   // Simple EMA calculations for the cascaded EMAs
   double alpha = 2.0 / (length + 1.0);
   
   // Calculate first EMA (on the raw price)
   for(int i = shift + length - 1; i >= shift; i--) {
      // For the first EMA, use the selected price as input
      if(i == shift + length - 1)
         ema1[i] = prices[i];
      else
         ema1[i] = alpha * prices[i] + (1 - alpha) * ema1[i+1];
   }
   
   // Calculate second EMA (using first EMA as input)
   for(int i = shift + length - 1; i >= shift; i--) {
      if(i == shift + length - 1)
         ema2[i] = ema1[i];
      else
         ema2[i] = alpha * ema1[i] + (1 - alpha) * ema2[i+1];
   }
   
   // Calculate third EMA (using second EMA as input)
   for(int i = shift + length - 1; i >= shift; i--) {
      if(i == shift + length - 1)
         ema3[i] = ema2[i];
      else
         ema3[i] = alpha * ema2[i] + (1 - alpha) * ema3[i+1];
   }
   
   // Calculate fourth EMA (using third EMA as input)
   for(int i = shift + length - 1; i >= shift; i--) {
      if(i == shift + length - 1)
         ema4[i] = ema3[i];
      else
         ema4[i] = alpha * ema3[i] + (1 - alpha) * ema4[i+1];
   }
   
   // Calculate fifth EMA (using fourth EMA as input)
   for(int i = shift + length - 1; i >= shift; i--) {
      if(i == shift + length - 1)
         ema5[i] = ema4[i];
      else
         ema5[i] = alpha * ema4[i] + (1 - alpha) * ema5[i+1];
   }
   
   // Calculate sixth EMA (using fifth EMA as input)
   for(int i = shift + length - 1; i >= shift; i--) {
      if(i == shift + length - 1)
         ema6[i] = ema5[i];
      else
         ema6[i] = alpha * ema5[i] + (1 - alpha) * ema6[i+1];
   }
   
   // Calculate the T3 coefficients based on the factor
   double c1 = -factor * factor * factor;
   double c2 = 3 * factor * factor + 3 * factor * factor * factor;
   double c3 = -6 * factor * factor - 3 * factor - 3 * factor * factor * factor;
   double c4 = 1 + 3 * factor + factor * factor * factor + 3 * factor * factor;
   
   // Apply the T3 formula
   return c1 * ema6[shift] + c2 * ema5[shift] + c3 * ema4[shift] + c4 * ema3[shift];
}

//+------------------------------------------------------------------+
//| Run all tests on historical data                                 |
//+------------------------------------------------------------------+
void RunTests()
{
   Print("==========================================");
   Print("BEGINNING T3 & VWAP SIGNAL TESTS");
   if(UseTickPrecision) {
      Print("Testing Mode: TICK PRECISION (more accurate)");
   } else {
      Print("Testing Mode: BAR PRECISION (faster)");
   }
   Print("==========================================");
   
   // Get historical price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, TestDurationBars + 10, rates) <= 0) {
      Print("ERROR: Could not get historical price data for testing.");
      return;
   }
   
   Print("Loaded ", ArraySize(rates), " bars of historical data for testing");
   
   // Initialize the T3 and VWAP indicators
   T3.Init(T3Length, T3Factor, T3_Applied_Price, UseTickPrecision);
   
   // Convert PRICE_TYPE for VWAP
   PRICE_TYPE vwapPriceType;
   switch(VWAP_Price_Type) {
      case PRICE_CLOSE: vwapPriceType = CLOSE; break;
      case PRICE_OPEN: vwapPriceType = OPEN; break;
      case PRICE_HIGH: vwapPriceType = HIGH; break;
      case PRICE_LOW: vwapPriceType = LOW; break;
      case PRICE_MEDIAN: vwapPriceType = HIGH_LOW; break;
      case PRICE_TYPICAL: vwapPriceType = CLOSE_HIGH_LOW; break;
      case PRICE_WEIGHTED: vwapPriceType = OPEN_CLOSE_HIGH_LOW; break;
      default: vwapPriceType = CLOSE; break;
   }
   
   VWAP.Init(vwapPriceType, Enable_Daily_VWAP, VWAP_Timeframe1, VWAP_Timeframe2, VWAP_Timeframe3, VWAP_Timeframe4, UseTickPrecision);
   
   // Choose testing mode based on settings
   if(UseTickPrecision) {
      // First generate tick data from historical bars
      if(!GenerateTickData(rates, TicksPerBar)) {
         Print("ERROR: Failed to generate tick data");
         return;
      }
      
      // Calculate indicators on tick data
      if(!CalculateTickIndicators()) {
         Print("ERROR: Failed to calculate tick-level indicators");
         return;
      }
      
      // Process tick data for signals
      ProcessTickSignals();
   } 
   else {
      // Traditional bar-based calculations below
      
      // Calculate T3 values for all bars
      double t3Values[];
      ArrayResize(t3Values, ArraySize(rates));
      ArraySetAsSeries(t3Values, true);
      
      if(UseT3Indicator) {
         // Create price arrays based on selected price type
         double priceArray[];
         ArrayResize(priceArray, ArraySize(rates));
         ArraySetAsSeries(priceArray, true);
         
         // Fill price array
         for(int i = 0; i < ArraySize(rates); i++) {
            switch(T3_Applied_Price) {
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
         
         // Calculate T3 for all bars using our class
         Print("Calculating T3 values for all bars...");
         for(int i = 0; i < ArraySize(rates) - T3Length; i++) {
            t3Values[i] = T3.Calculate(priceArray, i);
            
            // Print occasional progress updates
            if(i % 100 == 0 || i == ArraySize(rates) - T3Length - 1) {
               Print("Processed ", i + 1, " of ", ArraySize(rates) - T3Length, " bars for T3 calculation");
            }
         }
         
         Print("T3 calculation complete");
      }
      
      // Calculate VWAP values if enabled
      double vwapDailyValues[];
      double vwapTF1Values[];
      double vwapTF2Values[];
      double vwapTF3Values[];
      double vwapTF4Values[];
      
      ArrayResize(vwapDailyValues, ArraySize(rates));
      ArrayResize(vwapTF1Values, ArraySize(rates));
      ArrayResize(vwapTF2Values, ArraySize(rates));
      ArrayResize(vwapTF3Values, ArraySize(rates));
      ArrayResize(vwapTF4Values, ArraySize(rates));
      
      ArraySetAsSeries(vwapDailyValues, true);
      ArraySetAsSeries(vwapTF1Values, true);
      ArraySetAsSeries(vwapTF2Values, true);
      ArraySetAsSeries(vwapTF3Values, true);
      ArraySetAsSeries(vwapTF4Values, true);
      
      if(UseVWAPIndicator) {
         Print("Calculating VWAP values for all bars...");
         
         // Calculate VWAP using our class
         VWAP.CalculateOnBar(rates, ArraySize(rates), vwapDailyValues, vwapTF1Values, vwapTF2Values, vwapTF3Values, vwapTF4Values);
         
         Print("VWAP calculation complete");
      }
      
      // Now detect signals by processing the indicator values
      Print("Scanning for T3/VWAP signal patterns...");
      
      // Iterate through historical data and check for signals
      for(int i = SignalConfirmationBars + 3; i < ArraySize(rates) - 1; i++) {
         // For signal detection, we look at the previous bars
         double prevT3 = t3Values[i+1];
         double currT3 = t3Values[i];
         double prevVWAP = vwapDailyValues[i+1];  // Using Daily VWAP for primary signals
         double currVWAP = vwapDailyValues[i];
         
         // Additional VWAP values for filtering if needed
         double currVWAPTF1 = VWAP_Timeframe1 != PERIOD_CURRENT ? vwapTF1Values[i] : 0;
         double currVWAPTF2 = VWAP_Timeframe2 != PERIOD_CURRENT ? vwapTF2Values[i] : 0; 
         double currVWAPTF3 = VWAP_Timeframe3 != PERIOD_CURRENT ? vwapTF3Values[i] : 0;
         double currVWAPTF4 = VWAP_Timeframe4 != PERIOD_CURRENT ? vwapTF4Values[i] : 0;
         
         // Check for T3 crossing VWAP upward (buy signal)
         if(prevT3 < prevVWAP && currT3 > currVWAP) {
            // Confirm with price action
            bool priceConfirmation = rates[i].close > rates[i].open && rates[i+1].close > rates[i+1].open;
            
            // Additional VWAP timeframe filters if enabled
            bool tf1Filter = VWAP_Timeframe1 != PERIOD_CURRENT ? rates[i].close > currVWAPTF1 : true;
            bool tf2Filter = VWAP_Timeframe2 != PERIOD_CURRENT ? rates[i].close > currVWAPTF2 : true;
            bool tf3Filter = VWAP_Timeframe3 != PERIOD_CURRENT ? rates[i].close > currVWAPTF3 : true;
            bool tf4Filter = VWAP_Timeframe4 != PERIOD_CURRENT ? rates[i].close > currVWAPTF4 : true;
            
            if(priceConfirmation && tf1Filter && tf2Filter && tf3Filter && tf4Filter) {
               totalBuySignals++;
               
               // Check if signal was successful (using next bar for testing)
               if(rates[i-1].close > rates[i].close) {
                  successfulBuySignals++;
               }
               
               // Draw arrow on chart if enabled
               if(DrawSignals) {
                  datetime arrowTime = rates[i].time;
                  double arrowPrice = rates[i].low - (50 * _Point);
                  string arrowName = buyArrowPrefix + IntegerToString(buyArrowCounter++);
                  CreateArrow(arrowName, arrowTime, arrowPrice, OBJ_ARROW_BUY, clrLime);
               }
            }
         }
         
         // Check for T3 crossing VWAP downward (sell signal)
         else if(prevT3 > prevVWAP && currT3 < currVWAP) {
            // Confirm with price action
            bool priceConfirmation = rates[i].close < rates[i].open && rates[i+1].close < rates[i+1].open;
            
            // Additional VWAP timeframe filters if enabled
            bool tf1Filter = VWAP_Timeframe1 != PERIOD_CURRENT ? rates[i].close < currVWAPTF1 : true;
            bool tf2Filter = VWAP_Timeframe2 != PERIOD_CURRENT ? rates[i].close < currVWAPTF2 : true;
            bool tf3Filter = VWAP_Timeframe3 != PERIOD_CURRENT ? rates[i].close < currVWAPTF3 : true;
            bool tf4Filter = VWAP_Timeframe4 != PERIOD_CURRENT ? rates[i].close < currVWAPTF4 : true;
            
            if(priceConfirmation && tf1Filter && tf2Filter && tf3Filter && tf4Filter) {
               totalSellSignals++;
               
               // Check if signal was successful (using next bar for testing)
               if(rates[i-1].close < rates[i].close) {
                  successfulSellSignals++;
               }
               
               // Draw arrow on chart if enabled
               if(DrawSignals) {
                  datetime arrowTime = rates[i].time;
                  double arrowPrice = rates[i].high + (50 * _Point);
                  string arrowName = sellArrowPrefix + IntegerToString(sellArrowCounter++);
                  CreateArrow(arrowName, arrowTime, arrowPrice, OBJ_ARROW_SELL, clrRed);
               }
            }
         }
         
         // Print progress occasionally
         if(i % 100 == 0 || i == ArraySize(rates) - 2) {
            Print("Scanned ", i - SignalConfirmationBars - 3 + 1, " of ", 
                  ArraySize(rates) - SignalConfirmationBars - 4, " bars for signals");
         }
      }
   }
   
   // Display test results
   double buySuccessRate = totalBuySignals > 0 ? (successfulBuySignals * 100.0 / totalBuySignals) : 0;
   double sellSuccessRate = totalSellSignals > 0 ? (successfulSellSignals * 100.0 / totalSellSignals) : 0;
   double overallSuccessRate = (totalBuySignals + totalSellSignals) > 0 ? 
      ((successfulBuySignals + successfulSellSignals) * 100.0 / (totalBuySignals + totalSellSignals)) : 0;
   
   Print("==========================================");
   Print("T3 & VWAP SIGNAL TEST RESULTS:");
   Print("==========================================");
   Print("Total Bars Analyzed: ", ArraySize(rates));
   if(UseTickPrecision) {
      Print("Total Ticks Analyzed: ", totalTicks);
      Print("Mode: Tick Precision (", TicksPerBar, " ticks per bar)");
   } else {
      Print("Mode: Bar Precision");
   }
   Print("T3 Length: ", T3Length, ", Factor: ", T3Factor);
   
   // Show VWAP timeframes that are enabled
   string vwapTypeText = Enable_Daily_VWAP ? "Daily" : "";
   if(VWAP_Timeframe1 != PERIOD_CURRENT) vwapTypeText += " " + EnumToString(VWAP_Timeframe1);
   if(VWAP_Timeframe2 != PERIOD_CURRENT) vwapTypeText += " " + EnumToString(VWAP_Timeframe2);
   if(VWAP_Timeframe3 != PERIOD_CURRENT) vwapTypeText += " " + EnumToString(VWAP_Timeframe3);
   if(VWAP_Timeframe4 != PERIOD_CURRENT) vwapTypeText += " " + EnumToString(VWAP_Timeframe4);
   
   Print("VWAP Type: ", vwapTypeText);
   
   Print("------------------------------------------");
   Print("Total Buy Signals: ", totalBuySignals);
   Print("Successful Buy Signals: ", successfulBuySignals, " (", DoubleToString(buySuccessRate, 1), "% successful)");
   if(UseTickPrecision) {
      Print("Average Buy Movement: ", DoubleToString(avgBuyPriceMovement, 1), " points");
      Print("Maximum Buy Movement: ", DoubleToString(maxBuyPriceMovement, 1), " points");
   }
   Print("------------------------------------------");
   Print("Total Sell Signals: ", totalSellSignals);
   Print("Successful Sell Signals: ", successfulSellSignals, " (", DoubleToString(sellSuccessRate, 1), "% successful)");
   if(UseTickPrecision) {
      Print("Average Sell Movement: ", DoubleToString(avgSellPriceMovement, 1), " points");
      Print("Maximum Sell Movement: ", DoubleToString(maxSellPriceMovement, 1), " points");
   }
   Print("------------------------------------------");
   Print("Overall Signals: ", totalBuySignals + totalSellSignals);
   Print("Overall Success Rate: ", DoubleToString(overallSuccessRate, 1), "%");
   Print("==========================================");
   Print("UNIT TEST COMPLETE");
   Print("==========================================");
   
   // Update chart display
   UpdateStatisticsDisplay();
   
   // Mark test as completed
   testCompleted = true;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Clean up any existing objects
   CleanupObjects();
   
   Print("==========================================");
   Print("T3 & VWAP UNIT TESTER STARTING");
   Print("==========================================");
   
   // Create on-screen test label
   CreateLabel("TestLabel", "T3 & VWAP Signal Tester Running", 20, 20, clrWhite, 12);
   
   // Reset statistics
   ResetStatistics();
   
   // Immediately run tests on initialization
   RunTests();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Display final statistics again if tests were completed
   if(testCompleted)
   {
      double buySuccessRate = totalBuySignals > 0 ? (successfulBuySignals * 100.0 / totalBuySignals) : 0;
      double sellSuccessRate = totalSellSignals > 0 ? (successfulSellSignals * 100.0 / totalSellSignals) : 0;
      double overallSuccessRate = (totalBuySignals + totalSellSignals) > 0 ? 
         ((successfulBuySignals + successfulSellSignals) * 100.0 / (totalBuySignals + totalSellSignals)) : 0;
      
      Print("=================================");
      Print("T3 & VWAP FINAL TEST RESULTS:");
      Print("Buy Signals: ", totalBuySignals, ", Success Rate: ", DoubleToString(buySuccessRate, 1), "%");
      Print("Sell Signals: ", totalSellSignals, ", Success Rate: ", DoubleToString(sellSuccessRate, 1), "%");
      Print("Overall Success Rate: ", DoubleToString(overallSuccessRate, 1), "%");
      Print("=================================");
   }
   else
   {
      Print("=================================");
      Print("T3 & VWAP TEST INTERRUPTED");
      Print("=================================");
   }
   
   // Clean up objects
   CleanupObjects();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Nothing to do here - all tests are run at initialization
   
   // Just update the display to show the current status
   static int tickCount = 0;
   if(tickCount++ % 100 == 0) {
      if(testCompleted) {
         // Creating statistics display with final results
         double buySuccessRate = totalBuySignals > 0 ? (successfulBuySignals * 100.0 / totalBuySignals) : 0;
         double sellSuccessRate = totalSellSignals > 0 ? (successfulSellSignals * 100.0 / totalSellSignals) : 0;
         double overallSuccessRate = (totalBuySignals + totalSellSignals) > 0 ? 
            ((successfulBuySignals + successfulSellSignals) * 100.0 / (totalBuySignals + totalSellSignals)) : 0;
         
         // Create/update statistics labels
         string modeText = UseTickPrecision ? "Mode: Tick Precision (" + IntegerToString(TicksPerBar) + " ticks/bar)" : "Mode: Bar Precision";
         
         CreateLabel("TestLabel", "T3 & VWAP Signal Test COMPLETED", 20, 20, clrWhite, 12);
         CreateLabel("ModeLabel", modeText, 20, 40, clrYellow, 10);
         
         CreateLabel("StatsLabel_1", "TEST RESULTS:", 20, 60, clrWhite, 10);
         
         // Base vertical position for signals
         int yPos = 80;
         
         CreateLabel("StatsLabel_2", "Buy Signals: " + IntegerToString(totalBuySignals) + 
                  " (" + DoubleToString(buySuccessRate, 1) + "% successful)", 20, yPos, clrLime, 10);
         yPos += 20;
         
         // Display price movement statistics if in tick precision mode
         if(UseTickPrecision) {
            CreateLabel("StatsLabel_BuyAvg", "Avg Movement: " + DoubleToString(avgBuyPriceMovement, 1) + " pts", 
                        40, yPos, clrLime, 9);
            yPos += 15;
            CreateLabel("StatsLabel_BuyMax", "Max Movement: " + DoubleToString(maxBuyPriceMovement, 1) + " pts", 
                        40, yPos, clrLime, 9);
            yPos += 20;
         } else {
            yPos += 20;
         }
         
         CreateLabel("StatsLabel_3", "Sell Signals: " + IntegerToString(totalSellSignals) + 
                  " (" + DoubleToString(sellSuccessRate, 1) + "% successful)", 20, yPos, clrRed, 10);
         yPos += 20;
         
         // Display price movement statistics if in tick precision mode
         if(UseTickPrecision) {
            CreateLabel("StatsLabel_SellAvg", "Avg Movement: " + DoubleToString(avgSellPriceMovement, 1) + " pts", 
                        40, yPos, clrRed, 9);
            yPos += 15;
            CreateLabel("StatsLabel_SellMax", "Max Movement: " + DoubleToString(maxSellPriceMovement, 1) + " pts", 
                        40, yPos, clrRed, 9);
            yPos += 20;
         } else {
            yPos += 20;
         }
         
         CreateLabel("StatsLabel_4", "Overall Success Rate: " + DoubleToString(overallSuccessRate, 1) + "%", 
                  20, yPos, clrYellow, 10);
                  
         if(UseTickPrecision) {
            yPos += 20;
            CreateLabel("TicksLabel", "Total Ticks Analyzed: " + IntegerToString(totalTicks), 20, yPos, clrWhite, 10);
         }
      }
      else {
         CreateLabel("TestLabel", "T3 & VWAP Signal Test IN PROGRESS...", 20, 20, clrWhite, 12);
         
         if(UseTickPrecision) {
            CreateLabel("ModeLabel", "Mode: Tick Precision", 20, 40, clrYellow, 10);
         } else {
            CreateLabel("ModeLabel", "Mode: Bar Precision", 20, 40, clrYellow, 10);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Reset statistics counters                                        |
//+------------------------------------------------------------------+
void ResetStatistics()
{
   totalBuySignals = 0;
   totalSellSignals = 0;
   successfulBuySignals = 0;
   successfulSellSignals = 0;
   buyArrowCounter = 0;
   sellArrowCounter = 0;
   testCompleted = false;
   
   // Reset price movement statistics
   totalBuyPriceMovement = 0;
   totalSellPriceMovement = 0;
   maxBuyPriceMovement = 0;
   maxSellPriceMovement = 0;
   avgBuyPriceMovement = 0;
   avgSellPriceMovement = 0;
}

//+------------------------------------------------------------------+
//| Create a text label on the chart                                 |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color textColor, int fontSize = 10)
{
   // Delete if exists
   ObjectDelete(0, name);
   
   // Create label
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Create an arrow on the chart                                     |
//+------------------------------------------------------------------+
void CreateArrow(string name, datetime time, double price, ENUM_OBJECT arrowType, color arrowColor)
{
   // Delete if exists
   ObjectDelete(0, name);
   
   // Create arrow
   ObjectCreate(0, name, arrowType, 0, time, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, arrowColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
}

//+------------------------------------------------------------------+
//| Update the statistics display on chart                           |
//+------------------------------------------------------------------+
void UpdateStatisticsDisplay()
{
   // Calculate success rates
   double buySuccessRate = totalBuySignals > 0 ? (successfulBuySignals * 100.0 / totalBuySignals) : 0;
   double sellSuccessRate = totalSellSignals > 0 ? (successfulSellSignals * 100.0 / totalSellSignals) : 0;
   double overallSuccessRate = (totalBuySignals + totalSellSignals) > 0 ? 
      ((successfulBuySignals + successfulSellSignals) * 100.0 / (totalBuySignals + totalSellSignals)) : 0;
   
   // Create/update statistics labels
   CreateLabel("StatsLabel_1", "TEST RESULTS:", 20, 60, clrWhite, 10);
   
   // Show mode of operation
   string modeText = UseTickPrecision ? "Mode: Tick Precision (" + IntegerToString(TicksPerBar) + " ticks/bar)" : "Mode: Bar Precision";
   CreateLabel("StatsLabel_Mode", modeText, 20, 80, clrYellow, 10);
   
   // Show VWAP timeframes that are enabled
   string vwapTypeText = Enable_Daily_VWAP ? "Daily" : "";
   if(VWAP_Timeframe1 != PERIOD_CURRENT) vwapTypeText += " " + EnumToString(VWAP_Timeframe1);
   if(VWAP_Timeframe2 != PERIOD_CURRENT) vwapTypeText += " " + EnumToString(VWAP_Timeframe2);
   if(VWAP_Timeframe3 != PERIOD_CURRENT) vwapTypeText += " " + EnumToString(VWAP_Timeframe3);
   if(VWAP_Timeframe4 != PERIOD_CURRENT) vwapTypeText += " " + EnumToString(VWAP_Timeframe4);
   
   CreateLabel("StatsLabel_VWAP", "VWAP: " + vwapTypeText, 20, 100, clrYellow, 10);
   
   // Base vertical position for signals
   int yPos = 120;
   
   // Show signals
   CreateLabel("StatsLabel_2", "Buy Signals: " + IntegerToString(totalBuySignals) + 
               " (" + DoubleToString(buySuccessRate, 1) + "% successful)", 20, yPos, clrLime, 10);
   yPos += 20;
   
   // Show price movement statistics for buy signals if using tick precision
   if(UseTickPrecision) {
      CreateLabel("StatsLabel_BuyAvg", "Average Movement: " + DoubleToString(avgBuyPriceMovement, 1) + " points", 
                  40, yPos, clrLime, 9);
      yPos += 15;
      CreateLabel("StatsLabel_BuyMax", "Maximum Movement: " + DoubleToString(maxBuyPriceMovement, 1) + " points", 
                  40, yPos, clrLime, 9);
      yPos += 20;
   } else {
      yPos += 20; // Still add some spacing if no movement stats
   }
   
   CreateLabel("StatsLabel_3", "Sell Signals: " + IntegerToString(totalSellSignals) + 
               " (" + DoubleToString(sellSuccessRate, 1) + "% successful)", 20, yPos, clrRed, 10);
   yPos += 20;
   
   // Show price movement statistics for sell signals if using tick precision  
   if(UseTickPrecision) {
      CreateLabel("StatsLabel_SellAvg", "Average Movement: " + DoubleToString(avgSellPriceMovement, 1) + " points", 
                  40, yPos, clrRed, 9);
      yPos += 15;
      CreateLabel("StatsLabel_SellMax", "Maximum Movement: " + DoubleToString(maxSellPriceMovement, 1) + " points", 
                  40, yPos, clrRed, 9);
      yPos += 20;
   } else {
      yPos += 20; // Still add some spacing if no movement stats
   }
   
   CreateLabel("StatsLabel_4", "Overall Success Rate: " + DoubleToString(overallSuccessRate, 1) + "%", 
               20, yPos, clrYellow, 10);
   
   if(testCompleted) {
      CreateLabel("TestLabel", "T3 & VWAP Signal Test COMPLETED", 20, 20, clrWhite, 12);
   } else {
      CreateLabel("TestLabel", "T3 & VWAP Signal Test IN PROGRESS...", 20, 20, clrWhite, 12);
   }
}

//+------------------------------------------------------------------+
//| Clean up all objects created by this EA                          |
//+------------------------------------------------------------------+
void CleanupObjects()
{
   // Delete all test labels
   for(int i = 0; i < 10; i++)
   {
      ObjectDelete(0, "TestLabel" + IntegerToString(i));
      ObjectDelete(0, "StatsLabel_" + IntegerToString(i));
      ObjectDelete(0, "IndicatorLabel_" + IntegerToString(i));
   }
   
   // Delete specific labels
   ObjectDelete(0, "TestLabel");
   ObjectDelete(0, "CrossLabel");
   
   // Delete all buy/sell signal arrows
   for(int i = 0; i < buyArrowCounter; i++)
   {
      ObjectDelete(0, buyArrowPrefix + IntegerToString(i));
   }
   
   for(int i = 0; i < sellArrowCounter; i++)
   {
      ObjectDelete(0, sellArrowPrefix + IntegerToString(i));
   }
   
   // Force chart redraw
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Generate simulated tick data from bar data                       |
//+------------------------------------------------------------------+
bool GenerateTickData(MqlRates &bars[], int ticksPerBar)
{
   Print("Generating simulated tick data from bars...");
   int totalBars = ArraySize(bars);
   
   // Calculate total estimated ticks and resize the buffer
   totalTicks = totalBars * ticksPerBar;
   ArrayResize(tickBuffer, totalTicks);
   
   // Starting index for tick buffer
   int tickIndex = 0;
   
   // Process each bar
   for(int i = totalBars - 1; i >= 0; i--)
   {
      datetime barTime = bars[i].time;
      int secondsPerBar = PeriodSeconds(PERIOD_CURRENT);
      int secondsPerTick = secondsPerBar / ticksPerBar;
      if(secondsPerTick < 1) secondsPerTick = 1;
      
      // Determine price movement pattern within the bar
      double openPrice = bars[i].open;
      double closePrice = bars[i].close;
      double highPrice = bars[i].high;
      double lowPrice = bars[i].low;
      double totalVolume = (double)bars[i].tick_volume;
      double volumePerTick = totalVolume / ticksPerBar;
      
      // Determine if it's a bullish or bearish bar
      bool isBullish = closePrice >= openPrice;
      
      // Create price array for the path within this bar
      double tickPrices[];
      ArrayResize(tickPrices, ticksPerBar);
      
      // Create simple price path simulation
      // This is a simplified model - real tick data would be more random
      for(int t = 0; t < ticksPerBar; t++)
      {
         double progress = (double)t / (ticksPerBar - 1);  // 0.0 to 1.0
         
         // Create a price path that:
         // 1. Starts at open
         // 2. Reaches high/low at some point
         // 3. Ends at close
         // Using a simple quadratic function to make the path realistic
         
         double priceRange = highPrice - lowPrice;
         double midProgress = 0.5;  // When the extreme price (high or low) is reached
         
         // Sigmoid-like function for price path
         double pathValue;
         if(progress < midProgress) {
            // First half: Open to high/low
            pathValue = progress / midProgress;
            pathValue = pathValue * pathValue; // Make it non-linear
         } else {
            // Second half: high/low to close
            pathValue = (progress - midProgress) / (1.0 - midProgress);
            pathValue = 1.0 - (1.0 - pathValue) * (1.0 - pathValue); // Make it non-linear
         }
         
         double price;
         if(isBullish) {
            // For bullish bars: open -> high -> close
            if(progress < midProgress) {
               price = openPrice + (highPrice - openPrice) * pathValue;
            } else {
               price = highPrice - (highPrice - closePrice) * pathValue;
            }
         } else {
            // For bearish bars: open -> low -> close
            if(progress < midProgress) {
               price = openPrice - (openPrice - lowPrice) * pathValue;
            } else {
               price = lowPrice + (closePrice - lowPrice) * pathValue;
            }
         }
         
         // Add some small random noise to make it more realistic
         price += priceRange * 0.05 * (MathRand() / 32767.0 - 0.5);
         
         // Ensure price is within high-low range
         price = MathMin(highPrice, MathMax(lowPrice, price));
         
         // Store the generated price
         tickPrices[t] = price;
         
         // Create tick data
         tickBuffer[tickIndex].time = barTime + t * secondsPerTick;
         tickBuffer[tickIndex].price = price;
         tickBuffer[tickIndex].volume = volumePerTick * (1.0 + 0.5 * (MathRand() / 32767.0 - 0.5)); // Add some volume randomness
         
         // T3 and VWAP will be calculated later
         tickIndex++;
      }
   }
   
   Print("Generated ", tickIndex, " simulated ticks from ", totalBars, " bars");
   
   // If we didn't fill the entire buffer, resize it
   if(tickIndex < totalTicks) {
      totalTicks = tickIndex;
      ArrayResize(tickBuffer, totalTicks);
   }
   
   return totalTicks > 0;
}

//+------------------------------------------------------------------+
//| Calculate T3 and VWAP values for all ticks                       |
//+------------------------------------------------------------------+
bool CalculateTickIndicators()
{
   Print("Calculating T3 and VWAP values for all ticks...");
   
   if(totalTicks <= 0) {
      Print("ERROR: No tick data available");
      return false;
   }
   
   // Arrays for T3 calculation on ticks
   double tickPrices[];
   ArrayResize(tickPrices, totalTicks);
   ArraySetAsSeries(tickPrices, true);
   
   // Fill price array
   for(int i = 0; i < totalTicks; i++) {
      tickPrices[i] = tickBuffer[totalTicks - 1 - i].price; // Note: reversed order for time-descending
   }
   
   // Arrays for VWAP tick calculation
   datetime tickTimes[];
   long tickVolumes[];
   
   ArrayResize(tickTimes, totalTicks);
   ArrayResize(tickVolumes, totalTicks);
   
   // Fill arrays for VWAP calculation
   for(int i = 0; i < totalTicks; i++) {
      tickTimes[i] = tickBuffer[i].time;
      tickVolumes[i] = (long)tickBuffer[i].volume;  // Explicit cast to long
   }
   
   // Calculate T3 for all ticks (if enabled)
   if(UseT3Indicator) {
      Print("Calculating T3 values for all ticks...");
      
      for(int i = 0; i < totalTicks - T3Length; i++) {
         double t3Value = T3.CalculateOnTick(tickPrices, T3Length, T3Factor, i);
         tickBuffer[totalTicks - 1 - i].t3 = t3Value; // Note: reversed index
         
         // Print occasional progress updates
         if(i % 1000 == 0 || i == totalTicks - T3Length - 1) {
            Print("Processed ", i + 1, " of ", totalTicks - T3Length, " ticks for T3 calculation");
         }
      }
      
      Print("T3 calculation complete for tick data");
   }
   
   // Calculate VWAP for all ticks (if enabled)
   if(UseVWAPIndicator) {
      Print("Calculating VWAP values for all ticks...");
      
      // Buffers for VWAP values
      double vwapDailyValues[];
      double vwapTF1Values[];
      double vwapTF2Values[];
      double vwapTF3Values[];
      double vwapTF4Values[];
      
      ArrayResize(vwapDailyValues, totalTicks);
      ArrayResize(vwapTF1Values, totalTicks);
      ArrayResize(vwapTF2Values, totalTicks);
      ArrayResize(vwapTF3Values, totalTicks);
      ArrayResize(vwapTF4Values, totalTicks);
      
      // Calculate VWAP using our class
      VWAP.CalculateOnTick(tickTimes, tickPrices, tickVolumes, totalTicks, 
                          vwapDailyValues, vwapTF1Values, vwapTF2Values, vwapTF3Values, vwapTF4Values);
      
      // Convert values to tick buffer
      for(int i = 0; i < totalTicks; i++) {
         // We use Daily VWAP as the main reference for signals
         tickBuffer[i].vwap = vwapDailyValues[i];
      }
      
      Print("VWAP calculation complete for tick data");
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Process tick data to find signals                                |
//+------------------------------------------------------------------+
void ProcessTickSignals()
{
   Print("Scanning for T3/VWAP signal patterns in tick data...");
   
   // We need at least this many ticks for reliable signal detection
   int minTicksNeeded = T3Length + 10;
   
   if(totalTicks < minTicksNeeded) {
      Print("ERROR: Not enough tick data for signal detection. Need at least ", minTicksNeeded, " ticks.");
      return;
   }
   
   // Keep track of the last signal to avoid duplicate signals too close together
   datetime lastBuySignalTime = 0;
   datetime lastSellSignalTime = 0;
   int minTicksBetweenSignals = TicksPerBar / 2; // At least half a bar between signals
   
   // Define multiple look-ahead periods for measuring price movement
   int shortLookAhead = TicksPerBar / 4;     // 1/4 bar (used for success/fail determination)
   int mediumLookAhead = TicksPerBar / 2;    // 1/2 bar
   int longLookAhead = TicksPerBar;          // 1 full bar
   
   // Calculate VWAP buffers for all timeframes
   double vwapDailyValues[];
   double vwapTF1Values[];
   double vwapTF2Values[];
   double vwapTF3Values[];
   double vwapTF4Values[];
   
   ArrayResize(vwapDailyValues, totalTicks);
   ArrayResize(vwapTF1Values, totalTicks);
   ArrayResize(vwapTF2Values, totalTicks);
   ArrayResize(vwapTF3Values, totalTicks);
   ArrayResize(vwapTF4Values, totalTicks);
   
   // Arrays for VWAP tick calculation
   datetime tickTimes[];
   double tickPrices[];
   long tickVolumes[];  // Change from double to long
   
   ArrayResize(tickTimes, totalTicks);
   ArrayResize(tickPrices, totalTicks);
   ArrayResize(tickVolumes, totalTicks);
   
   // Fill arrays for VWAP calculation
   for(int i = 0; i < totalTicks; i++) {
      tickTimes[i] = tickBuffer[i].time;
      tickPrices[i] = tickBuffer[i].price;
      tickVolumes[i] = (long)tickBuffer[i].volume;  // Explicit cast to long
   }
   
   // Calculate VWAP for each timeframe
   if(UseVWAPIndicator) {
      VWAP.CalculateOnTick(tickTimes, tickPrices, tickVolumes, totalTicks, 
                          vwapDailyValues, vwapTF1Values, vwapTF2Values, vwapTF3Values, vwapTF4Values);
   }
   
   // Scan ticks for signal patterns
   for(int i = minTicksNeeded; i < totalTicks - longLookAhead; i++) {
      // Check for crossing
      double currT3 = tickBuffer[i].t3;
      double currVWAP = vwapDailyValues[i]; // Daily VWAP
      double prevT3 = tickBuffer[i-1].t3;
      double prevVWAP = vwapDailyValues[i-1]; // Daily VWAP
      
      // Get additional VWAP values for filtering if enabled
      double currVWAPTF1 = VWAP_Timeframe1 != PERIOD_CURRENT ? vwapTF1Values[i] : 0;
      double currVWAPTF2 = VWAP_Timeframe2 != PERIOD_CURRENT ? vwapTF2Values[i] : 0;
      double currVWAPTF3 = VWAP_Timeframe3 != PERIOD_CURRENT ? vwapTF3Values[i] : 0;
      double currVWAPTF4 = VWAP_Timeframe4 != PERIOD_CURRENT ? vwapTF4Values[i] : 0;
      
      // We need at least 2 consecutive ticks to confirm a trend direction
      double trend = 0;
      if(i >= minTicksNeeded + 2) {
         // Simple trend calculation: positive for bullish, negative for bearish
         trend = tickBuffer[i].price - tickBuffer[i-2].price;
      }
      
      // T3 crossing VWAP upward (buy signal)
      if(prevT3 < prevVWAP && currT3 > currVWAP) {
         // Additional confirmation: check if price is trending upward
         if(trend > 0) {
            // Apply additional VWAP timeframe filters if enabled
            bool tf1Filter = VWAP_Timeframe1 != PERIOD_CURRENT ? tickBuffer[i].price > currVWAPTF1 : true;
            bool tf2Filter = VWAP_Timeframe2 != PERIOD_CURRENT ? tickBuffer[i].price > currVWAPTF2 : true;
            bool tf3Filter = VWAP_Timeframe3 != PERIOD_CURRENT ? tickBuffer[i].price > currVWAPTF3 : true;
            bool tf4Filter = VWAP_Timeframe4 != PERIOD_CURRENT ? tickBuffer[i].price > currVWAPTF4 : true;
            
            // Avoid duplicate signals and check all filters
            if(i > minTicksBetweenSignals && 
               tickBuffer[i].time - lastBuySignalTime >= PeriodSeconds(PERIOD_CURRENT) &&
               tf1Filter && tf2Filter && tf3Filter && tf4Filter) 
            {
               double entryPrice = tickBuffer[i].price;
               double priceMovementShort = 0;
               double priceMovementMedium = 0;
               double priceMovementLong = 0;
               
               // Only count signal if we have enough data to measure long-term movement
               if(i + longLookAhead < totalTicks) {
                  totalBuySignals++;
                  lastBuySignalTime = tickBuffer[i].time;
                  
                  // Measure price movements at different time horizons
                  priceMovementShort = (tickBuffer[i + shortLookAhead].price - entryPrice) / _Point;
                  priceMovementMedium = (tickBuffer[i + mediumLookAhead].price - entryPrice) / _Point;
                  priceMovementLong = (tickBuffer[i + longLookAhead].price - entryPrice) / _Point;
                  
                  // Check if signal would be successful based on short lookAhead
                  if(priceMovementShort > 0) {
                     successfulBuySignals++;
                  }
                  
                  // Track price movement statistics
                  totalBuyPriceMovement += priceMovementLong; // Use long-term for avg calculation
                  
                  // Update max price movement if this one is larger
                  if(priceMovementLong > maxBuyPriceMovement) {
                     maxBuyPriceMovement = priceMovementLong;
                  }
                  
                  // Draw arrow on chart if enabled
                  if(DrawSignals) {
                     string arrowName = buyArrowPrefix + IntegerToString(buyArrowCounter++);
                     CreateArrow(arrowName, tickBuffer[i].time, tickBuffer[i].price - (10 * _Point), OBJ_ARROW_BUY, clrLime);
                     
                     // Optional: Add text label showing price movement
                     if(EnableDetailedLogs) {
                        string labelName = "PM_" + arrowName;
                        string labelText = DoubleToString(priceMovementLong, 1) + " pts";
                        CreateLabel(labelName, labelText, 0, 0, clrWhite, 8);
                        // Position the label near the arrow
                        ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
                        ObjectSetInteger(0, labelName, OBJPROP_TIME, tickBuffer[i].time);
                        ObjectSetDouble(0, labelName, OBJPROP_PRICE, tickBuffer[i].price - (20 * _Point));
                     }
                  }
               }
            }
         }
      }
      // T3 crossing VWAP downward (sell signal)
      else if(prevT3 > prevVWAP && currT3 < currVWAP) {
         // Additional confirmation: check if price is trending downward
         if(trend < 0) {
            // Apply additional VWAP timeframe filters if enabled
            bool tf1Filter = VWAP_Timeframe1 != PERIOD_CURRENT ? tickBuffer[i].price < currVWAPTF1 : true;
            bool tf2Filter = VWAP_Timeframe2 != PERIOD_CURRENT ? tickBuffer[i].price < currVWAPTF2 : true;
            bool tf3Filter = VWAP_Timeframe3 != PERIOD_CURRENT ? tickBuffer[i].price < currVWAPTF3 : true;
            bool tf4Filter = VWAP_Timeframe4 != PERIOD_CURRENT ? tickBuffer[i].price < currVWAPTF4 : true;
            
            // Avoid duplicate signals and check all filters
            if(i > minTicksBetweenSignals && 
               tickBuffer[i].time - lastSellSignalTime >= PeriodSeconds(PERIOD_CURRENT) &&
               tf1Filter && tf2Filter && tf3Filter && tf4Filter) 
            {
               double entryPrice = tickBuffer[i].price;
               double priceMovementShort = 0;
               double priceMovementMedium = 0;
               double priceMovementLong = 0;
               
               // Only count signal if we have enough data to measure long-term movement
               if(i + longLookAhead < totalTicks) {
                  totalSellSignals++;
                  lastSellSignalTime = tickBuffer[i].time;
                  
                  // For sell signals, we want downward price movement (negative is better)
                  // But we'll store as positive values for consistency in reporting
                  priceMovementShort = (entryPrice - tickBuffer[i + shortLookAhead].price) / _Point;
                  priceMovementMedium = (entryPrice - tickBuffer[i + mediumLookAhead].price) / _Point;
                  priceMovementLong = (entryPrice - tickBuffer[i + longLookAhead].price) / _Point;
                  
                  // Check if signal would be successful based on short lookAhead
                  if(priceMovementShort > 0) {
                     successfulSellSignals++;
                  }
                  
                  // Track price movement statistics
                  totalSellPriceMovement += priceMovementLong;
                  
                  // Update max price movement if this one is larger
                  if(priceMovementLong > maxSellPriceMovement) {
                     maxSellPriceMovement = priceMovementLong;
                  }
                  
                  // Draw arrow on chart if enabled
                  if(DrawSignals) {
                     string arrowName = sellArrowPrefix + IntegerToString(sellArrowCounter++);
                     CreateArrow(arrowName, tickBuffer[i].time, tickBuffer[i].price + (10 * _Point), OBJ_ARROW_SELL, clrRed);
                     
                     // Optional: Add text label showing price movement
                     if(EnableDetailedLogs) {
                        string labelName = "PM_" + arrowName;
                        string labelText = DoubleToString(priceMovementLong, 1) + " pts";
                        CreateLabel(labelName, labelText, 0, 0, clrWhite, 8);
                        // Position the label near the arrow
                        ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
                        ObjectSetInteger(0, labelName, OBJPROP_TIME, tickBuffer[i].time);
                        ObjectSetDouble(0, labelName, OBJPROP_PRICE, tickBuffer[i].price + (20 * _Point));
                     }
                  }
               }
            }
         }
      }
      
      // Print progress occasionally
      if(i % 1000 == 0 || i == totalTicks - longLookAhead - 1) {
         Print("Scanned ", i - minTicksNeeded + 1, " of ", 
               totalTicks - minTicksNeeded - longLookAhead, " ticks for signals");
      }
   }
   
   // Calculate average price movements
   if(totalBuySignals > 0) {
      avgBuyPriceMovement = totalBuyPriceMovement / totalBuySignals;
   }
   if(totalSellSignals > 0) {
      avgSellPriceMovement = totalSellPriceMovement / totalSellSignals;
   }
   
   Print("Tick-level signal detection complete");
   Print("Average price movement for buy signals: ", DoubleToString(avgBuyPriceMovement, 1), " points");
   Print("Maximum price movement for buy signals: ", DoubleToString(maxBuyPriceMovement, 1), " points");
   Print("Average price movement for sell signals: ", DoubleToString(avgSellPriceMovement, 1), " points");
   Print("Maximum price movement for sell signals: ", DoubleToString(maxSellPriceMovement, 1), " points");
} 