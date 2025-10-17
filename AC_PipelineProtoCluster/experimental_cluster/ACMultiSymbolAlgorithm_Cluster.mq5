//+------------------------------------------------------------------+
//|                                      ACMultiSymbolAlgorithm.mq5 |
//|                    Multi-symbol variant of Main AC Algorithm |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "1.04"
#property strict
#property description "Multi-symbol AC trading EA (subset: ATR trailing, T3, VWAP, Engulfing)"

#include <Trade/Trade.mqh>
#include <Arrays/ArrayObj.mqh>
#include <Object.mqh>

#include <T3.mqh>
#include <vwap_lite.mqh>
#include <EngulfingSignals.mqh>

#include <ACFunctions.mqh>
#include <SymbolValidator.mqh>
#include <ClusteringLib/Database.mqh>

//--- Performance / execution settings
input group "==== Performance Settings ===="
input bool     OptimizationMode = true;
input int      UpdateFrequency = 5;
input int      TimerIntervalSeconds = 1;

input group "==== Cluster Portfolio Settings ===="
sinput string  fileName_           = "database.sqlite"; // - SQLite database file
input int      idParentJob_        = 0;                 // - Parent job ID supplying passes
input bool     useClusters_        = true;              // - Enforce one pass per cluster
input double   minCustomOntester_  = 0.0;               // - Min normalized profit filter
input int      minTrades_          = 40;                // - Min trade count filter
input double   minSharpeRatio_     = 0.7;               // - Min Sharpe filter
input int      clusterSelectCount  = 16;                // - Number of passes to inspect

//--- Trading parameters
input group "==== Trading Settings ===="
input double   DefaultLot = 0.01;
input int      Slippage = 20;
input int      MagicNumber = 223344;
input string   TradeComment = "ACMulti";
input bool     UseTakeProfit = true;

//--- Risk settings
input group "==== Risk Management Settings ===="
input bool     UseACRiskManagement = true;
input int      MaxOpenTrades = 2;
input int      MaxCompoundTrades = 1;
input bool     AllowMultiplePositionsPerSymbol = false;

//--- Multi-symbol cluster configuration
input group "==== Multi-Symbol Clusters ===="
input bool     Cluster1Enabled = true;
input string   Cluster1Symbols = "NAS100,SP500,DJ30,GER40,UK100,HK50,CHINA50,USDX,SA40,BVSPX";
input bool     Cluster2Enabled = true;
input string   Cluster2Symbols = "XAUUSD,XAGUSD,XAUJPY,XPTUSD,XPDUSD";
input bool     Cluster3Enabled = true;
input string   Cluster3Symbols = "EURUSD,GBPUSD,USDJPY,USDCHF,AUDUSD,NZDUSD,USDCAD,EURJPY,GBPJPY,AUDJPY";
input bool     Cluster4Enabled = true;
input string   Cluster4Symbols = "BTCUSD,ETHUSD,ADAUSD,SOLUSD,XRPUSD,LTCUSD,BNBUSD,DOTUSD,TRXUSD,DOGUSD";

//--- Trade bias / thresholds
input group "==== Trade Direction Bias ===="
input int      MinSignalsToEnterBoth = 1;
input int      MinSignalsToEnterLong = 1;
input int      MinSignalsToEnterShort = 1;

//--- Stop clamp controls
input group "==== Stop Tightening Settings ===="
input int      MaxHoldBars = 0;

// Bias selection (reused from original EA)
enum ENUM_TRADE_BIAS
{
   Both      = 0,
   LongOnly  = 1,
   ShortOnly = 2
};
input ENUM_TRADE_BIAS TradeDirectionBias = Both;

//--- ATR-based trailing (simplified implementation)
input group "==== ATR Trailing Settings ===="
input bool     UseATRTrailing        = true;
input int      ATRTrailingPeriod     = 14;
input double   ATRTrailingMultiplier = 1.5;
input double   TrailingActivationPercent = 1.0;
input double   MinimumTrailingDistancePoints = 400.0;

//--- T3 indicator settings
input group "==== T3 Indicator Settings ===="
input bool     UseT3Indicator = true;
input int      T3_Length = 12;
input double   T3_Factor = 0.7;
input ENUM_APPLIED_PRICE T3_Applied_Price = PRICE_CLOSE;

//--- VWAP indicator settings
enum ENUM_VWAP_TIMEFRAMES
{
   VWAP_DISABLED = -1,
   VWAP_M1 = PERIOD_M1,
   VWAP_M5 = PERIOD_M5,
   VWAP_M15 = PERIOD_M15,
   VWAP_M30 = PERIOD_M30,
   VWAP_H1 = PERIOD_H1,
   VWAP_H4 = PERIOD_H4,
   VWAP_D1 = PERIOD_D1
};

input group "==== VWAP Indicator Settings ===="
input bool     UseVWAPIndicator = true;
input bool     Enable_Daily_VWAP = true;
input ENUM_VWAP_TIMEFRAMES VWAP_Timeframe1 = VWAP_M5;
input ENUM_VWAP_TIMEFRAMES VWAP_Timeframe2 = VWAP_DISABLED;
input ENUM_VWAP_TIMEFRAMES VWAP_Timeframe3 = VWAP_DISABLED;
input ENUM_VWAP_TIMEFRAMES VWAP_Timeframe4 = VWAP_DISABLED;
input ENUM_VWAP_TIMEFRAMES VWAP_Timeframe5 = VWAP_DISABLED;
input bool     UseT3VWAPFilter = true;

//--- Engulfing signal settings
input group "==== Engulfing Pattern Settings ===="
input bool     UseEngulfingPattern = false;

//--- Signal confirmation
input group "==== Signal Confirmation ===="
input int      SignalConfirmationBars = 2;

//------------------------------------------------------------------//
//                   Utility helpers & globals                      //
//------------------------------------------------------------------//

struct SymbolConfig
{
   string name;
};

bool    allowVerboseLogs = true;
bool    isFastModeContext = false;
bool    isInBacktest = false;
bool    isForwardTest = false;

CTrade  trade;
CSymbolValidator g_SymbolValidator;
CArrayObj g_SymbolContexts;

struct ClusterPassInfo
{
   ulong  idPass;
   int    cluster;
   double customOntester;
   string params;
};

ClusterPassInfo g_SelectedClusterPasses[];

//------------------------------------------------------------------//
//                Per-symbol trading context class                  //
//------------------------------------------------------------------//

class CSymbolContext : public CObject
{
private:
   string    m_symbol;
   datetime  m_lastBarTime;
   int       m_lastSignal;
   datetime  m_lastSignalTime;

   CT3Indicator        m_t3;
   CVWAPIndicator      m_vwap;
   CEngulfingSignalDetector m_engulfing;

   MqlRates m_rates[];
   double   m_priceDataT3[];

   double   m_prevT3;
   double   m_currT3;

   double   m_prevVWAPDaily;
   double   m_currVWAPDaily;

   double   m_prevVWAPTF1;
   double   m_currVWAPTF1;
   double   m_prevVWAPTF2;
   double   m_currVWAPTF2;
   double   m_prevVWAPTF3;
   double   m_currVWAPTF3;
   double   m_prevVWAPTF4;
   double   m_currVWAPTF4;
   double   m_prevVWAPTF5;
   double   m_currVWAPTF5;

   // VWAP buffers
   double   m_VWAPDailyBuffer[];
   double   m_VWAPTF1Buffer[];
   double   m_VWAPTF2Buffer[];
   double   m_VWAPTF3Buffer[];
   double   m_VWAPTF4Buffer[];
   double   m_VWAPTF5Buffer[];
   double   m_VWAPTF6Buffer[];
   double   m_VWAPTF7Buffer[];
   double   m_VWAPTF8Buffer[];

   int      m_signalCache;

   bool SafeCopyRates(const int barsRequired)
   {
      if(CopyRates(m_symbol, PERIOD_CURRENT, 0, barsRequired, m_rates) <= 0)
      {
         if(allowVerboseLogs)
            PrintFormat("[%s] CopyRates failed. Error=%d", m_symbol, GetLastError());
         return false;
      }
      ArraySetAsSeries(m_rates, true);
      return true;
   }

   ENUM_TIMEFRAMES MapVWAPTF(const ENUM_VWAP_TIMEFRAMES tf) const
   {
      if(tf == VWAP_DISABLED)
         return PERIOD_CURRENT;
      return (ENUM_TIMEFRAMES)tf;
   }

   void EnsureVWAPBufferSize(const int needed)
   {
      int bufferSize = MathMax(needed, ArraySize(m_VWAPDailyBuffer));
      ArrayResize(m_VWAPDailyBuffer, bufferSize);
      ArrayResize(m_VWAPTF1Buffer, bufferSize);
      ArrayResize(m_VWAPTF2Buffer, bufferSize);
      ArrayResize(m_VWAPTF3Buffer, bufferSize);
      ArrayResize(m_VWAPTF4Buffer, bufferSize);
      ArrayResize(m_VWAPTF5Buffer, bufferSize);
      ArrayResize(m_VWAPTF6Buffer, bufferSize);
      ArrayResize(m_VWAPTF7Buffer, bufferSize);
      ArrayResize(m_VWAPTF8Buffer, bufferSize);
   }

   void SafeCalculateVWAPOnBar(const int ratesCount)
   {
      EnsureVWAPBufferSize(ratesCount);
      ArraySetAsSeries(m_VWAPDailyBuffer, true);
      ArraySetAsSeries(m_VWAPTF1Buffer, true);
      ArraySetAsSeries(m_VWAPTF2Buffer, true);
      ArraySetAsSeries(m_VWAPTF3Buffer, true);
      ArraySetAsSeries(m_VWAPTF4Buffer, true);
      ArraySetAsSeries(m_VWAPTF5Buffer, true);
      ArraySetAsSeries(m_VWAPTF6Buffer, true);
      ArraySetAsSeries(m_VWAPTF7Buffer, true);
      ArraySetAsSeries(m_VWAPTF8Buffer, true);

      m_vwap.CalculateOnBar(m_rates, ratesCount,
                            m_VWAPDailyBuffer,
                            m_VWAPTF1Buffer, m_VWAPTF2Buffer,
                            m_VWAPTF3Buffer, m_VWAPTF4Buffer,
                            m_VWAPTF5Buffer, m_VWAPTF6Buffer,
                            m_VWAPTF7Buffer, m_VWAPTF8Buffer);
   }

   int CombineSignalVotes(const int &signals[], const bool &enabled[], const int moduleCount) const
   {
      int buyVotes = 0;
      int sellVotes = 0;
      int voteCount = 0;

      for(int i = 0; i < moduleCount; ++i)
      {
         if(!enabled[i])
            continue;
         if(signals[i] > 0)
         {
            ++buyVotes;
            ++voteCount;
         }
         else if(signals[i] < 0)
         {
            ++sellVotes;
            ++voteCount;
         }
      }

      int resolvedSignal = 0;

      bool allowLongs  = (TradeDirectionBias != ShortOnly);
      bool allowShorts = (TradeDirectionBias != LongOnly);

      int longThreshold  = MathMax(1, (TradeDirectionBias == LongOnly)
                                      ? MinSignalsToEnterLong
                                      : MinSignalsToEnterBoth);
      int shortThreshold = MathMax(1, (TradeDirectionBias == ShortOnly)
                                      ? MinSignalsToEnterShort
                                      : MinSignalsToEnterBoth);

      if(allowLongs && buyVotes >= longThreshold && sellVotes == 0)
         resolvedSignal = 1;

      if(allowShorts && sellVotes >= shortThreshold && buyVotes == 0)
      {
         if(resolvedSignal != 0)
            resolvedSignal = 0;
         else
            resolvedSignal = -1;
      }

      if(resolvedSignal != 0 && allowVerboseLogs)
      {
         PrintFormat("[%s][Signals] Votes -> Buy: %d (thresh %d) Sell: %d (thresh %d) Bias=%d",
                     m_symbol, buyVotes, longThreshold, sellVotes, shortThreshold, TradeDirectionBias);
      }

      return resolvedSignal;
   }

   int ComputeT3VWAPSignal()
   {
      if(!UseT3VWAPFilter || !UseT3Indicator || !UseVWAPIndicator)
         return 0;

      if(ArraySize(m_rates) < 3)
         return 0;

      int signal = 0;

      bool bullishCross = (m_prevT3 < m_prevVWAPDaily && m_currT3 > m_currVWAPDaily);
      bool bearishCross = (m_prevT3 > m_prevVWAPDaily && m_currT3 < m_currVWAPDaily);

      bool bullishPriceConfirm = (m_rates[1].close > m_rates[1].open && m_rates[2].close > m_rates[2].open);
      bool bearishPriceConfirm = (m_rates[1].close < m_rates[1].open && m_rates[2].close < m_rates[2].open);

      if(bullishCross && bullishPriceConfirm)
      {
         bool passes = true;
         if(VWAP_Timeframe1 != VWAP_DISABLED && m_rates[1].close < m_currVWAPTF1) passes = false;
         if(VWAP_Timeframe2 != VWAP_DISABLED && m_rates[1].close < m_currVWAPTF2) passes = false;
         if(VWAP_Timeframe3 != VWAP_DISABLED && m_rates[1].close < m_currVWAPTF3) passes = false;
         if(VWAP_Timeframe4 != VWAP_DISABLED && m_rates[1].close < m_currVWAPTF4) passes = false;
         if(VWAP_Timeframe5 != VWAP_DISABLED && m_rates[1].close < m_currVWAPTF5) passes = false;
         if(passes)
            signal = 1;
      }
      else if(bearishCross && bearishPriceConfirm)
      {
         bool passes = true;
         if(VWAP_Timeframe1 != VWAP_DISABLED && m_rates[1].close > m_currVWAPTF1) passes = false;
         if(VWAP_Timeframe2 != VWAP_DISABLED && m_rates[1].close > m_currVWAPTF2) passes = false;
         if(VWAP_Timeframe3 != VWAP_DISABLED && m_rates[1].close > m_currVWAPTF3) passes = false;
         if(VWAP_Timeframe4 != VWAP_DISABLED && m_rates[1].close > m_currVWAPTF4) passes = false;
         if(VWAP_Timeframe5 != VWAP_DISABLED && m_rates[1].close > m_currVWAPTF5) passes = false;
         if(passes)
            signal = -1;
      }

      if(signal != 0 && allowVerboseLogs)
      {
         PrintFormat("[%s][Signals] T3/VWAP crossover -> %s", m_symbol, signal > 0 ? "BUY" : "SELL");
      }
      return signal;
   }

   int CountSymbolPositions() const
   {
      int count = 0;
      int total = PositionsTotal();
      for(int i = 0; i < total; ++i)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
               PositionGetString(POSITION_SYMBOL) == m_symbol)
            {
               ++count;
            }
         }
      }
      return count;
   }

   double ComputeRiskCurrency(const ENUM_ORDER_TYPE orderType,
                              const double volume,
                              const double entryPrice,
                              const double stopPrice) const
   {
      double profit = 0.0;
      ResetLastError();
      if(!OrderCalcProfit(orderType, m_symbol, volume, entryPrice, stopPrice, profit))
      {
         if(allowVerboseLogs)
            PrintFormat("[%s] OrderCalcProfit failed for risk calculation (error %d)", m_symbol, GetLastError());
         return -1.0;
      }
      return MathAbs(profit);
   }

   double EstimatePointValue(const ENUM_ORDER_TYPE orderType,
                             const double referencePrice,
                             const double tickSize,
                             const double point,
                             const double tickValue) const
   {
      if(point <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0)
         return 0.0;

      double ticksPerPoint = point / tickSize;
      double baseValue = tickValue * ticksPerPoint;

      double adjustedPrice = (orderType == ORDER_TYPE_BUY)
                             ? referencePrice - tickSize
                             : referencePrice + tickSize;

      if(adjustedPrice <= 0.0)
         return baseValue;

      double profit = 0.0;
      ResetLastError();
      if(OrderCalcProfit(orderType, m_symbol, 1.0, referencePrice, adjustedPrice, profit))
      {
         double perTickLoss = MathAbs(profit);
         if(perTickLoss > 0.0)
            baseValue = perTickLoss * ticksPerPoint;
      }

      return baseValue;
   }

   bool PlaceTrade(const ENUM_ORDER_TYPE orderType,
                   const int totalOpenTrades,
                   const int maxCompoundTrades)
   {
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      if(bid == 0.0 || ask == 0.0)
         return false;

      double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;

      double stopLossDistance = CalculateStopDistance();
      if(stopLossDistance <= 0)
         return false;

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return false;

      double stopLossPoints = stopLossDistance / point;

      double effectiveRisk = currentRisk;
      double effectiveReward = currentReward;

      if(totalOpenTrades >= maxCompoundTrades)
      {
         effectiveRisk = AC_BaseRisk;
         effectiveReward = AC_BaseRisk * AC_BaseReward;
      }

      double volume = DefaultLot;
      double equity = 0.0;
      double riskAmount = 0.0;
      double tickSize = 0.0;
      double tickValue = 0.0;
      double ticksPerPoint = 0.0;
      double onePointValue = 0.0;
      double pointValuePerLot = 0.0;

      if(UseACRiskManagement && effectiveRisk > 0.0)
      {
         equity = AccountInfoDouble(ACCOUNT_EQUITY);
         tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
         tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
         if(tickSize <= 0.0 || tickValue <= 0.0)
            return false;

         ticksPerPoint = point / tickSize;
         onePointValue = tickValue * ticksPerPoint;
         if(onePointValue <= 0.0)
            return false;

         riskAmount = equity * (effectiveRisk / 100.0);
         if(riskAmount <= 0.0)
            return false;

         volume = riskAmount / (stopLossPoints * onePointValue);

         double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
         double maxLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
         double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

         if(lotStep > 0.0)
            volume = MathFloor(volume / lotStep) * lotStep;
         if(volume < minLot)
            volume = minLot;
         if(volume > maxLot)
            volume = maxLot;

         pointValuePerLot = EstimatePointValue(orderType, price, tickSize, point, tickValue);
         if(pointValuePerLot <= 0.0)
            pointValuePerLot = onePointValue;
      }

      double stopLossPrice = (orderType == ORDER_TYPE_BUY) ? price - stopLossDistance : price + stopLossDistance;

      double minStopLevel = (double)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      if(stopLossPoints < minStopLevel)
      {
         stopLossDistance = minStopLevel * point;
         stopLossPoints = stopLossDistance / point;
         stopLossPrice = (orderType == ORDER_TYPE_BUY) ? price - stopLossDistance : price + stopLossDistance;

         if(allowVerboseLogs)
            Print("WARNING: Stop distance adjusted to broker minimum: ", stopLossPoints, " points");
      }

      if(UseACRiskManagement && riskAmount > 0.0 && pointValuePerLot > 0.0 && volume > 0.0)
      {
         double allowedRiskCurrency = riskAmount;
         double maxStopDistanceFromTime = MaxStopLossDistance * point;
         double minStopDistanceAbs = MathMax(point, minStopLevel * point);
         double trailingMinAbs = MinimumTrailingDistancePoints * point;
         if(trailingMinAbs > minStopDistanceAbs)
            minStopDistanceAbs = trailingMinAbs;
         if(MaxHoldBars > 0)
         {
            double pointSize = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            if(pointSize > 0.0)
            {
               double atr = iATR(m_symbol, PERIOD_CURRENT, ATRPeriod);
               if(atr > 0.0)
               {
                  double averageBarRangePoints = atr / pointSize;
                  double candidateDistance = averageBarRangePoints * MaxHoldBars;
                  if(candidateDistance > 0.0)
                  {
                     double candidateAbs = candidateDistance * pointSize;
                     if(candidateAbs > 0.0 && candidateAbs < maxStopDistanceFromTime)
                        maxStopDistanceFromTime = candidateAbs;
                  }
               }
            }
         }

         if(maxStopDistanceFromTime < minStopDistanceAbs)
            maxStopDistanceFromTime = minStopDistanceAbs;

         if(maxStopDistanceFromTime > 0.0 && maxStopDistanceFromTime < stopLossDistance)
         {
            double newStopLossDistance = maxStopDistanceFromTime;
            double newStopLossPoints = newStopLossDistance / point;
            double newVolume = riskAmount / (newStopLossPoints * pointValuePerLot);

            double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
            double maxLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
            double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
            if(lotStep > 0.0)
               newVolume = MathFloor(newVolume / lotStep) * lotStep;
            if(newVolume < minLot)
               newVolume = minLot;
            if(newVolume > maxLot)
               newVolume = maxLot;

            double newStopLossPrice = (orderType == ORDER_TYPE_BUY) ? price - newStopLossDistance : price + newStopLossDistance;
            double newRiskCurrency = ComputeRiskCurrency(orderType, newVolume, price, newStopLossPrice);
            if(newRiskCurrency < 0.0)
               newRiskCurrency = newVolume * newStopLossPoints * pointValuePerLot;

            double riskToleranceCurrencyClamp = MathMax(riskAmount * 0.002, 0.01);
            double acceptableRiskUpper = riskAmount + riskToleranceCurrencyClamp;

            if(newRiskCurrency <= acceptableRiskUpper)
            {
               stopLossDistance = newStopLossDistance;
               stopLossPoints = newStopLossPoints;
               stopLossPrice = newStopLossPrice;
               volume = newVolume;
               if(allowVerboseLogs)
               {
                  PrintFormat("[%s] Stop reduced by clamp to %.2f points, volume adjusted to %.4f lots.",
                              m_symbol, stopLossPoints, volume);
               }
            }
         }

         allowedRiskCurrency = riskAmount;
         double riskToleranceCurrency = MathMax(allowedRiskCurrency * 0.002, 0.01);
         double actualRiskCurrency = ComputeRiskCurrency(orderType, volume, price, stopLossPrice);
         if(actualRiskCurrency < 0.0)
            actualRiskCurrency = volume * stopLossPoints * pointValuePerLot;

         if(actualRiskCurrency > allowedRiskCurrency + riskToleranceCurrency)
         {
            double maxStopLossPointsByRisk = allowedRiskCurrency / (volume * pointValuePerLot);
            if(maxStopLossPointsByRisk <= 0.0)
            {
               if(allowVerboseLogs)
                  PrintFormat("[%s] Risk control failed: invalid maximum stop distance %.5f points. Trade skipped.", m_symbol, maxStopLossPointsByRisk);
               return false;
            }

            double maxStopDistance = maxStopLossPointsByRisk * point;
            if(tickSize > 0.0)
               maxStopDistance = MathFloor(maxStopDistance / tickSize) * tickSize;

            double minAllowedDistance = (tickSize > 0.0) ? tickSize : point;
            double minStopDistance = MathMax(minAllowedDistance, minStopLevel * point);
            double trailingMinDistance = MinimumTrailingDistancePoints * point;
            if(trailingMinDistance > minStopDistance)
               minStopDistance = trailingMinDistance;

            if(maxStopDistance <= 0.0 || maxStopDistance < minStopDistance - 1e-8)
            {
               if(allowVerboseLogs)
               {
                  PrintFormat("[%s] Broker minimum stop (%.2f pts) conflicts with %.2f%% risk target (max %.2f pts). Trade skipped.",
                              m_symbol, minStopLevel, effectiveRisk, maxStopLossPointsByRisk);
               }
               return false;
            }

            if(maxStopDistance < stopLossDistance)
            {
               stopLossDistance = maxStopDistance;
               stopLossPoints = stopLossDistance / point;
               stopLossPrice = (orderType == ORDER_TYPE_BUY) ? price - stopLossDistance : price + stopLossDistance;

               actualRiskCurrency = ComputeRiskCurrency(orderType, volume, price, stopLossPrice);
               if(actualRiskCurrency < 0.0)
                  actualRiskCurrency = volume * stopLossPoints * pointValuePerLot;

               if(tickSize > 0.0)
               {
                  int safetyIterations = 0;
                  while(actualRiskCurrency > allowedRiskCurrency + riskToleranceCurrency)
                  {
                     double candidateDistance = stopLossDistance - tickSize;
                     if(candidateDistance < minStopDistance - 1e-8)
                        break;

                     stopLossDistance = candidateDistance;
                     stopLossPoints = stopLossDistance / point;
                     stopLossPrice = (orderType == ORDER_TYPE_BUY) ? price - stopLossDistance : price + stopLossDistance;

                     actualRiskCurrency = ComputeRiskCurrency(orderType, volume, price, stopLossPrice);
                     if(actualRiskCurrency < 0.0)
                        actualRiskCurrency = volume * stopLossPoints * pointValuePerLot;

                     if(++safetyIterations > 100)
                        break;
                  }
               }

               if(actualRiskCurrency > allowedRiskCurrency + riskToleranceCurrency)
               {
                  if(allowVerboseLogs)
                  {
                     PrintFormat("[%s] Unable to cap risk without violating broker constraints (allowed $%.2f, actual $%.2f). Trade skipped.",
                                 m_symbol, allowedRiskCurrency, actualRiskCurrency);
                  }
                  return false;
               }

               if(allowVerboseLogs)
               {
                  double finalRiskPercent = (equity > 0.0) ? (actualRiskCurrency / equity * 100.0) : 0.0;
                  PrintFormat("[%s] Stop tightened to %.2f points to respect %.2f%% risk (loss $%.2f, %.2f%% equity).",
                              m_symbol, stopLossPoints, effectiveRisk, actualRiskCurrency, finalRiskPercent);
               }
            }
         }
      }

      double takeProfitDistance = 0.0;
      double takeProfitPrice = 0.0;
      if(UseTakeProfit)
      {
         double rrRatio = (effectiveRisk > 0.0) ? (effectiveReward / effectiveRisk) : AC_BaseReward;
         takeProfitDistance = stopLossDistance * rrRatio;
         takeProfitPrice = (orderType == ORDER_TYPE_BUY) ? price + takeProfitDistance : price - takeProfitDistance;
      }

      if(!UseTakeProfit)
         takeProfitPrice = 0.0;

      trade.PositionOpen(m_symbol, orderType, volume, price, stopLossPrice, takeProfitPrice, TradeComment);
      bool ok = (trade.ResultRetcode() == TRADE_RETCODE_DONE);
      if(ok && allowVerboseLogs)
      {
         if(UseACRiskManagement && riskAmount > 0.0 && volume > 0.0)
         {
            double loggedRiskCurrency = ComputeRiskCurrency(orderType, volume, price, stopLossPrice);
            if(loggedRiskCurrency < 0.0 && pointValuePerLot > 0.0)
               loggedRiskCurrency = volume * stopLossPoints * pointValuePerLot;
            double loggedRiskPercent = (equity > 0.0 && loggedRiskCurrency > 0.0) ? (loggedRiskCurrency / equity * 100.0) : 0.0;

            PrintFormat("[%s] Opened %s %.4f @ %.5f | SL %.5f | TP %.5f | risk %.2f%% (target) | est loss $%.2f (%.2f%% equity)",
                        m_symbol,
                        (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                        volume, price, stopLossPrice,
                        UseTakeProfit ? takeProfitPrice : 0.0,
                        effectiveRisk,
                        loggedRiskCurrency,
                        loggedRiskPercent);
         }
         else
         {
            PrintFormat("[%s] Opened %s %.4f @ %.5f | SL %.5f | TP %.5f | risk %.2f%% (effective)",
                        m_symbol,
                        (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                        volume, price, stopLossPrice,
                        UseTakeProfit ? takeProfitPrice : 0.0,
                        effectiveRisk);
         }
      }
      return ok;
   }

   double CalculateStopDistance() const
   {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0)
         return 0.0;

      double atr = iATR(m_symbol, PERIOD_CURRENT, ATRPeriod);
      if(atr <= 0.0)
         return 0.0;

      double distance = atr * ATRMultiplier * 1.5;
      double maxDistance = MaxStopLossDistance * point;
      if(maxDistance > 0.0)
         distance = MathMin(distance, maxDistance);
      return distance;
   }

   void UpdateTrailingStops() const
   {
      if(!UseATRTrailing)
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
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;

         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = (posType == POSITION_TYPE_BUY)
                               ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                               : SymbolInfoDouble(m_symbol, SYMBOL_ASK);

         double profitPoints = (posType == POSITION_TYPE_BUY)
                               ? (currentPrice - entryPrice)
                               : (entryPrice - currentPrice);

         double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         if(point <= 0.0)
            continue;

         double profitCurrency = profitPoints / point * SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE)
                                 * (point / SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE))
                                 * volume;
         double profitPercent = 0.0;
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         if(balance > 0.0)
            profitPercent = (profitCurrency / balance) * 100.0;

         if(profitPercent < TrailingActivationPercent)
            continue;

         double atr = iATR(m_symbol, PERIOD_CURRENT, ATRTrailingPeriod);
         if(atr <= 0.0)
            continue;

         double trailDistance = atr * ATRTrailingMultiplier;
         double minDistance = MinimumTrailingDistancePoints * point;
         trailDistance = MathMax(trailDistance, minDistance);

         double newSL = (posType == POSITION_TYPE_BUY)
                        ? currentPrice - trailDistance
                        : currentPrice + trailDistance;

         double existingSL = PositionGetDouble(POSITION_SL);
         bool shouldModify = false;
         if(posType == POSITION_TYPE_BUY)
         {
            if(existingSL == 0.0 || newSL > existingSL)
               shouldModify = true;
         }
         else
         {
            if(existingSL == 0.0 || newSL < existingSL)
               shouldModify = true;
         }

         if(shouldModify)
         {
            double tp = PositionGetDouble(POSITION_TP);
            if(!trade.PositionModify(ticket, newSL, tp) && allowVerboseLogs)
            {
               PrintFormat("[%s] Trailing stop modify failed. Retcode=%d",
                           m_symbol, trade.ResultRetcode());
            }
         }
      }
   }

public:
   CSymbolContext(const string symbol)
   {
      m_symbol = symbol;
      m_lastBarTime = 0;
      m_lastSignal = 0;
      m_lastSignalTime = 0;
      m_prevT3 = m_currT3 = 0.0;
      m_prevVWAPDaily = m_currVWAPDaily = 0.0;
      m_prevVWAPTF1 = m_currVWAPTF1 = 0.0;
      m_prevVWAPTF2 = m_currVWAPTF2 = 0.0;
      m_prevVWAPTF3 = m_currVWAPTF3 = 0.0;
      m_prevVWAPTF4 = m_currVWAPTF4 = 0.0;
      m_prevVWAPTF5 = m_currVWAPTF5 = 0.0;
      m_signalCache = 0;
   }

   virtual ~CSymbolContext() {}

   string Symbol() const { return m_symbol; }

   bool Init()
   {
      if(!SymbolSelect(m_symbol, true))
      {
         PrintFormat("[Init] Failed to select symbol %s", m_symbol);
         return false;
      }

      if(UseT3Indicator)
      {
         m_t3.Init(T3_Length, T3_Factor, T3_Applied_Price, false);
         ArraySetAsSeries(m_priceDataT3, true);
         ArrayResize(m_priceDataT3, 512);
      }

      if(UseVWAPIndicator)
      {
         PRICE_TYPE priceType = CLOSE;
         switch(T3_Applied_Price)
         {
            case PRICE_OPEN:    priceType = OPEN; break;
            case PRICE_CLOSE:   priceType = CLOSE; break;
            case PRICE_HIGH:    priceType = HIGH; break;
            case PRICE_LOW:     priceType = LOW; break;
            case PRICE_MEDIAN:  priceType = HIGH_LOW; break;
            case PRICE_TYPICAL: priceType = CLOSE_HIGH_LOW; break;
            case PRICE_WEIGHTED: priceType = OPEN_CLOSE_HIGH_LOW; break;
            default:            priceType = CLOSE;
         }

         m_vwap.Init(priceType, Enable_Daily_VWAP,
                     MapVWAPTF(VWAP_Timeframe1),
                     MapVWAPTF(VWAP_Timeframe2),
                     MapVWAPTF(VWAP_Timeframe3),
                     MapVWAPTF(VWAP_Timeframe4),
                     MapVWAPTF(VWAP_Timeframe5),
                     PERIOD_CURRENT, PERIOD_CURRENT, PERIOD_CURRENT, false);

         ArraySetAsSeries(m_VWAPDailyBuffer, true);
         ArraySetAsSeries(m_VWAPTF1Buffer, true);
         ArraySetAsSeries(m_VWAPTF2Buffer, true);
         ArraySetAsSeries(m_VWAPTF3Buffer, true);
         ArraySetAsSeries(m_VWAPTF4Buffer, true);
         ArraySetAsSeries(m_VWAPTF5Buffer, true);
         ArraySetAsSeries(m_VWAPTF6Buffer, true);
         ArraySetAsSeries(m_VWAPTF7Buffer, true);
         ArraySetAsSeries(m_VWAPTF8Buffer, true);

         EnsureVWAPBufferSize(256);
      }

      return true;
   }

   void UpdateIndicators()
   {
      int barsToRequest = isFastModeContext ? 40 : 200;
      if(!SafeCopyRates(barsToRequest))
         return;

      int ratesCount = ArraySize(m_rates);

      if(UseT3Indicator)
      {
         if(ArraySize(m_priceDataT3) < ratesCount)
            ArrayResize(m_priceDataT3, ratesCount);

         for(int i = 0; i < ratesCount; ++i)
         {
            switch(T3_Applied_Price)
            {
               case PRICE_CLOSE:   m_priceDataT3[i] = m_rates[i].close; break;
               case PRICE_OPEN:    m_priceDataT3[i] = m_rates[i].open; break;
               case PRICE_HIGH:    m_priceDataT3[i] = m_rates[i].high; break;
               case PRICE_LOW:     m_priceDataT3[i] = m_rates[i].low; break;
               case PRICE_MEDIAN:  m_priceDataT3[i] = (m_rates[i].high + m_rates[i].low) / 2.0; break;
               case PRICE_TYPICAL: m_priceDataT3[i] = (m_rates[i].high + m_rates[i].low + m_rates[i].close) / 3.0; break;
               case PRICE_WEIGHTED: m_priceDataT3[i] = (m_rates[i].high + m_rates[i].low + m_rates[i].close + m_rates[i].open) / 4.0; break;
               default:            m_priceDataT3[i] = m_rates[i].close; break;
            }
         }

         double latest = m_t3.Calculate(m_priceDataT3, 0);
         double prev = m_t3.Calculate(m_priceDataT3, 1);
         m_prevT3 = m_currT3;
         m_currT3 = prev;
      }

      if(UseVWAPIndicator)
      {
         SafeCalculateVWAPOnBar(ratesCount);

         m_prevVWAPDaily = m_currVWAPDaily;
         m_currVWAPDaily = m_VWAPDailyBuffer[1];

         if(VWAP_Timeframe1 != VWAP_DISABLED)
         {
            m_prevVWAPTF1 = m_currVWAPTF1;
            m_currVWAPTF1 = m_VWAPTF1Buffer[1];
         }

         if(VWAP_Timeframe2 != VWAP_DISABLED)
         {
            m_prevVWAPTF2 = m_currVWAPTF2;
            m_currVWAPTF2 = m_VWAPTF2Buffer[1];
         }

         if(VWAP_Timeframe3 != VWAP_DISABLED)
         {
            m_prevVWAPTF3 = m_currVWAPTF3;
            m_currVWAPTF3 = m_VWAPTF3Buffer[1];
         }

         if(VWAP_Timeframe4 != VWAP_DISABLED)
         {
            m_prevVWAPTF4 = m_currVWAPTF4;
            m_currVWAPTF4 = m_VWAPTF4Buffer[1];
         }

         if(VWAP_Timeframe5 != VWAP_DISABLED)
         {
            m_prevVWAPTF5 = m_currVWAPTF5;
            m_currVWAPTF5 = m_VWAPTF5Buffer[1];
         }
      }

      int moduleCount = 0;
      int moduleSignals[3];
      bool moduleEnabled[3];

      if(UseT3Indicator && UseVWAPIndicator)
      {
         moduleSignals[moduleCount] = ComputeT3VWAPSignal();
         moduleEnabled[moduleCount] = UseT3VWAPFilter;
         ++moduleCount;
      }

      if(UseEngulfingPattern)
      {
         int engulfSignal = m_engulfing.Evaluate(m_rates, ratesCount);
         moduleSignals[moduleCount] = engulfSignal;
         moduleEnabled[moduleCount] = true;
         ++moduleCount;
      }

      m_signalCache = 0;
      if(moduleCount > 0)
         m_signalCache = CombineSignalVotes(moduleSignals, moduleEnabled, moduleCount);

      if(m_signalCache != 0)
      {
         m_lastSignal = m_signalCache;
         m_lastSignalTime = m_rates[1].time;
      }
   }

   bool Process(int &globalOpenTrades,
                const int maxOpenTrades,
                const int maxCompoundTrades,
                const bool allowMultiplePerSymbol)
   {
      UpdateTrailingStops();

      datetime currentBar = iTime(m_symbol, PERIOD_CURRENT, 0);
      bool newBar = (currentBar != m_lastBarTime);
      if(newBar)
      {
         m_lastBarTime = currentBar;
         UpdateIndicators();
      }

      if(globalOpenTrades >= maxOpenTrades)
         return false;

      if(!allowMultiplePerSymbol && CountSymbolPositions() > 0)
         return false;

      if(m_signalCache == 0)
         return false;

      ENUM_ORDER_TYPE orderType = (m_signalCache > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      bool placed = PlaceTrade(orderType, globalOpenTrades, maxCompoundTrades);
      if(placed)
      {
         ++globalOpenTrades;
         m_signalCache = 0;
         return true;
      }

      return false;
   }
};

//------------------------------------------------------------------//
//                          Helpers                                 //
//------------------------------------------------------------------//

int CountOpenTrades()
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; ++i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            ++count;
      }
   }
   return count;
}

void ClearContexts()
{
   for(int i = g_SymbolContexts.Total() - 1; i >= 0; --i)
   {
      CObject *obj = g_SymbolContexts.At(i);
      delete obj;
   }
   g_SymbolContexts.Clear();
}

void CollectClusterSymbols(string &uniqueSymbols[])
{
   string temp[];
   ArrayResize(uniqueSymbols, 0);

   struct ClusterEntry { bool enabled; string csv; };
   ClusterEntry clusters[4] = {
      {Cluster1Enabled, Cluster1Symbols},
      {Cluster2Enabled, Cluster2Symbols},
      {Cluster3Enabled, Cluster3Symbols},
      {Cluster4Enabled, Cluster4Symbols}
   };

   for(int i = 0; i < 4; ++i)
   {
      if(!clusters[i].enabled)
         continue;
      int parts = StringSplit(clusters[i].csv, ',', temp);
      for(int j = 0; j < parts; ++j)
      {
         string sym = temp[j];
         StringTrimLeft(sym);
         StringTrimRight(sym);
         if(sym == "")
            continue;

         StringToUpper(sym);
         bool exists = false;
         for(int k = 0; k < ArraySize(uniqueSymbols); ++k)
         {
            if(uniqueSymbols[k] == sym)
            {
               exists = true;
               break;
            }
         }
         if(!exists)
         {
            int newIdx = ArraySize(uniqueSymbols);
            ArrayResize(uniqueSymbols, newIdx + 1);
            uniqueSymbols[newIdx] = sym;
         }
      }
   }
}

bool IsSymbolTradeable(const string symbol, const bool logDetails)
{
   long tradeMode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   long orderMode = SymbolInfoInteger(symbol, SYMBOL_ORDER_MODE);
   bool tradeAllowed = (tradeMode != SYMBOL_TRADE_MODE_DISABLED &&
                        tradeMode != SYMBOL_TRADE_MODE_CLOSEONLY);
   bool hasMarketOrders = ((orderMode & SYMBOL_ORDER_MARKET) != 0);
   bool modeOk = (tradeMode == SYMBOL_TRADE_MODE_FULL ||
                  tradeMode == SYMBOL_TRADE_MODE_LONGONLY ||
                  tradeMode == SYMBOL_TRADE_MODE_SHORTONLY);

   if(tradeAllowed && hasMarketOrders && modeOk)
      return true;

   if(logDetails && allowVerboseLogs)
   {
      PrintFormat("[Init] Symbol '%s' is not tradeable (allowed=%s, mode=%d, marketOrders=%s).",
                  symbol,
                  tradeAllowed ? "true" : "false",
                  tradeMode,
                  hasMarketOrders ? "true" : "false");
   }
   return false;
}

void UpdateFallback(const string symbol,
                    const int score,
                    string &fallbackSymbol,
                    int &fallbackScore,
                    long &fallbackMode,
                    bool &fallbackAllowed,
                    bool &fallbackHasMarket)
{
   if(symbol == "" || score >= fallbackScore)
      return;

   fallbackSymbol = symbol;
   fallbackScore = score;
   fallbackMode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   fallbackAllowed = (fallbackMode != SYMBOL_TRADE_MODE_DISABLED &&
                      fallbackMode != SYMBOL_TRADE_MODE_CLOSEONLY);
   long orderFlags = SymbolInfoInteger(symbol, SYMBOL_ORDER_MODE);
   fallbackHasMarket = ((orderFlags & SYMBOL_ORDER_MARKET) != 0);
}

bool ResolveSymbolName(const string baseSymbol, string &resolvedSymbol)
{
   resolvedSymbol = baseSymbol;

   string fallbackSymbol = "";
   int fallbackScore = 2147483647;
   long fallbackMode = 0;
   bool fallbackAllowed = false;
   bool fallbackHasMarket = false;

   string trimmed = baseSymbol;
   StringTrimLeft(trimmed);
   StringTrimRight(trimmed);
   if(trimmed == "")
      return false;

   resolvedSymbol = trimmed;
   if(SymbolSelect(resolvedSymbol, true))
   {
      if(IsSymbolTradeable(resolvedSymbol, false))
         return true;

      UpdateFallback(resolvedSymbol, 0,
                     fallbackSymbol, fallbackScore, fallbackMode,
                     fallbackAllowed, fallbackHasMarket);
   }

   int total = SymbolsTotal(false);
   if(total <= 0)
      return false;

   string upperBase = trimmed;
   StringToUpper(upperBase);
   int baseLen = StringLen(upperBase);

   string bestPrefix = "";
   int bestPrefixScore = 2147483647;

   string bestPrefixFallback = "";
   int bestPrefixFallbackScore = 2147483647;

   for(int i = 0; i < total; ++i)
   {
      string candidate = SymbolName(i, false);
      if(candidate == "")
         continue;

      string upperCandidate = candidate;
      StringToUpper(upperCandidate);
      if(StringFind(upperCandidate, upperBase) == 0)
      {
         int score = StringLen(upperCandidate) - baseLen;
         if(SymbolSelect(candidate, true))
         {
            if(IsSymbolTradeable(candidate, false))
            {
               if(score < bestPrefixScore)
               {
                  bestPrefixScore = score;
                  bestPrefix = candidate;
               }
            }
            else
            {
               if(score < bestPrefixFallbackScore)
               {
                  bestPrefixFallbackScore = score;
                  bestPrefixFallback = candidate;
               }
            }
         }
      }
   }

   if(bestPrefix != "")
   {
      resolvedSymbol = bestPrefix;
      return true;
   }
   if(bestPrefixFallback != "")
   {
      UpdateFallback(bestPrefixFallback, bestPrefixFallbackScore,
                     fallbackSymbol, fallbackScore, fallbackMode,
                     fallbackAllowed, fallbackHasMarket);
   }

   string bestContains = "";
   int bestContainsScore = 2147483647;
   string bestContainsFallback = "";
   int bestContainsFallbackScore = 2147483647;

   for(int i = 0; i < total; ++i)
   {
      string candidate = SymbolName(i, false);
      if(candidate == "")
         continue;

      string upperCandidate = candidate;
      StringToUpper(upperCandidate);
      int pos = StringFind(upperCandidate, upperBase);
      if(pos >= 0)
      {
         int score = pos + (StringLen(upperCandidate) - baseLen);
         if(SymbolSelect(candidate, true))
         {
            if(IsSymbolTradeable(candidate, false))
            {
               if(score < bestContainsScore)
               {
                  bestContainsScore = score;
                  bestContains = candidate;
               }
            }
            else
            {
               if(score < bestContainsFallbackScore)
               {
                  bestContainsFallbackScore = score;
                  bestContainsFallback = candidate;
               }
            }
         }
      }
   }

   if(bestContains != "")
   {
      resolvedSymbol = bestContains;
      return true;
   }
   if(bestContainsFallback != "")
   {
      UpdateFallback(bestContainsFallback, bestContainsFallbackScore,
                     fallbackSymbol, fallbackScore, fallbackMode,
                     fallbackAllowed, fallbackHasMarket);
   }

   if(fallbackSymbol != "" && allowVerboseLogs)
   {
      PrintFormat("[Init] Symbol '%s' matched broker symbol '%s' but trading is disabled (allowed=%s, mode=%d, marketOrders=%s).",
                  baseSymbol,
                  fallbackSymbol,
                  fallbackAllowed ? "true" : "false",
                  fallbackMode,
                  fallbackHasMarket ? "true" : "false");
   }

   return false;
}

void ProcessContexts()
{
   int openTrades = CountOpenTrades();
   for(int i = 0; i < g_SymbolContexts.Total(); ++i)
   {
      CSymbolContext *ctx = (CSymbolContext*)g_SymbolContexts.At(i);
      if(ctx == NULL)
         continue;

      bool traded = ctx.Process(openTrades, MaxOpenTrades, MaxCompoundTrades, AllowMultiplePositionsPerSymbol);
      if(traded)
         openTrades = CountOpenTrades();
   }

   UpdateRiskManagement(MagicNumber);
}

//------------------------------------------------------------------//
//                    Expert lifecycle functions                    //
//------------------------------------------------------------------//

int LoadClusterPasses(int limit)
{
   ArrayResize(g_SelectedClusterPasses, 0);

   if(limit <= 0 || idParentJob_ <= 0 || fileName_ == "")
      return 0;

   if(!DB::Connect(fileName_))
   {
      PrintFormat(__FUNCTION__" | ERROR: unable to open DB %s (code %d)", fileName_, GetLastError());
      return 0;
   }

   string filter = StringFormat(
      " WHERE j.id_job=%d AND p.custom_ontester >= %.6f AND p.trades >= %d AND p.sharpe_ratio >= %.6f",
      idParentJob_,
      minCustomOntester_,
      minTrades_,
      minSharpeRatio_
   );

   string query;
   if(useClusters_)
   {
      query = StringFormat(
         "SELECT p.id_pass, pc.cluster, p.custom_ontester, p.params "
         "FROM passes p "
         "JOIN tasks t ON p.id_task = t.id_task "
         "JOIN jobs j ON t.id_job = j.id_job "
         "JOIN passes_clusters pc ON pc.id_pass = p.id_pass "
         "%s "
         "ORDER BY pc.cluster, p.custom_ontester DESC;",
         filter
      );
   }
   else
   {
      query = StringFormat(
         "SELECT p.id_pass, -1 AS cluster, p.custom_ontester, p.params "
         "FROM passes p "
         "JOIN tasks t ON p.id_task = t.id_task "
         "JOIN jobs j ON t.id_job = j.id_job "
         "%s "
         "ORDER BY p.custom_ontester DESC;",
         filter
      );
   }

   int request = DatabasePrepare(DB::Id(), query);
   if(request == INVALID_HANDLE)
   {
      PrintFormat(__FUNCTION__" | ERROR: query\n%s\nfailed with code %d", query, GetLastError());
      DB::Close();
      return 0;
   }

   struct Row
   {
      ulong  id_pass;
      int    cluster;
      double custom_ontester;
      string params;
   } row;

   int stored = 0;
   int lastCluster = 0;
   bool haveCluster = false;
   while(DatabaseReadBind(request, row))
   {
      if(useClusters_)
      {
         if(haveCluster && row.cluster == lastCluster)
            continue;
         lastCluster = row.cluster;
         haveCluster = true;
      }

      ArrayResize(g_SelectedClusterPasses, stored + 1);
      g_SelectedClusterPasses[stored].idPass = row.id_pass;
      g_SelectedClusterPasses[stored].cluster = row.cluster;
      g_SelectedClusterPasses[stored].customOntester = row.custom_ontester;
      g_SelectedClusterPasses[stored].params = row.params;

      ++stored;
      if(stored >= limit)
         break;
   }

   DatabaseFinalize(request);
   DB::Close();

   return stored;
}

void LogClusterSelectionSummary()
{
   if(ArraySize(g_SelectedClusterPasses) == 0)
      return;

   PrintFormat("[ClusterSelection] %d pass(es) selected (useClusters=%s)",
               ArraySize(g_SelectedClusterPasses), useClusters_ ? "true" : "false");

   for(int i = 0; i < ArraySize(g_SelectedClusterPasses); ++i)
   {
      const ClusterPassInfo &info = g_SelectedClusterPasses[i];
      PrintFormat("[ClusterSelection] #%d id_pass=%I64u cluster=%d custom=%.4f",
                  i + 1, info.idPass, info.cluster, info.customOntester);
   }
}

int OnInit()
{
   bool isOptimizationPass = (MQLInfoInteger(MQL_OPTIMIZATION) == 1);
   bool isTesterPass       = (MQLInfoInteger(MQL_TESTER) == 1);
   isForwardTest = (MQLInfoInteger(MQL_FORWARD) == 1);

   isInBacktest = isOptimizationPass || isTesterPass;
   bool fastByOptimization = OptimizationMode && isInBacktest && !isForwardTest;
   isFastModeContext = fastByOptimization;
   allowVerboseLogs = !isFastModeContext;

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MagicNumber);

   g_SymbolValidator.Init(_Symbol);
   g_SymbolValidator.Refresh();

   InitializeACRiskManagement();

   string symbols[];
   CollectClusterSymbols(symbols);
   if(ArraySize(symbols) == 0)
   {
      Print("No symbols configured/enabled. Please enable at least one cluster.");
      return INIT_FAILED;
   }

   ClearContexts();

   string resolvedSymbols[];
   string unresolvedSymbols[];

   for(int i = 0; i < ArraySize(symbols); ++i)
   {
      string baseSymbol = symbols[i];
      string resolvedSymbol;
      if(!ResolveSymbolName(baseSymbol, resolvedSymbol))
      {
         PrintFormat("[Init] Unable to resolve cluster symbol '%s' on this server.", baseSymbol);
         int idx = ArraySize(unresolvedSymbols);
         ArrayResize(unresolvedSymbols, idx + 1);
         unresolvedSymbols[idx] = baseSymbol;
         continue;
      }

      bool alreadyAdded = false;
      for(int existing = 0; existing < ArraySize(resolvedSymbols); ++existing)
      {
         if(resolvedSymbols[existing] == resolvedSymbol)
         {
            alreadyAdded = true;
            break;
         }
      }
      if(alreadyAdded)
         continue;

      int newIdx = ArraySize(resolvedSymbols);
      ArrayResize(resolvedSymbols, newIdx + 1);
      resolvedSymbols[newIdx] = resolvedSymbol;

      if(allowVerboseLogs && resolvedSymbol != baseSymbol)
      {
         PrintFormat("[Init] Cluster symbol '%s' mapped to '%s'.", baseSymbol, resolvedSymbol);
      }

      CSymbolContext *ctx = new CSymbolContext(resolvedSymbol);
      if(ctx == NULL)
         continue;
      if(!ctx.Init())
      {
         PrintFormat("[Init] Failed to initialise symbol context for '%s'.", resolvedSymbol);
         delete ctx;
         continue;
      }
      g_SymbolContexts.Add(ctx);
   }

   if(ArraySize(unresolvedSymbols) > 0)
   {
      string missingList = "";
      for(int i = 0; i < ArraySize(unresolvedSymbols); ++i)
      {
         if(i > 0)
            missingList += ", ";
         missingList += unresolvedSymbols[i];
      }
      PrintFormat("[Init] %d cluster symbol(s) could not be resolved: %s", ArraySize(unresolvedSymbols), missingList);
   }

   if(g_SymbolContexts.Total() == 0)
   {
      Print("Failed to initialise any symbol context.");
      return INIT_FAILED;
   }

   if(TimerIntervalSeconds > 0)
      EventSetTimer(TimerIntervalSeconds);

   if(allowVerboseLogs)
   {
      Print("==== ACMultiSymbolAlgorithm initialised ====");
      Print("Active symbols: ", g_SymbolContexts.Total());
      Print("Base risk: ", AC_BaseRisk, "% | Base reward: ", AC_BaseReward);
      Print("Max open trades: ", MaxOpenTrades, " | Max compound trades: ", MaxCompoundTrades);
      Print("Use AC Risk: ", UseACRiskManagement ? "Yes" : "No");
   }

   if(!MQLInfoInteger(MQL_OPTIMIZATION) && idParentJob_ > 0 && fileName_ != "")
   {
      int selected = LoadClusterPasses(clusterSelectCount);
      if(selected > 0)
         LogClusterSelectionSummary();
      else if(allowVerboseLogs)
         Print("[ClusterSelection] No passes matched filters at initialisation.");
   }

   return INIT_SUCCEEDED;
}

double OnTester()
{
   if(idParentJob_ > 0 && fileName_ != "")
   {
      int selected = LoadClusterPasses(clusterSelectCount);
      if(selected > 0)
         LogClusterSelectionSummary();
      else if(allowVerboseLogs)
         Print("[ClusterSelection] No passes matched filters for current optimisation pass.");
   }

   double profit        = TesterStatistics(STAT_PROFIT);
   double drawdownPct   = TesterStatistics(STAT_EQUITYDD_PERCENT);
   double trades        = TesterStatistics(STAT_TRADES);
   double profitFactor  = TesterStatistics(STAT_PROFIT_FACTOR);
   double sharpe        = TesterStatistics(STAT_SHARPE_RATIO);
   double recovery      = TesterStatistics(STAT_RECOVERY_FACTOR);

   if(trades < 1)
      return 0.0;

   double metric = profitFactor;

   if(drawdownPct > 20.0)
      metric *= 0.85;
   if(drawdownPct > 35.0)
      metric *= 0.6;

   if(recovery > 2.0)
      metric *= 1.1;
   if(sharpe > 1.0)
      metric *= 1.05;

   return metric;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ClearContexts();
}

void OnTick()
{
   ProcessContexts();
}

void OnTimer()
{
   ProcessContexts();
}
