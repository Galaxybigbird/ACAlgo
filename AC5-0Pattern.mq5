//+------------------------------------------------------------------+
//|                                                  AC5-0Pattern.mq5 |
//|                           AC asymmetric compounding 5-0 pattern  |
//+------------------------------------------------------------------+
#property copyright "AC Algo"
#property version   "1.01"
#property strict
#property description "5-0 harmonic pattern EA with AC risk management and ATR trailing"

#include <Trade/Trade.mqh>
#include <ACFunctions.mqh>
#include <ATRtrailing.mqh>
#include <AC_OptCriterion.mqh>
#include <SymbolValidator.mqh>

// Directional bias options (reuse the same enum as other AC EAs)
enum ENUM_TRADE_BIAS
{
   Both      = 0,
   LongOnly  = 1,
   ShortOnly = 2
};

CTrade           trade;
CSymbolValidator g_SymbolValidator;
ACOptConfig      g_ACOptCfg;

//--- Performance / execution flags
bool   isInBacktest     = false;
bool   isForwardTest    = false;
bool   isFastModeContext= false;
bool   allowVerboseLogs = false;    // keep false to avoid noisy experts logging

//--- Performance settings
input group "==== Performance Settings ===="
input bool     OptimizationMode = true;
input int      UpdateFrequency  = 5;

//--- Custom optimization criterion settings
input group "==== Optimization Criterion Settings ===="
input bool     UseCustomMax          = true;
input int      Opt_MinTrades         = 50;
input double   Opt_MinOosPF          = 1.20;
input double   Opt_MaxOosDDPercent   = 30.0;
input double   Opt_InSampleFraction  = 0.70;
input int      Opt_OosGapDays        = 1;
input int      Opt_McSimulations     = 500;
input int      Opt_McBlockLen        = 5;
input int      Opt_McSeed            = 1337;
input double   Opt_W_PF              = 1.0;
input double   Opt_W_DD              = 2.0;
input double   Opt_W_Sharpe          = 1.0;
input double   Opt_W_McPF            = 1.0;
input double   Opt_W_McDD            = 2.0;

//--- Trading settings
input group "==== Trading Settings ===="
input double   DefaultLot   = 0.60;
input int      Slippage     = 20;
input int      MagicNumber  = 14500;
input string   TradeComment = "AC5-0";
input bool     UseTakeProfit= true;
input ENUM_TRADE_BIAS TradeDirectionBias = Both;

//--- Risk management settings
input group "==== Risk Management Settings ===="
input bool     UseACRiskManagement = true;

//--- Stop tightening settings
input group "==== Stop Tightening Settings ===="
input int      MaxHoldBars = 0;

//--- Pattern configuration
input group "==== 5-0 Pattern Settings ===="
input ENUM_TIMEFRAMES PatternTimeframe = PERIOD_CURRENT;
input int      PatternLookbackBars = 400;
input int      PatternSwingDepth   = 4;
input double   Pattern_B_XA_Max    = 161.8;
input double   Pattern_B_XA_Min    = 113.0;
input double   Pattern_C_AB_Max    = 224.0;
input double   Pattern_C_AB_Min    = 161.8;
input double   Pattern_D_BC_Max    = 55.0;
input double   Pattern_D_BC_Min    = 50.0;

//--- Pattern buffers
double   openBuffer[];
double   closeBuffer[];
double   lowBuffer[];
double   highBuffer[];
datetime timeBuffer[];
datetime priceTimeBuffer[];

//--- Pattern state
datetime lastTradeBarTime = 0;
int      cachedBars       = 0;

//--- Trailing helpers
datetime lastProcessedBarTime = 0;
int      tickCounter = 0;

//--- Custom optimisation metrics
double customWinRate = 0;
double customWinningTrades = 0;
double customLosingTrades = 0;
double customFinalBalance = 0;
double customAvgTradesDaily = 0;
double customMaxConsecWinners = 0;
double customMaxConsecLosers = 0;
double customAvgWinAmount = 0;
double customAvgLossAmount = 0;

// Optimization summary globals (shown in tester grid)
double g_WinRate = 0;
double g_WinTrades = 0;
double g_LossTrades = 0;
double g_FinalBalance = 0;
double g_AvgTradesDaily = 0;
double g_MaxConsecWins = 0;
double g_MaxConsecLoss = 0;
double g_AvgWinAmount = 0;
double g_AvgLossAmount = 0;

//--- AC optimisation frame capture
int      g_ACOptCsvHandle = INVALID_HANDLE;
string   g_ACOptCsvFilename = "";
string   g_ACOptCsvPath = "";
datetime g_ACOptRunStart = 0;

//--- Forward declarations
bool   IsSwingLow(const double &low_prices[], int index, int lookback);
   bool   IsSwingHigh(const double &high_prices[], int index, int lookback);
   bool   HasOpenPosition();
bool   AttemptPatternEntry(double patternStopPrice, datetime barTime, ENUM_ORDER_TYPE orderType);
   bool   IsTradeBiasAllowed(ENUM_ORDER_TYPE orderType);
void   ExecuteTrade(ENUM_ORDER_TYPE orderType, double patternStopPrice);
void   UpdateAllTrailingStops(bool newBar);
double CalcTradesPerDayFromHistory();

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   bool isOptimizationPass = (MQLInfoInteger(MQL_OPTIMIZATION) == 1);
   bool isTesterPass       = (MQLInfoInteger(MQL_TESTER) == 1);
   isForwardTest           = (MQLInfoInteger(MQL_FORWARD) == 1);

   isInBacktest      = isOptimizationPass || isTesterPass;
   isFastModeContext = isInBacktest && (OptimizationMode || isForwardTest);
   allowVerboseLogs  = false; // remain silent unless debugging manually

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MagicNumber);

   if(!g_SymbolValidator.Init(_Symbol))
   {
      Print("ERROR: Failed to initialise symbol validator for ", _Symbol);
      return INIT_FAILED;
   }

   InitializeACRiskManagement();
   InitDEMAATR();

   ArraySetAsSeries(priceTimeBuffer, true);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanupATRTrailing();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateRiskManagement(MagicNumber);

   // Lightweight throttling during optimisations
   if(isFastModeContext)
   {
      tickCounter++;
      if(tickCounter < UpdateFrequency)
         return;
      tickCounter = 0;
   }

   datetime currentBarTime = iTime(_Symbol, PatternTimeframe, 0);
   bool isNewBar = (currentBarTime != lastProcessedBarTime);
   if(isNewBar)
      lastProcessedBarTime = currentBarTime;
   else
   {
      // No need to rescan the entire pattern tree multiple times per bar; just maintain trailing stops.
      UpdateAllTrailingStops(false);
      return;
   }

   // Prepare required price data
   int bars = Bars(_Symbol, PatternTimeframe);
   if(bars < PatternLookbackBars)
      return;

   datetime time_bar = currentBarTime;
   if(time_bar == 0)
      return;

   if(CopyOpen(_Symbol, PatternTimeframe, time_bar, PatternLookbackBars, openBuffer)   <= 0) return;
   if(CopyClose(_Symbol, PatternTimeframe, time_bar, PatternLookbackBars, closeBuffer) <= 0) return;
   if(CopyLow(_Symbol, PatternTimeframe, time_bar, PatternLookbackBars, lowBuffer)     <= 0) return;
   if(CopyHigh(_Symbol, PatternTimeframe, time_bar, PatternLookbackBars, highBuffer)   <= 0) return;
   if(CopyTime(_Symbol, PatternTimeframe, time_bar, PatternLookbackBars, timeBuffer)   <= 0) return;
   if(CopyTime(_Symbol, PatternTimeframe, 0, 2, priceTimeBuffer) <= 0) return;

   cachedBars = ArraySize(closeBuffer);
   if(ArraySize(openBuffer) != cachedBars ||
      ArraySize(lowBuffer)  != cachedBars ||
      ArraySize(highBuffer) != cachedBars ||
      ArraySize(timeBuffer) != cachedBars)
   {
      return;
   }
   if(cachedBars <= PatternSwingDepth * 2)
      return;

   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(askPrice <= 0)
      return;

   bool allowLongs  = IsTradeBiasAllowed(ORDER_TYPE_BUY);
   bool allowShorts = IsTradeBiasAllowed(ORDER_TYPE_SELL);
   if(!allowLongs && !allowShorts)
   {
      UpdateAllTrailingStops(isNewBar);
      return;
   }

   // Skip search if we already have a position open
   if(HasOpenPosition())
   {
      UpdateAllTrailingStops(isNewBar);
      return;
   }

   // Build swing index lists once per bar to limit combinatorial scans
   int swingHighIdx[];
   int swingLowIdx[];
   ArrayResize(swingHighIdx, 0);
   ArrayResize(swingLowIdx, 0);
   for(int idx = PatternSwingDepth; idx < cachedBars - PatternSwingDepth; ++idx)
   {
      if(IsSwingHigh(highBuffer, idx, PatternSwingDepth))
      {
         int pos = ArraySize(swingHighIdx);
         ArrayResize(swingHighIdx, pos + 1);
         swingHighIdx[pos] = idx;
      }
      if(IsSwingLow(lowBuffer, idx, PatternSwingDepth))
      {
         int pos = ArraySize(swingLowIdx);
         ArrayResize(swingLowIdx, pos + 1);
         swingLowIdx[pos] = idx;
      }
   }

   int highCount = ArraySize(swingHighIdx);
   int lowCount  = ArraySize(swingLowIdx);

   // Pattern search (long branch)
   if(allowLongs && highCount > 0 && lowCount > 0)
   {
      for(int idxI = 0; idxI < highCount; ++idxI)
      {
         int i = swingHighIdx[idxI];
         for(int idxJ = 0; idxJ < lowCount; ++idxJ)
         {
            int j = swingLowIdx[idxJ];
            if(j <= i)
               continue;

            double X_val = lowBuffer[j];
            double iHigh = highBuffer[i];
            if(X_val >= iHigh)
               continue;

            for(int idxA = idxI + 1; idxA < highCount; ++idxA)
            {
               int a = swingHighIdx[idxA];
               if(a > j)
                  break;

               double A_price = highBuffer[a];
               if(A_price <= X_val)
                  continue;

               double XA_length = MathAbs(A_price - X_val);
               if(XA_length == 0.0)
                  continue;

               for(int idxL = idxJ + 1; idxL < lowCount; ++idxL)
               {
                  int l = swingLowIdx[idxL];
                  if(l <= a)
                     continue;

                  double B_price = lowBuffer[l];
                  if(B_price >= X_val)
                     continue;

                  double B_XA_extension = ((B_price - X_val) / XA_length) * 100.0;
                  if(B_XA_extension < Pattern_B_XA_Min || B_XA_extension > Pattern_B_XA_Max)
                     continue;

                  double AB_length = MathAbs(B_price - A_price);
                  if(AB_length == 0.0)
                     continue;

                  for(int idxM = 0; idxM < highCount; ++idxM)
                  {
                     int m = swingHighIdx[idxM];
                     if(m <= l)
                        continue;

                     double C_price = highBuffer[m];
                     if(C_price <= B_price)
                        continue;

                     double C_AB_extension = ((C_price - B_price) / AB_length) * 100.0;
                     if(C_AB_extension < Pattern_C_AB_Min || C_AB_extension > Pattern_C_AB_Max)
                        continue;

                     double BC_length = MathAbs(C_price - B_price);
                     if(BC_length == 0.0)
                        continue;

                     for(int idxN = idxL + 1; idxN < lowCount; ++idxN)
                     {
                        int n = swingLowIdx[idxN];
                        if(n <= m)
                           continue;

                        double D_price = lowBuffer[n];
                        double D_BC_retrace = ((D_price - C_price) / BC_length) * 100.0;
                        if(D_BC_retrace < Pattern_D_BC_Min || D_BC_retrace > Pattern_D_BC_Max)
                           continue;

                        if(n + PatternSwingDepth >= cachedBars)
                           continue;

                        if(timeBuffer[n + PatternSwingDepth] != priceTimeBuffer[1])
                           continue;

                        if(closeBuffer[n + PatternSwingDepth] <= D_price)
                           continue;

                        if(currentBarTime == lastTradeBarTime)
                           continue;

                        if(AttemptPatternEntry(D_price, currentBarTime, ORDER_TYPE_BUY))
                        {
                           UpdateAllTrailingStops(isNewBar);
                           return;
                        }
                     }
                  }
               }
            }
         }
      }
   }

   // Pattern search (short branch)
   if(allowShorts && highCount > 0 && lowCount > 0)
   {
      for(int idxI = 0; idxI < lowCount; ++idxI)
      {
         int i = swingLowIdx[idxI];
         for(int idxJ = 0; idxJ < highCount; ++idxJ)
         {
            int j = swingHighIdx[idxJ];
            if(j <= i)
               continue;

            double X_val = highBuffer[j];
            double iLow = lowBuffer[i];
            if(X_val <= iLow)
               continue;

            for(int idxA = idxI + 1; idxA < lowCount; ++idxA)
            {
               int a = swingLowIdx[idxA];
               if(a > j)
                  break;

               double A_price = lowBuffer[a];
               if(A_price >= X_val)
                  continue;

               double XA_length = MathAbs(X_val - A_price);
               if(XA_length == 0.0)
                  continue;

               for(int idxL = idxJ + 1; idxL < highCount; ++idxL)
               {
                  int l = swingHighIdx[idxL];
                  if(l <= a)
                     continue;

                  double B_price = highBuffer[l];
                  if(B_price <= X_val)
                     continue;

                  double B_XA_extension = ((B_price - X_val) / XA_length) * 100.0;
                  if(B_XA_extension < Pattern_B_XA_Min || B_XA_extension > Pattern_B_XA_Max)
                     continue;

                  double AB_length = MathAbs(B_price - A_price);
                  if(AB_length == 0.0)
                     continue;

                  for(int idxM = 0; idxM < lowCount; ++idxM)
                  {
                     int m = swingLowIdx[idxM];
                     if(m <= l)
                        continue;

                     double C_price = lowBuffer[m];
                     if(C_price >= B_price)
                        continue;

                     double C_AB_extension = ((B_price - C_price) / AB_length) * 100.0;
                     if(C_AB_extension < Pattern_C_AB_Min || C_AB_extension > Pattern_C_AB_Max)
                        continue;

                     double BC_length = MathAbs(B_price - C_price);
                     if(BC_length == 0.0)
                        continue;

                     for(int idxN = idxL + 1; idxN < highCount; ++idxN)
                     {
                        int n = swingHighIdx[idxN];
                        if(n <= m)
                           continue;

                        double D_price = highBuffer[n];
                        double D_BC_retrace = ((D_price - C_price) / BC_length) * 100.0;
                        if(D_BC_retrace < Pattern_D_BC_Min || D_BC_retrace > Pattern_D_BC_Max)
                           continue;

                        if(n + PatternSwingDepth >= cachedBars)
                           continue;

                        if(timeBuffer[n + PatternSwingDepth] != priceTimeBuffer[1])
                           continue;

                        if(closeBuffer[n + PatternSwingDepth] >= D_price)
                           continue;

                        if(currentBarTime == lastTradeBarTime)
                           continue;

                        if(AttemptPatternEntry(D_price, currentBarTime, ORDER_TYPE_SELL))
                        {
                           UpdateAllTrailingStops(isNewBar);
                           return;
                        }
                     }
                  }
               }
            }
         }
      }
   }

   UpdateAllTrailingStops(isNewBar);
}

//+------------------------------------------------------------------+
//| Attempt to open a trade when pattern completes                   |
//+------------------------------------------------------------------+
bool AttemptPatternEntry(double patternStopPrice, datetime barTime, ENUM_ORDER_TYPE orderType)
{
   if(!IsTradeBiasAllowed(orderType))
      return false;

   if(HasOpenPosition())
      return false;

   ExecuteTrade(orderType, patternStopPrice);
   if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      lastTradeBarTime = barTime;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check trade bias filters                                          |
//+------------------------------------------------------------------+
bool IsTradeBiasAllowed(ENUM_ORDER_TYPE orderType)
{
   if(TradeDirectionBias == Both)
      return true;
   if(TradeDirectionBias == LongOnly && orderType == ORDER_TYPE_BUY)
      return true;
   if(TradeDirectionBias == ShortOnly && orderType == ORDER_TYPE_SELL)
      return true;
   return false;
}

//+------------------------------------------------------------------+
//| Determine if there is already an open position for this EA       |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Execute trade with AC risk management and ATR stop integration   |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType, double patternStopPrice)
{
   // Determine base stop loss from ATR
   double stopLossDistance = GetStopLossDistance();
   if(stopLossDistance <= 0.0)
   {
      Print("ERROR: Failed to calculate ATR-based stop distance.");
      return;
   }

   double symbolPoint = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(symbolPoint <= 0.0)
      symbolPoint = _Point;

   double price = SymbolInfoDouble(_Symbol,
                                   orderType == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
   if(price <= 0.0)
      return;

   // Blend pattern-derived stop with ATR-based stop
   if(orderType == ORDER_TYPE_BUY && patternStopPrice > 0.0 && price > patternStopPrice)
   {
      double patternDistance = price - patternStopPrice;
      double maxDistance = (MaxStopLossDistance > 0.0) ? MaxStopLossDistance * symbolPoint : 0.0;
      double desiredDistance = MathMax(stopLossDistance, patternDistance);
      if(maxDistance > 0.0)
         desiredDistance = MathMin(desiredDistance, maxDistance);
      if(desiredDistance > 0.0)
         stopLossDistance = desiredDistance;
   }
   else if(orderType == ORDER_TYPE_SELL && patternStopPrice > 0.0 && price < patternStopPrice)
   {
      double patternDistance = patternStopPrice - price;
      double maxDistance = (MaxStopLossDistance > 0.0) ? MaxStopLossDistance * symbolPoint : 0.0;
      double desiredDistance = MathMax(stopLossDistance, patternDistance);
      if(maxDistance > 0.0)
         desiredDistance = MathMin(desiredDistance, maxDistance);
      if(desiredDistance > 0.0)
         stopLossDistance = desiredDistance;
   }

   double stopLossLevel = (orderType == ORDER_TYPE_BUY)
                          ? price - stopLossDistance
                          : price + stopLossDistance;

   // Broker minimum stop distance
   double minStopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(minStopLevel < 0.0)
      minStopLevel = 0.0;

   double stopLossPoints = stopLossDistance / symbolPoint;
   if(stopLossPoints < minStopLevel)
   {
      stopLossPoints = minStopLevel;
      stopLossDistance = stopLossPoints * symbolPoint;
      stopLossLevel = (orderType == ORDER_TYPE_BUY)
                      ? price - stopLossDistance
                      : price + stopLossDistance;
   }

   // Align with tick size
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize > 0.0)
   {
      double ticks = MathFloor(stopLossDistance / tickSize);
      if(ticks < 1.0)
         ticks = 1.0;
      stopLossDistance = ticks * tickSize;
      stopLossPoints   = stopLossDistance / symbolPoint;
      stopLossLevel    = (orderType == ORDER_TYPE_BUY)
                         ? price - stopLossDistance
                         : price + stopLossDistance;
   }

   // Calculate lot sizing
   double lotSize = DefaultLot;
   if(UseACRiskManagement)
   {
      lotSize = CalculateLotSize(stopLossDistance);
      if(lotSize <= 0.0)
      {
         Print("ERROR: Calculated lot size was non-positive. Trade cancelled.");
         return;
      }

      // Optimise lot/stop pairing if required
      OptimizeRiskParameters(lotSize, stopLossDistance);
      stopLossPoints = stopLossDistance / symbolPoint;
      stopLossLevel  = (orderType == ORDER_TYPE_BUY)
                       ? price - stopLossDistance
                       : price + stopLossDistance;
   }

   lotSize = g_SymbolValidator.ValidateVolume(
      (orderType == ORDER_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, lotSize);
   if(lotSize <= 0.0)
   {
      Print("ERROR: Volume validation failed. Trade cancelled.");
      return;
   }

   stopLossLevel = g_SymbolValidator.ValidateStopLoss(
      (orderType == ORDER_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
      price,
      stopLossLevel);

   // Calculate take profit based on reward target
   double takeProfitDistance = 0.0;
   if(UseACRiskManagement)
   {
      double riskToRewardRatio = (currentRisk > 0.0) ? currentReward / currentRisk : AC_BaseReward;
      double takeProfitPoints = stopLossPoints * riskToRewardRatio;
      takeProfitDistance = takeProfitPoints * symbolPoint;
   }
   else
   {
      double takeProfitPoints = stopLossPoints * AC_BaseReward;
      takeProfitDistance = takeProfitPoints * symbolPoint;
   }

   double takeProfitLevel = (orderType == ORDER_TYPE_BUY)
                            ? price + takeProfitDistance
                            : price - takeProfitDistance;

   if(!UseTakeProfit)
      takeProfitLevel = 0.0;

   if(orderType == ORDER_TYPE_BUY)
      trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, lotSize, price, stopLossLevel, takeProfitLevel, TradeComment);
   else
      trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, lotSize, price, stopLossLevel, takeProfitLevel, TradeComment);

   if(trade.ResultRetcode() != TRADE_RETCODE_DONE)
   {
      Print("ERROR: Trade execution failed. Retcode=", trade.ResultRetcode(),
            " comment=", trade.ResultComment());
   }
}

//+------------------------------------------------------------------+
//| Update trailing stops                                            |
//+------------------------------------------------------------------+
void UpdateAllTrailingStops(bool newBar)
{
   if(isInBacktest && !newBar && !ManualTrailingActivated)
      return;

   int total = PositionsTotal();
   for(int i = 0; i < total; ++i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string orderType = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double volume = PositionGetDouble(POSITION_VOLUME);
      string positionComment = PositionGetString(POSITION_COMMENT);
         bool trailingAllowed = TrailingAllowedForPosition(positionComment, ticket);
      bool compoundedOverrideActive = IsCompoundedTrailingOverride(positionComment);

      if(!trailingAllowed)
         continue;

      if(!ManualTrailingActivated)
      {
         if(!ShouldActivateTrailing(entryPrice, currentPrice, orderType, volume, compoundedOverrideActive, ticket))
            continue;
      }

      UpdateTrailingStop(ticket, entryPrice, orderType);
   }
}

//+------------------------------------------------------------------+
//| Helper: calculate trades per day                                 |
//+------------------------------------------------------------------+
double CalcTradesPerDayFromHistory()
{
   if(!HistorySelect(0, TimeCurrent()))
      return 0.0;

   int totalDeals = (int)HistoryDealsTotal();
   if(totalDeals <= 0)
      return 0.0;

   datetime firstTime = 0;
   datetime lastTime = 0;
   int tradeCount = 0;

   for(int i = 0; i < totalDeals; ++i)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;

      long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
         continue;

      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(tradeCount == 0)
         firstTime = dealTime;
      lastTime = dealTime;
      ++tradeCount;
   }

   if(tradeCount <= 1)
      return (double)tradeCount;

   double days = MathMax(1.0, (double)(lastTime - firstTime) / 86400.0);
   return (double)tradeCount / days;
}

//+------------------------------------------------------------------+
//| Strategy tester optimisation metric                              |
//+------------------------------------------------------------------+
double OnTester()
{
   double trades = TesterStatistics((ENUM_STATISTICS)STAT_TRADES);
   if(trades < 1)
      return UseCustomMax ? -DBL_MAX : 0.0;

   double profit        = TesterStatistics((ENUM_STATISTICS)STAT_PROFIT);
   double profitFactor  = TesterStatistics((ENUM_STATISTICS)STAT_PROFIT_FACTOR);
   double sharpeRatio   = TesterStatistics((ENUM_STATISTICS)STAT_SHARPE_RATIO);
   double recoveryFactor= TesterStatistics((ENUM_STATISTICS)STAT_RECOVERY_FACTOR);
   double drawdownRel   = TesterStatistics((ENUM_STATISTICS)STAT_EQUITY_DDREL_PERCENT);
   double finalBalance  = AccountInfoDouble(ACCOUNT_BALANCE);

   double winningTrades = TesterStatistics((ENUM_STATISTICS)STAT_PROFIT_TRADES);
   double losingTrades  = TesterStatistics((ENUM_STATISTICS)STAT_LOSS_TRADES);
   double winRate       = (trades > 0.0) ? (winningTrades / trades) * 100.0 : 0.0;
   double avgTradesDaily= CalcTradesPerDayFromHistory();

   double maxConsecWinners = MathSqrt(MathMax(0.0, winningTrades));
   double maxConsecLosers  = MathSqrt(MathMax(0.0, losingTrades));

   double grossProfit = TesterStatistics((ENUM_STATISTICS)STAT_GROSS_PROFIT);
   double grossLoss   = TesterStatistics((ENUM_STATISTICS)STAT_GROSS_LOSS);
   double avgWinAmount  = (winningTrades > 0.0) ? grossProfit / winningTrades : 0.0;
   double avgLossAmount = (losingTrades  > 0.0) ? grossLoss / losingTrades   : 0.0;

   double metric = profitFactor;
   if(drawdownRel > 20.0) metric *= 0.8;
   if(drawdownRel > 30.0) metric *= 0.5;
   if(recoveryFactor > 2.0) metric *= 1.2;

   double resultScore = metric;

   if(UseCustomMax)
   {
      g_ACOptCfg.MinTrades        = Opt_MinTrades;
      g_ACOptCfg.MinOosPF         = Opt_MinOosPF;
      g_ACOptCfg.MaxOosDDPercent  = Opt_MaxOosDDPercent;
      g_ACOptCfg.InSampleFrac     = Opt_InSampleFraction;
      g_ACOptCfg.OosGapDays       = Opt_OosGapDays;
      g_ACOptCfg.McSimulations    = Opt_McSimulations;
      g_ACOptCfg.McBlockLenTrades = Opt_McBlockLen;
      g_ACOptCfg.McSeed           = Opt_McSeed;
      g_ACOptCfg.w_pf             = Opt_W_PF;
      g_ACOptCfg.w_dd             = Opt_W_DD;
      g_ACOptCfg.w_sharpe         = Opt_W_Sharpe;
      g_ACOptCfg.w_mc_pf          = Opt_W_McPF;
      g_ACOptCfg.w_mc_dd          = Opt_W_McDD;
      g_ACOptCfg.MagicFilter      = MagicNumber;

      AC_Opt_Init(g_ACOptCfg);
      resultScore = AC_CalcCustomCriterion();
      AC_PublishFrames();

      double tradesPerDayOpt = AC_GetTradesPerDay();
      if(tradesPerDayOpt > 0.0)
         avgTradesDaily = tradesPerDayOpt;

      double ddOpt = AC_GetOosDrawdownPercent();
      if(drawdownRel <= 0.0 && ddOpt > 0.0)
         drawdownRel = ddOpt;
   }

   customWinRate          = NormalizeDouble(winRate, 2);
   customWinningTrades    = winningTrades;
   customLosingTrades     = losingTrades;
   customFinalBalance     = NormalizeDouble(finalBalance, 2);
   customAvgTradesDaily   = NormalizeDouble(avgTradesDaily, 2);
   customMaxConsecWinners = maxConsecWinners;
   customMaxConsecLosers  = maxConsecLosers;
   customAvgWinAmount     = NormalizeDouble(avgWinAmount, 2);
   customAvgLossAmount    = NormalizeDouble(avgLossAmount, 2);

   if(MQLInfoInteger(MQL_OPTIMIZATION))
   {
      g_WinRate        = customWinRate;
      g_WinTrades      = customWinningTrades;
      g_LossTrades     = customLosingTrades;
      g_FinalBalance   = customFinalBalance;
      g_AvgTradesDaily = customAvgTradesDaily;
      g_MaxConsecWins  = customMaxConsecWinners;
      g_MaxConsecLoss  = customMaxConsecLosers;
      g_AvgWinAmount   = customAvgWinAmount;
      g_AvgLossAmount  = customAvgLossAmount;
   }

   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
   {
      Comment(StringFormat("WR=%.1f%% WT=%d LT=%d Bal=%.2f TpD=%.1f",
                           customWinRate,
                           (int)customWinningTrades,
                           (int)customLosingTrades,
                           customFinalBalance,
                           customAvgTradesDaily));
   }

   return resultScore;
}

//+------------------------------------------------------------------+
//| Helper: drain ACOPT frames into CSV                              |
//+------------------------------------------------------------------+
void AC_WriteFramesToCsv()
{
   if(!UseCustomMax || g_ACOptCsvHandle == INVALID_HANDLE)
      return;

   ulong frameId = 0;
   string frameName;
   long passId = 0;
   double frameScore = 0.0;
   double payload[];

   while(FrameNext(frameId, frameName, passId, frameScore, payload))
   {
      if(frameName != "ACOPT")
         continue;

      int payloadSize = ArraySize(payload);
      if(payloadSize < ACOPT__COUNT)
      {
         PrintFormat("ACOPT frame payload too small (%d).", payloadSize);
         continue;
      }

      payload[ACOPT_SCORE] = frameScore;

      FileWrite(g_ACOptCsvHandle,
                (int)passId,
                payload[ACOPT_SCORE],
                payload[ACOPT_PF_IS],
                payload[ACOPT_PF_OOS],
                payload[ACOPT_DD_IS_PCT],
                payload[ACOPT_DD_OOS_PCT],
                payload[ACOPT_SHARPE_IS],
                payload[ACOPT_SHARPE_OOS],
                payload[ACOPT_SORTINO_IS],
                payload[ACOPT_SORTINO_OOS],
                payload[ACOPT_SERENITY_IS],
                payload[ACOPT_SERENITY_OOS],
                payload[ACOPT_MC_PF_P5],
                payload[ACOPT_MC_DD_P95],
                payload[ACOPT_MC_P_RUIN],
                payload[ACOPT_KS_DIST],
                payload[ACOPT_JB_P],
                payload[ACOPT_TRADES_TOTAL],
                payload[ACOPT_TRADES_PER_DAY],
                payload[ACOPT_WINRATE_OOS_PCT],
                payload[ACOPT_EXP_PAYOFF_OOS],
                payload[ACOPT_AVG_WIN_OOS],
                payload[ACOPT_AVG_LOSS_OOS],
                payload[ACOPT_PAYOFF_RATIO_OOS]);
   }
}

//+------------------------------------------------------------------+
//| Tester lifecycle                                                 |
//+------------------------------------------------------------------+
void OnTesterInit()
{
   g_ACOptCsvHandle = INVALID_HANDLE;
   g_ACOptCsvFilename = "";
   g_ACOptCsvPath = "";
   g_ACOptRunStart = 0;

   if(!UseCustomMax)
      return;

   g_ACOptRunStart = TimeCurrent();
   g_ACOptCsvFilename = StringFormat("ACOPT_%s_%I64d.csv", _Symbol, (long)g_ACOptRunStart);
   g_ACOptCsvHandle = FileOpen(g_ACOptCsvFilename, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(g_ACOptCsvHandle == INVALID_HANDLE)
   {
      PrintFormat("Failed to create optimization CSV %s (%d).", g_ACOptCsvFilename, GetLastError());
      g_ACOptCsvFilename = "";
      return;
   }

   g_ACOptCsvPath = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" + g_ACOptCsvFilename;
   FileWrite(g_ACOptCsvHandle,
             "pass_id",
             "score",
             "pf_is",
             "pf_oos",
             "dd_is_percent",
             "dd_oos_percent",
             "sharpe_is",
             "sharpe_oos",
             "sortino_is",
             "sortino_oos",
             "serenity_is",
             "serenity_oos",
             "mc_pf_p5",
             "mc_dd_p95",
             "mc_p_ruin",
             "ks_dist",
             "jb_p",
             "trades_total",
             "trades_per_day",
             "winrate_oos_pct",
             "expected_payoff_oos",
             "avg_win_oos",
             "avg_loss_oos",
             "payoff_ratio_oos");
   FileFlush(g_ACOptCsvHandle);
}

void OnTesterPass()
{
   AC_WriteFramesToCsv();
}

void OnTesterDeinit()
{
   AC_WriteFramesToCsv();

   if(g_ACOptCsvHandle != INVALID_HANDLE)
   {
      FileClose(g_ACOptCsvHandle);
      g_ACOptCsvHandle = INVALID_HANDLE;
   }

   if(UseCustomMax && g_ACOptCsvFilename != "")
      PrintFormat("AC optimization frames saved to %s.", g_ACOptCsvPath);
}

//+------------------------------------------------------------------+
//| Swing helpers                                                    |
//+------------------------------------------------------------------+
bool IsSwingLow(const double &low_prices[], int index, int lookback)
{
   for(int i = 1; i <= lookback; ++i)
   {
      if(low_prices[index] > low_prices[index - i] || low_prices[index] > low_prices[index + i])
         return false;
   }
   return true;
}

bool IsSwingHigh(const double &high_prices[], int index, int lookback)
{
   for(int i = 1; i <= lookback; ++i)
   {
      if(high_prices[index] < high_prices[index - i] || high_prices[index] < high_prices[index + i])
         return false;
   }
   return true;
}
