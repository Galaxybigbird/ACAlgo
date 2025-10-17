//+------------------------------------------------------------------+
//|                        AC_SBS_Base_Stage2_Cluster.mq5            |
//|  Stage-2 selector for AC SBS optimisation passes (portfolio      |
//|  assembly with optional clustering filter).                      |
//+------------------------------------------------------------------+
#property copyright   "AC Algo"
#property link        ""
#property version     "0.10"
#property strict
#property description "Stage-2 selector for AC_SBS_Base passes"

#include <ClusteringLib/Database.mqh>

enum ENUM_PORTFOLIO_SCORE
{
   SCORE_CUSTOM_SUM = 0,
   SCORE_COMPLEX_SUM,
   SCORE_PROFIT_SUM,
   SCORE_SHARPE_AVG
};

enum ENUM_PORTFOLIO_SORT
{
   SORT_BY_CUSTOM = 0,
   SORT_BY_COMPLEX,
   SORT_BY_PROFIT,
   SORT_BY_SHARPE
};

sinput int      idTask_      = 0;
sinput string   fileName_    = "database.sqlite";

input group "::: Selection Settings"
input int       idParentJob_        = 0;
input bool      useClusters_        = true;
input double    minCustomOntester_  = 0.0;
input int       minTrades_          = 40;
input double    minSharpeRatio_     = 0.7;
input double    minRecoveryFactor_  = 1.0;
input int       portfolioSize_      = 10;

input group "::: Ordering & Scoring"
input ENUM_PORTFOLIO_SORT  sortMetric_    = SORT_BY_CUSTOM;
input ENUM_PORTFOLIO_SCORE scoringMetric_ = SCORE_CUSTOM_SUM;
input bool                 verboseLogs_   = true;

struct SPassRecord
{
   int     idPass;
   int     cluster;
   double  customOntester;
   double  complexCriterion;
   double  profit;
   double  sharpeRatio;
   double  recoveryFactor;
   double  trades;
   string  params;
};

int         g_clusterUsed[];
SPassRecord g_selected[32];
int         g_selectedTotal = 0;

bool ClusterAlreadyUsed(const int cluster)
{
   for(int i = 0; i < ArraySize(g_clusterUsed); ++i)
   {
      if(g_clusterUsed[i] == cluster)
         return true;
   }
   return false;
}

void RememberCluster(const int cluster)
{
   int idx = ArraySize(g_clusterUsed);
   ArrayResize(g_clusterUsed, idx + 1);
   g_clusterUsed[idx] = cluster;
}

string BuildOrderBy()
{
   switch(sortMetric_)
   {
      case SORT_BY_COMPLEX: return "p.complex_criterion DESC";
      case SORT_BY_PROFIT : return "p.profit DESC";
      case SORT_BY_SHARPE : return "p.sharpe_ratio DESC";
      case SORT_BY_CUSTOM:
      default:
         return "p.custom_ontester DESC";
   }
}

int OnInit()
{
   if(StringLen(fileName_) == 0)
   {
      Print("Stage-2 selector: fileName_ must reference the SQLite database.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(!DB::Connect(fileName_))
   {
      PrintFormat("Stage-2 selector: unable to open DB '%s' (code %d)",
                  fileName_, GetLastError());
      return(INIT_PARAMETERS_INCORRECT);
   }
   DB::Close();
   return(INIT_SUCCEEDED);
}

int LoadSelectedPasses(SPassRecord &buffer[])
{
   ArrayResize(buffer, 0);
   ArrayResize(g_clusterUsed, 0);
   g_selectedTotal = 0;

   if(idParentJob_ <= 0)
   {
      Print("Stage-2 selector: idParentJob_ must be a positive job ID.");
      return 0;
   }

   if(!DB::Connect(fileName_))
   {
      PrintFormat("Stage-2 selector: failed to connect to DB '%s' (code %d)",
                  fileName_, GetLastError());
      return 0;
   }

   string selectCluster = useClusters_
                          ? ", pc.cluster AS cluster"
                          : ", -1 AS cluster";
   string joinCluster   = useClusters_
                          ? " JOIN passes_clusters pc ON pc.id_pass = p.id_pass "
                          : " ";

   string query = StringFormat(
      "SELECT p.id_pass, p.custom_ontester, p.complex_criterion, p.profit, "
      "p.sharpe_ratio, p.recovery_factor, p.trades, p.params%s "
      "FROM passes p "
      "JOIN tasks t ON p.id_task = t.id_task "
      "JOIN jobs j ON t.id_job = j.id_job "
      "%s"
      "WHERE j.id_job = %d "
      "AND p.custom_ontester >= %.10f "
      "AND p.trades >= %d "
      "AND p.sharpe_ratio >= %.10f "
      "AND p.recovery_factor >= %.10f "
      "ORDER BY %s",
      selectCluster,
      joinCluster,
      idParentJob_,
      minCustomOntester_,
      minTrades_,
      minSharpeRatio_,
      minRecoveryFactor_,
      BuildOrderBy());

   int request = DatabasePrepare(DB::Id(), query);
   if(request == INVALID_HANDLE)
   {
      PrintFormat("Stage-2 selector: query preparation failed (code %d).\nQuery:\n%s",
                  GetLastError(), query);
      DB::Close();
      return 0;
   }

   struct Row
   {
      int    id_pass;
      double custom_ontester;
      double complex_criterion;
      double profit;
      double sharpe_ratio;
      double recovery_factor;
      double trades;
      string params;
      int    cluster;
   } row;

   int selected = 0;

   while(DatabaseReadBind(request, row))
   {
      if(useClusters_ && ClusterAlreadyUsed(row.cluster))
         continue;

      int idx = ArraySize(buffer);
      ArrayResize(buffer, idx + 1);

      buffer[idx].idPass            = row.id_pass;
      buffer[idx].cluster           = row.cluster;
      buffer[idx].customOntester    = row.custom_ontester;
      buffer[idx].complexCriterion  = row.complex_criterion;
      buffer[idx].profit            = row.profit;
      buffer[idx].sharpeRatio       = row.sharpe_ratio;
      buffer[idx].recoveryFactor    = row.recovery_factor;
      buffer[idx].trades            = row.trades;
      buffer[idx].params            = row.params;

      if(useClusters_)
         RememberCluster(row.cluster);

      ++selected;
      if(selected >= portfolioSize_)
         break;
   }

   DatabaseFinalize(request);
   DB::Close();

   g_selectedTotal = selected;
   return selected;
}

double EvaluatePortfolio(const SPassRecord &records[], const int count)
{
   if(count == 0)
      return 0.0;

   double customSum  = 0.0;
   double complexSum = 0.0;
   double profitSum  = 0.0;
   double sharpeSum  = 0.0;

   for(int i = 0; i < count; ++i)
   {
      customSum  += records[i].customOntester;
      complexSum += records[i].complexCriterion;
      profitSum  += records[i].profit;
      sharpeSum  += records[i].sharpeRatio;

      if(i < (int)ArraySize(g_selected))
         g_selected[i] = records[i];
   }

   switch(scoringMetric_)
   {
      case SCORE_COMPLEX_SUM: return complexSum;
      case SCORE_PROFIT_SUM : return profitSum;
      case SCORE_SHARPE_AVG : return sharpeSum / count;
      case SCORE_CUSTOM_SUM:
      default:
         return customSum;
   }
}

void PresentSelection(const SPassRecord &records[], const int count, const double score)
{
   if(count == 0)
   {
      Comment("SBS Stage-2 selector: no passes met the filter criteria.");
      return;
   }

   string lines = StringFormat("SBS Stage-2 portfolio (size=%d, score=%.4f)\n", count, score);

   for(int i = 0; i < count; ++i)
   {
      lines += StringFormat("#%d Pass=%d Cl=%d Custom=%.4f Sharpe=%.3f Profit=%.2f\n",
                            i + 1,
                            records[i].idPass,
                            records[i].cluster,
                            records[i].customOntester,
                            records[i].sharpeRatio,
                            records[i].profit);
   }

   Comment(lines);

   if(verboseLogs_)
      Print(lines);
}

double OnTester()
{
   SPassRecord records[];
   int selected = LoadSelectedPasses(records);

   double score = EvaluatePortfolio(records, selected);
   PresentSelection(records, selected, score);

   return score;
}

void OnDeinit(const int reason)
{
   Comment("");
}
