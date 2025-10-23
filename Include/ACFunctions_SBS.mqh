//+------------------------------------------------------------------+
//|           Asymmetrical Compounding Risk Management (SBS)         |
//|             Tailored for AC_SBS_Base EA                          |
//+------------------------------------------------------------------+
#include <SymbolValidator.mqh>

extern CSymbolValidator g_SymbolValidator;

input group "==== AC Risk Management Parameters (SBS) ===="
input double AC_BaseRisk_Input = 1.0;          // AC BaseRisk
input double AC_BaseReward_Input = 3.0;        // AC BaseReward & Multiplier
input bool   AC_BaseRewardIsPercent_Input = false; // Interpret BaseReward as absolute percent
input int    AC_CompoundingWins_Input = 2;     // AC CompoundingWins
input bool   AC_EnablePartialCompounding_Input = false; // AC EnablePartialCompounding
input double AC_PartialCompoundPercent_Input = 25.0;    // AC PartialCompoundPercent (0-100)

// Mutable copies
double AC_BaseRisk;
double AC_BaseReward;
bool   AC_BaseRewardIsPercent = false;
double AC_BaseRewardPercent = 0.0;
double AC_BaseRewardUserValue = 0.0;
int    AC_CompoundingWins;
bool   AC_EnablePartialCompoundingFlag = false;
double AC_PartialCompoundingPercentEffective = 100.0;
double AC_PartialCompoundFraction = 1.0;

// Risk tracking
double currentRisk = 0.0;
double currentReward = 0.0;
int    consecutiveWins = 0;
double previousCycleRisks[];
int    cycleCount = 0;
double baseCycleMultiplier = 1.0;
datetime lastProcessedDealTime = 0;

// Test overrides
double gSavedEquity = 0.0;

void EnsureValidCompoundingWins()
{
   if(AC_CompoundingWins <= 0)
   {
      int fallbackValue = (AC_CompoundingWins_Input > 0) ? AC_CompoundingWins_Input : 1;
      AC_CompoundingWins = fallbackValue;
      Print("WARNING: AC_CompoundingWins was zero or negative. Using fallback value of ", AC_CompoundingWins, ".");
   }

   int requiredSize = MathMax(AC_CompoundingWins, 1);
   int currentSize = ArraySize(previousCycleRisks);
   if(currentSize < requiredSize)
   {
      ArrayResize(previousCycleRisks, requiredSize);
      for(int i = currentSize; i < requiredSize; ++i)
         previousCycleRisks[i] = 0.0;
   }
}

void UpdateRiskBasedOnResultWithProfitSBS(bool isWin, int magic, double profit)
{
   EnsureValidCompoundingWins();

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(isWin)
   {
      int positionInCycle = consecutiveWins % AC_CompoundingWins;
      double previousRisk = currentRisk;
      consecutiveWins++;

      if(consecutiveWins >= AC_CompoundingWins)
      {
         cycleCount++;
         previousCycleRisks[positionInCycle] = currentRisk;
         consecutiveWins = 0;
         currentRisk = AC_BaseRisk;
         currentReward = currentRisk * AC_BaseReward;
         baseCycleMultiplier = 1.0;
         Print("Maximum compounding reached. Risk reset to base level (",
               NormalizeDouble(currentRisk, 2), "%). Cycle #", cycleCount);
         return;
      }

      bool shouldCompound = true;
      double profitPercent = 0.0;

      if(profit > 0.0)
      {
         double approxEntryEquity = currentEquity - profit;
         profitPercent = (profit / approxEntryEquity) * 100.0;

         if(profitPercent < currentReward)
         {
            shouldCompound = false;
            Print("Profit (", NormalizeDouble(profitPercent, 2), "%) below target (",
                  currentReward, "%). Not compounding risk.");
         }
      }

      if(shouldCompound)
      {
         double previousReward = currentReward;
         if(consecutiveWins == 1)
         {
            previousRisk = AC_BaseRisk;
            previousReward = AC_BaseRisk * AC_BaseReward;
         }

         double rewardContribution = previousReward * AC_PartialCompoundFraction;
         currentRisk = previousRisk + rewardContribution;
         currentReward = currentRisk * AC_BaseReward;

         if(positionInCycle < ArraySize(previousCycleRisks))
            previousCycleRisks[positionInCycle] = currentRisk;

         Print("============ ASYM COMPOUNDING (SBS) ===========");
         Print("Prev Risk: ", NormalizeDouble(previousRisk, 2), "%, Prev Reward: ",
               NormalizeDouble(previousReward, 2), "%");
         Print("Added Portion: ", NormalizeDouble(rewardContribution, 2),
               "% -> New Risk: ", NormalizeDouble(currentRisk, 2), "%");
         Print("New Reward Target: ", NormalizeDouble(currentReward, 2), "%");
         Print("Consecutive Wins: ", consecutiveWins);
         Print("================================================");
      }
      else
      {
         Print("Win recorded but profit below target. Risk unchanged at ", currentRisk, "%");
      }
   }
   else
   {
      consecutiveWins = 0;
      cycleCount = 0;
      baseCycleMultiplier = 1.0;
      currentRisk = AC_BaseRisk;
      currentReward = AC_BaseRisk * AC_BaseReward;

      for(int i = 0; i < ArraySize(previousCycleRisks); i++)
         previousCycleRisks[i] = 0;

      Print("Trade loss detected. Resetting consecutive wins and cycle count.");
      Print("Risk set to ", currentRisk, "%, reward target: ", currentReward, "%");
   }

   Print("Updated risk: ", NormalizeDouble(currentRisk, 2), "%, reward target: ",
         NormalizeDouble(currentReward, 2), "%");
}

void UpdateRiskBasedOnResultSBS(bool isWin, int magic)
{
   UpdateRiskBasedOnResultWithProfitSBS(isWin, magic, 0.0);
}

void InitializeACRMSBS(bool resetFromInputs = true)
{
   if(resetFromInputs)
   {
      AC_BaseRisk = (AC_BaseRisk_Input <= 0) ? 1.0 : AC_BaseRisk_Input;
      AC_BaseRewardIsPercent = AC_BaseRewardIsPercent_Input;
      AC_BaseRewardUserValue = (AC_BaseReward_Input <= 0)
                               ? (AC_BaseRewardIsPercent ? AC_BaseRisk : 3.0)
                               : AC_BaseReward_Input;
      if(AC_BaseRewardIsPercent)
      {
         AC_BaseRewardPercent = AC_BaseRewardUserValue;
         if(AC_BaseRisk > 0.0)
            AC_BaseReward = AC_BaseRewardPercent / AC_BaseRisk;
         else
         {
            AC_BaseReward = 3.0;
            AC_BaseRewardPercent = AC_BaseRisk * AC_BaseReward;
         }
      }
      else
      {
         AC_BaseReward = AC_BaseRewardUserValue;
         AC_BaseRewardPercent = AC_BaseRisk * AC_BaseReward;
      }
      AC_CompoundingWins = (AC_CompoundingWins_Input <= 0) ? 3 : AC_CompoundingWins_Input;
      AC_EnablePartialCompoundingFlag = AC_EnablePartialCompounding_Input;
      double sanitisedPercent = MathMax(0.0, MathMin(100.0, AC_PartialCompoundPercent_Input));
      if(AC_EnablePartialCompoundingFlag)
      {
         AC_PartialCompoundingPercentEffective = sanitisedPercent;
         AC_PartialCompoundFraction = AC_PartialCompoundingPercentEffective / 100.0;
      }
      else
      {
         AC_PartialCompoundingPercentEffective = 100.0;
         AC_PartialCompoundFraction = 1.0;
      }
   }

   EnsureValidCompoundingWins();
   consecutiveWins = 0;
   cycleCount = 0;
   baseCycleMultiplier = 1.0;
   currentRisk = AC_BaseRisk;
   currentReward = currentRisk * AC_BaseReward;

   for(int i = 0; i < ArraySize(previousCycleRisks); i++)
      previousCycleRisks[i] = 0;

   if(currentRisk <= 0)
   {
      Print("WARNING: Risk percentage was zero or negative. Setting to minimum 0.1%");
      currentRisk = 0.1;
      currentReward = currentRisk * AC_BaseReward;
   }

   lastProcessedDealTime = TimeCurrent();

   // Align saved equity with live equity unless an override is set
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(resetFromInputs || gSavedEquity <= 0.0)
      gSavedEquity = accountEquity;

   Print("===== Asymmetrical Compounding (SBS) Settings =====");
   Print("Base risk: ", AC_BaseRisk, "%");
   if(AC_BaseRewardIsPercent)
      Print("Base reward target: ", NormalizeDouble(AC_BaseRewardPercent, 2),
            "% (interpreted as absolute percent, equivalent multiplier 1:",
            NormalizeDouble(AC_BaseReward, 4), ")");
   else
      Print("Base reward multiplier: ", AC_BaseReward, " (targets ",
            NormalizeDouble(AC_BaseRewardPercent, 2), "% with current base risk)");
   Print("Max consecutive wins to compound: ", AC_CompoundingWins);
   if(AC_EnablePartialCompoundingFlag)
      Print("Partial compounding: Enabled (", NormalizeDouble(AC_PartialCompoundingPercentEffective, 2), "% recycled)");
   else
      Print("Partial compounding: Disabled (full reward recycled)");
   Print("Current risk: ", currentRisk, "%");
   Print("Current reward target: ", currentReward, "%");

}

double CalculateLotSize_SBS(double stopLossDistance)
{
   if(stopLossDistance <= 0)
   {
      Print("ERROR in CalculateLotSize_SBS: Stop loss distance must be greater than zero");
      return 0.01;
   }

   double equity = (gSavedEquity > 0) ? gSavedEquity : AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (currentRisk / 100.0);
   if(riskAmount <= 0)
   {
      Print("ERROR in CalculateLotSize_SBS: Risk amount must be greater than zero");
      return 0.01;
   }

   double point = g_SymbolValidator.Point();
   double stopLossInPoints = stopLossDistance / point;

   double tickValue = g_SymbolValidator.TickValue();
   double tickSize = g_SymbolValidator.TickSize();
   double ticksPerPoint = point / tickSize;
   double onePointValue = tickValue * ticksPerPoint;

   double positionSize = riskAmount / (stopLossInPoints * onePointValue);

   double lotStep = g_SymbolValidator.LotStep();
   double minLot = g_SymbolValidator.MinLot();
   double maxLot = g_SymbolValidator.MaxLot();

   int steps = (int)MathFloor(positionSize / lotStep);
   positionSize = steps * lotStep;

   if(positionSize < minLot)
   {
      Print("WARNING: Calculated lot size (", positionSize, ") below minimum (", minLot, "). Using minimum lot size.");
      positionSize = minLot;
   }
   if(positionSize > maxLot)
   {
      Print("WARNING: Calculated lot size (", positionSize, ") exceeds maximum (", maxLot, "). Limiting to maximum lot size.");
      positionSize = maxLot;
   }

   return positionSize;
}

double CalculateLotsSBS(double stopDistance)
{
   return CalculateLotSize_SBS(stopDistance);
}

void UpdateRiskManagementSBS(int magicNumber)
{
   datetime now = TimeCurrent();
   if(!HistorySelect(lastProcessedDealTime, now))
      return;

   int totalDeals = HistoryDealsTotal();
   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      if(dealTime <= lastProcessedDealTime)
         break;

      long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      if(magic != magicNumber)
         continue;

      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      bool isWin = (profit > 0);
      UpdateRiskBasedOnResultWithProfitSBS(isWin, magicNumber, profit);
      lastProcessedDealTime = dealTime;
   }
}
