#ifndef __SUPER_TREND_INDICATOR_MQH__
#define __SUPER_TREND_INDICATOR_MQH__

class CSuperTrendIndicator
{
private:
   int                m_atrHandle;
   int                m_atrPeriod;
   double             m_multiplier;
   ENUM_APPLIED_PRICE m_priceSource;
   bool               m_takeWicks;

   datetime m_lastProcessedBar;
   bool     m_initialised;
   int      m_prevDirection;
   double   m_prevFinalUpper;
   double   m_prevFinalLower;
   double   m_prevSuperTrend;

   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;

   double ResolveSourcePrice(const MqlRates &bar) const
   {
      switch(m_priceSource)
      {
         case PRICE_OPEN:    return(bar.open);
         case PRICE_HIGH:    return(bar.high);
         case PRICE_LOW:     return(bar.low);
         case PRICE_MEDIAN:  return((bar.high + bar.low) * 0.5);
         case PRICE_TYPICAL: return((bar.high + bar.low + bar.close) / 3.0);
         case PRICE_WEIGHTED:return((bar.high + bar.low + bar.close + bar.open) * 0.25);
         default:            return(bar.close);
      }
   }

public:
   CSuperTrendIndicator()
      : m_atrHandle(INVALID_HANDLE),
        m_atrPeriod(22),
        m_multiplier(3.0),
        m_priceSource(PRICE_MEDIAN),
        m_takeWicks(true),
        m_lastProcessedBar(0),
        m_initialised(false),
        m_prevDirection(1),
        m_prevFinalUpper(0.0),
        m_prevFinalLower(0.0),
        m_prevSuperTrend(0.0),
        m_symbol(_Symbol),
        m_timeframe(PERIOD_CURRENT)
   {
   }

   bool Init(const string symbol,
             const ENUM_TIMEFRAMES timeframe,
             const int atrPeriod,
             const double multiplier,
             const ENUM_APPLIED_PRICE priceSource,
             const bool takeWicks)
   {
      Shutdown();

      m_symbol = symbol;
      m_timeframe = timeframe;
      m_atrPeriod = MathMax(1, atrPeriod);
      m_multiplier = MathMax(0.1, multiplier);
      m_priceSource = priceSource;
      m_takeWicks = takeWicks;

      m_atrHandle = iATR(symbol, timeframe, m_atrPeriod);
      if(m_atrHandle == INVALID_HANDLE)
      {
         Print("[SuperTrend] Failed to create ATR handle. Error: ", GetLastError());
         return(false);
      }

      m_lastProcessedBar = 0;
      m_initialised = false;
      m_prevDirection = 1;
      m_prevFinalUpper = 0.0;
      m_prevFinalLower = 0.0;
      m_prevSuperTrend = 0.0;
      return(true);
   }

   void Shutdown()
   {
      if(m_atrHandle != INVALID_HANDLE)
      {
         IndicatorRelease(m_atrHandle);
         m_atrHandle = INVALID_HANDLE;
      }
      m_initialised = false;
      m_lastProcessedBar = 0;
   }

   int Evaluate(const MqlRates &rates[], const int count, double &outSuperTrend)
   {
      outSuperTrend = m_prevSuperTrend;

      if(m_atrHandle == INVALID_HANDLE || count <= 2)
         return(0);

      datetime barTime = rates[1].time;
      if(barTime == m_lastProcessedBar)
         return(0);

      double atrBuffer[3];
      ResetLastError();
      if(CopyBuffer(m_atrHandle, 0, 0, 3, atrBuffer) < 3)
         return(0);

      MqlRates currentBar = rates[1];
      double atr = atrBuffer[1];
      double corePrice = ResolveSourcePrice(currentBar);
      double wickMid = (currentBar.high + currentBar.low) * 0.5;
      double basis = m_takeWicks ? (corePrice + wickMid) * 0.5 : corePrice;

      double basicUpper = basis + m_multiplier * atr;
      double basicLower = basis - m_multiplier * atr;

      double finalUpper = basicUpper;
      double finalLower = basicLower;

      if(m_initialised)
      {
         if(basicUpper < m_prevFinalUpper || currentBar.close > m_prevFinalUpper)
            finalUpper = basicUpper;
         else
            finalUpper = m_prevFinalUpper;

         if(basicLower > m_prevFinalLower || currentBar.close < m_prevFinalLower)
            finalLower = basicLower;
         else
            finalLower = m_prevFinalLower;
      }

      int direction = m_prevDirection;
      if(!m_initialised)
         direction = 1;
      else
      {
         if(direction == 1 && currentBar.close <= finalUpper)
            direction = -1;
         else if(direction == -1 && currentBar.close >= finalLower)
            direction = 1;
      }

      double superTrend = (direction == 1) ? finalLower : finalUpper;

      int signal = 0;
      if(m_initialised && direction != m_prevDirection)
         signal = direction;

      m_prevDirection = direction;
      m_prevFinalUpper = finalUpper;
      m_prevFinalLower = finalLower;
      m_prevSuperTrend = superTrend;
      m_lastProcessedBar = barTime;
      m_initialised = true;

      outSuperTrend = superTrend;
      return(signal);
   }
};

#endif // __SUPER_TREND_INDICATOR_MQH__
