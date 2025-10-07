//+------------------------------------------------------------------+
//|                                  TestMainACAlgorithm.mq5         |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.04"
#property strict

// Include necessary libraries
#include "c:/Users/marth/AppData/Roaming/MetaQuotes/Terminal/E62C655ED163FFC555DD40DBEA67E6BB/MQL5/Experts/MainACAlgo/Include/ACFunctions.mqh"
#include "c:/Users/marth/AppData/Roaming/MetaQuotes/Terminal/E62C655ED163FFC555DD40DBEA67E6BB/MQL5/Experts/MainACAlgo/Include/ATRtrailing.mqh"
#include <Trade/Trade.mqh>

CSymbolValidator g_SymbolValidator;

// Global test settings
string testSymbol = "NAS100.s";  // Changed to match the actual test symbol
double testEquity = 10000.0;   // Default test account size
int totalTests = 0;
int passedTests = 0;

// Mock globals used in the main algorithm
CTrade trade;
int MagicNumber = 12345;
double DefaultLot = 0.01;
int Slippage = 20;
string TradeComment = "TEST";
bool UseACRiskManagement = true;
bool hasRun = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!g_SymbolValidator.Init(testSymbol))
   {
      Print("[TestMainACAlgorithm] Failed to initialise symbol validator.");
      return(INIT_FAILED);
   }
   g_SymbolValidator.Refresh();

   // Force specific settings for testing
   gSavedEquity = testEquity;
   
   // Initialize AC risk management
   InitializeACRiskManagement();
   
   // Initialize trade object
   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Set test symbol (need to make sure this symbol is in your Market Watch)
   if(!SymbolSelect(testSymbol, true))
   {
      Print("ERROR: Could not select symbol ", testSymbol, " for testing");
      Print("Please add this symbol to your Market Watch and try again");
      return INIT_FAILED;
   }
   
   Print("=== MAIN ALGORITHM TRADING FUNCTION TEST ===");
   Print("Testing with symbol: ", testSymbol);
   Print("Test equity: $", testEquity);
   
   // Run all tests
   RunAllTests();
   
   // Print summary
   Print("=== TEST SUMMARY ===");
   Print("Total tests: ", totalTests);
   Print("Passed tests: ", passedTests);
   Print("Success rate: ", (totalTests > 0) ? (passedTests * 100.0 / totalTests) : 0, "%");
   
   // Cleanup
   gSavedEquity = 0.0;  // Reset to use actual account equity after tests
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Nothing to clean up
}

//+------------------------------------------------------------------+
//| Run all test cases                                               |
//+------------------------------------------------------------------+
void RunAllTests()
{
   // Test GetStopLossDistance
   TestGetStopLossDistance();
   
   // Test the point value calculation in ExecuteTrade
   TestPointValueCalculation();
   
   // Test lot size calculation
   TestLotSizeCalculation();
   
   // Test trailing stop activation by profit percentage
   TestTrailingActivation();
}

//+------------------------------------------------------------------+
//| Test the GetStopLossDistance function                            |
//+------------------------------------------------------------------+
void TestGetStopLossDistance()
{
   Print("=== TEST: GetStopLossDistance Function ===");
   
   // Since GetStopLossDistance is based on ATR which depends on price data,
   // we can only verify that the function returns a reasonable value
   
   double stopDistance = GetStopLossDistance();
   double stopPoints = stopDistance / SymbolInfoDouble(testSymbol, SYMBOL_POINT);
   
   Print("Symbol: ", testSymbol);
   Print("ATR-based stop loss distance: ", stopDistance, " (", stopPoints, " points)");
   
   totalTests++;
   if(stopDistance > 0 && stopPoints > 0)
   {
      passedTests++;
      Print("TEST PASSED - Stop loss distance is positive");
   }
   else
   {
      Print("TEST FAILED - Stop loss distance should be positive");
   }
   
   Print("");
}

//+------------------------------------------------------------------+
//| Test the point value calculation in ExecuteTrade                 |
//+------------------------------------------------------------------+
void TestPointValueCalculation()
{
   Print("=== TEST: Point Value Calculation ===");
   
   // Get symbol specifications
   double point = SymbolInfoDouble(testSymbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(testSymbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(testSymbol, SYMBOL_TRADE_TICK_VALUE);
   
   // Calculate how many ticks are in one point
   double ticksPerPoint = point / tickSize;
   
   // Calculate money value of one point for 1.0 lot
   double onePointValue = tickValue * ticksPerPoint;
   
   Print("Symbol: ", testSymbol);
   Print("Point: ", point);
   Print("Tick Size: ", tickSize);
   Print("Tick Value: $", tickValue);
   Print("Ticks per Point: ", ticksPerPoint);
   Print("One Point Value (1.0 lot): $", onePointValue);
   
   // Test with different stop loss distances and lot sizes
   double testStopLossPoints[] = {50, 100, 200};
   double testLots[] = {0.01, 0.1, 0.5};
   
   for(int i = 0; i < ArraySize(testStopLossPoints); i++)
   {
      for(int j = 0; j < ArraySize(testLots); j++)
      {
         double stopLossPoints = testStopLossPoints[i];
         double lotSize = testLots[j];
         
         // Calculate expected money at risk
         double expectedRisk = stopLossPoints * onePointValue * lotSize;
         double expectedRiskPercent = (expectedRisk / testEquity) * 100.0;
         
         Print("Test case: ", stopLossPoints, " points stop with ", lotSize, " lots:");
         Print("Expected risk amount: $", expectedRisk);
         Print("Expected risk percent: ", expectedRiskPercent, "%");
         
         // Verify risk calculation
         bool withinLimits = VerifyRiskCalculation(testEquity, lotSize, stopLossPoints, expectedRiskPercent);
         
         totalTests++;
         if(withinLimits)
         {
            passedTests++;
            Print("TEST PASSED - Risk calculation is accurate");
         }
         else
         {
            Print("TEST FAILED - Risk calculation is inaccurate");
         }
         
         Print("");
      }
   }
}

//+------------------------------------------------------------------+
//| Test lot size calculation part of ExecuteTrade                   |
//+------------------------------------------------------------------+
void TestLotSizeCalculation()
{
   Print("=== TEST: Lot Size Calculation ===");
   
   // Set risk percentages for testing
   double riskPercentages[] = {0.5, 1.0, 2.0};
   
   for(int i = 0; i < ArraySize(riskPercentages); i++)
   {
      // Set current risk
      currentRisk = riskPercentages[i];
      
      Print("Test with risk: ", currentRisk, "%");
      
      // Get ATR-based stop loss
      double stopLossDistance = GetStopLossDistance();
      double stopLossPoints = stopLossDistance / SymbolInfoDouble(testSymbol, SYMBOL_POINT);
      
      Print("Stop loss distance: ", stopLossDistance, " (", stopLossPoints, " points)");
      
      // Calculate risk amount
      double riskAmount = testEquity * (currentRisk / 100.0);
      
      // Get symbol specifications
      double point = SymbolInfoDouble(testSymbol, SYMBOL_POINT);
      double tickSize = SymbolInfoDouble(testSymbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(testSymbol, SYMBOL_TRADE_TICK_VALUE);
      double ticksPerPoint = point / tickSize;
      double onePointValue = tickValue * ticksPerPoint;
      
      // Calculate expected lot size
      double expectedLotSize = riskAmount / (stopLossPoints * onePointValue);
      double minLot = SymbolInfoDouble(testSymbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(testSymbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(testSymbol, SYMBOL_VOLUME_STEP);
      
      // Round down to the nearest lot step
      int steps = (int)MathFloor(expectedLotSize / lotStep);
      expectedLotSize = steps * lotStep;
      
      // Apply volume constraints
      if(expectedLotSize < minLot) expectedLotSize = minLot;
      if(expectedLotSize > maxLot) expectedLotSize = maxLot;
      
      Print("Expected lot size: ", expectedLotSize);
      
      // Calculate actual lot size using our function
      double actualLotSize = CalculateLotSize(stopLossDistance);
      
      Print("Actual calculated lot size: ", actualLotSize);
      
      // Verify lot size is close to expected
      double lotSizeTolerance = 0.01; // Increased tolerance for numerical stability
      bool lotSizeCorrect = MathAbs(actualLotSize - expectedLotSize) <= lotSizeTolerance;
      
      totalTests++;
      if(lotSizeCorrect)
      {
         passedTests++;
         Print("TEST PASSED - Lot size calculation is correct");
      }
      else
      {
         Print("TEST FAILED - Lot size calculation differs from expected");
         Print("Difference: ", MathAbs(actualLotSize - expectedLotSize));
      }
      
      // Also verify that the lot size gives the correct risk
      // IMPORTANT: When verifying risk, we need to use the stop points from the calculation,
      // not the raw points from the symbol's point value
      bool riskVerified = VerifyRiskCalculation(testEquity, actualLotSize, stopLossPoints, currentRisk);
      
      totalTests++;
      if(riskVerified)
      {
         passedTests++;
         Print("TEST PASSED - Risk verification with calculated lot size successful");
      }
      else
      {
         Print("TEST FAILED - Risk verification with calculated lot size failed");
      }
      
      Print("");
   }
}

//+------------------------------------------------------------------+
//| Mock of ExecuteTrade function with test hooks                    |
//+------------------------------------------------------------------+
void TestExecuteTrade(ENUM_ORDER_TYPE orderType)
{
   Print("Testing ExecuteTrade for ", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL", " order...");
   
   // Calculate stop loss distance based on ATR
   double stopLossDistance = GetStopLossDistance();
   if(stopLossDistance <= 0)
   {
      Print("ERROR: Could not calculate stop loss distance. Test aborted.");
      return;
   }
   
   double stopLossPoints = stopLossDistance / SymbolInfoDouble(testSymbol, SYMBOL_POINT);
   Print("Stop loss distance calculated: ", stopLossDistance, " (", stopLossPoints, " points)");
   
   // Get account equity and risk amount in account currency
   double equity = testEquity;
   double riskAmount = equity * (currentRisk / 100.0);
   Print("Account equity: $", equity, ", Risk amount ($): ", riskAmount);
   
   // Get current price for order
   double price = SymbolInfoDouble(testSymbol, orderType == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
   
   // Calculate stop loss level based on order type
   double stopLossLevel = (orderType == ORDER_TYPE_BUY) ? 
                        price - stopLossDistance : 
                        price + stopLossDistance;
   
   Print("Entry price: ", price, ", Stop loss level: ", stopLossLevel, " (", stopLossPoints, " points)");
   
   // Get symbol specifications
   double point = SymbolInfoDouble(testSymbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(testSymbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(testSymbol, SYMBOL_TRADE_TICK_VALUE);
   double contractSize = SymbolInfoDouble(testSymbol, SYMBOL_TRADE_CONTRACT_SIZE);
   
   // Calculate how many ticks are in one point
   double ticksPerPoint = point / tickSize;
   
   // Calculate money value of one point for 1.0 lot
   double onePointValue = tickValue * ticksPerPoint;
   
   Print("SYMBOL SPECIFICATIONS:");
   Print("- Contract Size: ", contractSize);
   Print("- Tick Value: ", tickValue);
   Print("- Tick Size: ", tickSize);
   Print("- Point Size: ", point);
   Print("- Ticks per Point: ", ticksPerPoint);
   Print("- Value of ONE POINT for 1.0 lot: $", onePointValue);
   
   // Calculate lot size to achieve desired risk
   double lotSize = UseACRiskManagement ? 
                   CalculateLotSize(stopLossDistance) : 
                   DefaultLot;
   
   Print("Calculated lot size: ", lotSize);
   
   // Verify risk calculation
   bool riskVerified = VerifyRiskCalculation(equity, lotSize, stopLossPoints, currentRisk);
   
   totalTests++;
   if(riskVerified)
   {
      passedTests++;
      Print("TEST PASSED - Final risk verification successful");
   }
   else
   {
      Print("TEST FAILED - Final risk verification failed");
   }
}

//+------------------------------------------------------------------+
//| Test trailing stop activation based on profit percentage         |
//+------------------------------------------------------------------+
void TestTrailingActivation()
{
   Print("=== TEST: Trailing Stop Activation By Profit Percentage ===");
   
   // The TrailingActivationPercent is directly accessed from ATRtrailing.mqh
   Print("Current trailing activation percentage: ", TrailingActivationPercent, "%");
   
   // Get symbol specifications for calculation
   double point = SymbolInfoDouble(testSymbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(testSymbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(testSymbol, SYMBOL_TRADE_TICK_VALUE);
   double ticksPerPoint = point / tickSize;
   double onePointValue = tickValue * ticksPerPoint;
   
   // Test percentages around the activation threshold
   double testPercentages[] = {
      0.25, // Far below threshold (25% of threshold)
      0.5,  // Half of threshold (50% of threshold)
      0.9,  // Just below threshold (90% of threshold)
      0.99, // Very close below threshold (99% of threshold)
      1.0,  // Exactly at threshold (100%)
      1.01, // Just above threshold (101% of threshold)
      1.5,  // Above threshold (150% of threshold)
      2.0   // Double threshold (200% of threshold)
   };
   
   // Test with different lot sizes
   double testLots[] = {0.01, 0.1, 1.0, 5.0};
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   Print("=== Testing with multiple percentages and lot sizes ===");
   Print("Current account balance: $", accountBalance);
   
   for(int i = 0; i < ArraySize(testLots); i++)
   {
      double testLot = testLots[i];
      Print("--- Testing with lot size: ", testLot, " ---");
      
      for(int j = 0; j < ArraySize(testPercentages); j++)
      {
         double testPercent = testPercentages[j];
         
         // Calculate required profit in account currency
         double targetProfit = accountBalance * (testPercent / 100.0);
         
         // Calculate required price move in points
         double requiredPoints = MathAbs(targetProfit / (testLot * onePointValue));
         double priceDifference = requiredPoints * point;
         
         // Test for BUY order
         double entryPrice = SymbolInfoDouble(testSymbol, SYMBOL_ASK);
         double currentPrice = entryPrice + priceDifference; // Simulate price moved up
         
         // Test if trailing should activate
         bool shouldActivate = ShouldActivateTrailing(entryPrice, currentPrice, "BUY", testLot);
         bool expectedResult = (testPercent >= TrailingActivationPercent);
         
         Print("BUY - ", testPercent, "% profit ($", targetProfit, ") with ", testLot, " lot: ", 
               shouldActivate ? "ACTIVATES" : "NO ACTIVATION");
         
         totalTests++;
         if(shouldActivate == expectedResult)
         {
            passedTests++;
            Print("✅ PASS");
         }
         else
         {
            Print("❌ FAIL - Expected: ", expectedResult ? "ACTIVATE" : "NO ACTIVATION");
         }
         
         // Test for SELL order
         entryPrice = SymbolInfoDouble(testSymbol, SYMBOL_BID);
         currentPrice = entryPrice - priceDifference; // Simulate price moved down
         
         // Test if trailing should activate
         shouldActivate = ShouldActivateTrailing(entryPrice, currentPrice, "SELL", testLot);
         
         Print("SELL - ", testPercent, "% profit ($", targetProfit, ") with ", testLot, " lot: ", 
               shouldActivate ? "ACTIVATES" : "NO ACTIVATION");
         
         totalTests++;
         if(shouldActivate == expectedResult)
         {
            passedTests++;
            Print("✅ PASS");
         }
         else
         {
            Print("❌ FAIL - Expected: ", expectedResult ? "ACTIVATE" : "NO ACTIVATION");
         }
      }
   }
   
   // Test extreme edge cases
   Print("");
   Print("=== Testing extreme account percentage cases ===");
   
   // 1. Very small profit (0.01% of account)
   TestTrailingEdgeCaseByAccountPercent(0.01, "Very small profit (0.01% of account)");
   
   // 2. Exactly 0% profit
   TestTrailingEdgeCaseByAccountPercent(0.0, "Zero profit (0% of account)");
   
   // 3. Exactly at threshold
   TestTrailingEdgeCaseByAccountPercent(TrailingActivationPercent, "Exactly at threshold (" + DoubleToString(TrailingActivationPercent, 2) + "% of account)");
   
   // 4. Very large profit (20% of account)
   TestTrailingEdgeCaseByAccountPercent(20.0, "Very large profit (20% of account)");
   
   // 5. Negative profit (loss)
   TestTrailingEdgeCaseByAccountPercent(-0.5, "Negative profit (loss)");
   
   // Test precision at the exact threshold
   Print("");
   Print("=== Precision testing at exact account threshold ===");
   
   double testLot = 1.0;
   
   // Test with exact account %
   double exactPercent = TrailingActivationPercent;
   double targetProfit = accountBalance * (exactPercent / 100.0);
   double pointsNeeded = targetProfit / (testLot * onePointValue);
   
   Print("For exact ", exactPercent, "% profit activation:");
   Print("- Account balance: $", accountBalance);
   Print("- Target profit amount: $", targetProfit);
   Print("- Points needed to reach target: ", pointsNeeded);
   
   // Test the exact point where activation should happen
   double entryPrice = SymbolInfoDouble(testSymbol, SYMBOL_ASK);
   double exactActivationPrice = entryPrice + (pointsNeeded * point);
   
   // Test at precise threshold points
   bool activatesAtExact = ShouldActivateTrailing(entryPrice, exactActivationPrice, "BUY", testLot);
   bool activatesBelowMicro = ShouldActivateTrailing(entryPrice, exactActivationPrice - (point * 0.01), "BUY", testLot);
   bool activatesAboveMicro = ShouldActivateTrailing(entryPrice, exactActivationPrice + (point * 0.01), "BUY", testLot);
   
   Print("At exactly ", exactPercent, "% account profit: ", activatesAtExact ? "ACTIVATES" : "NO ACTIVATION");
   Print("0.01 point below: ", activatesBelowMicro ? "ACTIVATES" : "NO ACTIVATION");
   Print("0.01 point above: ", activatesAboveMicro ? "ACTIVATES" : "NO ACTIVATION");
   
   totalTests += 3;
   if(activatesAtExact && !activatesBelowMicro && activatesAboveMicro)
   {
      passedTests += 3;
      Print("✅ HIGH PRECISION TEST PASSED - Exact activation boundary");
   }
   else
   {
      passedTests += (activatesAtExact ? 1 : 0) + (!activatesBelowMicro ? 1 : 0) + (activatesAboveMicro ? 1 : 0);
      Print("❌ HIGH PRECISION TEST PARTIALLY FAILED - Boundary not exact");
      Print("- Expected: Exact=YES, Below=NO, Above=YES");
      Print("- Actual: Exact=", activatesAtExact ? "YES" : "NO", 
            ", Below=", activatesBelowMicro ? "YES" : "NO", 
            ", Above=", activatesAboveMicro ? "YES" : "NO");
   }
}

//+------------------------------------------------------------------+
//| Helper function to test account percentage edge cases             |
//+------------------------------------------------------------------+
void TestTrailingEdgeCaseByAccountPercent(double accountPercent, string testDescription)
{
   // Get symbol specifications for calculation
   double point = SymbolInfoDouble(testSymbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(testSymbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(testSymbol, SYMBOL_TRADE_TICK_VALUE);
   double ticksPerPoint = point / tickSize;
   double onePointValue = tickValue * ticksPerPoint;
   double testLot = 1.0;
   
   // Calculate required profit in account currency
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double targetProfit = accountBalance * (accountPercent / 100.0);
   
   // Calculate required price move in points
   double requiredPoints = MathAbs(targetProfit / (testLot * onePointValue));
   double priceDifference = requiredPoints * point;
   if(accountPercent < 0) priceDifference = -priceDifference; // For losses
   
   // Handle negative points (losses) for the price calculation
   double entryPrice = SymbolInfoDouble(testSymbol, SYMBOL_ASK);
   double currentPrice = entryPrice + priceDifference; // For BUY
   
   Print("Testing case: ", testDescription);
   Print("- Account balance: $", accountBalance);
   Print("- Profit amount: $", targetProfit);
   Print("- Profit percentage: ", accountPercent, "% of account");
   Print("- Required points: ", requiredPoints);
   
   // Test if trailing should activate
   bool shouldActivate = ShouldActivateTrailing(entryPrice, currentPrice, "BUY", testLot);
   bool expectedResult = (accountPercent >= TrailingActivationPercent); // Compare to activation threshold
   
   Print("- Activation expected: ", expectedResult ? "YES" : "NO");
   Print("- Actual result: ", shouldActivate ? "ACTIVATES" : "NO ACTIVATION");
   
   totalTests++;
   if(shouldActivate == expectedResult)
   {
      passedTests++;
      Print("✅ PASS");
   }
   else
   {
      Print("❌ FAIL");
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!hasRun)
   {
      hasRun = true;
      
      // Run all tests
      TestGetStopLossDistance();
      TestPointValueCalculation();
      TestLotSizeCalculation();
      TestTrailingActivation();
      
      // Print final summary
      Print("=== TEST SUMMARY ===");
      Print("Total tests: ", totalTests);
      Print("Passed tests: ", passedTests);
      Print("Success rate: ", (totalTests > 0) ? (passedTests * 100.0 / totalTests) : 0, "%");
      
      // Finish testing
      ExpertRemove();
   }
}

//+------------------------------------------------------------------+
//| Helper function to print test results                            |
//+------------------------------------------------------------------+
void PrintTestResults()
{
   Print("=== TEST SUMMARY ===");
   Print("Total tests: ", totalTests);
   Print("Passed tests: ", passedTests);
   Print("Success rate: ", (totalTests > 0) ? (passedTests * 100.0 / totalTests) : 0, "%");
} 
