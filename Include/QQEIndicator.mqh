#ifndef __QQE_INDICATOR_MQH__
#define __QQE_INDICATOR_MQH__

class CQQEIndicator
{
private:
   int       m_rsiHandle;
   int       m_rsiPeriod;
   int       m_smoothingFactor;
   double    m_alertLevel;
   bool      m_useLevelFilter;
   datetime  m_lastProcessedBar;
   bool      m_initialised;

   double    m_prevRsiMa;
   double    m_prevMaAtr;
   double    m_prevMaMaAtr;
   double    m_prevTrLevel;

   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;

   double SmoothEMA(const double value, const double prevValue, const int period) const
   {
      double alpha = 2.0 / (period + 1.0);
      return(value * alpha + prevValue * (1.0 - alpha));
   }

   bool Warmup()
   {
      int warmBars = MathMax(40, m_rsiPeriod * 4);
      warmBars = MathMin(warmBars, 512);

      double rsiBuffer[];
      ResetLastError();
      if(CopyBuffer(m_rsiHandle, 0, 0, warmBars, rsiBuffer) < warmBars)
         return(false);

      m_prevRsiMa   = rsiBuffer[warmBars - 1];
      m_prevMaAtr   = 0.0;
      m_prevMaMaAtr = 0.0;
      m_prevTrLevel = m_prevRsiMa;

      for(int i = warmBars - 2; i >= 0; --i)
      {
         double rsiValue = rsiBuffer[i];
         double rsiMa = SmoothEMA(rsiValue, m_prevRsiMa, m_smoothingFactor);
         double atrRsi = MathAbs(rsiMa - m_prevRsiMa);
         double maAtr = SmoothEMA(atrRsi, m_prevMaAtr, m_rsiPeriod * 2 - 1);
         double maMaAtr = SmoothEMA(maAtr, m_prevMaMaAtr, m_rsiPeriod * 2 - 1);
         double dar = maMaAtr * 4.236;
         double tr = m_prevTrLevel;

         if(rsiMa < tr)
         {
            double candidate = rsiMa + dar;
            if((m_prevRsiMa < tr) && (candidate > tr))
               candidate = tr;
            tr = candidate;
         }
         else if(rsiMa > tr)
         {
            double candidate = rsiMa - dar;
            if((m_prevRsiMa > tr) && (candidate < tr))
               candidate = tr;
            tr = candidate;
         }

         m_prevTrLevel = tr;
         m_prevMaMaAtr = maMaAtr;
         m_prevMaAtr = maAtr;
         m_prevRsiMa = rsiMa;
      }

      m_initialised = true;
      return(true);
   }

public:
   CQQEIndicator()
      : m_rsiHandle(INVALID_HANDLE),
        m_rsiPeriod(14),
        m_smoothingFactor(5),
        m_alertLevel(50.0),
        m_useLevelFilter(false),
        m_lastProcessedBar(0),
        m_initialised(false),
        m_prevRsiMa(50.0),
        m_prevMaAtr(0.0),
        m_prevMaMaAtr(0.0),
        m_prevTrLevel(50.0),
        m_symbol(_Symbol),
        m_timeframe(PERIOD_CURRENT)
   {
   }

   bool Init(const string symbol,
             const ENUM_TIMEFRAMES timeframe,
             const int rsiPeriod,
             const int smoothingFactor,
             const double alertLevel,
             const bool useLevelFilter)
   {
      Shutdown();

      m_symbol = symbol;
      m_timeframe = timeframe;
      m_rsiPeriod = MathMax(2, rsiPeriod);
      m_smoothingFactor = MathMax(1, smoothingFactor);
      m_alertLevel = alertLevel;
      m_useLevelFilter = useLevelFilter;

      m_rsiHandle = iRSI(symbol, timeframe, m_rsiPeriod, PRICE_CLOSE);
      if(m_rsiHandle == INVALID_HANDLE)
      {
         Print("[QQE] Failed to create iRSI handle. Error: ", GetLastError());
         return(false);
      }

      m_initialised = false;
      m_lastProcessedBar = 0;
      return(true);
   }

   void Shutdown()
   {
      if(m_rsiHandle != INVALID_HANDLE)
      {
         IndicatorRelease(m_rsiHandle);
         m_rsiHandle = INVALID_HANDLE;
      }
      m_initialised = false;
      m_lastProcessedBar = 0;
   }

   int Evaluate(const MqlRates &rates[], const int count, double &outRsiMa, double &outTrLevel)
   {
      outRsiMa = 0.0;
      outTrLevel = 0.0;

      if(m_rsiHandle == INVALID_HANDLE || count <= 2)
         return(0);

      if(!m_initialised)
      {
         if(!Warmup())
            return(0);
      }

      datetime barTime = rates[1].time;
      if(barTime == m_lastProcessedBar)
      {
         outRsiMa = m_prevRsiMa;
         outTrLevel = m_prevTrLevel;
         return(0);
      }

      double rsiBuffer[3];
      ResetLastError();
      if(CopyBuffer(m_rsiHandle, 0, 0, 3, rsiBuffer) < 3)
         return(0);

      double rsiValue = rsiBuffer[1];
      double rsiMa = SmoothEMA(rsiValue, m_prevRsiMa, m_smoothingFactor);
      double atrRsi = MathAbs(rsiMa - m_prevRsiMa);
      double maAtr = SmoothEMA(atrRsi, m_prevMaAtr, m_rsiPeriod * 2 - 1);
      double maMaAtr = SmoothEMA(maAtr, m_prevMaMaAtr, m_rsiPeriod * 2 - 1);
      double dar = maMaAtr * 4.236;
      double tr = m_prevTrLevel;

      if(rsiMa < tr)
      {
         double candidate = rsiMa + dar;
         if((m_prevRsiMa < tr) && (candidate > tr))
            candidate = tr;
         tr = candidate;
      }
      else if(rsiMa > tr)
      {
         double candidate = rsiMa - dar;
         if((m_prevRsiMa > tr) && (candidate < tr))
            candidate = tr;
         tr = candidate;
      }

      int direction = 0;
      if(m_prevRsiMa < m_prevTrLevel && rsiMa > tr)
         direction = 1;
      else if(m_prevRsiMa > m_prevTrLevel && rsiMa < tr)
         direction = -1;

      if(direction != 0 && m_useLevelFilter)
      {
         if(direction == 1 && rsiMa < m_alertLevel)
            direction = 0;
         else if(direction == -1 && rsiMa > m_alertLevel)
            direction = 0;
      }

      m_prevTrLevel = tr;
      m_prevMaMaAtr = maMaAtr;
      m_prevMaAtr = maAtr;
      m_prevRsiMa = rsiMa;
      m_lastProcessedBar = barTime;

      outRsiMa = rsiMa;
      outTrLevel = tr;
      return(direction);
   }
};

#endif // __QQE_INDICATOR_MQH__
