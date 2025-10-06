#ifndef __FIBO_ZIGZAG_MQH__
#define __FIBO_ZIGZAG_MQH__

class CFiboZigZag
{
private:
   double m_retracement;
   double m_minSizeAtr;
   int    m_atrPeriod;

   // Wave tracking state
   int    m_waveType;             // 0 = none, 1 = up, -1 = down
   double m_waveStartPrice;
   double m_waveEndPrice;
   int    m_waveStartDistance;
   int    m_waveEndDistance;

   double m_highMem;
   double m_lowMem;
   int    m_distFromHigh;
   int    m_distFromLow;

   double m_rollingAtr;
   int    m_rollingAtrCount;

   // Latest signal
   int    m_lastSignal;
   bool   m_useHighLowPrice;
   bool   m_useAtrFilter;
   bool   m_requireConfirmation;
   int    m_confirmationBars;
   int    m_pendingSignal;
   int    m_pendingDistance;

public:
   CFiboZigZag()
   {
      m_retracement   = 23.6;
      m_minSizeAtr    = 0.0;
      m_atrPeriod     = 14;
      m_useHighLowPrice = true;
      m_useAtrFilter = true;
      m_requireConfirmation = false;
      m_confirmationBars = 1;
      ResetState();
   }

   void Init(double retracementPercent,
             double minSizeInAtrUnits,
             int atrPeriod,
             bool useHighLowPrice,
             bool useAtrFilter,
             bool requireConfirmation,
             int confirmationBars)
   {
      m_retracement = retracementPercent;
      m_minSizeAtr  = minSizeInAtrUnits;
      m_atrPeriod   = MathMax(1, atrPeriod);
      m_useHighLowPrice = useHighLowPrice;
      m_useAtrFilter = useAtrFilter;
      m_requireConfirmation = requireConfirmation;
      m_confirmationBars = MathMax(0, confirmationBars);
      ResetState();
   }

   void ResetState()
   {
      m_waveType = 0;
      m_waveStartPrice = 0.0;
      m_waveEndPrice = 0.0;
      m_waveStartDistance = 0;
      m_waveEndDistance = 0;
      m_highMem = 0.0;
      m_lowMem  = 0.0;
      m_distFromHigh = 0;
      m_distFromLow  = 0;
      m_rollingAtr = 0.0;
      m_rollingAtrCount = 0;
      m_lastSignal = 0;
      m_pendingSignal = 0;
      m_pendingDistance = 0;
   }

   int Evaluate(const MqlRates &rates[], int count)
   {
      m_lastSignal = 0;
      if(count < 3)
         return 0;

      MqlRates data[];
      ArrayResize(data, count);
      for(int i = 0; i < count; ++i)
         data[i] = rates[count - 1 - i];

      ResetState();

      int from = 1;
      m_rollingAtr = (data[0].high - data[0].low) / _Point;
      if(m_rollingAtr <= 0.0)
         m_rollingAtr = MathMax(_Point, 1e-6);
      m_rollingAtrCount = 1;

      for(int i = from; i < count - 1; ++i)
      {
         if(m_pendingSignal != 0)
            m_pendingDistance++;

         double evalHigh = m_useHighLowPrice ? data[i].high : data[i].close;
         double evalLow  = m_useHighLowPrice ? data[i].low  : data[i].close;

         m_distFromHigh++;
         m_distFromLow++;

         double rangePoints = (data[i].high - data[i].low) / _Point;

         if(m_rollingAtrCount < m_atrPeriod)
         {
            m_rollingAtr += rangePoints;
            m_rollingAtrCount++;
            if(m_rollingAtrCount == m_atrPeriod)
            {
               m_rollingAtr /= (double)m_rollingAtrCount;
               if(m_rollingAtr <= 0.0)
                  m_rollingAtr = MathMax(_Point, 1e-6);
               m_highMem = evalHigh;
               m_lowMem  = evalLow;
               m_distFromHigh = 0;
               m_distFromLow  = 0;
            }
            continue;
         }
         else
         {
            double newPortion = rangePoints / (double)m_atrPeriod;
            m_rollingAtr = m_rollingAtr - (m_rollingAtr / (double)m_atrPeriod) + newPortion;
            if(m_rollingAtr <= 0.0)
               m_rollingAtr = MathMax(_Point, 1e-6);
         }

         if(m_waveType != 0)
         {
            m_waveStartDistance++;
            m_waveEndDistance++;
         }

         if(m_waveType == 1)
         {
            if(evalHigh > m_waveEndPrice)
            {
               m_waveEndPrice = evalHigh;
               m_waveEndDistance = 0;
               m_highMem = evalHigh;
               m_lowMem  = evalLow;
               m_distFromHigh = 0;
               m_distFromLow  = 0;
            }

            if(evalLow < m_lowMem || m_distFromLow == 0)
            {
               m_lowMem = evalLow;
               m_distFromLow = 0;
               double waveSize = (m_waveEndPrice - m_waveStartPrice) / _Point;
               double retraceSize = (m_waveEndPrice - m_lowMem) / _Point;
               if(waveSize > 0.0)
               {
                  double retracedPercent = (retraceSize / waveSize) * 100.0;
                  double atrUnits = retraceSize / m_rollingAtr;
                  if((!m_useAtrFilter || atrUnits >= m_minSizeAtr) && retracedPercent >= m_retracement)
                  {
                     m_waveType = -1;
                     int prevIdx = MathMax(0, i - m_distFromHigh);
                     double prevHigh = m_useHighLowPrice ? data[prevIdx].high : data[prevIdx].close;
                     m_waveStartPrice = prevHigh;
                     m_waveStartDistance = m_distFromHigh;
                     m_waveEndPrice = evalLow;
                     m_waveEndDistance = 0;
                     m_highMem = evalHigh;
                     m_lowMem  = evalLow;
                     m_distFromHigh = 0;
                     m_distFromLow  = 0;
                     m_pendingSignal = -1;
                     m_pendingDistance = 0;
                  }
               }
            }
         }
         else if(m_waveType == -1)
         {
            if(evalLow < m_waveEndPrice)
            {
               m_waveEndPrice = evalLow;
               m_waveEndDistance = 0;
               m_highMem = evalHigh;
               m_lowMem  = evalLow;
               m_distFromHigh = 0;
               m_distFromLow  = 0;
            }

            if(evalHigh > m_highMem || m_distFromHigh == 0)
            {
               m_highMem = evalHigh;
               m_distFromHigh = 0;
               double waveSize = (m_waveStartPrice - m_waveEndPrice) / _Point;
               double retraceSize = (m_highMem - m_waveEndPrice) / _Point;
               if(waveSize > 0.0)
               {
                  double retracedPercent = (retraceSize / waveSize) * 100.0;
                  double atrUnits = retraceSize / m_rollingAtr;
                  if((!m_useAtrFilter || atrUnits >= m_minSizeAtr) && retracedPercent >= m_retracement)
                  {
                     m_waveType = 1;
                     m_waveStartPrice = m_lowMem;
                     m_waveStartDistance = m_distFromLow;
                     m_waveEndPrice = evalHigh;
                     m_waveEndDistance = 0;
                     m_highMem = evalHigh;
                     m_lowMem  = evalLow;
                     m_distFromHigh = 0;
                     m_distFromLow  = 0;
                     m_pendingSignal = 1;
                     m_pendingDistance = 0;
                  }
               }
            }
         }
         else
         {
            if(evalHigh > m_highMem && evalLow >= m_lowMem)
            {
               double atrUnits = ((evalHigh - m_lowMem) / _Point) / m_rollingAtr;
               if((!m_useAtrFilter || atrUnits >= m_minSizeAtr))
               {
                  m_waveType = 1;
                  m_waveStartPrice = m_lowMem;
                  m_waveStartDistance = m_distFromLow;
                  m_waveEndPrice = evalHigh;
                  m_waveEndDistance = 0;
                  m_highMem = evalHigh;
                  m_lowMem  = evalLow;
                  m_distFromHigh = 0;
                  m_distFromLow  = 0;
                  m_pendingSignal = 1;
                  m_pendingDistance = 0;
               }
            }
            else if(evalLow < m_lowMem && evalHigh <= m_highMem)
            {
               double atrUnits = ((m_highMem - evalLow) / _Point) / m_rollingAtr;
               if((!m_useAtrFilter || atrUnits >= m_minSizeAtr))
               {
                  m_waveType = -1;
                  m_waveStartPrice = m_highMem;
                  m_waveStartDistance = m_distFromHigh;
                  m_waveEndPrice = evalLow;
                  m_waveEndDistance = 0;
                  m_highMem = evalHigh;
                  m_lowMem  = evalLow;
                  m_distFromHigh = 0;
                  m_distFromLow  = 0;
                  m_pendingSignal = -1;
                  m_pendingDistance = 0;
               }
            }
            else if(evalLow < m_lowMem && evalHigh > m_highMem)
            {
               m_highMem = evalHigh;
               m_lowMem  = evalLow;
               m_distFromHigh = 0;
               m_distFromLow  = 0;
            }
         }
      }

      int result = 0;
      if(m_pendingSignal != 0)
      {
         if(!m_requireConfirmation)
            result = m_pendingSignal;
         else if(m_confirmationBars <= 0 || m_pendingDistance >= m_confirmationBars)
            result = m_pendingSignal;
      }

      m_lastSignal = result;
      return result;
   }
};

#endif // __FIBO_ZIGZAG_MQH__
