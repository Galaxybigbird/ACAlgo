#ifndef __TOTAL_POWER_INDICATOR_MQH__
#define __TOTAL_POWER_INDICATOR_MQH__

class CTotalPowerIndicator
{
private:
   int  m_lookback;
   int  m_powerPeriod;
   bool m_useHundred;
   bool m_useCrossover;
   int  m_triggerCandle;

   int  m_bearHandle;
   int  m_bullHandle;

public:
   CTotalPowerIndicator()
   {
      m_lookback = 45;
      m_powerPeriod = 10;
      m_useHundred = false;
      m_useCrossover = false;
      m_triggerCandle = 1;
      m_bearHandle = INVALID_HANDLE;
      m_bullHandle = INVALID_HANDLE;
   }

   bool Init(const string symbol,
             ENUM_TIMEFRAMES timeframe,
             int lookback,
             int powerPeriod,
             bool useHundred,
             bool useCrossover,
             int triggerCandle)
   {
      Shutdown();

      m_lookback = MathMax(1, lookback);
      m_powerPeriod = MathMax(1, powerPeriod);
      m_useHundred = useHundred;
      m_useCrossover = useCrossover;
      m_triggerCandle = MathMax(0, triggerCandle);

      m_bearHandle = iBearsPower(symbol, timeframe, m_powerPeriod);
      m_bullHandle = iBullsPower(symbol, timeframe, m_powerPeriod);

      return (m_bearHandle != INVALID_HANDLE && m_bullHandle != INVALID_HANDLE);
   }

   void Shutdown()
   {
      if(m_bearHandle != INVALID_HANDLE)
         IndicatorRelease(m_bearHandle);
      if(m_bullHandle != INVALID_HANDLE)
         IndicatorRelease(m_bullHandle);
      m_bearHandle = INVALID_HANDLE;
      m_bullHandle = INVALID_HANDLE;
   }

   int Evaluate(const MqlRates &rates[], int count)
   {
      if(m_bearHandle == INVALID_HANDLE || m_bullHandle == INVALID_HANDLE)
         return 0;

      int barsNeeded = m_powerPeriod + m_lookback + m_triggerCandle + 2;
      if(count < barsNeeded)
         return 0;

      int bufferCount = m_lookback + m_triggerCandle + 2;
      double bearsBuffer[];
      double bullsBuffer[];

      if(CopyBuffer(m_bearHandle, 0, m_triggerCandle, bufferCount, bearsBuffer) != bufferCount)
         return 0;
      if(CopyBuffer(m_bullHandle, 0, m_triggerCandle, bufferCount, bullsBuffer) != bufferCount)
         return 0;

      int bearCount = 0;
      int bullCount = 0;
      for(int j = 0; j < m_lookback; ++j)
      {
         if(bearsBuffer[j] < 0.0)
            bearCount++;
         if(bullsBuffer[j] > 0.0)
            bullCount++;
      }

      double bullPercent = 100.0 * bullCount / (double)m_lookback;
      double bearPercent = 100.0 * bearCount / (double)m_lookback;

      double prevBullPercent = 0.0;
      double prevBearPercent = 0.0;
      int countPrev = MathMin(m_lookback, bufferCount - (m_triggerCandle + 1));
      if(countPrev > 0)
      {
         int prevBullCount = 0;
         int prevBearCount = 0;
         for(int j = 0; j < countPrev; ++j)
         {
            if(bullsBuffer[j + 1] > 0.0)
               prevBullCount++;
            if(bearsBuffer[j + 1] < 0.0)
               prevBearCount++;
         }
         prevBullPercent = 100.0 * prevBullCount / (double)countPrev;
         prevBearPercent = 100.0 * prevBearCount / (double)countPrev;
      }

      int signal = 0;

      if(m_useHundred)
      {
         if(bullPercent >= 100.0 && bearPercent < 100.0)
            signal = 1;
         else if(bearPercent >= 100.0 && bullPercent < 100.0)
            signal = -1;
      }

      if(m_useCrossover)
      {
         bool bullGreater = (bullPercent > bearPercent);
         bool bullGreaterPrev = (prevBullPercent > prevBearPercent);
         if(bullGreater && !bullGreaterPrev)
         {
            if(signal == 0)
               signal = 1;
            else if(signal < 0)
               signal = 0;
         }
         else if(!bullGreater && bullGreaterPrev)
         {
            if(signal == 0)
               signal = -1;
            else if(signal > 0)
               signal = 0;
         }
      }

      return signal;
   }
};

#endif // __TOTAL_POWER_INDICATOR_MQH__
