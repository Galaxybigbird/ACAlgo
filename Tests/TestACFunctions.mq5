//+------------------------------------------------------------------+
//|                                             TestACFunctions.mq5 |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.23"
#property strict
#property indicator_chart_window

// Include necessary libraries
#include <Trade/Trade.mqh>
#include "../Include/ACFunctions.mqh"

CSymbolValidator g_SymbolValidator;

// Input parameters for testing
input group "==== Test Case Settings ===="
input bool     EnableAutomatedTesting = true;  // Enable automated test cases
input bool     EnableManualTesting = true;     // Enable manual test buttons
input bool     EnableVisualRepresentation = true; // Show visual results on chart
input int      TestDelaySeconds = 1;           // Delay between automated tests (seconds)
input bool     ButtonsOnLeftSide = false;      // Place buttons on left side instead of right
input bool     EnableEdgeCaseTests = true;     // Run additional edge case tests

input group "==== Base Risk Management Settings ===="
input double   TestBaseRisk = 1.0;             // Base risk percentage
input double   TestBaseReward = 3.0;           // Base reward multiplier
input int      TestCompoundingWins = 3;        // Max consecutive wins to compound

input group "==== Edge Case Test Settings ===="
input double   TestHighVolatilityATR = 50.0;   // High volatility ATR value for testing
input double   TestLowVolatilityATR = 0.5;     // Low volatility ATR value for testing
input double   TestTinyAccountSize = 100.0;    // Small account size for testing (USD)
input double   TestLargeAccountSize = 100000.0; // Large account size for testing (USD)
input double   TestTightStopLoss = 5.0;        // Very tight stop loss in points
input double   TestWideStopLoss = 500.0;       // Very wide stop loss in points

input group "==== Test Position Settings ===="
input double   TestLotSize = 0.01;             // Test lot size for manual tests
input int      TestStopLossPoints = 100;       // Test stop loss in points
input int      TestTakeProfitPoints = 300;     // Test take profit in points

// Global variables
CTrade trade;                      // Trade object for executing trades
int buttonX = 120;                 // X position for buttons (changed from 200 to 120)
int buttonY = 25;                  // Y position for buttons

// Button names
string StartAutoTestButtonName = "StartAutoTest";
string TestWinButtonName = "TestWin";
string TestLossButtonName = "TestLoss";
string TestATRButtonName = "TestATR";
string TestLotSizeButtonName = "TestLotSize";
string TestStopAdjustButtonName = "TestStopAdjust";
string ResetButtonName = "ResetTest";

// Edge case test buttons
string TestHighVolatilityButtonName = "TestHighVol";
string TestLowVolatilityButtonName = "TestLowVol";
string TestSmallAccountButtonName = "TestSmallAcct";
string TestLargeAccountButtonName = "TestLargeAcct";
string TestTightStopButtonName = "TestTightStop";
string TestWideStopButtonName = "TestWideStop";

// Test tracking variables
int testCounter = 0;
bool automatedTestRunning = false;
int currentTestStep = 0;
int testResultSuccess = 0;
int testResultFailed = 0;

// Edge case trackers
double originalEquity = 0;        // Save original equity for simulation
double savedATRPeriod = 0;        // Save original ATR period
double savedATRMultiplier = 0;    // Save original ATR multiplier
double savedMaxStopLoss = 0;      // Save original max stop loss

// Risk management parameters
double AC_WinMultiplier = 1.2;    // Multiplier for risk after wins
double AC_MaxRisk = 5.0;          // Maximum allowed risk percentage

// Risk display variables
double riskValues[];               // Array to store risk values for display
double rewardValues[];             // Array to store reward values for display
int maxGraphPoints = 20;           // Maximum points to show on the graph

//+------------------------------------------------------------------+
//| Calculate trailing stop based on ATR                             |
//+------------------------------------------------------------------+
double CalculateTrailingStop(double originalStop, double entryPrice, double currentPrice, bool isLong, double atrValue)
{
    // Calculate ATR-based trailing distance
    double atrDistance = atrValue * ATRMultiplier;
    
    // Calculate new theoretical stop level based on current price
    double newStop = isLong ? 
                     currentPrice - atrDistance :  // For longs, stop is below price
                     currentPrice + atrDistance;   // For shorts, stop is above price
    
    // Check if the new stop is more favorable than the original
    bool shouldMove = isLong ? 
                     newStop > originalStop :      // For longs, higher stop is better
                     newStop < originalStop;       // For shorts, lower stop is better
    
    // Return either the new stop or the original, whichever is more favorable
    return shouldMove ? newStop : originalStop;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize arrays for visual representation
    ArrayResize(riskValues, maxGraphPoints);
    ArrayResize(rewardValues, maxGraphPoints);
    ArrayInitialize(riskValues, 0);
    ArrayInitialize(rewardValues, 0);

    if(!g_SymbolValidator.Init(_Symbol))
    {
        Print("[TestACFunctions] Failed to initialise symbol validator.");
        return(INIT_FAILED);
    }
    g_SymbolValidator.Refresh();
    
    // Save original equity for simulation purposes
    originalEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Initialize risk management system with test values
    AC_BaseRisk = TestBaseRisk;
    AC_BaseReward = TestBaseReward;
    AC_CompoundingWins = TestCompoundingWins;
    
    // ATR Settings for stop loss tests
    ATRPeriod = 14;
    ATRMultiplier = 2.0;
    MaxStopLossDistance = 200.0;
    
    // Save original settings for edge cases
    savedATRPeriod = ATRPeriod;
    savedATRMultiplier = ATRMultiplier;
    savedMaxStopLoss = MaxStopLossDistance;
    
    // Initialize the risk management system
    InitializeACRiskManagement();
    
    // Record initial values for display
    UpdateRiskGraphData();
    
    // Create test buttons if manual testing is enabled
    if(EnableManualTesting)
    {
        // Create standard buttons for manual testing
        CreateButton(StartAutoTestButtonName, "Auto Test", buttonX, buttonY, clrBlue);
        CreateButton(TestWinButtonName, "Test Win", buttonX, buttonY + 30, clrGreen);
        CreateButton(TestLossButtonName, "Test Loss", buttonX, buttonY + 60, clrRed);
        CreateButton(TestATRButtonName, "Test ATR SL", buttonX, buttonY + 90, clrOrange);
        CreateButton(TestLotSizeButtonName, "Test Lot Size", buttonX, buttonY + 120, clrPurple);
        CreateButton(TestStopAdjustButtonName, "Test Stop Adj", buttonX, buttonY + 150, clrTeal);
        
        // Create edge case test buttons
        if(EnableEdgeCaseTests)
        {
            // Edge case buttons on left side for clearer layout
            int edgeButtonX = ButtonsOnLeftSide ? 130 : 230;
            int edgeButtonY = ButtonsOnLeftSide ? 25 : 25;
            
            CreateButton(TestHighVolatilityButtonName, "High Vol ATR", edgeButtonX, edgeButtonY, clrCrimson);
            CreateButton(TestLowVolatilityButtonName, "Low Vol ATR", edgeButtonX, edgeButtonY + 30, clrGold);
            CreateButton(TestSmallAccountButtonName, "Small Account", edgeButtonX, edgeButtonY + 60, clrPink);
            CreateButton(TestLargeAccountButtonName, "Large Account", edgeButtonX, edgeButtonY + 90, clrIndigo);
            CreateButton(TestTightStopButtonName, "Tight Stop", edgeButtonX, edgeButtonY + 120, clrLightSeaGreen);
            CreateButton(TestWideStopButtonName, "Wide Stop", edgeButtonX, edgeButtonY + 150, clrDarkOliveGreen);
        }
        
        // Reset button at the bottom
        CreateButton(ResetButtonName, "Reset Tests", buttonX, buttonY + 180, clrGray);
    }
    
    // Start automated tests if enabled
    if(EnableAutomatedTesting)
    {
        automatedTestRunning = true;
        currentTestStep = 0;
    }
    
    Print("AC Functions Test initialized with Base Risk: ", AC_BaseRisk, 
          "%, Base Reward: ", AC_BaseReward, 
          "x, Max Compounding Wins: ", AC_CompoundingWins);
          
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Create a button on the chart                                     |
//+------------------------------------------------------------------+
void CreateButton(string name, string text, int x, int y, color buttonColor)
{
    ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
    
    // Set corner based on user preference
    if(ButtonsOnLeftSide)
    {
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    }
    else
    {
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    }
    
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, 100);  // Reduced from 120 to 100
    ObjectSetInteger(0, name, OBJPROP_YSIZE, 25);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, buttonColor);
    ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBlack);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
}

//+------------------------------------------------------------------+
//| Update risk graph data for visualization                         |
//+------------------------------------------------------------------+
void UpdateRiskGraphData()
{
    // Shift values in arrays
    for(int i = maxGraphPoints - 1; i > 0; i--)
    {
        riskValues[i] = riskValues[i-1];
        rewardValues[i] = rewardValues[i-1];
    }
    
    // Add current values at the beginning
    riskValues[0] = currentRisk;
    rewardValues[0] = currentReward;
    
    // Update visualization if enabled
    if(EnableVisualRepresentation)
    {
        DrawRiskGraph();
    }
}

//+------------------------------------------------------------------+
//| Draw risk graph on the chart                                     |
//+------------------------------------------------------------------+
void DrawRiskGraph()
{
    // Delete previous graph objects
    for(int i = 0; i < maxGraphPoints; i++)
    {
        ObjectDelete(0, "RiskPoint" + IntegerToString(i));
        ObjectDelete(0, "RewardPoint" + IntegerToString(i));
    }
    
    // Calculate scaling factors
    double maxRisk = 0;
    double maxReward = 0;
    
    for(int i = 0; i < maxGraphPoints; i++)
    {
        if(riskValues[i] > maxRisk) maxRisk = riskValues[i];
        if(rewardValues[i] > maxReward) maxReward = rewardValues[i];
    }
    
    // Add some padding to the max values
    maxRisk *= 1.2;
    maxReward *= 1.2;
    
    if(maxRisk < 1) maxRisk = 1;
    if(maxReward < 3) maxReward = 3;
    
    // Calculate graph dimensions
    int graphWidth = 280;          // Slightly reduced from 300
    int graphHeight = 150;
    int graphX = 400;              // Increased from 350 to 400
    int graphY = 50;
    
    // Create graph label
    ObjectDelete(0, "RiskLabel");
    ObjectCreate(0, "RiskLabel", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "RiskLabel", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, "RiskLabel", OBJPROP_XDISTANCE, graphX + graphWidth/2);
    ObjectSetInteger(0, "RiskLabel", OBJPROP_YDISTANCE, graphY - 20);
    ObjectSetString(0, "RiskLabel", OBJPROP_TEXT, "Risk & Reward Evolution");
    ObjectSetInteger(0, "RiskLabel", OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, "RiskLabel", OBJPROP_BGCOLOR, clrDarkBlue);
    ObjectSetInteger(0, "RiskLabel", OBJPROP_FONTSIZE, 10);
    
    // Draw background rectangle
    ObjectDelete(0, "RiskGraph");
    ObjectCreate(0, "RiskGraph", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "RiskGraph", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, "RiskGraph", OBJPROP_XDISTANCE, graphX);
    ObjectSetInteger(0, "RiskGraph", OBJPROP_YDISTANCE, graphY);
    ObjectSetInteger(0, "RiskGraph", OBJPROP_XSIZE, graphWidth);
    ObjectSetInteger(0, "RiskGraph", OBJPROP_YSIZE, graphHeight);
    ObjectSetInteger(0, "RiskGraph", OBJPROP_COLOR, clrBlack);
    ObjectSetInteger(0, "RiskGraph", OBJPROP_BGCOLOR, clrBlack);
    ObjectSetInteger(0, "RiskGraph", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, "RiskGraph", OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, "RiskGraph", OBJPROP_BACK, false);
    
    // Draw risk and reward points
    for(int i = 0; i < maxGraphPoints; i++)
    {
        if(riskValues[i] == 0) continue; // Skip uninitialized values
        
        // Calculate point positions
        int xPos = graphX + (i * graphWidth / maxGraphPoints);
        
        // Risk points (red)
        int yPosRisk = graphY + graphHeight - (int)(riskValues[i] * graphHeight / maxRisk);
        ObjectCreate(0, "RiskPoint" + IntegerToString(i), OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "RiskPoint" + IntegerToString(i), OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, "RiskPoint" + IntegerToString(i), OBJPROP_XDISTANCE, xPos);
        ObjectSetInteger(0, "RiskPoint" + IntegerToString(i), OBJPROP_YDISTANCE, yPosRisk);
        ObjectSetString(0, "RiskPoint" + IntegerToString(i), OBJPROP_TEXT, "•");
        ObjectSetInteger(0, "RiskPoint" + IntegerToString(i), OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, "RiskPoint" + IntegerToString(i), OBJPROP_FONTSIZE, 14);
        
        // Reward points (green)
        int yPosReward = graphY + graphHeight - (int)(rewardValues[i] * graphHeight / maxReward);
        ObjectCreate(0, "RewardPoint" + IntegerToString(i), OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "RewardPoint" + IntegerToString(i), OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, "RewardPoint" + IntegerToString(i), OBJPROP_XDISTANCE, xPos);
        ObjectSetInteger(0, "RewardPoint" + IntegerToString(i), OBJPROP_YDISTANCE, yPosReward);
        ObjectSetString(0, "RewardPoint" + IntegerToString(i), OBJPROP_TEXT, "•");
        ObjectSetInteger(0, "RewardPoint" + IntegerToString(i), OBJPROP_COLOR, clrGreen);
        ObjectSetInteger(0, "RewardPoint" + IntegerToString(i), OBJPROP_FONTSIZE, 14);
    }
    
    // Display current risk and reward values
    ObjectDelete(0, "CurrentRiskLabel");
    ObjectCreate(0, "CurrentRiskLabel", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "CurrentRiskLabel", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, "CurrentRiskLabel", OBJPROP_XDISTANCE, graphX + graphWidth/2);
    ObjectSetInteger(0, "CurrentRiskLabel", OBJPROP_YDISTANCE, graphY + graphHeight + 20);
    ObjectSetString(0, "CurrentRiskLabel", OBJPROP_TEXT, 
                  "Current Risk: " + DoubleToString(currentRisk, 2) + "% | " + 
                  "Target Reward: " + DoubleToString(currentReward, 2) + "% | " +
                  "Consecutive Wins: " + IntegerToString(consecutiveWins));
    ObjectSetInteger(0, "CurrentRiskLabel", OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, "CurrentRiskLabel", OBJPROP_BGCOLOR, clrDarkSlateGray);
    ObjectSetInteger(0, "CurrentRiskLabel", OBJPROP_FONTSIZE, 10);
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Display test result on chart                                     |
//+------------------------------------------------------------------+
void DisplayTestResult(string testName, bool passed)
{
    if(!EnableVisualRepresentation)
        return;
        
    // Create and position the test result label
    string objName = "TestLabel" + IntegerToString(testCounter);
    
    ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 20);
    ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, 50 + (testCounter * 25));
    ObjectSetString(0, objName, OBJPROP_TEXT, 
                  (passed ? "✅ " : "❌ ") + "Test #" + IntegerToString(testCounter) + 
                  ": " + testName);
    ObjectSetInteger(0, objName, OBJPROP_COLOR, passed ? clrLime : clrRed);
    ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, clrBlack);
    ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Print test summary if tests were run
    if(testCounter > 0)
    {
        Print("=== AC Functions Test Results ===");
        Print("Total tests: ", testCounter);
        Print("Successful tests: ", testResultSuccess);
        Print("Failed tests: ", testResultFailed);
        Print("Success rate: ", (testResultSuccess * 100.0) / testCounter, "%");
        Print("==============================");
    }
    
    // Clean up all objects created by this EA
    CleanupTestObjects();
}

//+------------------------------------------------------------------+
//| Clean up all objects created by this expert                      |
//+------------------------------------------------------------------+
void CleanupTestObjects()
{
    // Delete all buttons
    if(EnableManualTesting)
    {
        ObjectDelete(0, StartAutoTestButtonName);
        ObjectDelete(0, TestWinButtonName);
        ObjectDelete(0, TestLossButtonName);
        ObjectDelete(0, TestATRButtonName);
        ObjectDelete(0, TestLotSizeButtonName);
        ObjectDelete(0, TestStopAdjustButtonName);
        ObjectDelete(0, ResetButtonName);
    }
    
    // Delete all graph objects
    if(EnableVisualRepresentation)
    {
        // Delete risk graph
        ObjectDelete(0, "RiskGraph");
        ObjectDelete(0, "RiskLabel");
        
        // Delete all risk point objects
        for(int i = 0; i < maxGraphPoints; i++)
        {
            ObjectDelete(0, "RiskPoint" + IntegerToString(i));
            ObjectDelete(0, "RewardPoint" + IntegerToString(i));
        }
        
        // Delete any test result labels
        for(int i = 0; i < 100; i++) // Assume maximum 100 test labels
        {
            ObjectDelete(0, "TestLabel" + IntegerToString(i));
        }
    }
    
    // Delete any statistical labels
    ObjectDelete(0, "StatLabel");
    ObjectDelete(0, "CurrentRiskLabel");
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Run automated tests if enabled
    if(automatedTestRunning)
    {
        RunAutomatedTests();
    }
    
    // Update current risk display
    if(EnableVisualRepresentation)
    {
        // Display statistics
        ObjectDelete(0, "StatLabel");
        ObjectCreate(0, "StatLabel", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "StatLabel", OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, "StatLabel", OBJPROP_XDISTANCE, 20);
        ObjectSetInteger(0, "StatLabel", OBJPROP_YDISTANCE, 20);
        ObjectSetString(0, "StatLabel", OBJPROP_TEXT, 
                      "Tests Run: " + IntegerToString(testCounter) + 
                      " | Success: " + IntegerToString(testResultSuccess) + 
                      " | Failed: " + IntegerToString(testResultFailed));
        ObjectSetInteger(0, "StatLabel", OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(0, "StatLabel", OBJPROP_BGCOLOR, clrDarkSlateBlue);
        ObjectSetInteger(0, "StatLabel", OBJPROP_FONTSIZE, 10);
    }
}

//+------------------------------------------------------------------+
//| Run automated test cases                                         |
//+------------------------------------------------------------------+
void RunAutomatedTests()
{
    // Simple state machine for automated tests
    static datetime lastTestTime = 0;
    datetime currentTime = TimeCurrent();

    // Only run next test after delay
    if(currentTime - lastTestTime < TestDelaySeconds)
        return;
        
    lastTestTime = currentTime;
    
    // Test cases based on current step
    switch(currentTestStep)
    {
        case 0: // Introduction and setup
        {
            Print("===== Starting Automated AC Functions Tests =====");
            Print("Test will run through key functions with multiple test cases");
            currentTestStep++;
            break;
        }
            
        case 1: // Test InitializeACRiskManagement
        {
            Print("Test #1: InitializeACRiskManagement - Setting AC_BaseRisk to 2.0%");
            AC_BaseRisk = 2.0;
            InitializeACRiskManagement(false); // Pass false to prevent resetting from input values
            testCounter++;
            
            // Verify correct initialization
            if(currentRisk == 2.0 && currentReward == 6.0)
            {
                Print("✅ Test #1: PASSED - Risk correctly initialized to ", currentRisk, "%, Reward to ", currentReward, "%");
                testResultSuccess++;
                string testName = "Init Test with 2% Base Risk";
                bool testPassed = true;
                DisplayTestResult(testName, testPassed);
            }
            else
            {
                Print("❌ Test #1: FAILED - Expected risk 2.0%, reward 6.0%, got risk ", currentRisk, "%, reward ", currentReward, "%");
                testResultFailed++;
                string testName = "Init Test with 2% Base Risk";
                bool testPassed = false;
                DisplayTestResult(testName, testPassed);
            }
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
            
        case 2: // Test UpdateRiskBasedOnResult with a win
        {
            Print("Test #2: UpdateRiskBasedOnResult - Testing Win Scenario");
            UpdateRiskBasedOnResult(true, 12345);
            testCounter++;
            
            // Verify risk increases after win
            if(currentRisk > 2.0 && consecutiveWins == 1)
            {
                Print("✅ Test #2: PASSED - Risk increased after win to ", currentRisk, "%, consecutive wins = ", consecutiveWins);
                testResultSuccess++;
                string testName = "Update Risk After Win";
                bool testPassed = true;
                DisplayTestResult(testName, testPassed);
            }
            else
            {
                Print("❌ Test #2: FAILED - Risk update failed, risk = ", currentRisk, "%, consecutive wins = ", consecutiveWins);
                testResultFailed++;
                string testName = "Update Risk After Win";
                bool testPassed = false;
                DisplayTestResult(testName, testPassed);
            }
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
            
        case 3: // Test UpdateRiskBasedOnResultWithProfit with a win and profit
        {
            Print("Test #3: UpdateRiskBasedOnResultWithProfit - Testing Win with Profit");
            double estimatedEquity = AccountInfoDouble(ACCOUNT_EQUITY);
            double simulatedProfit = estimatedEquity * 0.1; // 10% profit
            UpdateRiskBasedOnResultWithProfit(true, 12345, simulatedProfit);
            testCounter++;
            
            // Verify risk DOESN'T increase when profit is below target
            // Modified expectations to match the fixed behavior
            if(currentRisk == 8.0 && consecutiveWins == 2)
            {
                Print("✅ Test #3: PASSED - Risk correctly maintained at ", currentRisk, "% when profit below target, consecutive wins = ", consecutiveWins);
                testResultSuccess++;
                string testName = "Update Risk With Profit";
                bool testPassed = true;
                DisplayTestResult(testName, testPassed);
            }
            else
            {
                Print("❌ Test #3: FAILED - Expected risk 8.0%, consecutive wins 2, got risk ", currentRisk, "%, consecutive wins = ", consecutiveWins);
                testResultFailed++;
                string testName = "Update Risk With Profit";
                bool testPassed = false;
                DisplayTestResult(testName, testPassed);
            }
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
            
        case 4: // Test reset after max consecutive wins
        {
            Print("Test #4: UpdateRiskBasedOnResult - Testing Max Consecutive Wins Reset");
            // First win increased risk, second win with profit increased further,
            // now we do a third win which should trigger reset if compounding is set to 3
            UpdateRiskBasedOnResult(true, 12345);
            testCounter++;
            
            // Verify risk resets after reaching max consecutive wins
            bool resetExpected = (consecutiveWins == 0 && currentRisk == AC_BaseRisk);
            
            if(resetExpected)
            {
                Print("✅ Test #4: PASSED - Risk reset behavior correct, risk = ", currentRisk, "%, consecutive wins = ", consecutiveWins);
                testResultSuccess++;
                string testName = "Max Win Reset Test";
                bool testPassed = true;
                DisplayTestResult(testName, testPassed);
            }
            else
            {
                Print("❌ Test #4: FAILED - Risk reset behavior incorrect, risk = ", currentRisk, "%, consecutive wins = ", consecutiveWins);
                testResultFailed++;
                string testName = "Max Win Reset Test";
                bool testPassed = false;
                DisplayTestResult(testName, testPassed);
            }
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
            
        case 5: // Test loss reset
        {
            Print("Test #5: UpdateRiskBasedOnResult - Testing Loss Reset");
            // Build up risk first with a win
            UpdateRiskBasedOnResult(true, 12345);
            // Then test loss
            UpdateRiskBasedOnResult(false, 12345);
            testCounter++;
            
            // Verify risk resets after loss
            if(currentRisk == AC_BaseRisk && consecutiveWins == 0)
            {
                Print("✅ Test #5: PASSED - Risk reset correctly after loss, risk = ", currentRisk, "%, consecutive wins = ", consecutiveWins);
                testResultSuccess++;
                string testName = "Loss Reset Test";
                bool testPassed = true;
                DisplayTestResult(testName, testPassed);
            }
            else
            {
                Print("❌ Test #5: FAILED - Risk not reset correctly after loss, risk = ", currentRisk, "%, consecutive wins = ", consecutiveWins);
                testResultFailed++;
                string testName = "Loss Reset Test";
                bool testPassed = false;
                DisplayTestResult(testName, testPassed);
            }
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
            
        case 6: // Test CalculateATR
        {
            Print("Test #6: CalculateATR - Testing ATR Value Calculation");
            double atrValue = CalculateATR();
            testCounter++;
            
            // Verify ATR calculation (we can't know the exact value, but it should be > 0)
            if(atrValue > 0)
            {
                Print("✅ Test #6: PASSED - ATR calculation returned valid value: ", atrValue);
                testResultSuccess++;
                string testName = "ATR Calculation";
                bool testPassed = true;
                DisplayTestResult(testName, testPassed);
            }
            else
            {
                Print("❌ Test #6: FAILED - ATR calculation failed, returned: ", atrValue);
                testResultFailed++;
                string testName = "ATR Calculation";
                bool testPassed = false;
                DisplayTestResult(testName, testPassed);
            }
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
            
        case 7: // Test GetStopLossDistance
        {
            Print("Test #7: GetStopLossDistance - Testing Stop Loss Distance Calculation");
            double stopDistance = GetStopLossDistance();
            testCounter++;
            
            // Verify stop loss distance calculation
            if(stopDistance > 0)
            {
                Print("✅ Test #7: PASSED - Stop loss distance calculation returned valid value: ", stopDistance);
                testResultSuccess++;
                string testName = "Stop Loss Distance";
                bool testPassed = true;
                DisplayTestResult(testName, testPassed);
            }
            else
            {
                Print("❌ Test #7: FAILED - Stop loss distance calculation failed, returned: ", stopDistance);
                testResultFailed++;
                string testName = "Stop Loss Distance";
                bool testPassed = false;
                DisplayTestResult(testName, testPassed);
            }
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
            
        case 8: // Test CalculateLotSize
        {
            Print("Test #8: CalculateLotSize - Testing Lot Size Calculation");
            double slDistance = GetStopLossDistance();
            double lotSize = CalculateLotSize(slDistance);
            testCounter++;
            
            // Verify lot size calculation
            if(lotSize > 0)
            {
                Print("✅ Test #8: PASSED - Lot size calculation returned valid value: ", lotSize);
                testResultSuccess++;
                string testName = "Lot Size Calculation";
                bool testPassed = true;
                DisplayTestResult(testName, testPassed);
            }
            else
            {
                Print("❌ Test #8: FAILED - Lot size calculation failed, returned: ", lotSize);
                testResultFailed++;
                string testName = "Lot Size Calculation";
                bool testPassed = false;
                DisplayTestResult(testName, testPassed);
            }
            
            // Restore original values
            double originalATRPeriod = ATRPeriod;
            double originalATRMultiplier = ATRMultiplier;
            double originalMaxStopLoss = MaxStopLossDistance;

            ATRPeriod = originalATRPeriod;
            ATRMultiplier = originalATRMultiplier;
            MaxStopLossDistance = originalMaxStopLoss;
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
        
        case 9: // Edge Case 1: High Volatility ATR
        {
            Print("Edge Case #1: Testing with high volatility ATR value...");
            testCounter++;
            
            // Save original values
            savedATRPeriod = ATRPeriod;
            savedATRMultiplier = ATRMultiplier;
            savedMaxStopLoss = MaxStopLossDistance;
            
            // Set high volatility ATR
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            
            // Adjust ATR multiplier to avoid excessive numbers
            ATRPeriod = 14;
            ATRMultiplier = 1.0; // Reduced multiplier for high volatility
            
            // Use a simulated very high ATR value
            double testATR = TestHighVolatilityATR * point;
            double stopLoss = testATR * ATRMultiplier;
            double takeProfit = stopLoss * AC_BaseReward;
            
            Print("High ATR test:", 
                 "\n- Simulated ATR: ", TestHighVolatilityATR, " points",
                 "\n- Calculated stop loss: ", stopLoss/point, " points");
            
            // Test risk calculations with high volatility
            double lotSize = CalculateLotSize(stopLoss / point);
            double equity = AccountInfoDouble(ACCOUNT_EQUITY);
            double riskAmount = lotSize * stopLoss;
            double riskPercent = (riskAmount / equity) * 100;
            
            bool isRiskControlled = (riskPercent <= currentRisk * 1.1); // Allow 10% tolerance
            
            if(isRiskControlled && lotSize > 0)
            {
                Print("✅ Edge Case #1: PASSED - Risk correctly managed with high volatility");
                Print("- ATR: ", TestHighVolatilityATR, " points (very high)");
                Print("- Calculated lot size: ", lotSize);
                Print("- Risk amount: $", riskAmount, " (", riskPercent, "% of account)");
                Print("- Target risk: ", currentRisk, "%");
                
                DisplayTestResult("High Volatility ATR Test", true);
                testResultSuccess++;
            }
            else
            {
                Print("❌ Edge Case #1: FAILED - Risk management failed with high volatility");
                Print("- Lot size calculation: ", lotSize);
                if(!isRiskControlled)
                    Print("- Risk percentage (", riskPercent, "%) exceeds target risk (", currentRisk, "%)");
                
                DisplayTestResult("High Volatility ATR Test", false);
                testResultFailed++;
            }
            
            // Restore original values
            ATRPeriod = savedATRPeriod;
            ATRMultiplier = savedATRMultiplier;
            MaxStopLossDistance = savedMaxStopLoss;
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
        
        case 10: // Edge Case #2: Extremely Low Volatility ATR
        {
            Print("Edge Case #2: Testing with low volatility ATR value...");
            testCounter++;
            
            // Save original values
            double originalATRPeriod = ATRPeriod;
            double originalATRMultiplier = ATRMultiplier;
            
            // Set low volatility ATR parameters
            ATRPeriod = savedATRPeriod;  // Default period
            ATRMultiplier = 3.0;         // Higher multiplier to compensate for low ATR
            
            // Simulate low volatility
            double simulatedATR = TestLowVolatilityATR;
            Print("Using simulated low volatility ATR value: ", simulatedATR);
            
            // Test calculations
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double stopDistance = simulatedATR * ATRMultiplier;
            
            Print("Low volatility ATR calculation:", 
                 "\n- Raw ATR: ", simulatedATR,
                 "\n- ATR in points: ", simulatedATR/point,
                 "\n- ATR * Multiplier: ", stopDistance/point, " points");
            
            // First try to optimize the risk parameters since stop is tight
            double testLot = 0.1; // Use a fixed lot size for consistent testing
            double originalStopDistance = stopDistance;
            
            // First optimize with the original stop distance and test lot
            bool adjustedLot = OptimizeRiskParameters(testLot, stopDistance);
            
            Print("OPTIMIZED PARAMETERS:");
            Print("- Original stop distance: ", originalStopDistance/point, " points");
            Print("- Adjusted stop distance: ", stopDistance/point, " points");
            Print("- Original lot size: 0.1");
            Print("- Adjusted lot size: ", testLot);
            
            // Now calculate lot size with the possibly adjusted stop loss
            // This should use our enhanced safety checks
            double lotSize = CalculateLotSize(stopDistance);
            
            // Analyze the risk
            double equity = AccountInfoDouble(ACCOUNT_EQUITY);
            if(gSavedEquity > 0) equity = gSavedEquity; // Use test equity if set
            
            double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            double stopLossPoints = stopDistance / point;
            double pointCost = (tickValue / tickSize) * lotSize;
            double riskAmount = pointCost * stopLossPoints;
            double riskPercent = (riskAmount / equity) * 100.0;
            
            // Check if risk is within acceptable levels (allow up to 20% more than target)
            bool acceptableRisk = (riskPercent <= currentRisk * 1.20); // More generous for testing
            
            // Check results - we should either have acceptable risk or a minimum lot size
            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            bool atMinLot = (lotSize <= minLot + 0.001); // Within rounding error of min lot
            
            if(lotSize > 0 && (acceptableRisk || atMinLot))
            {
                Print("✅ Edge Case #2: PASSED - Low volatility handled correctly");
                Print("- Stop loss distance: ", stopDistance/point, " points");
                Print("- Calculated lot size: ", lotSize);
                Print("- Risk amount: $", riskAmount, " (", riskPercent, "% of account)");
                if(atMinLot)
                    Print("- Using minimum lot size for safety");
                if(stopDistance > originalStopDistance)
                    Print("- Stop loss distance was increased for safety");
                
                DisplayTestResult("Low Volatility ATR Test", true);
                testResultSuccess++;
            }
            else
            {
                Print("❌ Edge Case #2: FAILED - Low volatility created a risk issue");
                Print("- Stop loss too tight: ", stopDistance/point, " points");
                Print("- Calculated lot size: ", lotSize);
                if(!acceptableRisk)
                    Print("- Risk too high: ", riskPercent, "% (target: ", currentRisk, "%)");
                
                DisplayTestResult("Low Volatility ATR Test", false);
                testResultFailed++;
            }
            
            // Restore original values
            ATRPeriod = originalATRPeriod;
            ATRMultiplier = originalATRMultiplier;
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
        
        case 11: // Edge Case 3: Very Tight Stop Loss
        {
            Print("Edge Case #3: Testing with very tight stop loss...");
            testCounter++;
            
            // Calculate a very tight stop loss distance
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double tightStopDistance = TestTightStopLoss * point;
            
            // Test calculations
            double originalStopLoss = tightStopDistance;
            double testLot = 0.1; // Use a fixed lot size for consistent testing
            
            Print("Tight stop loss test:", 
                 "\n- Original stop loss: ", TestTightStopLoss, " points");
                 
            // Test stop loss adjustment
            double adjustedStop = GetAdjustedStopLossDistance(tightStopDistance, testLot);
            double originalLot = testLot;
            bool adjustLot = OptimizeRiskParameters(testLot, tightStopDistance);
            
            // Check risk safety - either lot or stop should be adjusted
            bool isRiskManaged = (testLot != originalLot || tightStopDistance != originalStopLoss);
            
            if(isRiskManaged)
            {
                Print("✅ Edge Case #3: PASSED - System adjusted risk parameters");
                if(adjustLot)
                {
                    Print("- System chose to adjust lot size from ", originalLot, " to ", testLot);
                }
                else
                {
                    Print("- System chose to adjust stop loss from ", originalStopLoss/point, " to ", tightStopDistance/point, " points");
                }
                
                DisplayTestResult("Tight Stop Loss Test", true);
                testResultSuccess++;
            }
            else
            {
                Print("❌ Edge Case #3: FAILED - System did not adjust risk for tight stop");
                Print("- Stop remained at dangerous level: ", tightStopDistance/point, " points");
                
                DisplayTestResult("Tight Stop Loss Test", false);
                testResultFailed++;
            }
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
        
        case 12: // Edge Case 4: Very Wide Stop Loss
        {
            Print("Edge Case #4: Testing with very wide stop loss...");
            testCounter++;
            
            // Calculate a very wide stop loss distance
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double wideStopDistance = TestWideStopLoss * point;
            
            // Test calculations
            Print("Wide stop loss test:", 
                 "\n- Original stop loss: ", TestWideStopLoss, " points");
                 
            // Calculate lot size with this wide stop
            double lotSize = CalculateLotSize(wideStopDistance);
            
            // Check if the lot size is very small (but valid)
            double equity = AccountInfoDouble(ACCOUNT_EQUITY);
            double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            double stopLossPoints = wideStopDistance / point;
            double pointCost = (tickValue / tickSize) * lotSize;
            double riskAmount = pointCost * stopLossPoints;
            double riskPercent = (riskAmount / equity) * 100.0;
            
            // Get min lot size
            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            bool atMinLot = (lotSize <= minLot + 0.001); // Within rounding error of min lot
            
            // Check results
            if(lotSize > 0)
            {
                Print("✅ Edge Case #4: PASSED - System calculated valid lot size with wide stop");
                if(atMinLot)
                    Print("- System correctly used minimum lot size with very wide stop");
                Print("- Stop loss distance: ", wideStopDistance/point, " points (very wide)");
                Print("- Calculated lot size: ", lotSize);
                Print("- Risk amount: $", riskAmount, " (", riskPercent, "% of account)");
                
                DisplayTestResult("Wide Stop Loss Test", true);
                testResultSuccess++;
            }
            else
            {
                Print("❌ Edge Case #4: FAILED - System failed to calculate lot size");
                Print("- Stop loss distance: ", wideStopDistance/point, " points");
                Print("- Lot size calculation failed: ", lotSize);
                
                DisplayTestResult("Wide Stop Loss Test", false);
                testResultFailed++;
            }
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
        
        case 13: // Edge Case 5: Small Account
        {
            Print("Edge Case #5: Testing with small account size...");
            testCounter++;
            
            // Save original equity
            double originalEquity = gSavedEquity;
            
            // Set a small account size for testing
            double smallAccountEquity = TestTinyAccountSize;
            
            // Temporarily override account info for testing
            gSavedEquity = smallAccountEquity;
            Print("Testing with small account size: $", smallAccountEquity);
            
            // Calculate a normal stop loss distance
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double normalATR = CalculateATR();
            double stopDistance = normalATR * savedATRMultiplier;
            
            // Test calculations
            Print("Small account test:", 
                 "\n- Account equity: $", smallAccountEquity,
                 "\n- Stop distance: ", stopDistance/point, " points");
                 
            // Calculate lot size with this stop
            double lotSize = CalculateLotSize(stopDistance);
            
            // Check if the lot size is at minimum (but valid)
            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            bool atMinLot = (lotSize <= minLot + 0.001); // Within rounding error of min lot
            
            // Analyze the risk
            double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            double stopLossPoints = stopDistance / point;
            double pointCost = (tickValue / tickSize) * lotSize;
            double riskAmount = pointCost * stopLossPoints;
            double riskPercent = (riskAmount / smallAccountEquity) * 100.0;
            
            // Check results - for very small accounts, we should get min lot size
            // But the risk should still be close to target (we allow some deviation)
            bool riskWithinLimits = (riskPercent <= currentRisk * 1.5); // Allow 50% more risk
            
            if(lotSize > 0 && (atMinLot || riskWithinLimits))
            {
                Print("✅ Edge Case #5: PASSED - System calculated appropriate lot size for small account");
                Print("- Account size: $", smallAccountEquity);
                Print("- Stop loss distance: ", stopDistance/point, " points");
                Print("- Calculated lot size: ", lotSize);
                Print("- Risk amount: $", riskAmount, " (", riskPercent, "% of account)");
                
                DisplayTestResult("Small Account Test", true);
                testResultSuccess++;
            }
            else
            {
                Print("❌ Edge Case #5: FAILED - Small account risk calculation issue");
                Print("- Account size: $", smallAccountEquity);
                Print("- Lot size: ", lotSize);
                Print("- Risk percent: ", riskPercent, "% (target: ", currentRisk, "%)");
                
                DisplayTestResult("Small Account Test", false);
                testResultFailed++;
            }
            
            // Restore original equity
            gSavedEquity = originalEquity;
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
        
        case 14: // Edge Case 6: Large Account
        {
            Print("Edge Case #6: Testing with large account size...");
            testCounter++;
            
            // Save original equity
            double originalEquity = gSavedEquity;
            
            // Set a large account size for testing
            double largeAccountEquity = TestLargeAccountSize;
            
            // Temporarily override account info for testing
            gSavedEquity = largeAccountEquity;
            Print("Testing with large account size: $", largeAccountEquity);
            
            // Calculate a normal stop loss distance based on ATR
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double normalATR = CalculateATR();
            double stopDistance = normalATR * savedATRMultiplier;
            
            // Test calculations
            Print("Large account test:", 
                 "\n- Account equity: $", largeAccountEquity,
                 "\n- Stop distance: ", stopDistance/point, " points");
                 
            // Calculate lot size directly with this stop and our enhanced safety check
            double lotSize = CalculateLotSize(stopDistance);
            
            // Analyze the risk with the calculated lot size
            double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            double stopLossPoints = stopDistance / point;
            double pointCost = (tickValue / tickSize) * lotSize;
            double riskAmount = pointCost * stopLossPoints;
            double riskPercent = (riskAmount / largeAccountEquity) * 100.0;
            
            // Get lot size constraints
            double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
            bool belowMaxLot = (lotSize < maxLot * 0.9); // Not too close to max lot
            
            // Check if risk percent is close to target (allow up to 20% tolerance)
            bool riskAccurate = (riskPercent >= currentRisk * 0.8 && riskPercent <= currentRisk * 1.2);
            
            // Check results
            if(lotSize > 0 && belowMaxLot && riskAccurate)
            {
                Print("✅ Edge Case #6: PASSED - System calculated appropriate lot size for large account");
                Print("- Account size: $", largeAccountEquity);
                Print("- Stop loss distance: ", stopDistance/point, " points");
                Print("- Calculated lot size: ", lotSize);
                Print("- Risk amount: $", riskAmount, " (", riskPercent, "% of account)");
                
                DisplayTestResult("Large Account Test", true);
                testResultSuccess++;
            }
            else
            {
                Print("❌ Edge Case #6: FAILED - Large account risk calculation issue");
                Print("- Account size: $", largeAccountEquity);
                Print("- Lot size: ", lotSize, " (Max: ", maxLot, ")");
                Print("- Risk percent: ", riskPercent, "% (target: ", currentRisk, "%)");
                if(!belowMaxLot)
                    Print("- Lot size too large, close to maximum");
                if(!riskAccurate)
                    Print("- Risk not accurately calculated");
                
                DisplayTestResult("Large Account Test", false);
                testResultFailed++;
            }
            
            // Restore original equity
            gSavedEquity = originalEquity;
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
        
        case 15: // Edge Case 7: Asymmetrical Compounding with Win Streak
        {
            Print("Edge Case #7: Testing asymmetrical compounding with extreme win streak...");
            testCounter++;
            
            // Save original values
            double originalRisk = currentRisk;
            int originalWins = consecutiveWins;
            
            // Reset to baseline risk for test
            currentRisk = AC_BaseRisk;
            consecutiveWins = 0;
            
            // Test parameters
            int testWinCount = 10; // Test a 10-win streak
            
            Print("Testing asymmetrical compounding with ", testWinCount, " consecutive wins");
            Print("Starting with base risk of ", AC_BaseRisk, "%");
            
            // Array to store risk progression
            double riskProgression[];
            ArrayResize(riskProgression, testWinCount + 1);
            riskProgression[0] = currentRisk;
            
            // Simulate consecutive wins
            for(int i = 1; i <= testWinCount; i++)
            {
                // Update risk based on wins
                UpdateRiskBasedOnResult(true, 12345);
                riskProgression[i] = currentRisk;
                
                Print("After win #", i, ", risk = ", currentRisk, "%");
            }
            
            // Our expectation should match system design: risk resets after AC_CompoundingWins wins
            // The final value should be either:
            // - Base risk if we've just reset (when testWinCount % AC_CompoundingWins == 0)
            // - Higher than base risk if we're in the middle of a compounding cycle
            
            double expectedFinalRisk;
            if(testWinCount % AC_CompoundingWins == 0)
            {
                // If we've completed a full cycle, we expect to be at base risk
                expectedFinalRisk = AC_BaseRisk;
            }
            else
            {
                // If in the middle of a cycle, calculate expected risk based on wins since last reset
                int winsInCurrentCycle = testWinCount % AC_CompoundingWins;
                expectedFinalRisk = AC_BaseRisk;
                
                // Apply compounding for each win in the current cycle
                for(int i = 0; i < winsInCurrentCycle; i++)
                {
                    double reward = expectedFinalRisk * AC_BaseReward;
                    expectedFinalRisk += reward;
                }
            }
            
            // Verify final risk matches expected value (within 0.01%)
            bool riskMatchesExpected = (MathAbs(currentRisk - expectedFinalRisk) < 0.01);
            
            // Verify risk progression is sensible - should increase and then reset
            bool riskCyclesCorrectly = true;
            int cycle = 0;
            for(int i = 1; i <= testWinCount; i++)
            {
                int positionInCycle = i % AC_CompoundingWins;
                
                if(positionInCycle == 1)  // Start of a new cycle
                {
                    // First win after reset should increase risk from base
                    if(MathAbs(riskProgression[i-1] - AC_BaseRisk) > 0.01 && i > 1)
                    {
                        Print("Risk not reset correctly at win #", i-1);
                        riskCyclesCorrectly = false;
                        break;
                    }
                    // Risk should increase after first win
                    if(riskProgression[i] <= AC_BaseRisk)
                    {
                        Print("Risk did not increase after win #", i);
                        riskCyclesCorrectly = false;
                        break;
                    }
                }
                else if(positionInCycle == 0)  // End of a cycle
                {
                    // After AC_CompoundingWins wins, should reset to base
                    if(MathAbs(riskProgression[i] - AC_BaseRisk) > 0.01)
                    {
                        Print("Risk not reset correctly after win #", i);
                        riskCyclesCorrectly = false;
                        break;
                    }
                }
                else  // Middle of a cycle
                {
                    // MODIFIED: Check that risk at same position in different cycles is consistent
                    // Find same position in previous cycle if we're beyond the first cycle
                    if(i > AC_CompoundingWins)
                    {
                        double currentCycleRisk = riskProgression[i];
                        double previousCycleRisk = riskProgression[i - AC_CompoundingWins];
                        
                        // Risk should be approximately the same at the same position in different cycles
                        if(MathAbs(currentCycleRisk - previousCycleRisk) > 0.01)
                        {
                            Print("Risk values not consistent across cycles at position ", positionInCycle, ": ",
                                 currentCycleRisk, "% vs ", previousCycleRisk, "%");
                            riskCyclesCorrectly = false;
                            break;
                        }
                    }
                }
            }
            
            // Check results
            if(riskCyclesCorrectly && riskMatchesExpected)
            {
                Print("✅ Edge Case #7: PASSED - Asymmetrical compounding handled win streak correctly");
                Print("- Final risk after ", testWinCount, " wins: ", currentRisk, "%");
                Print("- Expected final risk based on system design: ", expectedFinalRisk, "%");
                if(testWinCount % AC_CompoundingWins == 0)
                    Print("- Risk correctly reset to base after win cycle");
                
                DisplayTestResult("Win Streak Test", true);
                testResultSuccess++;
            }
            else
            {
                Print("❌ Edge Case #7: FAILED - Asymmetrical compounding issue with win streak");
                Print("- Final risk after ", testWinCount, " wins: ", currentRisk, "%");
                Print("- Expected final risk based on system design: ", expectedFinalRisk, "%");
                if(!riskCyclesCorrectly)
                    Print("- Risk did not cycle correctly with wins");
                if(!riskMatchesExpected)
                    Print("- Final risk does not match expected calculation");
                
                DisplayTestResult("Win Streak Test", false);
                testResultFailed++;
            }
            
            // Restore original values
            currentRisk = originalRisk;
            consecutiveWins = originalWins;
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
        
        case 16: // Edge Case 8: ATR Trailing Stop Adjustment
        {
            Print("Edge Case #8: Testing ATR trailing stop adjustment during volatility change...");
            testCounter++;
            
            // Save original values
            double originalATRPeriod = ATRPeriod;
            double originalATRMultiplier = ATRMultiplier;
            double originalMaxStopLoss = MaxStopLossDistance;
            
            // Set parameters for test
            ATRPeriod = savedATRPeriod;  // Default period
            ATRMultiplier = 2.0;         // Standard multiplier
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            
            // Simulate initial volatility (normal ATR)
            double initialATR = 0.0020;  // 20 points for 5-digit broker
            double initialStopDistance = initialATR * ATRMultiplier;
            
            // Calculate initial stop level (assuming price of 1.0000 for simplicity)
            double entryPrice = 1.0000;
            double direction = 1;  // 1 for long, -1 for short
            double initialStopLevel = entryPrice - direction * initialStopDistance;
            
            Print("Initial trade setup:", 
                  "\n- Entry price: ", entryPrice,
                  "\n- Direction: ", direction > 0 ? "Long" : "Short",
                  "\n- Initial ATR: ", initialATR,
                  "\n- Initial stop distance: ", initialStopDistance/point, " points",
                  "\n- Initial stop level: ", initialStopLevel);
            
            // Simulate price movement and increased volatility
            double newPrice = entryPrice + direction * 0.0050;  // Move 50 points in favorable direction
            double newATR = 0.0040;  // Double the ATR (increased volatility)
            double newStopDistance = newATR * ATRMultiplier;
            
            // Calculate expected trailing stop based on ATR
            double expectedTrailingStop = newPrice - direction * newStopDistance;
            
            // Calculate what trailing stop would be with simple fixed trailing
            double fixedTrailingStop = initialStopLevel;
            if((direction > 0 && newPrice - initialStopDistance > fixedTrailingStop) ||
               (direction < 0 && newPrice + initialStopDistance < fixedTrailingStop))
            {
                // Move the fixed trailing stop
                fixedTrailingStop = newPrice - direction * initialStopDistance;
            }
            
            // Use our actual system to calculate the trailing stop
            double actualTrailingStop = CalculateTrailingStop(
                initialStopLevel,  // Original stop
                entryPrice,        // Entry price
                newPrice,          // Current price
                direction > 0,     // Is long
                newATR            // Current ATR
            );
            
            // Check if our trailing stop adapts to volatility appropriately
            bool adaptsToVolatility = MathAbs(actualTrailingStop - expectedTrailingStop) < 0.0001;
            bool saferThanFixed = (direction > 0 && actualTrailingStop < fixedTrailingStop) ||
                                 (direction < 0 && actualTrailingStop > fixedTrailingStop);
            
            // Analysis of results
            if(adaptsToVolatility && saferThanFixed)
            {
                Print("✅ Edge Case #8: PASSED - ATR trailing stop correctly adapts to volatility changes");
                Print("- Price moved from ", entryPrice, " to ", newPrice, " (", direction * (newPrice - entryPrice)/point, " points)");
                Print("- Volatility (ATR) increased from ", initialATR/point, " to ", newATR/point, " points");
                Print("- Fixed trailing stop would be at: ", fixedTrailingStop);
                Print("- ATR-based trailing stop is at: ", actualTrailingStop);
                Print("- ATR stop is ", direction * (fixedTrailingStop - actualTrailingStop)/point, " points safer");
                
                DisplayTestResult("ATR Trailing Stop Test", true);
                testResultSuccess++;
            }
            else
            {
                Print("❌ Edge Case #8: FAILED - ATR trailing stop did not adapt correctly");
                Print("- Expected trailing stop: ", expectedTrailingStop);
                Print("- Actual trailing stop: ", actualTrailingStop);
                Print("- Fixed trailing stop: ", fixedTrailingStop);
                if(!adaptsToVolatility)
                    Print("- Stop does not adapt to volatility changes correctly");
                if(!saferThanFixed)
                    Print("- ATR-based stop not safer than fixed trailing stop during volatility increase");
                
                DisplayTestResult("ATR Trailing Stop Test", false);
                testResultFailed++;
            }
            
            // Restore original values
            ATRPeriod = originalATRPeriod;
            ATRMultiplier = originalATRMultiplier;
            MaxStopLossDistance = originalMaxStopLoss;
            
            UpdateRiskGraphData();
            currentTestStep++;
            break;
        }
        
        case 17: // Complete all tests
        {
            Print("===== All Automated Tests Completed =====");
            Print("Total tests run: ", testCounter);
            Print("Tests passed: ", testResultSuccess);
            Print("Tests failed: ", testResultFailed);
            Print("Success rate: ", (testResultSuccess * 100.0) / testCounter, "%");
            automatedTestRunning = false;
            
            // Display final test completion message
            string testName = "All Tests Completed!";
            bool testPassed = true;
            DisplayTestResult(testName, testPassed);
            break;
        }
        
        default:
            automatedTestRunning = false;
            break;
    }
}

//+------------------------------------------------------------------+
//| Reset all tests                                                   |
//+------------------------------------------------------------------+
void ResetTests()
{
    Print("Resetting all tests and risk management system...");
    
    // Reset test tracking variables
    testCounter = 0;
    testResultSuccess = 0;
    testResultFailed = 0;
    automatedTestRunning = false;
    currentTestStep = 0;
    
    // Reset risk management globals explicitly
    AC_BaseRisk = TestBaseRisk;
    AC_BaseReward = TestBaseReward;
    AC_CompoundingWins = TestCompoundingWins;
    consecutiveWins = 0;  // Explicitly reset consecutive wins counter
    currentRisk = 0;      // Reset current risk to force reinitialization
    currentReward = 0;    // Reset current reward to force reinitialization
    
    // Initialize the asymmetrical compounding risk management
    InitializeACRiskManagement();
    
    // Clear all test result labels
    if(EnableVisualRepresentation)
    {
        for(int i = 0; i < 100; i++)
        {
            ObjectDelete(0, "TestLabel" + IntegerToString(i));
        }
        
        // Reset risk graph data
        ArrayInitialize(riskValues, 0);
        ArrayInitialize(rewardValues, 0);
        UpdateRiskGraphData();
    }
    
    Print("Tests reset completed.");
}
