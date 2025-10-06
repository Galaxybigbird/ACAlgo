#ifndef __INTRABAR_VOLUME_MQH__
#define __INTRABAR_VOLUME_MQH__

class CIntrabarVolumeIndicator
{
private:
   int  m_period;
   int  m_lookback;
   bool m_granularTrend;
   bool m_requireVolume;

   double SimpleMA(const MqlRates &rates[], int count, int startShift) const
   {
      double sum = 0.0;
      for(int i = 0; i < m_period; ++i)
         sum += rates[startShift + i].close;
      return sum / (double)m_period;
   }

public:
   CIntrabarVolumeIndicator()
   {
      m_period = 20;
      m_lookback = 20;
      m_granularTrend = false;
      m_requireVolume = true;
   }

   void Init(int maPeriod, int lookback, bool granularTrend, bool requireVolume)
   {
      m_period = MathMax(1, maPeriod);
      m_lookback = MathMax(1, lookback);
      m_granularTrend = granularTrend;
      m_requireVolume = requireVolume;
   }

   int Evaluate(const MqlRates &rates[], int count) const
   {
      if(count <= m_lookback + m_period + 1)
         return 0;

      double volumeSum = 0.0;
      for(int i = 1; i <= m_lookback; ++i)
         volumeSum += (double)rates[i].tick_volume;
      double volumeThreshold = volumeSum / (double)m_lookback;
      double currentVolume = (double)rates[1].tick_volume;

      if(m_requireVolume && currentVolume < volumeThreshold)
         return 0;

      double currentValue;
      double prevValue;

      if(m_granularTrend)
      {
         currentValue = rates[1].close;
         prevValue    = rates[2].close;
      }
      else
      {
         currentValue = SimpleMA(rates, count, 1);
         prevValue    = SimpleMA(rates, count, 2);
      }

      double slope = currentValue - prevValue;
      if(slope > 0.0)
         return 1;
      if(slope < 0.0)
         return -1;
      return 0;
   }
};

#endif // __INTRABAR_VOLUME_MQH__
