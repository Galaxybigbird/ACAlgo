#ifndef __ENGULFING_SIGNALS_MQH__
#define __ENGULFING_SIGNALS_MQH__

enum ENUM_ENGULFING_SIGNAL
{
   ENGULFING_NONE   = 0,
   ENGULFING_BULLISH = 1,
   ENGULFING_BEARISH = -1
};

class CEngulfingSignalDetector
{
private:
   datetime m_lastProcessedBar;

   static bool IsGreen(const double openPrice, const double closePrice)
   {
      return(openPrice < closePrice);
   }

public:
   CEngulfingSignalDetector(): m_lastProcessedBar(0) {}

   void Reset()
   {
      m_lastProcessedBar = 0;
   }

   static bool IsBullishPattern(const MqlRates &previousBar, const MqlRates &currentBar)
   {
      if(!IsGreen(currentBar.open, currentBar.close) || IsGreen(previousBar.open, previousBar.close))
         return(false);

      return(currentBar.open <= previousBar.close && currentBar.close > previousBar.open);
   }

   static bool IsBearishPattern(const MqlRates &previousBar, const MqlRates &currentBar)
   {
      if(IsGreen(currentBar.open, currentBar.close) || !IsGreen(previousBar.open, previousBar.close))
         return(false);

      return(currentBar.open >= previousBar.close && currentBar.close < previousBar.open);
   }

   int Evaluate(const MqlRates &rates[], const int count)
   {
      if(count <= 2)
         return(ENGULFING_NONE);

      datetime barTime = rates[1].time;
      if(barTime == m_lastProcessedBar)
         return(ENGULFING_NONE);

      m_lastProcessedBar = barTime;

      MqlRates previousBar = rates[2];
      MqlRates currentBar  = rates[1];

      if(IsBullishPattern(previousBar, currentBar))
         return(ENGULFING_BULLISH);

      if(IsBearishPattern(previousBar, currentBar))
         return(ENGULFING_BEARISH);

      return(ENGULFING_NONE);
   }
};

#endif // __ENGULFING_SIGNALS_MQH__
