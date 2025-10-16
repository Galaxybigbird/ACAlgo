#ifndef __AC_OPTCRITERION_MQH
#define __AC_OPTCRITERION_MQH
#property strict

// === ACOPT frame payload index map (keep in sync with AC_PublishFrames & CSV) ===
enum ACOPT_IDX
{
   ACOPT_SCORE = 0,

   ACOPT_PF_IS,
   ACOPT_PF_OOS,
   ACOPT_DD_IS_PCT,
   ACOPT_DD_OOS_PCT,
   ACOPT_SHARPE_IS,
   ACOPT_SHARPE_OOS,
   ACOPT_SORTINO_IS,
   ACOPT_SORTINO_OOS,
   ACOPT_SERENITY_IS,
   ACOPT_SERENITY_OOS,

   ACOPT_MC_PF_P5,
   ACOPT_MC_DD_P95,
   ACOPT_MC_P_RUIN,

   ACOPT_KS_DIST,
   ACOPT_JB_P,

   ACOPT_TRADES_TOTAL,
   ACOPT_TRADES_PER_DAY,

   ACOPT_WINRATE_OOS_PCT,
   ACOPT_EXP_PAYOFF_OOS,
   ACOPT_AVG_WIN_OOS,
   ACOPT_AVG_LOSS_OOS,
   ACOPT_PAYOFF_RATIO_OOS,

   ACOPT__COUNT
};

struct ACOptConfig
{
   int    MinTrades;
   double MinOosPF;
   double MaxOosDDPercent;
   double InSampleFrac;
   int    OosGapDays;
   int    McSimulations;
   int    McBlockLenTrades;
   int    McSeed;
   double w_pf;
   double w_dd;
   double w_sharpe;
   double w_mc_pf;
   double w_mc_dd;
   long   MagicFilter;
};

// internal state shared between calls
static ACOptConfig g_acCfg;
static bool        g_acInitialized      = false;
static double      g_acDeposit          = 0.0;
static double      g_acScore            = -DBL_MAX;
static double      g_acPfIS             = 0.0;
static double      g_acPfOOS            = 0.0;
static double      g_acDdIS             = 0.0;
static double      g_acDdOOS            = 0.0;
static double      g_acSharpeIS         = 0.0;
static double      g_acSharpeOOS        = 0.0;
static double      g_acSerenityIS       = 0.0;
static double      g_acSerenityOOS      = 0.0;
static double      g_acSortinoIS        = 0.0;
static double      g_acSortinoOOS       = 0.0;
static double      g_acSkewIS           = 0.0;
static double      g_acSkewOOS          = 0.0;
static double      g_acKurtIS           = 0.0;
static double      g_acKurtOOS          = 0.0;
static double      g_acDdFracIS         = 0.0;
static double      g_acDdFracOOS        = 0.0;
static double      g_acPfP5             = 0.0;
static double      g_acDd95             = 0.0;
static double      g_acPRuin            = 0.0;
static double      g_acKsP              = 1.0;
static double      g_acKsDist           = 0.0;
static double      g_acJbP              = 1.0;
static double      g_acWinRateOOS       = 0.0;
static double      g_acExpPayoffOOS     = 0.0;
static double      g_acWinsorFlag       = 0.0;
static double      g_acTradesPerDay     = 0.0;
static double      g_acAvgWinOOS        = 0.0;
static double      g_acAvgLossOOS       = 0.0;
static double      g_acPayoffRatioOOS   = 0.0;
static int         g_acTradeCount       = 0;
static long        g_acFrameCounter     = 0;
static long        g_acCurrentFrameId   = 0;

// buffers reused per run
static double      g_acAllReturns[];
static datetime    g_acAllTimes[];
static double      g_acReturnsIS[];
static double      g_acReturnsOOS[];
static double      g_acAllReturnsNorm[];
static double      g_acReturnsISNorm[];
static double      g_acReturnsOOSNorm[];
static datetime    g_acTimesIS[];
static datetime    g_acTimesOOS[];

struct ACStats
{
   double pf;
   double ddPercent;
   double ddFraction;
   double sharpe;
   double sortino;
   double serenity;
   double skew;
   double kurt;
   double winRate;
   double expectedPayoff;
   double avgWin;
   double avgLossAbs;
   double payoffRatio;
   double jbP;
   bool   winsorized;
   double tradesPerDay;
};
double AC_Tanh(const double x)
{
   double e2 = MathExp(2.0 * x);
   return (e2 - 1.0) / (e2 + 1.0);
}


bool AC_Opt_Init(const ACOptConfig &cfg)
{
   g_acCfg = cfg;
   if(g_acCfg.MinTrades <= 0)          g_acCfg.MinTrades = 50;
   if(g_acCfg.MinOosPF <= 0.0)        g_acCfg.MinOosPF = 1.20;
   if(g_acCfg.MaxOosDDPercent <= 0.0) g_acCfg.MaxOosDDPercent = 30.0;
   if(g_acCfg.InSampleFrac <= 0.0 || g_acCfg.InSampleFrac >= 1.0)
      g_acCfg.InSampleFrac = 0.70;
   if(g_acCfg.OosGapDays < 0)         g_acCfg.OosGapDays = 1;
   if(g_acCfg.McSimulations <= 0)     g_acCfg.McSimulations = 500;
   if(g_acCfg.McBlockLenTrades <= 0)  g_acCfg.McBlockLenTrades = 5;
   if(g_acCfg.McSeed == 0)            g_acCfg.McSeed = 1337;
   if(g_acCfg.w_pf <= 0.0)            g_acCfg.w_pf = 1.0;
   if(g_acCfg.w_dd <= 0.0)            g_acCfg.w_dd = 2.0;
   if(g_acCfg.w_sharpe <= 0.0)        g_acCfg.w_sharpe = 1.0;
   if(g_acCfg.w_mc_pf <= 0.0)         g_acCfg.w_mc_pf = 1.0;
   if(g_acCfg.w_mc_dd <= 0.0)         g_acCfg.w_mc_dd = 2.0;
   if(g_acCfg.MagicFilter < 0)        g_acCfg.MagicFilter = 0;
   g_acInitialized = true;
   g_acFrameCounter = 0;
   g_acCurrentFrameId = 0;
   g_acDeposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
   if(g_acDeposit <= 0.0)
      g_acDeposit = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_acDeposit <= 0.0)
      g_acDeposit = 100000.0;
   MathSrand((uint)g_acCfg.McSeed);
   AC_ResetState();
   return true;
}

double AC_CalcCustomCriterion()
{
   if(!g_acInitialized)
      return TesterStatistics(STAT_PROFIT);

   g_acCurrentFrameId = ++g_acFrameCounter;
   AC_ResetState();

   if(!AC_CollectTrades(g_acAllReturns, g_acAllTimes, g_acReturnsIS, g_acReturnsOOS))
      return g_acScore;

   g_acTradeCount = ArraySize(g_acAllReturns);
   if(g_acTradeCount < g_acCfg.MinTrades)
      return g_acScore;

   if(ArraySize(g_acReturnsOOS) == 0)
      return g_acScore;

   AC_NormalizeReturns(g_acAllReturns, g_acAllReturnsNorm, g_acDeposit);
   AC_NormalizeReturns(g_acReturnsIS, g_acReturnsISNorm, g_acDeposit);
   AC_NormalizeReturns(g_acReturnsOOS, g_acReturnsOOSNorm, g_acDeposit);

   ACStats statsIS;
   ACStats statsOOS;
   AC_ComputeStats(g_acReturnsIS, g_acTimesIS, statsIS);
   AC_ComputeStats(g_acReturnsOOS, g_acTimesOOS, statsOOS);
   g_acTradesPerDay = AC_TradesPerDay(g_acAllTimes);

   g_acPfIS        = statsIS.pf;
   g_acPfOOS       = statsOOS.pf;
   g_acDdIS        = statsIS.ddPercent;
   g_acDdOOS       = statsOOS.ddPercent;
   g_acDdFracIS    = statsIS.ddFraction;
   g_acDdFracOOS   = statsOOS.ddFraction;
   g_acSharpeIS    = statsIS.sharpe;
   g_acSharpeOOS   = statsOOS.sharpe;
   g_acSortinoIS   = statsIS.sortino;
   g_acSortinoOOS  = statsOOS.sortino;
   g_acSerenityIS  = statsIS.serenity;
   g_acSerenityOOS = statsOOS.serenity;
   g_acSkewIS      = statsIS.skew;
   g_acSkewOOS     = statsOOS.skew;
   g_acKurtIS      = statsIS.kurt;
   g_acKurtOOS     = statsOOS.kurt;
   g_acWinRateOOS  = statsOOS.winRate;
   g_acExpPayoffOOS= statsOOS.expectedPayoff;
   g_acAvgWinOOS   = statsOOS.avgWin;
   g_acAvgLossOOS  = statsOOS.avgLossAbs;
   g_acPayoffRatioOOS = statsOOS.payoffRatio;
   g_acWinsorFlag  = (statsIS.winsorized || statsOOS.winsorized) ? 1.0 : 0.0;

   g_acJbP = MathMin(statsIS.jbP, statsOOS.jbP);

   AC_KS_Test(g_acReturnsISNorm, g_acReturnsOOSNorm, g_acKsDist, g_acKsP);

   AC_MonteCarloBootstrap(g_acAllReturns, g_acCfg.McSimulations, g_acCfg.McBlockLenTrades, (uint)g_acCfg.McSeed, g_acPfP5, g_acDd95, g_acPRuin);

   g_acScore = AC_CompositeScore(g_acCfg,
                                 g_acPfIS, g_acPfOOS,
                                 g_acDdIS, g_acDdOOS, g_acDdFracOOS,
                                 g_acSharpeIS, g_acSharpeOOS,
                                 g_acSortinoIS, g_acSortinoOOS,
                                 g_acSerenityIS, g_acSerenityOOS,
                                 g_acPfP5, g_acDd95,
                                 g_acKsP, g_acKsDist, g_acJbP,
                                 g_acWinRateOOS, g_acExpPayoffOOS,
                                 g_acPRuin,
                                 g_acTradeCount);

   return g_acScore;
}

void AC_PublishFrames()
{
   if(!g_acInitialized)
      return;

   if(!MQLInfoInteger(MQL_OPTIMIZATION))
      return;

   AC_PushFrames();
}

// -------------------------------------------------------------
// internal helpers

void AC_ResetState()
{
   g_acScore      = -DBL_MAX;
   g_acPfIS       = 0.0;
   g_acPfOOS      = 0.0;
   g_acDdIS       = 0.0;
   g_acDdOOS      = 0.0;
   g_acSharpeIS   = 0.0;
   g_acSharpeOOS  = 0.0;
   g_acSerenityIS = 0.0;
   g_acSerenityOOS= 0.0;
   g_acSortinoIS  = 0.0;
   g_acSortinoOOS = 0.0;
   g_acSkewIS     = 0.0;
   g_acSkewOOS    = 0.0;
   g_acKurtIS     = 0.0;
   g_acKurtOOS    = 0.0;
   g_acDdFracIS   = 0.0;
   g_acDdFracOOS  = 0.0;
   g_acPfP5       = 0.0;
   g_acDd95       = 0.0;
   g_acPRuin      = 0.0;
   g_acKsP        = 1.0;
   g_acKsDist     = 0.0;
   g_acJbP        = 1.0;
   g_acWinRateOOS = 0.0;
   g_acExpPayoffOOS = 0.0;
   g_acAvgWinOOS  = 0.0;
   g_acAvgLossOOS = 0.0;
   g_acPayoffRatioOOS = 0.0;
   g_acWinsorFlag = 0.0;
   g_acTradesPerDay = 0.0;
   g_acTradeCount = 0;

   ArrayResize(g_acAllReturns, 0);
   ArrayResize(g_acAllTimes, 0);
   ArrayResize(g_acReturnsIS, 0);
   ArrayResize(g_acReturnsOOS, 0);
   ArrayResize(g_acAllReturnsNorm, 0);
   ArrayResize(g_acReturnsISNorm, 0);
   ArrayResize(g_acReturnsOOSNorm, 0);
   ArrayResize(g_acTimesIS, 0);
   ArrayResize(g_acTimesOOS, 0);
}

int AC_FindPositionIndex(const ulong &ids[], ulong id)
{
   int total = ArraySize(ids);
   for(int i = 0; i < total; ++i)
   {
      if(ids[i] == id)
         return i;
   }
   return -1;
}

bool AC_CollectTrades(double &r[], datetime &t[], double &r_is[], double &r_oos[])
{
   ArrayResize(r, 0);
   ArrayResize(t, 0);
   ArrayResize(r_is, 0);
   ArrayResize(r_oos, 0);

   if(!HistorySelect(0, TimeCurrent()))
      return false;

   int totalDeals = (int)HistoryDealsTotal();
   if(totalDeals <= 0)
      return false;

   ulong   positionIds[];
   double  netResults[];
   datetime closeTimes[];

   ArrayResize(positionIds, 0);
   ArrayResize(netResults, 0);
   ArrayResize(closeTimes, 0);

   for(int i = 0; i < totalDeals; ++i)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      string dealSymbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      if(dealSymbol != _Symbol)
         continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT)
         continue;

      long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
         continue;

      if(g_acCfg.MagicFilter > 0)
      {
         long dealMagic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         if(dealMagic != g_acCfg.MagicFilter)
            continue;
      }

      ulong positionId = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      if(positionId == 0)
         positionId = ticket;

      datetime closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      double profit     = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double swap       = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double totalPL    = profit + commission + swap;

      int idx = AC_FindPositionIndex(positionIds, positionId);
      if(idx < 0)
      {
         idx = ArraySize(positionIds);
         ArrayResize(positionIds, idx + 1);
         ArrayResize(netResults, idx + 1);
         ArrayResize(closeTimes, idx + 1);
         positionIds[idx] = positionId;
         netResults[idx] = 0.0;
         closeTimes[idx] = closeTime;
      }

      netResults[idx] += totalPL;
      if(closeTime > closeTimes[idx])
         closeTimes[idx] = closeTime;
   }

   int trades = ArraySize(positionIds);
   if(trades <= 0)
      return false;

   ArrayResize(r, trades);
   ArrayResize(t, trades);
   for(int i = 0; i < trades; ++i)
   {
      r[i] = netResults[i];
      t[i] = closeTimes[i];
   }

   AC_SortTrades(t, r);
   AC_SplitIS_OOS(r, t, r_is, r_oos, g_acTimesIS, g_acTimesOOS);

   return (ArraySize(r) > 0);
}

void AC_SortTrades(datetime &t[], double &r[])
{
   int n = ArraySize(t);
   if(n <= 1)
      return;

   int idx[];
   ArrayResize(idx, n);
   for(int i = 0; i < n; ++i)
      idx[i] = i;

   AC_QuickSortIdxByTime(idx, t, 0, n - 1);

   datetime sortedTimes[];
   double   sortedReturns[];
   ArrayResize(sortedTimes, n);
   ArrayResize(sortedReturns, n);
   for(int i = 0; i < n; ++i)
   {
      int order = idx[i];
      sortedTimes[i]   = t[order];
      sortedReturns[i] = r[order];
   }

   ArrayCopy(t, sortedTimes);
   ArrayCopy(r, sortedReturns);
}

void AC_QuickSortIdxByTime(int &idx[], const datetime &t[], int lo, int hi)
{
   int i = lo;
   int j = hi;
   datetime pivot = t[idx[(lo + hi) >> 1]];

   while(i <= j)
   {
      while(t[idx[i]] < pivot)
         ++i;
      while(t[idx[j]] > pivot)
         --j;
      if(i <= j)
      {
         int tmp = idx[i];
         idx[i] = idx[j];
         idx[j] = tmp;
         ++i;
         --j;
      }
   }
   if(lo < j)
      AC_QuickSortIdxByTime(idx, t, lo, j);
   if(i < hi)
      AC_QuickSortIdxByTime(idx, t, i, hi);
}

void AC_SplitIS_OOS(const double &r[], const datetime &t[], double &r_is[], double &r_oos[], datetime &t_is[], datetime &t_oos[])
{
   ArrayResize(r_is, 0);
   ArrayResize(r_oos, 0);
   ArrayResize(t_is, 0);
   ArrayResize(t_oos, 0);

   int n = ArraySize(r);
   if(n == 0)
      return;

   datetime firstTime = t[0];
   datetime lastTime  = t[n - 1];
   long span = (long)(lastTime - firstTime);

   if(span <= 0)
   {
      int splitIndex = (int)MathRound(n * g_acCfg.InSampleFrac);
      if(splitIndex <= 0)
         splitIndex = n / 2;
      if(splitIndex >= n)
         splitIndex = n - 1;
      ArrayResize(r_is, splitIndex);
      ArrayResize(t_is, splitIndex);
      ArrayResize(r_oos, n - splitIndex);
      ArrayResize(t_oos, n - splitIndex);
      for(int i = 0; i < n; ++i)
      {
         if(i < splitIndex)
         {
            r_is[i] = r[i];
            t_is[i] = t[i];
         }
         else
         {
            int oIdx = i - splitIndex;
            r_oos[oIdx] = r[i];
            t_oos[oIdx] = t[i];
         }
      }
      return;
   }

   long gapSeconds = (long)MathRound((double)g_acCfg.OosGapDays * 86400.0);
   long isSpan     = (long)MathRound((double)span * g_acCfg.InSampleFrac);
   datetime isEnd  = firstTime + (datetime)isSpan;
   datetime oosStart = isEnd + (datetime)gapSeconds;
   if(oosStart > lastTime)
      oosStart = isEnd;

   int isCount = 0;
   int oosCount = 0;
   for(int i = 0; i < n; ++i)
   {
      if(t[i] <= isEnd)
         ++isCount;
      else if(t[i] >= oosStart)
         ++oosCount;
   }

   if(isCount == 0 || oosCount == 0)
   {
      int splitIndex = (int)MathRound(n * g_acCfg.InSampleFrac);
      if(splitIndex <= 0)
         splitIndex = n / 2;
      if(splitIndex >= n)
         splitIndex = n - 1;
      ArrayResize(r_is, splitIndex);
      ArrayResize(t_is, splitIndex);
      ArrayResize(r_oos, n - splitIndex);
      ArrayResize(t_oos, n - splitIndex);
      for(int i = 0; i < n; ++i)
      {
         if(i < splitIndex)
         {
            r_is[i] = r[i];
            t_is[i] = t[i];
         }
         else
         {
            int oIdx = i - splitIndex;
            r_oos[oIdx] = r[i];
            t_oos[oIdx] = t[i];
         }
      }
      return;
   }

   ArrayResize(r_is, isCount);
   ArrayResize(t_is, isCount);
   ArrayResize(r_oos, oosCount);
   ArrayResize(t_oos, oosCount);

   int isIdx = 0;
   int oosIdx = 0;
   for(int i = 0; i < n; ++i)
   {
      if(t[i] <= isEnd)
      {
         r_is[isIdx] = r[i];
         t_is[isIdx] = t[i];
         ++isIdx;
      }
      else if(t[i] >= oosStart)
      {
         r_oos[oosIdx] = r[i];
         t_oos[oosIdx] = t[i];
         ++oosIdx;
      }
   }
}

double AC_TradesPerDay(const datetime &t[])
{
   int n = ArraySize(t);
   if(n == 0)
      return 0.0;
   if(n == 1)
      return 1.0;

   datetime first_t = t[0];
   datetime last_t  = t[n - 1];
   double days = MathMax(1.0, (double)(last_t - first_t) / 86400.0);
   return (double)n / days;
}

void AC_NormalizeReturns(const double &src[], double &dst[], double scale)
{
   ArrayResize(dst, 0);
   int n = ArraySize(src);
   if(n == 0 || MathAbs(scale) < DBL_EPSILON)
      return;
   ArrayResize(dst, n);
   double inv = 1.0 / scale;
   for(int i = 0; i < n; ++i)
      dst[i] = src[i] * inv;
}

void AC_ComputeStats(const double &r_currency[], const datetime &t[], ACStats &stats)
{
   stats.pf = 0.0;
   stats.ddPercent = 0.0;
   stats.ddFraction = 0.0;
   stats.sharpe = 0.0;
   stats.sortino = 0.0;
   stats.serenity = 0.0;
   stats.skew = 0.0;
   stats.kurt = 0.0;
   stats.winRate = 0.0;
   stats.expectedPayoff = 0.0;
   stats.avgWin = 0.0;
   stats.avgLossAbs = 0.0;
   stats.payoffRatio = 0.0;
   stats.jbP = 1.0;
   stats.winsorized = false;
   stats.tradesPerDay = 0.0;

   int n = ArraySize(r_currency);
   if(n == 0)
      return;

   double grossProfit = 0.0;
   double grossLoss   = 0.0;
   double equity      = g_acDeposit;
   double peak        = g_acDeposit;
   double maxDdAbs    = 0.0;

   double sumWin = 0.0;
   double sumLossAbs = 0.0;
   int    countWin = 0;
   int    countLoss = 0;
   double sumAll = 0.0;

   for(int i = 0; i < n; ++i)
   {
      double ri = r_currency[i];
      sumAll += ri;
      if(ri > 0.0)
      {
         grossProfit += ri;
         sumWin += ri;
         ++countWin;
      }
      else if(ri < 0.0)
      {
         grossLoss += -ri;
         sumLossAbs += -ri;
         ++countLoss;
      }

      equity += ri;
      if(equity > peak)
         peak = equity;
      double ddAbs = peak - equity;
      if(ddAbs > maxDdAbs)
         maxDdAbs = ddAbs;
   }

   stats.expectedPayoff = (n > 0) ? sumAll / (double)n : 0.0;
   stats.winRate        = (n > 0) ? (double)countWin / (double)n : 0.0;
   stats.avgWin         = (countWin > 0) ? sumWin / (double)countWin : 0.0;
   stats.avgLossAbs     = (countLoss > 0) ? sumLossAbs / (double)countLoss : 0.0;
   stats.payoffRatio    = (stats.avgLossAbs > 0.0) ? stats.avgWin / stats.avgLossAbs : 0.0;

   if(grossLoss > 0.0)
      stats.pf = grossProfit / grossLoss;
   else
      stats.pf = (grossProfit > 0.0 ? 100.0 : 0.0);

   double denom = (peak > 0.0) ? peak : g_acDeposit;
   stats.ddPercent  = (denom > 0.0) ? (maxDdAbs / denom) * 100.0 : 0.0;
   stats.ddFraction = (denom > 0.0) ? (maxDdAbs / denom) : 0.0;

   double rn[];
   AC_NormalizeReturns(r_currency, rn, g_acDeposit);

   stats.sharpe  = AC_CalculateSharpe(rn);
   stats.sortino = AC_CalculateSortino(rn);
   stats.serenity = AC_CalculateSerenity(rn, stats.ddFraction);

   double rnWins[];
   ArrayCopy(rnWins, rn);
   if(ArraySize(rnWins) > 2)
      stats.winsorized = AC_Winsorize(rnWins, 1.0, 99.0);

   if(stats.winsorized)
   {
      stats.skew = AC_Skewness(rnWins);
      stats.kurt = AC_Kurtosis(rnWins);
   }
   else
   {
      stats.skew = AC_Skewness(rn);
      stats.kurt = AC_Kurtosis(rn);
   }
   stats.jbP  = AC_JarqueBeraPValue(rn);

   stats.tradesPerDay = AC_TradesPerDay(t);
}

bool AC_KS_Test(const double &r_is_norm[], const double &r_oos_norm[], double &ks_dist, double &ks_p)
{
   ks_dist = 0.0;
   ks_p    = 1.0;

   int n_is = ArraySize(r_is_norm);
   int n_oos= ArraySize(r_oos_norm);
   if(n_is < 2 || n_oos < 2)
      return false;

   double tmp_is[];
   double tmp_oos[];
   ArrayCopy(tmp_is, r_is_norm);
   ArrayCopy(tmp_oos, r_oos_norm);

   ks_dist = AC_KolmogorovStatistic(tmp_is, tmp_oos);
   ks_p    = AC_KolmogorovPValue(ks_dist, n_is, n_oos);
   return true;
}

void AC_MonteCarloBootstrap(const double &r[], int sims, int block, uint seed, double &pf_p5, double &dd_p95, double &p_ruin)
{
   pf_p5 = 0.0;
   dd_p95 = 0.0;
   p_ruin = 0.0;

   int n = ArraySize(r);
   if(n == 0 || sims <= 0)
      return;

   if(block <= 0)
      block = 1;

   MathSrand(seed);

   double pfSamples[];
   double ddSamples[];
   ArrayResize(pfSamples, sims);
   ArrayResize(ddSamples, sims);

   int ruinCount = 0;

   for(int s = 0; s < sims; ++s)
   {
      double grossProfit = 0.0;
      double grossLoss   = 0.0;
      double balance     = g_acDeposit;
      double peak        = balance;
      double maxDdAbs    = 0.0;

      int generated = 0;
      while(generated < n)
      {
         int start = MathRand() % n;
         for(int b = 0; b < block && generated < n; ++b)
         {
            double ret = r[(start + b) % n];
            if(ret >= 0.0)
               grossProfit += ret;
            else
               grossLoss += -ret;

            balance += ret;
            if(balance > peak)
               peak = balance;
            double ddAbs = peak - balance;
            if(ddAbs > maxDdAbs)
               maxDdAbs = ddAbs;

            ++generated;
         }
      }

      double pf = (grossLoss > 0.0) ? grossProfit / grossLoss : (grossProfit > 0.0 ? 100.0 : 0.0);
      double denom = (peak > 0.0) ? peak : g_acDeposit;
      double ddPercent = (denom > 0.0) ? (maxDdAbs / denom) * 100.0 : 0.0;

      pfSamples[s] = pf;
      ddSamples[s] = ddPercent;

      if(ddPercent > g_acCfg.MaxOosDDPercent)
         ++ruinCount;
   }

   pf_p5 = AC_Percentile(pfSamples, 5.0);
   dd_p95 = AC_Percentile(ddSamples, 95.0);
   p_ruin = (double)ruinCount / (double)sims;
}

double AC_CompositeScore(const ACOptConfig &cfg,
                                double pf_is, double pf_oos,
                                double dd_is, double dd_oos, double dd_frac_oos,
                                double sharpe_is, double sharpe_oos,
                                double sortino_is, double sortino_oos,
                                double serenity_is, double serenity_oos,
                                double pf_p5, double dd95,
                                double ks_p, double ks_dist, double jb_p,
                                double winrate_oos, double exp_payoff_oos,
                                double p_ruin,
                                int trades)
{
   if(trades < cfg.MinTrades)
      return -DBL_MAX;
   if(pf_oos < cfg.MinOosPF)
      return -DBL_MAX;
   if(dd_oos > cfg.MaxOosDDPercent)
      return -DBL_MAX;
   if(pf_p5 < cfg.MinOosPF)
      return -DBL_MAX;
   if(dd95 > cfg.MaxOosDDPercent)
      return -DBL_MAX;
   if(p_ruin >= 0.5)
      return -DBL_MAX;

   double pfTerm        = cfg.w_pf    * MathLog(1.0 + MathMax(pf_oos - 1.0, 0.0));
   double sharpeTerm    = 0.5 * cfg.w_sharpe * AC_Tanh(sharpe_oos);
   double sortinoTerm   = cfg.w_sharpe * AC_Tanh(sortino_oos);
   double serenityWeight= MathMin(1.5, cfg.w_sharpe * 0.75);
   double serenityTerm  = serenityWeight * AC_Tanh(serenity_oos);
   double mcPfTerm      = cfg.w_mc_pf * MathLog(1.0 + MathMax(pf_p5, 0.0));
   double ddPenalty     = -cfg.w_dd   * AC_Tanh(dd_oos / MathMax(1.0, cfg.MaxOosDDPercent));
   double mcDdPenalty   = -cfg.w_mc_dd * AC_Tanh(dd95 / MathMax(1.0, cfg.MaxOosDDPercent));

   double pfConsistency = (pf_is > 0.0) ? AC_Tanh(MathMax(0.0, pf_oos / pf_is) - 1.0) : 0.0;
   double sortinoConsistency = (sortino_is > 0.0) ? AC_Tanh(MathMax(0.0, sortino_oos / sortino_is) - 1.0) : 0.0;
   double stabilityBonus = 0.25 * (pfConsistency + sortinoConsistency);

   double ddFractionPenalty = (dd_frac_oos > 0.0) ? -0.2 * AC_Tanh(dd_frac_oos * 5.0) : 0.0;

   double winBonus     = 0.2 * AC_Tanh(MathMax(0.0, winrate_oos - 0.5));
   double payoffBonus  = 0.1 * AC_Tanh(MathLog(1.0 + MathMax(exp_payoff_oos, 0.0)));

   double statsBonus   = 0.1 * AC_Tanh(MathMax(0.0, ks_p - 0.05)) +
                         0.1 * AC_Tanh(1.0 - MathMin(1.0, ks_dist)) +
                         0.1 * AC_Tanh(MathMax(0.0, jb_p - 0.05));

   double score = pfTerm + sharpeTerm + sortinoTerm + serenityTerm +
                  mcPfTerm + ddPenalty + mcDdPenalty +
                  stabilityBonus + ddFractionPenalty +
                  winBonus + payoffBonus + statsBonus;

   score *= (1.0 - MathMin(p_ruin, 0.99));
   return score;
}

void AC_PushFrames()
{
   /*
      Payload order (see ACOPT_IDX):
      score,
      pf_is, pf_oos,
      dd_is_pct, dd_oos_pct,
      sharpe_is, sharpe_oos,
      sortino_is, sortino_oos,
      serenity_is, serenity_oos,
      mc_pf_p5, mc_dd_p95, mc_p_ruin,
      ks_dist, jb_p,
      trades_total, trades_per_day,
      winrate_oos_pct, expected_payoff_oos,
      avg_win_oos, avg_loss_oos, payoff_ratio_oos.
   */
   double payload[];
   ArrayResize(payload, ACOPT__COUNT);
   payload[ACOPT_SCORE]              = g_acScore;
   payload[ACOPT_PF_IS]              = g_acPfIS;
   payload[ACOPT_PF_OOS]             = g_acPfOOS;
   payload[ACOPT_DD_IS_PCT]          = g_acDdIS;
   payload[ACOPT_DD_OOS_PCT]         = g_acDdOOS;
   payload[ACOPT_SHARPE_IS]          = g_acSharpeIS;
   payload[ACOPT_SHARPE_OOS]         = g_acSharpeOOS;
   payload[ACOPT_SORTINO_IS]         = g_acSortinoIS;
   payload[ACOPT_SORTINO_OOS]        = g_acSortinoOOS;
   payload[ACOPT_SERENITY_IS]        = g_acSerenityIS;
   payload[ACOPT_SERENITY_OOS]       = g_acSerenityOOS;
   payload[ACOPT_MC_PF_P5]           = g_acPfP5;
   payload[ACOPT_MC_DD_P95]          = g_acDd95;
   payload[ACOPT_MC_P_RUIN]          = g_acPRuin;
   payload[ACOPT_KS_DIST]            = g_acKsDist;
   payload[ACOPT_JB_P]               = g_acJbP;
   payload[ACOPT_TRADES_TOTAL]       = (double)g_acTradeCount;
   payload[ACOPT_TRADES_PER_DAY]     = g_acTradesPerDay;
   payload[ACOPT_WINRATE_OOS_PCT]    = g_acWinRateOOS * 100.0;
   payload[ACOPT_EXP_PAYOFF_OOS]     = g_acExpPayoffOOS;
   payload[ACOPT_AVG_WIN_OOS]        = g_acAvgWinOOS;
   payload[ACOPT_AVG_LOSS_OOS]       = g_acAvgLossOOS;
   payload[ACOPT_PAYOFF_RATIO_OOS]   = g_acPayoffRatioOOS;
   if(!FrameAdd("ACOPT", g_acCurrentFrameId, g_acScore, payload))
      PrintFormat("ACOPT FrameAdd failed (%d)", GetLastError());
}

double AC_Percentile(const double &data[], double pct)
{
   int n = ArraySize(data);
   if(n == 0)
      return 0.0;

   double sorted[];
   ArrayCopy(sorted, data);
   ArraySort(sorted);

   if(n == 1)
      return sorted[0];

   double rank = (pct / 100.0) * (n - 1);
   int lower = (int)MathFloor(rank);
   int upper = (int)MathCeil(rank);
   if(upper >= n)
      upper = n - 1;
   double weight = rank - lower;

   double lowerVal = sorted[lower];
   double upperVal = sorted[upper];
   return lowerVal + (upperVal - lowerVal) * weight;
}

bool AC_Winsorize(double &data[], double lowerPct, double upperPct)
{
   int n = ArraySize(data);
   if(n == 0)
      return false;
   double lower = AC_Percentile(data, lowerPct);
   double upper = AC_Percentile(data, upperPct);
   if(lower >= upper)
      return false;

   bool changed = false;
   for(int i = 0; i < n; ++i)
   {
      if(data[i] < lower)
      {
         data[i] = lower;
         changed = true;
      }
      else if(data[i] > upper)
      {
         data[i] = upper;
         changed = true;
      }
   }
   return changed;
}

double AC_CalculateSharpe(const double &returns[])
{
   int n = ArraySize(returns);
   if(n < 2)
      return 0.0;

   double mean = AC_Mean(returns);
   double variance = 0.0;
   for(int i = 0; i < n; ++i)
      variance += MathPow(returns[i] - mean, 2);
   variance = (n > 1) ? variance / (n - 1) : 0.0;
   double stddev = (variance > 0.0) ? MathSqrt(variance) : 0.0;
   if(stddev == 0.0)
      return 0.0;
   return (mean / stddev) * MathSqrt((double)n);
}

double AC_CalculateSortino(const double &returns[])
{
   int n = ArraySize(returns);
   if(n == 0)
      return 0.0;

   double mean = AC_Mean(returns);
   double downside = 0.0;
   int count = 0;
   for(int i = 0; i < n; ++i)
   {
      if(returns[i] < 0.0)
      {
         downside += MathPow(returns[i], 2);
         ++count;
      }
   }
   if(count == 0)
      return 100.0;
   downside = MathSqrt(downside / count);
   if(downside == 0.0)
      return 0.0;
   return (mean / downside) * MathSqrt((double)n);
}

double AC_CalculateSerenity(const double &returns[], double ddFraction)
{
   if(ddFraction <= 0.0)
      return 0.0;

   int n = ArraySize(returns);
   if(n < 2)
      return 0.0;

   double mean = AC_Mean(returns);
   double variance = 0.0;
   for(int i = 0; i < n; ++i)
      variance += MathPow(returns[i] - mean, 2);
   variance = (n > 1) ? variance / (n - 1) : 0.0;
   double stddev = (variance > 0.0) ? MathSqrt(variance) : 0.0;
   if(stddev == 0.0)
      return 0.0;

   return (mean * stddev) / ddFraction;
}

double AC_Mean(const double &r[])
{
   int n = ArraySize(r);
   if(n == 0)
      return 0.0;
   double sum = 0.0;
   for(int i = 0; i < n; ++i)
      sum += r[i];
   return sum / n;
}

double AC_Skewness(const double &r[])
{
   int n = ArraySize(r);
   if(n < 2)
      return 0.0;

   double mean = AC_Mean(r);
   double m2 = 0.0;
   double m3 = 0.0;

   for(int i = 0; i < n; ++i)
   {
      double diff = r[i] - mean;
      m2 += diff * diff;
      m3 += diff * diff * diff;
   }

   double variance = (n > 1) ? m2 / (n - 1) : 0.0;
   if(variance <= 0.0)
      return 0.0;

   double stddev = MathSqrt(variance);
   return (m3 / n) / MathPow(stddev, 3);
}

double AC_Kurtosis(const double &r[])
{
   int n = ArraySize(r);
   if(n < 2)
      return 0.0;

   double mean = AC_Mean(r);
   double m2 = 0.0;
   double m4 = 0.0;

   for(int i = 0; i < n; ++i)
   {
      double diff = r[i] - mean;
      double diff2 = diff * diff;
      m2 += diff2;
      m4 += diff2 * diff2;
   }

   double variance = (n > 1) ? m2 / (n - 1) : 0.0;
   if(variance <= 0.0)
      return 0.0;

   return (m4 / n) / MathPow(variance, 2) - 3.0;
}

double AC_JarqueBeraPValue(const double &r[])
{
   int n = ArraySize(r);
   if(n < 3)
      return 1.0;

   double mean = AC_Mean(r);
   double m2 = 0.0;
   double m3 = 0.0;
   double m4 = 0.0;

   for(int i = 0; i < n; ++i)
   {
      double diff = r[i] - mean;
      double diff2 = diff * diff;
      m2 += diff2;
      m3 += diff2 * diff;
      m4 += diff2 * diff2;
   }

   double variance = m2 / (n - 1);
   if(variance <= 0.0)
      return 1.0;

   double stddev = MathSqrt(variance);
   double skew = (m3 / n) / MathPow(stddev, 3);
   double kurt = (m4 / n) / MathPow(variance, 2);
   double jb = n * (MathPow(skew, 2) / 6.0 + MathPow(kurt - 3.0, 2) / 24.0);
   double p = MathExp(-0.5 * jb);
   if(p < 0.0)
      p = 0.0;
   if(p > 1.0)
      p = 1.0;
   return p;
}

double AC_KolmogorovStatistic(double &sample1[], double &sample2[])
{
   ArraySort(sample1);
   ArraySort(sample2);

   int n1 = ArraySize(sample1);
   int n2 = ArraySize(sample2);

   double maxDiff = 0.0;
   int i = 0;
   int j = 0;

   while(i < n1 && j < n2)
   {
      double value1 = sample1[i];
      double value2 = sample2[j];
      if(value1 <= value2)
      {
         double cdf1 = (double)(i + 1) / n1;
         double cdf2 = (double)j / n2;
         double diff = MathAbs(cdf1 - cdf2);
         if(diff > maxDiff)
            maxDiff = diff;
         ++i;
      }
      else
      {
         double cdf1 = (double)i / n1;
         double cdf2 = (double)(j + 1) / n2;
         double diff = MathAbs(cdf1 - cdf2);
         if(diff > maxDiff)
            maxDiff = diff;
         ++j;
      }
   }

   while(i < n1)
   {
      double cdf1 = (double)(i + 1) / n1;
      double diff = MathAbs(cdf1 - 1.0);
      if(diff > maxDiff)
         maxDiff = diff;
      ++i;
   }

   while(j < n2)
   {
      double cdf2 = (double)(j + 1) / n2;
      double diff = MathAbs(1.0 - cdf2);
      if(diff > maxDiff)
         maxDiff = diff;
      ++j;
   }

   return maxDiff;
}

double AC_KolmogorovPValue(double d, int n1, int n2)
{
   if(n1 <= 0 || n2 <= 0)
      return 1.0;

   double ne = MathSqrt((double)n1 * n2 / (n1 + n2));
   double x = (ne + 0.12 + 0.11 / ne) * d;

   double sum = 0.0;
   for(int k = 1; k < 100; ++k)
   {
      double term = MathExp(-2.0 * k * k * x * x);
      double sign = (k % 2 == 1) ? 1.0 : -1.0;
      sum += sign * term;
      if(term < 1e-10)
         break;
   }

   double p = MathMax(0.0, MathMin(2.0 * sum, 1.0));
   return p;
}

double AC_GetTradesPerDay()
{
   return g_acTradesPerDay;
}

double AC_GetOosDrawdownPercent()
{
   return g_acDdOOS;
}

#endif // __AC_OPTCRITERION_MQH
