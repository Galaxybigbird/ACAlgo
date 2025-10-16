//+------------------------------------------------------------------+
//|                                                     AC_SBS_Base.mq5|
//|  Mechanical Swing Breakout Sequence (SBS) EA foundation.         |
//|                                                                  |
//|  This revision wraps pattern logic inside a class, exposes       |
//|  granular validation toggles, adds structured logging, and       |
//|  ensures CalculateLots() is consulted for every order so that    |
//|  the external ACRM module can plug in cleanly.                   |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

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

//--- General SBS structure controls -------------------------------------------------------------
input int      InpPivotLeft        = 2;       // pivot lookback left
input int      InpPivotRight       = 2;       // pivot lookback right
input double   InpMinHeightPct     = 0.10;    // minimum pattern height (% of price)
input int      InpMaxWidthBars     = 50;      // maximum bars contained in pattern
input double   InpMinQualityRatio  = 0.90;    // SBS ratio threshold (TP distance / SL distance)

//--- Validation toggles -------------------------------------------------------------------------
input bool              InpUseStrictPattern   = true;   // enforce strict alternating structure
input bool              InpRequireSweep       = true;   // require liquidity sweep (P4 vs P2)
input bool              InpUseQualityGate     = true;   // enforce quality ratio at validation bar
input bool              InpUseInvalidation    = true;   // invalidate if price mitigates guard level
input INVALIDATION_MODE InpInvalidationMode   = INVALIDATE_WICK; // wick or close invalidation
input bool              InpLogEvents          = true;   // enable verbose logging for tracing

//--- Market structure filters -------------------------------------------------------------------
input bool     InpUseBOSFilter     = true;    // require Break of Structure in pattern direction
input bool     InpUseMSSFilter     = false;   // require Market Structure Shift (ICT style)

//--- Entry & execution --------------------------------------------------------------------------
input ENTRY_PROFILE InpEntryProfile = ENTRY_BREAKOUT;
input int      InpBreakoutSwing     = 3;      // swing to break: 1..4
input bool     InpUseGoldenFib      = true;   // enable fib/"gold" logic
input double   InpFibLevel          = 0.618;  // fibonacci entry level (0..1)
input bool     InpImmediateSwing4   = false;  // validate on fib tap without waiting for swing-5

//--- Exits / risk placeholders ------------------------------------------------------------------
input SL_MODE  InpSLMode            = SL_ATR;
input int      InpATRPeriod         = 14;
input double   InpATRMul            = 2.0;
input TP_MODE  InpTPMode            = TP_RR;
input double   InpRRTarget          = 2.0;

//--- Runtime / misc -----------------------------------------------------------------------------
input int      InpLookbackBars      = 1500;   // scan depth in bars
input int      InpMagic             = 270915;
input double   InpLots              = 0.10;   // fallback lot size (ACRM replaces via CalculateLots)
input bool     InpAllowShorts       = true;
input bool     InpAllowLongs        = true;
input bool     InpPreventDuplicateOrders = true;  // avoid stacking identical pending orders
input bool     InpCancelOnInvalidation   = true;  // delete orders when guard breached
input int      InpPendingTTLMinutes      = 0;     // pending order time-to-live (minutes, 0=disable)

//--- Global runtime objects ---------------------------------------------------------------------
CTrade         Trade;
int            atrHandle = INVALID_HANDLE;
MqlTick        lastTick;
datetime       lastBarTime = 0;

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
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   return StringFormat("SBS|p%d|d%d|g%s|m%d",
                       (int)profile,
                       (isBuy ? 1 : 0),
                       DoubleToString(guard,digits),
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
   int count=StringSplit(comment,"|",parts);
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
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
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
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   return NormalizeDouble(value,digits);
  }

double NormalizeVolume(double lots)
  {
   double step   = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step>0.0)
      lots = MathRound(lots/step)*step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   int volDigits=(int)SymbolInfoInteger(_Symbol,SYMBOL_VOLUME_DIGITS);
   if(volDigits>0)
      lots = NormalizeDouble(lots, volDigits);
   return lots;
  }

//+------------------------------------------------------------------+
//| ATR helper                                                       |
//+------------------------------------------------------------------+
double GetATR(int shift)
  {
   static double buffer[];
   if(atrHandle==INVALID_HANDLE)
     {
      atrHandle = iATR(_Symbol,_Period,InpATRPeriod);
      if(atrHandle==INVALID_HANDLE)
         return 0.0;
     }
   if(CopyBuffer(atrHandle,0,shift,1,buffer)!=1)
      return 0.0;
   return buffer[0];
  }

//+------------------------------------------------------------------+
//| Height (% of price) utility                                      |
//+------------------------------------------------------------------+
double PercentOfPrice(double points)
  {
   double mid=(High[0]+Low[0])*0.5;
   if(mid<=0.0)
      mid=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   return(points/mid);
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

   bool              BuildFromSwings(const SwingPoint swings[],int count,bool enforceStrict,string &reason);
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
bool CSBSPattern::BuildFromSwings(const SwingPoint swings[],int count,bool enforceStrict,string &reason)
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
   if(bar-left<0 || bar+right>=Bars(_Symbol,_Period))
      return false;
   double probe=High[bar];
   for(int k=bar-left;k<=bar+right;++k)
      if(High[k]>probe)
         return false;
   return true;
  }

bool IsPivotLow(int bar,int left,int right)
  {
   if(bar-left<0 || bar+right>=Bars(_Symbol,_Period))
      return false;
   double probe=Low[bar];
   for(int k=bar-left;k<=bar+right;++k)
      if(Low[k]<probe)
         return false;
   return true;
  }

int CollectSwings(SwingPoint &buffer[],int maxOut,int lookbackBars)
  {
   int count=0;
   int start=MathMax(0,Bars(_Symbol,_Period)-1 - lookbackBars);
   int end  =Bars(_Symbol,_Period)-1 - InpPivotRight;
   int lastType=0;

   for(int i=end;i>=start && count<maxOut;--i)
     {
      if(IsPivotHigh(i,InpPivotLeft,InpPivotRight))
        {
         if(lastType!=+1)
           {
            buffer[count].index=i;
            buffer[count].price=High[i];
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
            buffer[count].price=Low[i];
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
bool CheckBOS(const SwingPoint swings[],int n,bool bullish)
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

bool CheckMSS(const SwingPoint swings[],int n,bool bullish)
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
double PrepareLots(double stopPrice,bool isBuy)
  {
   double lots=CalculateLots(stopPrice,isBuy);
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
               double lots=PrepareLots(stop,true);
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
               double lots=PrepareLots(stop,false);
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
               double lots=PrepareLots(stop,true);
               if(lots>0.0)
                 {
                  string comment=BuildOrderComment(ENTRY_GOLDEN_FIB,true,pattern.GuardLevel(),InpInvalidationMode);
                  if(!Trade.BuyLimit(lots,entry,_Symbol,stop,tp,0,comment))
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
               double lots=PrepareLots(stop,false);
               if(lots>0.0)
                 {
                  string comment=BuildOrderComment(ENTRY_GOLDEN_FIB,false,pattern.GuardLevel(),InpInvalidationMode);
                  if(!Trade.SellLimit(lots,entry,_Symbol,stop,tp,0,comment))
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
         double entryPrice=(lastTick.ask>0.0 ? lastTick.ask : Ask);
         double stop=DetermineStop(true,entryPrice,pattern,atrValue);
         if(stop<=0.0 || entryPrice-stop<=point)
            Log("Skipped liquidity-reversal buy: invalid stop configuration.");
         else
           {
            double tp=DetermineTakeProfit(true,entryPrice,stop,pattern);
            double lots=PrepareLots(stop,true);
            if(lots>0.0)
               Trade.Buy(lots,_Symbol,0.0,stop,tp,0,"SBS_LIQREV_BUY");
           }
        }
      else if(!pattern.IsBullish() && InpAllowShorts)
        {
         double entryPrice=(lastTick.bid>0.0 ? lastTick.bid : Bid);
         double stop=DetermineStop(false,entryPrice,pattern,atrValue);
         if(stop<=0.0 || stop-entryPrice<=point)
            Log("Skipped liquidity-reversal sell: invalid stop configuration.");
         else
           {
            double tp=DetermineTakeProfit(false,entryPrice,stop,pattern);
            double lots=PrepareLots(stop,false);
            if(lots>0.0)
               Trade.Sell(lots,_Symbol,0.0,stop,tp,0,"SBS_LIQREV_SELL");
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

   double prevClose = (Bars(_Symbol,_Period)>1 ? Close[1] : Close[0]);
   double currLow   = Low[0];
   double currHigh  = High[0];
   datetime now     = TimeCurrent();

   for(int i=total-1;i>=0;--i)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;

      if(OrderGetInteger(ORDER_MAGIC)!=InpMagic)
         continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol)
         continue;

      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(!IsPendingOrderType(type))
         continue;

      ulong ticket=(ulong)OrderGetInteger(ORDER_TICKET);
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
   const int MAX_SW=200;
   SwingPoint swings[MAX_SW];
   int n=CollectSwings(swings,MAX_SW,InpLookbackBars);
   if(n<5)
      return;

   int barsAvailable=Bars(_Symbol,_Period);
   double prevClose=(barsAvailable>1 ? Close[1] : Close[0]);
   double currClose=Close[0];
   double prevHigh =(barsAvailable>1 ? High[1]  : High[0]);
   double prevLow  =(barsAvailable>1 ? Low[1]   : Low[0]);

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
      double refHigh=MathMax(prevHigh,High[0]);
      double refLow =MathMin(prevLow,Low[0]);
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
      valHigh=MathMax(valHigh,High[0]);
      valLow =MathMin(valLow,Low[0]);
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
   Log("AC_SBS_Base initialised.");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(atrHandle!=INVALID_HANDLE)
     {
      IndicatorRelease(atrHandle);
      atrHandle=INVALID_HANDLE;
     }
   Log("AC_SBS_Base deinitialised.");
  }

void OnTick(void)
  {
   if(!SymbolInfoTick(_Symbol,lastTick))
      return;

   ManagePendingOrders();

   datetime barTime=iTime(_Symbol,_Period,0);
   if(barTime!=lastBarTime)
     {
      lastBarTime=barTime;
      EvaluateAndTrade();
     }
  }

//+------------------------------------------------------------------+
//| Placeholder lot calculator hook (ACRM integrates here)           |
//+------------------------------------------------------------------+
double CalculateLots(double stopPrice,bool isBuy)
  {
   // TODO: replace with Asymmetrical Compound Risk sizing.
   return InpLots;
  }
