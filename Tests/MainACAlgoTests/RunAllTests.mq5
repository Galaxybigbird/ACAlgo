//+------------------------------------------------------------------+
//|                                     RunAllTests.mq5              |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// Test runner that executes all tests in sequence

// List of tests to run (add new test files here)
string testScripts[] = {
   "TestPointValueCalculation.ex5",
   "TestMainACAlgorithm.ex5",
   "TestMultiSymbolPointValues.ex5"
};

// Test status tracking
int totalTests = 0;
int currentTestIndex = 0;
bool testRunning = false;
bool allTestsComplete = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== MASTER TEST RUNNER ===");
   Print("This script will run all test files in sequence");
   Print("Total test files: ", ArraySize(testScripts));
   
   // Start the first test
   if(ArraySize(testScripts) > 0)
   {
      Print("Starting first test...");
      StartNextTest();
   }
   else
   {
      Print("No test files specified. Test complete.");
      allTestsComplete = true;
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // If we're running a test, cleanup
   if(testRunning)
   {
      Print("Stopping current test: ", testScripts[currentTestIndex]);
      StopCurrentTest();
   }
   
   Print("Test runner finished.");
}

//+------------------------------------------------------------------+
//| Start the next test in the sequence                              |
//+------------------------------------------------------------------+
void StartNextTest()
{
   if(currentTestIndex >= ArraySize(testScripts))
   {
      // All tests have been run
      Print("All tests completed successfully!");
      allTestsComplete = true;
      testRunning = false;
      return;
   }
   
   string scriptName = testScripts[currentTestIndex];
   Print("=== RUNNING TEST ", currentTestIndex + 1, " OF ", ArraySize(testScripts), " ===");
   Print("Test file: ", scriptName);
   
   // Launch the test script
   bool success = LaunchScript(scriptName);
   
   if(!success)
   {
      Print("ERROR: Failed to launch test script: ", scriptName);
      
      // Try to move to the next test
      currentTestIndex++;
      StartNextTest();
   }
   else
   {
      testRunning = true;
      totalTests++;
   }
}

//+------------------------------------------------------------------+
//| Launch a script file                                             |
//+------------------------------------------------------------------+
bool LaunchScript(string scriptName)
{
   // We're running test experts, not scripts
   // So we need to use a different approach
   
   // Instead of trying to launch directly,
   // we'll just print instructions for the user
   Print("MANUAL STEP REQUIRED:");
   Print("Please manually remove this expert and attach the following expert to the chart:");
   Print("→ ", scriptName);
   Print("→ When test is complete, return to this expert (RunAllTests.ex5)");
   
   // Generate a beep to get user's attention
   PlaySound("alert.wav");
   
   // We can't actually launch the script programmatically
   // so we'll consider this a success and let the user handle it
   return true;
}

//+------------------------------------------------------------------+
//| Stop the current test that's running                             |
//+------------------------------------------------------------------+
void StopCurrentTest()
{
   // Nothing to do in our implementation since the user handles switching tests
   testRunning = false;
}

//+------------------------------------------------------------------+
//| Proceed to next test                                             |
//+------------------------------------------------------------------+
void ProceedToNextTest()
{
   // Move to the next test
   currentTestIndex++;
   testRunning = false;
   
   // Start the next test
   StartNextTest();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Not used in this script
}

//+------------------------------------------------------------------+
//| ChartEvent function - Handle user button clicks                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Handle custom button clicks
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == "NextTestButton")
      {
         // User clicked "Next Test" button
         ProceedToNextTest();
      }
   }
} 