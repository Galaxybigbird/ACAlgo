//+------------------------------------------------------------------+
//|                                                     AC_SBS_Base.mq5|
//|  Mechanical Swing Breakout Sequence (SBS) EA foundation.         |
//|                                                                  |
//|  This revision wraps pattern logic inside a class, exposes       |
//|  granular validation toggles, adds structured logging, and       |
//|  leverages AC risk management for dynamic position sizing.       |
//+------------------------------------------------------------------+
#property copyright   "AC Algo"
#property link        ""
#property version     "1.04"
#property description "Swing Breakout Sequence base EA with AC risk integration"
#property strict
#include <Trade/Trade.mqh>
#include <Trade/OrderInfo.mqh>
#include <ACFunctions_SBS.mqh>
#include <ATRtrailing.mqh>
#include <ClusteringLib/Database.mqh>
#include <ClusteringLib/TesterHandler.mqh>

CSymbolValidator g_SymbolValidator;
double g_LastStopDistance   = 0.0;
bool   g_SymbolReady        = false;

enum ENTRY_PROFILE
  {
   ENTRY_BREAKOUT=0,
   ENTRY_LIQ_REVERSAL=1,
   ENTRY_GOLDEN_FIB=2
  };

enum SL_MODE { SL_ATR=0, SL_SWING=1 };
enum TP_MODE { TP_RR=0, TP_SWING3=1 };

enum INVALIDATION_MODE
  {
   INVALIDATE_WICK=0,
   INVALIDATE_CLOSE=1
  };

//--- Input groups --------------------------------------------------------------------------------
input group "==== SBS Structure Settings ===="
input int      InpPivotLeft        = 2;       // pivot lookback left
input int      InpPivotRight       = 2;       // pivot lookback right
input double   InpMinHeightPct     = 0.10;    // InpMinHeightPct (minimum pattern height (% of price))
input int      InpMaxWidthBars     = 50;      // InpMaxWidthBars (maximum bars contained in pattern)
input double   InpMinQualityRatio  = 0.90;    // InpMinQualityRatio (SBS ratio threshold (TP distance / SL distance))

input group "==== Validation Toggles ===="
input bool              InpUseStrictPattern   = true;   // InpUseStrictPattern (enforce strict alternating structure)
input bool              InpRequireSweep       = true;   // InpRequireSweep (require liquidity sweep (P4 vs P2))
input bool              InpUseQualityGate     = true;   // InpUseQualityGate (enforce quality ratio at validation bar)
input bool              InpUseInvalidation    = true;   // InpUseInvalidation (invalidate if price mitigates guard level)
input INVALIDATION_MODE InpInvalidationMode   = INVALIDATE_WICK; // InpInvalidationMode (wick or close invalidation)
input bool              InpLogEvents          = true;   // InpLogEvents (enable verbose logging for tracing)

input group "==== Market Structure Filters ===="
input bool     InpUseBOSFilter     = true;    // InpUseBOSFilter (require Break of Structure in pattern direction)
input bool     InpUseMSSFilter     = false;   // InpUseMSSFilter (require Market Structure Shift (ICT style))

input group "==== Entry & Execution ===="
input ENTRY_PROFILE InpEntryProfile = ENTRY_BREAKOUT;
input int      InpBreakoutSwing     = 3;      // InpBreakoutSwing (swing to break: 1..4)
input bool     InpUseGoldenFib      = true;   // InpUseGoldenFib (enable fib/"gold" logic)
input double   InpFibLevel          = 0.618;  // InpFibLevel (fibonacci entry level (0..1))
input bool     InpImmediateSwing4   = false;  // InpImmediateSwing4 (validate on fib tap without waiting for swing-5)

input group "==== Exit & Risk Settings ===="
input SL_MODE  InpSLMode            = SL_ATR;
input int      InpATRPeriod         = 14;
input double   InpATRMul            = 2.0;
input TP_MODE  InpTPMode            = TP_RR;
input double   InpRRTarget          = 2.0;

input group "==== General Settings ===="
input int      InpLookbackBars      = 1500;   // InpLookbackBars (scan depth in bars)
input int      InpMagic             = 270915;
input double   InpLots              = 0.10;   // InpLots (fallback lot size (ACRM replaces via CalculateLots))
input bool     InpAllowShorts       = true;
input bool     InpAllowLongs        = true;
input bool     InpPreventDuplicateOrders = true;  // InpPreventDuplicateOrders (avoid stacking identical pending orders)
input bool     InpCancelOnInvalidation   = true;  // InpCancelOnInvalidation (delete orders when guard breached)
input int      InpPendingTTLMinutes      = 0;     // InpPendingTTLMinutes (pending order time-to-live (minutes, 0=disable))

input group "==== Optimization Logging ===="
sinput int     idTask_         = 0;        // - Optimization task ID for clustering DB
sinput string  fileName_       = "database.sqlite"; // - SQLite database file (ClusteringLib schema)

//--- Global runtime objects ---------------------------------------------------------------------
CTrade         Trade;
int            g_AtrHandle = INVALID_HANDLE;
MqlTick        lastTick;
datetime       lastBarTime = 0;

double         g_HighSeries[];
double         g_LowSeries[];
double         g_CloseSeries[];
int            g_SeriesCount = 0;
double         g_LastATR = 0.0;
bool           g_SeriesInitialized = false;

//--- Lightweight swing descriptor ---------------------------------------------------------------
struct SwingPoint
  {
   int    index;
   double price;
   int    type;    // +1 = swing high, -1 = swing low
  };

//+------------------------------------------------------------------+
//| Utility logging helper                                           |
//+------------------------------------------------------------------+
void Log(const string message)
  {
   if(InpLogEvents)
      Print(message);
  }

//+------------------------------------------------------------------+
//| Order comment helpers                                            |
//+------------------------------------------------------------------+
string BuildOrderComment(ENTRY_PROFILE profile,bool isBuy,double guard,INVALIDATION_MODE mode)
  {
   long digits=0;
   if(!SymbolInfoInteger(_Symbol,SYMBOL_DIGITS,digits))
      digits=0;
   return StringFormat("SBS|p%d|d%d|g%s|m%d",
                       (int)profile,
                       (isBuy ? 1 : 0),
                       DoubleToString(guard,(int)digits),
                       (int)mode);
  }

bool ParseOrderComment(const string comment,ENTRY_PROFILE &profile,bool &isBuy,double &guard,INVALIDATION_MODE &mode)
  {
   profile=(ENTRY_PROFILE)0;
   isBuy=true;
   guard=0.0;
   mode=InpInvalidationMode;

   if(StringLen(comment)<3 || StringFind(comment,"SBS|")!=0)
      return false;

   string parts[];
   int count=StringSplit(comment,'|',parts);
   if(count<5)
      return false;

   bool haveP=false,haveD=false,haveG=false,haveM=false;
   for(int i=1;i<count;i++)
     {
      if(StringLen(parts[i])<2)
         continue;
      ushort tag=StringGetCharacter(parts[i],0);
      string value=StringSubstr(parts[i],1);
      switch(tag)
        {
         case 'p':
            profile=(ENTRY_PROFILE)StringToInteger(value);
            haveP=true;
            break;
         case 'd':
            isBuy=(StringToInteger(value)!=0);
            haveD=true;
            break;
         case 'g':
            guard=StringToDouble(value);
            haveG=true;
            break;
         case 'm':
            mode=(INVALIDATION_MODE)StringToInteger(value);
            haveM=true;
            break;
        }
     }
   return(haveP && haveD && haveG && haveM);
  }

bool IsPendingOrderType(ENUM_ORDER_TYPE type)
  {
   switch(type)
     {
      case ORDER_TYPE_BUY_LIMIT:
      case ORDER_TYPE_SELL_LIMIT:
      case ORDER_TYPE_BUY_STOP:
      case ORDER_TYPE_SELL_STOP:
      case ORDER_TYPE_BUY_STOP_LIMIT:
      case ORDER_TYPE_SELL_STOP_LIMIT:
         return true;
     }
   return false;
  }

bool IsBuyOrderType(ENUM_ORDER_TYPE type)
  {
   return(type==ORDER_TYPE_BUY_LIMIT ||
          type==ORDER_TYPE_BUY_STOP ||
          type==ORDER_TYPE_BUY_STOP_LIMIT);
  }

bool HasActiveOrder(ENTRY_PROFILE profile,bool isBuy)
  {
   int total=OrdersTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetInteger(ORDER_MAGIC)!=InpMagic)
         continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol)
         continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(!IsPendingOrderType(type))
         continue;
      bool orderBuy=IsBuyOrderType(type);
      string comment=OrderGetString(ORDER_COMMENT);
      ENTRY_PROFILE metaProfile;
      bool metaBuy;
      double guard;
      INVALIDATION_MODE mode;
      if(ParseOrderComment(comment,metaProfile,metaBuy,guard,mode))
        {
         if(metaProfile==profile && metaBuy==isBuy)
            return true;
        }
      else
        {
         if(orderBuy==isBuy)
            return true;
        }
     }
   return false;
  }

bool CancelOrder(ulong ticket,const string reason)
  {
   if(!Trade.OrderDelete(ticket))
     {
      uint ret=Trade.ResultRetcode();
      Log(StringFormat("Failed to cancel order %I64u (%u %s): %s",
                       ticket,
                       ret,
                       Trade.ResultRetcodeDescription(),
                       reason));
      return false;
     }
   Log(StringFormat("Pending order %I64u canceled: %s",ticket,reason));
   return true;
  }

//+------------------------------------------------------------------+
//| Symbol helpers                                                   |
//+------------------------------------------------------------------+
double NormalizePrice(double value)
  {
   long digits=0;
   if(SymbolInfoInteger(_Symbol,SYMBOL_DIGITS,digits))
      return NormalizeDouble(value,(int)digits);
   return value;
  }

double NormalizeVolume(double lots)
  {
   double step   = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step>0.0)
      lots = MathRound(lots/step)*step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   int volumeDigits=0;
   double tmpStep=step;
   while(volumeDigits<8 && tmpStep>0.0 && MathAbs(tmpStep-MathRound(tmpStep))>1e-10)
     {
      tmpStep*=10.0;
      volumeDigits++;
     }
   if(volumeDigits>0)
      lots = NormalizeDouble(lots,volumeDigits);
   return lots;
  }

//+------------------------------------------------------------------+
//| ATR helper                                                       |
//+------------------------------------------------------------------+
double GetATR(int shift)
  {
   if(g_SeriesCount<=0)
      return g_LastATR;

   if(g_LastATR<=0.0 || g_SeriesCount<InpATRPeriod+1)
     {
      g_AtrHandle = iATR(_Symbol,_Period,InpATRPeriod);
      if(g_AtrHandle==INVALID_HANDLE)
         return g_LastATR;
      double atrBuf[];
      if(CopyBuffer(g_AtrHandle,0,0,InpATRPeriod+1,atrBuf)<=0)
        {
         IndicatorRelease(g_AtrHandle);
         g_AtrHandle=INVALID_HANDLE;
         return g_LastATR;
        }
      g_LastATR = atrBuf[0];
      IndicatorRelease(g_AtrHandle);
      g_AtrHandle=INVALID_HANDLE;
      return g_LastATR;
     }

   double tr=0.0;
   double currHigh=g_HighSeries[0];
   double currLow =g_LowSeries[0];
   double prevClose=(g_SeriesCount>1) ? g_CloseSeries[1] : g_CloseSeries[0];
   double diff1=currHigh-currLow;
   double diff2=MathAbs(currHigh-prevClose);
   double diff3=MathAbs(currLow-prevClose);
   tr = MathMax(diff1,MathMax(diff2,diff3));
   g_LastATR = ((g_LastATR*(InpATRPeriod-1))+tr)/InpATRPeriod;
   return g_LastATR;
  }

//+------------------------------------------------------------------+
//| Height (% of price) utility                                      |
//+------------------------------------------------------------------+
double PercentOfPrice(double points)
  {
   if(g_SeriesCount==0)
      return 0.0;
   double mid=(g_HighSeries[0]+g_LowSeries[0])*0.5;
   if(mid<=0.0)
      mid=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   return(points/mid);
  }

void ShiftSeries(int requiredBars)
  {
   if(g_SeriesCount<=0)
      return;

   int keep=MathMin(g_SeriesCount-1,requiredBars-1);
   if(keep<0)
      keep=0;

   if(keep>0)
     {
      ArrayResize(g_HighSeries,keep);
      ArrayResize(g_LowSeries,keep);
      ArrayResize(g_CloseSeries,keep);
     }
   else
     {
      ArrayResize(g_HighSeries,0);
      ArrayResize(g_LowSeries,0);
      ArrayResize(g_CloseSeries,0);
     }
   g_SeriesCount=keep;
  }

bool AppendLatestBar(int requiredBars)
  {
   MqlRates rates[];
   int copyCount=CopyRates(_Symbol,_Period,0,2,rates);
   if(copyCount<=0)
      return false;

   double high=rates[0].high;
   double low =rates[0].low;
   double close=rates[0].close;

   ArraySetAsSeries(g_HighSeries,true);
   ArraySetAsSeries(g_LowSeries,true);
   ArraySetAsSeries(g_CloseSeries,true);

   ArrayResize(g_HighSeries,g_SeriesCount+1);
   ArrayResize(g_LowSeries,g_SeriesCount+1);
   ArrayResize(g_CloseSeries,g_SeriesCount+1);

   for(int i=g_SeriesCount;i>0;--i)
     {
      g_HighSeries[i]=g_HighSeries[i-1];
      g_LowSeries[i]=g_LowSeries[i-1];
      g_CloseSeries[i]=g_CloseSeries[i-1];
     }

   g_HighSeries[0]=high;
   g_LowSeries[0]=low;
   g_CloseSeries[0]=close;
   g_SeriesCount=MathMin(g_SeriesCount+1,requiredBars);

   if(g_SeriesCount<=InpPivotRight)
      return false;

   return true;
  }

bool LoadInitialSeries(int requiredBars)
  {
   int bars=MathMin(requiredBars,(int)Bars(_Symbol,_Period));
   if(bars<=0)
      return false;

   ArraySetAsSeries(g_HighSeries,true);
   ArraySetAsSeries(g_LowSeries,true);
   ArraySetAsSeries(g_CloseSeries,true);

  if(CopyHigh(_Symbol,_Period,0,bars,g_HighSeries)!=bars)
     return false;
  if(CopyLow(_Symbol,_Period,0,bars,g_LowSeries)!=bars)
     return false;
  if(CopyClose(_Symbol,_Period,0,bars,g_CloseSeries)!=bars)
     return false;

  g_SeriesCount=bars;
  if(g_SeriesCount<=InpPivotRight)
     return false;

   g_LastATR=0.0;

  return true;
  }

//+------------------------------------------------------------------+
//| SBS pattern model                                                |
//+------------------------------------------------------------------+
class CSBSPattern
  {
private:
   bool        m_ready;
   bool        m_bullish;
   SwingPoint  m_points[5];
   int         m_firstBar;
   int         m_lastBar;
   double      m_heightPct;
   int         m_widthBars;
   double      m_stopLevel;

public:
                     CSBSPattern(void) : m_ready(false), m_bullish(false),
                                       m_firstBar(-1), m_lastBar(-1),
                                       m_heightPct(0.0), m_widthBars(0),
                                       m_stopLevel(0.0) {}

   bool              BuildFromSwings(const SwingPoint &swings[],int count,bool enforceStrict,string &reason);
   bool              IsReady(void) const      { return m_ready; }
   bool              IsBullish(void) const    { return m_bullish; }
   double            HeightPct(void) const    { return m_heightPct; }
   int               WidthBars(void) const    { return m_widthBars; }
   double            TargetLevel(void) const  { return m_points[3].price; }
   double            StopLevel(void) const    { return m_stopLevel; }
   double            GuardLevel(void) const;  // swing used for invalidation checks
   SwingPoint        Point(int ordinal) const { return m_points[MathMax(0,MathMin(4,ordinal))]; }

   double            BreakoutLevel(int breakoutSwing) const;
   double            FibEntry(double fibLevel) const;

   bool              HasLiquiditySweep(void) const;
   bool              ComputeQuality(double entryPrice,double &outRatio) const;
   bool              IsInvalidated(INVALIDATION_MODE mode,double closePrice,double highPrice,double lowPrice) const;
   bool              BreakoutValidated(double closePrice,double highPrice,double lowPrice,int breakoutSwing) const;
   bool              FibTouched(double fibLevel,double highPrice,double lowPrice) const;
   bool              IsLiquidityReversalArmed(double closePrev,double closeCurr) const;
  };

//+------------------------------------------------------------------+
//| Build pattern from swings                                        |
//+------------------------------------------------------------------+
bool CSBSPattern::BuildFromSwings(const SwingPoint &swings[],int count,bool enforceStrict,string &reason)
  {
   m_ready=false;
   if(count<5)
     {
      reason="insufficient swings in buffer";
      return false;
     }

   // Collect last five alternating swings (chronological)
   SwingPoint seq[5];
   int filled=0;
   int lastType=0;
   for(int i=count-1;i>=0 && filled<5;--i)
     {
      if(filled==0 || swings[i].type!=lastType)
        {
         seq[filled++]=swings[i];
         lastType=swings[i].type;
        }
     }
   if(filled<5)
     {
      reason="could not isolate five alternating swings";
      return false;
     }
   for(int a=0,b=4;a<b;++a,--b)
     {
      SwingPoint tmp=seq[a];
      seq[a]=seq[b];
      seq[b]=tmp;
     }

   m_bullish=(seq[4].type==-1);

   if(enforceStrict)
     {
      if(m_bullish)
        {
         if(!(seq[0].type==-1 && seq[1].type==+1 && seq[2].type==-1 && seq[3].type==+1 && seq[4].type==-1))
           {
            reason="strict bullish alternation failed";
            return false;
           }
        }
      else
        {
         if(!(seq[0].type==+1 && seq[1].type==-1 && seq[2].type==+1 && seq[3].type==-1 && seq[4].type==+1))
           {
            reason="strict bearish alternation failed";
            return false;
           }
        }
     }

   double highest=-DBL_MAX;
   double lowest=DBL_MAX;
   int minIndex=seq[0].index;
   int maxIndex=seq[0].index;

   for(int k=0;k<5;k++)
     {
      highest = (seq[k].type==+1) ? MathMax(highest,seq[k].price) : highest;
      lowest  = (seq[k].type==-1) ? MathMin(lowest,seq[k].price)  : lowest;
      minIndex=MathMin(minIndex,seq[k].index);
      maxIndex=MathMax(maxIndex,seq[k].index);
      m_points[k]=seq[k];
     }

   double rangePct=PercentOfPrice(MathAbs(highest-lowest));
   if(rangePct<InpMinHeightPct)
     {
      reason=StringFormat("pattern rejected: height %.5f < minimum %.5f",rangePct,InpMinHeightPct);
      return false;
     }

   int width=MathAbs(maxIndex-minIndex);
   if(width>InpMaxWidthBars)
     {
      reason=StringFormat("pattern rejected: width %d > max %d",width,InpMaxWidthBars);
      return false;
     }

   // Determine swing-based stop: lowest low for bullish, highest high for bearish
   if(m_bullish)
     {
      double minLow=MathMin(MathMin(seq[0].price,seq[2].price),seq[4].price);
      m_stopLevel=minLow;
     }
   else
     {
      double maxHigh=MathMax(MathMax(seq[0].price,seq[2].price),seq[4].price);
      m_stopLevel=maxHigh;
     }

   m_heightPct=rangePct;
   m_widthBars=width;
   m_firstBar=minIndex;
   m_lastBar =maxIndex;
   m_ready   =true;
   reason    ="";
   return true;
  }

//+------------------------------------------------------------------+
//| Guard level (liquidity reference)                                |
//+------------------------------------------------------------------+
double CSBSPattern::GuardLevel(void) const
  {
   return m_bullish ? m_points[2].price : m_points[2].price;
  }

//+------------------------------------------------------------------+
//| Determine breakout level for a given swing                       |
//+------------------------------------------------------------------+
double CSBSPattern::BreakoutLevel(int breakoutSwing) const
  {
   int idx=MathMax(1,MathMin(4,breakoutSwing));
   return m_points[idx].price;
  }

//+------------------------------------------------------------------+
//| Fib entry calculation                                            |
//+------------------------------------------------------------------+
double CSBSPattern::FibEntry(double fibLevel) const
  {
   double from=m_points[2].price;
   double to  =m_points[3].price;
   if(m_bullish)
      return from + fibLevel*(to-from);
   return from - fibLevel*(from-to);
  }

//+------------------------------------------------------------------+
//| Liquidity sweep test                                             |
//+------------------------------------------------------------------+
bool CSBSPattern::HasLiquiditySweep(void) const
  {
   if(!m_ready)
      return false;
   return m_bullish ? (m_points[4].price < m_points[2].price)
                    : (m_points[4].price > m_points[2].price);
  }

//+------------------------------------------------------------------+
//| Quality ratio computation (TP distance / SL distance)            |
//+------------------------------------------------------------------+
bool CSBSPattern::ComputeQuality(double entryPrice,double &outRatio) const
  {
   if(!m_ready)
      return false;

   double stop = StopLevel();
   double target = TargetLevel();
   if(m_bullish)
     {
      double tpDist = target - entryPrice;
      double slDist = entryPrice - stop;
      if(tpDist<=0.0 || slDist<=0.0)
         return false;
      outRatio = tpDist/slDist;
      return true;
     }
   double tpDist = entryPrice - target;
   double slDist = stop - entryPrice;
   if(tpDist<=0.0 || slDist<=0.0)
      return false;
   outRatio = tpDist/slDist;
   return true;
  }

//+------------------------------------------------------------------+
//| Invalidation check                                               |
//+------------------------------------------------------------------+
bool CSBSPattern::IsInvalidated(INVALIDATION_MODE mode,double closePrice,double highPrice,double lowPrice) const
  {
   if(!m_ready)
      return true;
   double guard=GuardLevel();
   if(m_bullish)
     {
      if(mode==INVALIDATE_WICK)
         return (lowPrice <= guard);
      return (closePrice <= guard);
     }
   if(mode==INVALIDATE_WICK)
      return (highPrice >= guard);
   return (closePrice >= guard);
  }

//+------------------------------------------------------------------+
//| Breakout validation                                              |
//+------------------------------------------------------------------+
bool CSBSPattern::BreakoutValidated(double closePrice,double highPrice,double lowPrice,int breakoutSwing) const
  {
   double lvl=BreakoutLevel(breakoutSwing);
   if(m_bullish)
      return (closePrice>lvl || highPrice>lvl);
   return (closePrice<lvl || lowPrice<lvl);
  }

//+------------------------------------------------------------------+
//| Fibonacci touch check                                            |
//+------------------------------------------------------------------+
bool CSBSPattern::FibTouched(double fibLevel,double highPrice,double lowPrice) const
  {
   double fib=FibEntry(fibLevel);
   if(m_bullish)
      return (lowPrice<=fib && highPrice>=fib);
   return (lowPrice<=fib && highPrice>=fib);
  }

//+------------------------------------------------------------------+
//| Liquidity reversal armed?                                        |
//+------------------------------------------------------------------+
bool CSBSPattern::IsLiquidityReversalArmed(double closePrev,double closeCurr) const
  {
   if(!HasLiquiditySweep())
      return false;
   double guard=GuardLevel();
   if(m_bullish)
      return (closePrev>guard || closeCurr>guard);
   return (closePrev<guard || closeCurr<guard);
  }

//+------------------------------------------------------------------+
//| Pivot helpers                                                    |
//+------------------------------------------------------------------+
bool IsPivotHigh(int bar,int left,int right)
  {
   if(bar-left<0 || bar+right>=g_SeriesCount)
      return false;
   double probe=g_HighSeries[bar];
   for(int k=bar-left;k<=bar+right;++k)
      if(g_HighSeries[k]>probe)
         return false;
   return true;
  }

bool IsPivotLow(int bar,int left,int right)
  {
   if(bar-left<0 || bar+right>=g_SeriesCount)
      return false;
   double probe=g_LowSeries[bar];
   for(int k=bar-left;k<=bar+right;++k)
      if(g_LowSeries[k]<probe)
         return false;
   return true;
  }

int CollectSwings(SwingPoint &buffer[],int maxOut,int lookbackBars)
  {
   int count=0;
   int start=MathMax(0,g_SeriesCount-1 - lookbackBars);
   int end  =g_SeriesCount-1 - InpPivotRight;
   int lastType=0;

   if(end<0)
      return 0;
   if(start>end)
      start=end;

   for(int i=end;i>=start && count<maxOut;--i)
     {
      if(IsPivotHigh(i,InpPivotLeft,InpPivotRight))
        {
         if(lastType!=+1)
           {
            buffer[count].index=i;
            buffer[count].price=g_HighSeries[i];
            buffer[count].type=+1;
            lastType=+1;
            count++;
           }
        }
      else if(IsPivotLow(i,InpPivotLeft,InpPivotRight))
        {
         if(lastType!=-1)
           {
            buffer[count].index=i;
            buffer[count].price=g_LowSeries[i];
            buffer[count].type=-1;
            lastType=-1;
            count++;
           }
        }
     }

   for(int a=0,b=count-1;a<b;++a,--b)
     {
      SwingPoint tmp=buffer[a];
      buffer[a]=buffer[b];
      buffer[b]=tmp;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| BOS/MSS utilities (unchanged from skeleton)                      |
//+------------------------------------------------------------------+
bool CheckBOS(const SwingPoint &swings[],int n,bool bullish)
  {
   if(n<4)
      return false;
   if(bullish)
     {
      double lastH=-DBL_MAX,prevH=-DBL_MAX;
      for(int i=n-1;i>=0;--i)
        {
         if(swings[i].type==+1)
           {
            if(lastH==-DBL_MAX)
               lastH=swings[i].price;
            else
              {
               prevH=swings[i].price;
               break;
              }
           }
        }
      if(prevH==-DBL_MAX)
         return false;
      return(lastH>prevH);
     }
   double lastL=DBL_MAX,prevL=DBL_MAX;
   for(int j=n-1;j>=0;--j)
     {
      if(swings[j].type==-1)
        {
         if(lastL==DBL_MAX)
            lastL=swings[j].price;
         else
           {
            prevL=swings[j].price;
            break;
           }
        }
     }
   if(prevL==DBL_MAX)
      return false;
   return(lastL<prevL);
  }

bool CheckMSS(const SwingPoint &swings[],int n,bool bullish)
  {
   if(n<5)
      return false;
   int s=n-5;
   if(s<0)
      s=0;
   double H1=-DBL_MAX,H2=-DBL_MAX;
   double L1=DBL_MAX,L2=DBL_MAX;
   for(int i=s;i<n;i++)
     {
      if(swings[i].type==+1)
        {
         if(H1==-DBL_MAX)
            H1=swings[i].price;
         else
            H2=swings[i].price;
        }
      if(swings[i].type==-1)
        {
         if(L1==DBL_MAX)
            L1=swings[i].price;
         else
            L2=swings[i].price;
        }
     }
   if(bullish)
     {
      if(L2!=DBL_MAX && L2<L1 && H2!=-DBL_MAX && H2>H1)
         return true;
     }
   else
     {
      if(H2!=-DBL_MAX && H2>H1 && L2!=DBL_MAX && L2<L1)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Determine validation price for quality checks                    |
//+------------------------------------------------------------------+
double DetermineValidationPrice(const CSBSPattern &pattern,double closePrev,double closeCurr,double highPrev,double lowPrev,bool &usedValidated)
  {
   usedValidated=false;
   switch(InpEntryProfile)
     {
      case ENTRY_BREAKOUT:
        {
         if(pattern.BreakoutValidated(closePrev,highPrev,lowPrev,InpBreakoutSwing))
           {
            usedValidated=true;
            return closePrev;
           }
         return pattern.BreakoutLevel(InpBreakoutSwing);
        }
      case ENTRY_GOLDEN_FIB:
        {
         double fib=pattern.FibEntry(InpFibLevel);
         if(pattern.FibTouched(InpFibLevel,highPrev,lowPrev))
            usedValidated=true;
         return fib;
        }
      case ENTRY_LIQ_REVERSAL:
        {
         if(pattern.IsLiquidityReversalArmed(closePrev,closeCurr))
            usedValidated=true;
         return closePrev;
        }
     }
   return closePrev;
  }

//+------------------------------------------------------------------+
//| Determine stop price given current configuration                 |
//+------------------------------------------------------------------+
double DetermineStop(bool isBuy,double entryPrice,const CSBSPattern &pattern,double atrValue)
  {
   if(InpSLMode==SL_SWING)
      return NormalizePrice(pattern.StopLevel());
   if(atrValue<=0.0)
      return 0.0;
   double stop=isBuy ? (entryPrice - InpATRMul*atrValue)
                     : (entryPrice + InpATRMul*atrValue);
   return NormalizePrice(stop);
  }

//+------------------------------------------------------------------+
//| Determine take profit                                            |
//+------------------------------------------------------------------+
double DetermineTakeProfit(bool isBuy,double entryPrice,double stopPrice,const CSBSPattern &pattern)
  {
   if(InpTPMode==TP_SWING3)
      return NormalizePrice(pattern.TargetLevel());

   double risk=isBuy ? (entryPrice - stopPrice) : (stopPrice - entryPrice);
   if(risk<=0.0)
      return 0.0;

   double tp=isBuy ? (entryPrice + InpRRTarget*risk)
                   : (entryPrice - InpRRTarget*risk);
   return NormalizePrice(tp);
  }

//+------------------------------------------------------------------+
//| Volume helper using CalculateLots hook                           |
//+------------------------------------------------------------------+
double PrepareLots(double stopPrice,bool isBuy,double entryPrice,ENUM_ORDER_TYPE orderType)
  {
   g_LastStopDistance = MathAbs(entryPrice - stopPrice);

   double lots=CalculateLots(stopPrice,isBuy);
   if(lots<=0.0)
      lots=InpLots;

   if(g_SymbolReady)
      lots = g_SymbolValidator.ValidateVolume(orderType,lots);

   if(lots<=0.0)
      lots=InpLots;

   return NormalizeVolume(lots);
  }

//+------------------------------------------------------------------+
//| Entry dispatch                                                   |
//+------------------------------------------------------------------+
void PlaceEntries(const CSBSPattern &pattern,double atrValue)
  {
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);

   if(InpEntryProfile==ENTRY_BREAKOUT)
     {
      double breakout=pattern.BreakoutLevel(InpBreakoutSwing);
      if(pattern.IsBullish() && InpAllowLongs)
        {
         double entry=NormalizePrice(breakout + point);
         double stop = DetermineStop(true,entry,pattern,atrValue);
         if(stop<=0.0 || entry-stop<=point)
           {
            Log("Skipped breakout buy: invalid stop configuration.");
           }
         else
           {
            double tp=DetermineTakeProfit(true,entry,stop,pattern);
            if(InpPreventDuplicateOrders && HasActiveOrder(ENTRY_BREAKOUT,true))
               Log("Skipped breakout buy: pending order already active.");
            else
              {
               double lots=PrepareLots(stop,true,entry,ORDER_TYPE_BUY_STOP);
               if(lots>0.0)
                 {
                  string comment=BuildOrderComment(ENTRY_BREAKOUT,true,pattern.GuardLevel(),InpInvalidationMode);
                  if(!Trade.BuyStop(lots,entry,_Symbol,stop,tp,0,0,comment))
                     Log(StringFormat("Failed to place breakout buy stop: %s",Trade.ResultRetcodeDescription()));
                 }
              }
           }
        }
      else if(!pattern.IsBullish() && InpAllowShorts)
        {
         double entry=NormalizePrice(breakout - point);
         double stop = DetermineStop(false,entry,pattern,atrValue);
         if(stop<=0.0 || stop-entry<=point)
           {
            Log("Skipped breakout sell: invalid stop configuration.");
           }
         else
           {
            double tp=DetermineTakeProfit(false,entry,stop,pattern);
            if(InpPreventDuplicateOrders && HasActiveOrder(ENTRY_BREAKOUT,false))
               Log("Skipped breakout sell: pending order already active.");
            else
              {
               double lots=PrepareLots(stop,false,entry,ORDER_TYPE_SELL_STOP);
               if(lots>0.0)
                 {
                  string comment=BuildOrderComment(ENTRY_BREAKOUT,false,pattern.GuardLevel(),InpInvalidationMode);
                  if(!Trade.SellStop(lots,entry,_Symbol,stop,tp,0,0,comment))
                     Log(StringFormat("Failed to place breakout sell stop: %s",Trade.ResultRetcodeDescription()));
                 }
              }
           }
        }
     }
   else if(InpEntryProfile==ENTRY_GOLDEN_FIB && InpUseGoldenFib)
     {
      double fib=pattern.FibEntry(InpFibLevel);
      if(pattern.IsBullish() && InpAllowLongs)
        {
         double entry=NormalizePrice(fib);
         double stop=DetermineStop(true,entry,pattern,atrValue);
         if(stop<=0.0 || entry-stop<=point)
            Log("Skipped golden buy: invalid stop configuration.");
         else
           {
            double tp=DetermineTakeProfit(true,entry,stop,pattern);
            if(InpPreventDuplicateOrders && HasActiveOrder(ENTRY_GOLDEN_FIB,true))
               Log("Skipped golden buy: pending order already active.");
            else
              {
               double lots=PrepareLots(stop,true,entry,ORDER_TYPE_BUY_LIMIT);
               if(lots>0.0)
                 {
                  string comment=BuildOrderComment(ENTRY_GOLDEN_FIB,true,pattern.GuardLevel(),InpInvalidationMode);
                  if(!Trade.BuyLimit(lots,entry,_Symbol,stop,tp,0,0,comment))
                     Log(StringFormat("Failed to place golden-entry buy limit: %s",Trade.ResultRetcodeDescription()));
                 }
              }
           }
        }
      else if(!pattern.IsBullish() && InpAllowShorts)
        {
         double entry=NormalizePrice(fib);
         double stop=DetermineStop(false,entry,pattern,atrValue);
         if(stop<=0.0 || stop-entry<=point)
            Log("Skipped golden sell: invalid stop configuration.");
         else
           {
            double tp=DetermineTakeProfit(false,entry,stop,pattern);
            if(InpPreventDuplicateOrders && HasActiveOrder(ENTRY_GOLDEN_FIB,false))
               Log("Skipped golden sell: pending order already active.");
            else
              {
               double lots=PrepareLots(stop,false,entry,ORDER_TYPE_SELL_LIMIT);
               if(lots>0.0)
                 {
                  string comment=BuildOrderComment(ENTRY_GOLDEN_FIB,false,pattern.GuardLevel(),InpInvalidationMode);
                  if(!Trade.SellLimit(lots,entry,_Symbol,stop,tp,0,0,comment))
                     Log(StringFormat("Failed to place golden-entry sell limit: %s",Trade.ResultRetcodeDescription()));
                 }
              }
           }
        }
     }
   else if(InpEntryProfile==ENTRY_LIQ_REVERSAL)
     {
      if(pattern.IsBullish() && InpAllowLongs)
        {
         double entryPrice=lastTick.ask;
         if(entryPrice<=0.0)
            entryPrice=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         double stop=DetermineStop(true,entryPrice,pattern,atrValue);
         if(stop<=0.0 || entryPrice-stop<=point)
            Log("Skipped liquidity-reversal buy: invalid stop configuration.");
         else
           {
            double tp=DetermineTakeProfit(true,entryPrice,stop,pattern);
            double lots=PrepareLots(stop,true,entryPrice,ORDER_TYPE_BUY);
            if(lots>0.0)
               Trade.Buy(lots,_Symbol,0.0,stop,tp,"SBS_LIQREV_BUY");
           }
        }
      else if(!pattern.IsBullish() && InpAllowShorts)
        {
         double entryPrice=lastTick.bid;
         if(entryPrice<=0.0)
            entryPrice=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         double stop=DetermineStop(false,entryPrice,pattern,atrValue);
         if(stop<=0.0 || stop-entryPrice<=point)
            Log("Skipped liquidity-reversal sell: invalid stop configuration.");
         else
           {
            double tp=DetermineTakeProfit(false,entryPrice,stop,pattern);
            double lots=PrepareLots(stop,false,entryPrice,ORDER_TYPE_SELL);
            if(lots>0.0)
               Trade.Sell(lots,_Symbol,0.0,stop,tp,"SBS_LIQREV_SELL");
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Pending order management                                         |
//+------------------------------------------------------------------+
void ManagePendingOrders(void)
  {
   int total=OrdersTotal();
   if(total<=0)
      return;

   double closeBuf[];
   ArraySetAsSeries(closeBuf,true);
   int copiedClose=CopyClose(_Symbol,_Period,0,2,closeBuf);
   if(copiedClose<=0)
      return;
   ArrayResize(closeBuf,copiedClose);
   double prevClose = (copiedClose>1 ? closeBuf[1] : closeBuf[0]);

   double lowBuf[];
   double highBuf[];
   ArraySetAsSeries(lowBuf,true);
   ArraySetAsSeries(highBuf,true);
   if(CopyLow(_Symbol,_Period,0,1,lowBuf)!=1)
      return;
   if(CopyHigh(_Symbol,_Period,0,1,highBuf)!=1)
      return;
   ArrayResize(lowBuf,1);
   ArrayResize(highBuf,1);
   double currLow   = lowBuf[0];
   double currHigh  = highBuf[0];
   datetime now     = TimeCurrent();

   for(int i=total-1;i>=0;--i)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0)
         continue;
      if(!OrderSelect(ticket))
         continue;

      if(OrderGetInteger(ORDER_MAGIC)!=InpMagic)
         continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol)
         continue;

      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(!IsPendingOrderType(type))
         continue;

      bool orderBuy=IsBuyOrderType(type);
      string comment=OrderGetString(ORDER_COMMENT);
      ENTRY_PROFILE profile;
      bool metaBuy;
      double guard;
      INVALIDATION_MODE mode=InpInvalidationMode;
      bool metaParsed=ParseOrderComment(comment,profile,metaBuy,guard,mode);

      bool cancel=false;
      string cancelReason="";

      if(InpCancelOnInvalidation && metaParsed && guard>0.0)
        {
         if(mode==INVALIDATE_WICK)
           {
            if(orderBuy && currLow<=guard)
              {
               cancel=true;
               cancelReason="guard breached by wick";
              }
            else if(!orderBuy && currHigh>=guard)
              {
               cancel=true;
               cancelReason="guard breached by wick";
              }
           }
         else
           {
            if(orderBuy && prevClose<=guard)
              {
               cancel=true;
               cancelReason="guard breached by close";
              }
            else if(!orderBuy && prevClose>=guard)
              {
               cancel=true;
               cancelReason="guard breached by close";
              }
           }
        }

      if(!cancel && InpPendingTTLMinutes>0)
        {
         datetime setup=(datetime)OrderGetInteger(ORDER_TIME_SETUP);
         if(setup>0 && (now - setup) >= (InpPendingTTLMinutes*60))
           {
            cancel=true;
            cancelReason=StringFormat("time-out %d minute(s)",InpPendingTTLMinutes);
           }
        }

      if(cancel)
         CancelOrder(ticket,cancelReason);
     }
  }

//+------------------------------------------------------------------+
//| Main evaluation pipeline                                         |
//+------------------------------------------------------------------+
void EvaluateAndTrade(void)
  {
   int requiredBars = InpLookbackBars + InpPivotLeft + InpPivotRight + 10;
   if(!g_SeriesInitialized)
     {
      if(!LoadInitialSeries(requiredBars))
         return;
      g_SeriesInitialized=true;
     }
   else
     {
      ShiftSeries(requiredBars);
      if(!AppendLatestBar(requiredBars))
        {
         if(!LoadInitialSeries(requiredBars))
            return;
        }
     }

   SwingPoint swings[200];
   if(g_SeriesCount<=0)
      return;

   int n=CollectSwings(swings,200,InpLookbackBars);
   if(n<5)
      return;

   double currClose = g_CloseSeries[0];
   double prevClose = (g_SeriesCount>1 ? g_CloseSeries[1] : currClose);

   double prevHigh = (g_SeriesCount>1 ? g_HighSeries[1] : g_HighSeries[0]);
   double prevLow  = (g_SeriesCount>1 ? g_LowSeries[1] : g_LowSeries[0]);

   CSBSPattern pattern;
   string reason;
   if(!pattern.BuildFromSwings(swings,n,InpUseStrictPattern,reason))
     {
      if(reason!="")
         Log(StringFormat("Pattern rejected: %s",reason));
      return;
     }

   bool immediateTriggered=false;
   if(InpImmediateSwing4 && InpBreakoutSwing==4)
     {
      double refHigh=MathMax(prevHigh,g_HighSeries[0]);
      double refLow =MathMin(prevLow,g_LowSeries[0]);
      if(pattern.FibTouched(InpFibLevel,refHigh,refLow))
        {
         immediateTriggered=true;
         Log("Immediate Swing-4 validation armed via fib tap.");
        }
     }

   if(InpRequireSweep && !immediateTriggered && !pattern.HasLiquiditySweep())
     {
      Log("Pattern rejected: liquidity sweep requirement not met.");
      return;
     }

   if(InpUseInvalidation && pattern.IsInvalidated(InpInvalidationMode,prevClose,prevHigh,prevLow))
     {
      Log("Pattern rejected: invalidated by price action.");
      return;
     }

   if(InpUseBOSFilter && !CheckBOS(swings,n,pattern.IsBullish()))
     {
      Log("Pattern rejected: BOS filter failed.");
      return;
     }

   if(InpUseMSSFilter && !CheckMSS(swings,n,pattern.IsBullish()))
     {
      Log("Pattern rejected: MSS filter failed.");
      return;
     }

   double valHigh=prevHigh;
   double valLow =prevLow;
   if(immediateTriggered)
     {
      valHigh=MathMax(valHigh,g_HighSeries[0]);
      valLow =MathMin(valLow,g_LowSeries[0]);
     }

   bool usedValidated=false;
   double validationPrice=DetermineValidationPrice(pattern,prevClose,currClose,valHigh,valLow,usedValidated);

   if(InpUseQualityGate)
     {
      double quality=0.0;
      if(!pattern.ComputeQuality(validationPrice,quality))
        {
         Log("Pattern rejected: unable to compute SBS ratio at validation price.");
         return;
        }
      if(quality<InpMinQualityRatio)
        {
         Log(StringFormat("Pattern rejected: quality %.3f < threshold %.3f",quality,InpMinQualityRatio));
         return;
        }
      if(usedValidated)
         Log(StringFormat("Pattern validated with quality %.3f (using bar close).",quality));
      else
         Log(StringFormat("Pattern quality computed at projected entry: %.3f.",quality));
     }

   if(InpEntryProfile==ENTRY_LIQ_REVERSAL)
     {
      if(!pattern.IsLiquidityReversalArmed(prevClose,currClose))
        {
         Log("Liquidity reversal profile: waiting for confirmation close.");
         return;
        }
     }

   double atrValue=0.0;
   if(InpSLMode==SL_ATR || (InpTPMode==TP_RR && InpSLMode==SL_ATR))
     {
      atrValue=GetATR(0);
      if(atrValue<=0.0)
        {
         Log("ATR unavailable; skipping trade dispatch.");
         return;
        }
     }

   PlaceEntries(pattern,atrValue);
  }

//+------------------------------------------------------------------+
//| Expert lifecycle                                                 |
//+------------------------------------------------------------------+
int OnInit(void)
  {
  Trade.SetExpertMagicNumber(InpMagic);
  if(!g_SymbolValidator.Init(_Symbol))
    {
     Log(StringFormat("Failed to initialise AC symbol validator for %s",_Symbol));
     return INIT_FAILED;
    }
  g_SymbolValidator.Refresh();
  g_SymbolReady=true;
  g_SeriesInitialized=false;
  g_SeriesCount=0;
  g_LastATR=0.0;
  InitDEMAATR();

  InitializeACRMSBS();
  Log("AC_SBS_Base initialised with AC risk management.");
  return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
  if(g_AtrHandle!=INVALID_HANDLE)
    {
     IndicatorRelease(g_AtrHandle);
     g_AtrHandle=INVALID_HANDLE;
    }
  g_SymbolReady=false;
  g_SeriesInitialized=false;
  g_SeriesCount=0;
  g_LastATR=0.0;
  CleanupATRTrailing();
  Log("AC_SBS_Base deinitialised.");
  }

void OnTick(void)
  {
   if(!SymbolInfoTick(_Symbol,lastTick))
      return;

   if(g_SymbolReady)
      g_SymbolValidator.Refresh();

   UpdateRiskManagementSBS(InpMagic);

   if(PositionSelect(_Symbol))
     {
      ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      string orderType = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) ? "BUY" : "SELL";
      UpdateTrailingStop(ticket, entry, orderType);
     }

   ManagePendingOrders();

   datetime barTime=iTime(_Symbol,_Period,0);
   if(barTime!=lastBarTime)
     {
      lastBarTime=barTime;
      EvaluateAndTrade();
     }
  }

//+------------------------------------------------------------------+
//| Optimization DB integration hooks                                |
//+------------------------------------------------------------------+
int OnTesterInit()
  {
   if(idTask_ <= 0 || fileName_ == "")
      return INIT_SUCCEEDED;

   return CTesterHandler::TesterInit((ulong)idTask_, fileName_);
  }

void OnTesterPass()
  {
   if(idTask_ > 0)
      CTesterHandler::TesterPass();
  }

void OnTesterDeinit()
  {
   if(idTask_ > 0)
      CTesterHandler::TesterDeinit();
  }

double OnTester()
  {
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

   if(idTask_ > 0)
      CTesterHandler::Tester(metric, "");

   return metric;
  }

//+------------------------------------------------------------------+
//| Lot calculator leveraging AC risk management modules             |
//+------------------------------------------------------------------+
double CalculateLots(double stopPrice,bool isBuy)
  {
   if(!g_SymbolReady)
      return InpLots;

   double stopDistance = g_LastStopDistance;
   if(stopDistance<=0.0)
     {
      double refPrice = isBuy ? lastTick.ask : lastTick.bid;
      if(refPrice<=0.0)
         refPrice = SymbolInfoDouble(_Symbol,isBuy ? SYMBOL_ASK : SYMBOL_BID);
      stopDistance = MathAbs(refPrice - stopPrice);
     }

   if(stopDistance<=0.0)
      return InpLots;

   double volume = CalculateLotsSBS(stopDistance);
   if(volume<=0.0)
      volume = InpLots;

   g_LastStopDistance = 0.0;
   return volume;
  }
