//+------------------------------------------------------------------+
//|                                             TestACPartialComp…   |
//| Verifies partial compounding, cycle reset, and stop logic.       |
//| Usage: run as script; results appear in Experts log.             |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <Trade/Trade.mqh>
#include <SymbolValidator.mqh>

CSymbolValidator g_SymbolValidator;

#include <ACFunctions.mqh>

// Helper to print pass/fail lines
void PrintResult(const string label, const bool passed, const string details)
{
   PrintFormat("%s [%s] - %s", label, passed ? "PASS" : "FAIL", details);
}

void OnStart()
{
   if(!g_SymbolValidator.Init(_Symbol))
   {
      Print("[TestACPartialCompounding] Failed to init SymbolValidator for ", _Symbol);
      return;
   }
   g_SymbolValidator.Refresh();

   // Preserve existing globals we temporarily modify
   const double originalEquity   = gSavedEquity;
   const double originalRisk     = AC_BaseRisk;
   const double originalReward   = AC_BaseReward;
   const int    originalWins     = AC_CompoundingWins;
   const bool   originalPartial  = AC_EnablePartialCompoundingFlag;
   const double originalPercent  = AC_PartialCompoundingPercentEffective;
   const double originalFraction = AC_PartialCompoundFraction;

   // Use current account equity so the profit percentage logic matches runtime
   const double testEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   gSavedEquity = testEquity;

   // ------------------------------ //
   // Baseline: partial OFF
   // ------------------------------ //
   AC_BaseRisk  = 2.0;
   AC_BaseReward = 3.0;
   AC_CompoundingWins = 2;
   AC_EnablePartialCompoundingFlag = false;
   AC_PartialCompoundingPercentEffective = 100.0;
   AC_PartialCompoundFraction = 1.0;

   InitializeACRiskManagement(false);

   const double rewardPercent = currentReward;
   const double profitMeetingTarget = testEquity * (rewardPercent / 100.0);
   UpdateRiskBasedOnResultWithProfit(true, 0, profitMeetingTarget + 0.01);
   bool passFull = MathAbs(currentRisk - 8.0) < 0.001;
   PrintResult("Full Compounding", passFull,
               StringFormat("Expected 8.00, got %.2f (CurrentReward=%.2f)", currentRisk, currentReward));

   // ------------------------------ //
   // Partial compounding ON
   // ------------------------------ //
   AC_EnablePartialCompoundingFlag = true;
   AC_CompoundingWins = 3; // allow two wins before reset so we can inspect second-step compounding
   AC_PartialCompoundingPercentEffective = 25.0;
   AC_PartialCompoundFraction = 0.25;
   InitializeACRiskManagement(false);

   UpdateRiskBasedOnResultWithProfit(true, 0, profitMeetingTarget + 0.01);
   bool passPartialFirst = MathAbs(currentRisk - 3.5) < 0.001;
   PrintResult("Partial First Win", passPartialFirst,
               StringFormat("Expected 3.50, got %.2f", currentRisk));

   UpdateRiskBasedOnResultWithProfit(true, 0,
      testEquity * (currentReward / 100.0) + 0.01); // second win
   double expectedSecond = 3.5 + (3.5 * 3.0) * 0.25; // 3.5 + (10.5*0.25)=6.125
   bool passPartialSecond = MathAbs(currentRisk - expectedSecond) < 0.001;
   PrintResult("Partial Second Win", passPartialSecond,
               StringFormat("Expected %.3f, got %.3f", expectedSecond, currentRisk));

   // Third win should reset once compounding win limit is reached
   UpdateRiskBasedOnResultWithProfit(true, 0, testEquity * (currentReward / 100.0) + 0.01);
   bool passReset = MathAbs(currentRisk - AC_BaseRisk) < 0.001;
   PrintResult("Cycle Reset", passReset,
               StringFormat("Expected %.2f, got %.2f", AC_BaseRisk, currentRisk));

   // ------------------------------ //
   // Stop distance sanity
   // ------------------------------ //
   // Configure ATR multiplier and limit, then compute expected values manually
   ATRMultiplier = 2.0;
   MaxStopLossDistance = 100.0;
   double atr = CalculateATR();     // live ATR
   double point = g_SymbolValidator.Point();
   double expectedDistance = MathMin(atr * ATRMultiplier * 1.5, MaxStopLossDistance * point);
   double computed = GetStopLossDistance();
   bool passStops = MathAbs(expectedDistance - computed) < point * 0.5;
   PrintResult("Stop Distance", passStops,
               StringFormat("Expected %.5f, got %.5f (ATR=%.5f point=%.5f)", expectedDistance, computed, atr, point));

   // ------------------------------ //
   // Restore globals
   // ------------------------------ //
   gSavedEquity = originalEquity;
   AC_BaseRisk = originalRisk;
   AC_BaseReward = originalReward;
   AC_CompoundingWins = originalWins;
   AC_EnablePartialCompoundingFlag = originalPartial;
   AC_PartialCompoundingPercentEffective = originalPercent;
   AC_PartialCompoundFraction = originalFraction;

   Print("TestACPartialCompounding complete.");
}
