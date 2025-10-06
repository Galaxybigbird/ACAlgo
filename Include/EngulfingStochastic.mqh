#ifndef __ENGULFING_STOCHASTIC_MQH__
#define __ENGULFING_STOCHASTIC_MQH__

#include <EngulfingSignals.mqh>

class CEngulfingStochasticSignal
{
private:
   int               m_handle;
   int               m_overSold;
   int               m_overBought;
   datetime          m_lastProcessedBar;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;

public:
   CEngulfingStochasticSignal()
      : m_handle(INVALID_HANDLE),
        m_overSold(20),
        m_overBought(80),
        m_lastProcessedBar(0),
        m_symbol(_Symbol),
        m_timeframe(PERIOD_CURRENT)
   {
   }

   bool Init(const string symbol,
             const ENUM_TIMEFRAMES timeframe,
             const int overSold,
             const int overBought,
             const int kPeriod,
             const int dPeriod,
             const int slowing,
             const ENUM_MA_METHOD maMethod,
             const ENUM_STO_PRICE priceField)
   {
      Shutdown();

      m_symbol = symbol;
      m_timeframe = timeframe;
      m_overSold = overSold;
      m_overBought = overBought;
      m_handle = iStochastic(symbol, timeframe, kPeriod, dPeriod, slowing, maMethod, priceField);

      if(m_handle == INVALID_HANDLE)
      {
         Print("[EngulfingStoch] Failed to create iStochastic handle. Error: ", GetLastError());
         return(false);
      }

      m_lastProcessedBar = 0;
      return(true);
   }

   void Shutdown()
   {
      if(m_handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_handle);
         m_handle = INVALID_HANDLE;
      }
      m_lastProcessedBar = 0;
   }

   int Evaluate(const MqlRates &rates[], const int count)
   {
      if(m_handle == INVALID_HANDLE || count <= 2)
         return(ENGULFING_NONE);

      datetime barTime = rates[1].time;
      if(barTime == m_lastProcessedBar)
         return(ENGULFING_NONE);

      double signalBuffer[3];
      ResetLastError();
      if(CopyBuffer(m_handle, SIGNAL_LINE, 0, 3, signalBuffer) < 3)
         return(ENGULFING_NONE);

      double currentSignal = signalBuffer[1];
      double prevSignal    = signalBuffer[2];

      bool crossedIntoOverBought = (prevSignal < m_overBought && currentSignal > m_overBought);
      bool crossedIntoOverSold   = (prevSignal > m_overSold && currentSignal < m_overSold);

      MqlRates previousBar = rates[2];
      MqlRates currentBar  = rates[1];

      int direction = ENGULFING_NONE;

      if(crossedIntoOverSold && CEngulfingSignalDetector::IsBullishPattern(previousBar, currentBar))
         direction = ENGULFING_BULLISH;
      else if(crossedIntoOverBought && CEngulfingSignalDetector::IsBearishPattern(previousBar, currentBar))
         direction = ENGULFING_BEARISH;

      m_lastProcessedBar = barTime;
      return(direction);
   }
};

#endif // __ENGULFING_STOCHASTIC_MQH__
