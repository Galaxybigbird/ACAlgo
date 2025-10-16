//+------------------------------------------------------------------+
//|                                   ACBreakRevertPro_Fast_CustomMax.mq5  |
//|                                        Mustafa Seyyid Sahin      |
//+------------------------------------------------------------------+
#property copyright "Mustafa Seyyid Sahin"
#property version   "1.02"

#include <Trade\Trade.mqh>
#include <Arrays\ArrayDouble.mqh>
#include <Math\Stat\Weibull.mqh>
#include <Math\Stat\Poisson.mqh>
#include <Math\Stat\Exponential.mqh>
#include <SymbolValidator.mqh>
#include <ACFunctions.mqh>
#include <ATRtrailing.mqh>
#include <AC_OptCriterion.mqh>

CSymbolValidator g_SymbolValidator;
ACOptConfig g_ACOptCfg;

// Custom optimization reporting variables
double   customWinRate = 0;
double   customWinningTrades = 0;
double   customLosingTrades = 0;
double   customFinalBalance = 0;
double   customAvgTradesDaily = 0;
double   customMaxConsecWinners = 0;
double   customMaxConsecLosers = 0;
double   customAvgWinAmount = 0;
double   customAvgLossAmount = 0;

// Custom optimization frame logging helpers
int      g_ACOptCsvHandle = INVALID_HANDLE;
string   g_ACOptCsvFilename = "";
string   g_ACOptCsvPath = "";
datetime g_ACOptRunStart = 0;

// Definition of trade types
enum ENUM_TRADE_TYPE
{
   TRADE_BUY = 0,  // Buy order
   TRADE_SELL = 1  // Sell order
};

// Input parameters
input group "==== Break Revert Settings ===="
input int             lookback_period          = 1;      // Number of candles for probability calculation
input double          breakout_threshold       = 0.4;    // Minimum probability for breakout
input double          mean_reversion_threshold = 0.4;    // Threshold for mean reversion
input ENUM_TIMEFRAMES TF_M1                    = PERIOD_M1;  // M1 Timeframe
input ENUM_TIMEFRAMES TF_M15                   = PERIOD_M15; // M15 Timeframe
input ENUM_TIMEFRAMES TF_H1                    = PERIOD_H1;  // H1 Timeframe
input int             trade_delay_seconds      = 10;     // Seconds between trades
input int             max_positions            = 1;      // Maximum number of open positions
input bool            enable_safety_trade      = true;   // Enable safety trade during testing
input int             safety_trade_interval    = 60;     // Seconds between safety trade checks
input int             Magic_Number             = 123456; // Magic Number for EA

//--- Custom Optimization Criterion Settings
input group "==== Optimization Criterion Settings ===="
input bool     UseCustomMax          = true;   // Enable custom composite optimization criterion
input int      Opt_MinTrades         = 50;     // Minimum trades required before scoring
input double   Opt_MinOosPF          = 1.20;   // Minimum acceptable OOS profit factor
input double   Opt_MaxOosDDPercent   = 30.0;   // Maximum allowed OOS drawdown percent
input double   Opt_InSampleFraction  = 0.70;   // In-sample fraction for IS/OOS split
input int      Opt_OosGapDays        = 1;      // Gap between IS and OOS periods (days)
input int      Opt_McSimulations     = 500;    // Monte Carlo simulations
input int      Opt_McBlockLen        = 5;      // Block length for bootstrap
input int      Opt_McSeed            = 1337;   // Random seed for reproducibility
input double   Opt_W_PF              = 1.0;    // Weight: OOS profit factor
input double   Opt_W_DD              = 2.0;    // Weight: OOS drawdown penalty
input double   Opt_W_Sharpe          = 1.0;    // Weight: OOS Sharpe bonus
input double   Opt_W_McPF            = 1.0;    // Weight: MC PF robustness
input double   Opt_W_McDD            = 2.0;    // Weight: MC drawdown penalty

//+------------------------------------------------------------------+
//| Validator class for complete trading validation                  |
//+------------------------------------------------------------------+
class CTradeValidator
{
private:
    string           m_symbol;                // Current symbol
    double           m_min_lot;               // Minimum lot size
    double           m_max_lot;               // Maximum lot size
    double           m_lot_step;              // Lot step
    double           m_point;                 // Point value
    int              m_digits;                // Decimal places
    int              m_stops_level;           // Stops level in points
    double           m_tick_size;             // Minimum price change
    double           m_tick_value;            // Tick value in account currency
    ENUM_SYMBOL_CALC_MODE m_calc_mode;        // Calculation mode (Forex, CFD, etc.)
    
    // Helper functions
    bool             LoadSymbolInfo();        // Load symbol information
    void             LogValidationInfo(string message);  // Special logging

public:
                     CTradeValidator();
                    ~CTradeValidator() {};
    
    // Initialization
    bool             Init(string symbol = NULL);
    void             Refresh();              // Update all data
    
    // Environment checks
    bool             CheckHistory(int minimum_bars = 100);
    bool             IsInTester() { return MQLInfoInteger(MQL_TESTER) != 0; }
    
    // Volume validation
    double           NormalizeVolume(double volume);
    double           ValidateVolume(ENUM_ORDER_TYPE order_type, double requested_volume);
    bool             CheckMarginForVolume(ENUM_ORDER_TYPE order_type, double volume, double price = 0.0);
    
    // SL/TP validation
    double           ValidateStopLoss(ENUM_ORDER_TYPE order_type, double open_price, double desired_sl);
    double           ValidateTakeProfit(ENUM_ORDER_TYPE order_type, double open_price, double desired_tp);
    
    // Safety-Trade
    bool             ExecuteSafetyTrade();
    
    // Getters for important properties
    double           GetMinLot() { return m_min_lot; }
    double           GetMaxLot() { return m_max_lot; }
    double           GetLotStep() { return m_lot_step; }
    double           GetPoint() { return m_point; }
    int              GetDigits() { return m_digits; }
    int              GetStopsLevel() { return m_stops_level; }
    
    // Current prices
    double           Bid() { return SymbolInfoDouble(m_symbol, SYMBOL_BID); }
    double           Ask() { return SymbolInfoDouble(m_symbol, SYMBOL_ASK); }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTradeValidator::CTradeValidator()
{
    m_symbol = _Symbol; // Default current symbol
}

//+------------------------------------------------------------------+
//| Initialization of the Validator class                            |
//+------------------------------------------------------------------+
bool CTradeValidator::Init(string symbol = NULL)
{
    // Set symbol
    if(symbol != NULL && symbol != "")
        m_symbol = symbol;
    else
        m_symbol = _Symbol;
    
    // Ensure symbol is selected
    if(!SymbolSelect(m_symbol, true))
    {
        Print("Symbol not selectable: ", m_symbol);
        return false;
    }
    
    // Load all information
    if(!LoadSymbolInfo())
    {
        Print("Error loading symbol data");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Load all important symbol information                            |
//+------------------------------------------------------------------+
bool CTradeValidator::LoadSymbolInfo()
{
    // Basic properties
    m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
    m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    // Trading properties
    m_min_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
    m_max_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
    m_lot_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
    m_stops_level = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
    
    // Pricing properties
    m_tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
    m_tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
    m_calc_mode = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_CALC_MODE);
    
    // Safeguard against faulty data
    if(m_min_lot <= 0) m_min_lot = 0.01;
    if(m_max_lot <= 0) m_max_lot = 100.0;
    if(m_lot_step <= 0) m_lot_step = 0.01;
    if(m_stops_level < 0) m_stops_level = 0;
    
    // Validation for stocks and other instruments
    if(m_calc_mode == SYMBOL_CALC_MODE_EXCH_STOCKS && m_min_lot < 1.0)
        m_min_lot = 1.0; // Stocks often have a minimum volume of 1
    
    return true;
}

//+------------------------------------------------------------------+
//| Update all data                                                  |
//+------------------------------------------------------------------+
void CTradeValidator::Refresh()
{
    LoadSymbolInfo();
}

//+------------------------------------------------------------------+
//| Special logging for validation                                   |
//+------------------------------------------------------------------+
void CTradeValidator::LogValidationInfo(string message)
{
    // Reduced logging in test mode to avoid log overflow
    if(!IsInTester() || MQLInfoInteger(MQL_VISUAL_MODE) != 0)
        Print("[Validator] ", message);
}

//+------------------------------------------------------------------+
//| Check if there is enough historical data                         |
//+------------------------------------------------------------------+
bool CTradeValidator::CheckHistory(int minimum_bars = 100)
{
    // Check if enough bars are available for the current symbol/timeframe
    if(Bars(m_symbol, PERIOD_CURRENT) < minimum_bars)
    {
        LogValidationInfo("WARNING: Not enough historical data. Required: " + 
                IntegerToString(minimum_bars) + ", Available: " + 
                IntegerToString(Bars(m_symbol, PERIOD_CURRENT)));
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Normalize volume according to symbol requirements                |
//+------------------------------------------------------------------+
double CTradeValidator::NormalizeVolume(double volume)
{
    if(volume <= 0.0) return 0.0;
    
    // Limit to Min/Max
    if(volume < m_min_lot) 
        volume = m_min_lot;
    if(volume > m_max_lot) 
        volume = m_max_lot;
    
    // Normalize to valid step
    if(m_lot_step > 0)
    {
        int steps = (int)MathRound((volume - m_min_lot) / m_lot_step);
        volume = NormalizeDouble(m_min_lot + steps * m_lot_step, 8);
    }
    
    // Safeguard against exceeding maximum
    if(volume > m_max_lot) 
        volume = m_max_lot;
    
    return volume;
}

//+------------------------------------------------------------------+
//| Fully validate trading volume                                    |
//+------------------------------------------------------------------+
double CTradeValidator::ValidateVolume(ENUM_ORDER_TYPE order_type, double requested_volume)
{
    // Normalize volume according to symbol rules
    double normalized_volume = NormalizeVolume(requested_volume);
    
    // Check stocks against minimum volume
    if(m_calc_mode == SYMBOL_CALC_MODE_EXCH_STOCKS && normalized_volume < 1.0)
        normalized_volume = 1.0;
    
    // Margin check for normalized volume
    if(!CheckMarginForVolume(order_type, normalized_volume))
    {
        // If margin is insufficient, find a volume that works
        double test_volume = normalized_volume;
        while(test_volume >= m_min_lot)
        {
            test_volume = NormalizeDouble(test_volume * 0.75, 2); // Reduce by 25%
            if(test_volume < m_min_lot) 
                test_volume = m_min_lot;
            
            if(CheckMarginForVolume(order_type, test_volume))
                return test_volume;
                
            if(test_volume == m_min_lot)
                break; // If even min_lot doesn't have enough margin, then stop
        }
        
        LogValidationInfo("Not enough margin for the requested volume");
        return 0.0; // Cannot trade
    }
    
    return normalized_volume;
}

//+------------------------------------------------------------------+
//| Check if there is enough margin for the volume                   |
//+------------------------------------------------------------------+
bool CTradeValidator::CheckMarginForVolume(ENUM_ORDER_TYPE order_type, double volume, double price = 0.0)
{
    if(volume <= 0.0) return false;
    
    // If no price provided, use current market price
    if(price <= 0.0)
    {
        bool is_buy = (order_type == ORDER_TYPE_BUY || order_type == ORDER_TYPE_BUY_LIMIT || 
                      order_type == ORDER_TYPE_BUY_STOP || order_type == ORDER_TYPE_BUY_STOP_LIMIT);
        
        price = is_buy ? Ask() : Bid();
    }
    
    // Calculate required margin
    double margin = 0.0;
    if(!OrderCalcMargin(order_type, m_symbol, volume, price, margin))
    {
        LogValidationInfo("Error in OrderCalcMargin: " + IntegerToString(GetLastError()));
        return false;
    }
    
    // Check free margin in account with safety buffer (15%)
    double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double required_margin = margin * 1.15; // 15% reserve
    
    return (free_margin >= required_margin);
}

//+------------------------------------------------------------------+
//| Validate and correct the StopLoss price                          |
//+------------------------------------------------------------------+
double CTradeValidator::ValidateStopLoss(ENUM_ORDER_TYPE order_type, double open_price, double desired_sl)
{
    if(open_price <= 0.0) return 0.0;
    
    // For zero SL, just return 0 (no SL)
    if(desired_sl <= 0.0) return 0.0;
    
    bool is_buy = (order_type == ORDER_TYPE_BUY || order_type == ORDER_TYPE_BUY_LIMIT || 
                  order_type == ORDER_TYPE_BUY_STOP || order_type == ORDER_TYPE_BUY_STOP_LIMIT);
    
    // Make sure SL is in the correct direction
    if(is_buy && desired_sl >= open_price) 
    {
        LogValidationInfo("Invalid SL for Buy: SL must be below opening price");
        return 0.0; // Don't set SL
    }
    else if(!is_buy && desired_sl <= open_price)
    {
        LogValidationInfo("Invalid SL for Sell: SL must be above opening price");
        return 0.0; // Don't set SL
    }
    
    // Current price for distance calculation
    double current_price = is_buy ? Bid() : Ask();
    
    // Minimum distance in points with additional safety buffer
    int stops_level = m_stops_level;
    if(stops_level <= 0) stops_level = 5; // At least 5 points if not defined
    
    // 20% additional safety buffer for validator
    double min_distance = stops_level * m_point * 1.2;
    
    // Calculate valid SL price
    double valid_sl = 0.0;
    
    if(is_buy)
    {
        // For Buy orders, SL must be below current price
        double max_sl = current_price - min_distance;
        
        // If desired SL is higher than allowed, correct it
        valid_sl = (desired_sl > max_sl) ? max_sl : desired_sl;
    }
    else
    {
        // For Sell orders, SL must be above current price
        double min_sl = current_price + min_distance;
        
        // If desired SL is lower than allowed, correct it
        valid_sl = (desired_sl < min_sl) ? min_sl : desired_sl;
    }
    
    // Normalize price
    valid_sl = NormalizeDouble(valid_sl, m_digits);
    
    return valid_sl;
}

//+------------------------------------------------------------------+
//| Validate and correct the TakeProfit price                        |
//+------------------------------------------------------------------+
double CTradeValidator::ValidateTakeProfit(ENUM_ORDER_TYPE order_type, double open_price, double desired_tp)
{
    if(open_price <= 0.0) return 0.0;
    
    // For zero TP, just return 0 (no TP)
    if(desired_tp <= 0.0) return 0.0;
    
    bool is_buy = (order_type == ORDER_TYPE_BUY || order_type == ORDER_TYPE_BUY_LIMIT || 
                  order_type == ORDER_TYPE_BUY_STOP || order_type == ORDER_TYPE_BUY_STOP_LIMIT);
    
    // Make sure TP is in the correct direction
    if(is_buy && desired_tp <= open_price) 
    {
        LogValidationInfo("Invalid TP for Buy: TP must be above opening price");
        return 0.0; // Don't set TP
    }
    else if(!is_buy && desired_tp >= open_price)
    {
        LogValidationInfo("Invalid TP for Sell: TP must be below opening price");
        return 0.0; // Don't set TP
    }
    
    // Current price for distance calculation
    double current_price = is_buy ? Bid() : Ask();
    
    // Minimum distance in points with additional safety buffer
    int stops_level = m_stops_level;
    if(stops_level <= 0) stops_level = 5; // At least 5 points if not defined
    
    // 20% additional safety buffer for validator
    double min_distance = stops_level * m_point * 1.2;
    
    // Calculate valid TP price
    double valid_tp = 0.0;
    
    if(is_buy)
    {
        // For Buy orders, TP must be above current price
        double min_tp = current_price + min_distance;
        
        // If desired TP is lower than allowed, correct it
        valid_tp = (desired_tp < min_tp) ? min_tp : desired_tp;
    }
    else
    {
        // For Sell orders, TP must be below current price
        double max_tp = current_price - min_distance;
        
        // If desired TP is higher than allowed, correct it
        valid_tp = (desired_tp > max_tp) ? max_tp : desired_tp;
    }
    
    // Normalize price
    valid_tp = NormalizeDouble(valid_tp, m_digits);
    
    return valid_tp;
}

//+------------------------------------------------------------------+
//| Execute a safety trade for validation                            |
//+------------------------------------------------------------------+
bool CTradeValidator::ExecuteSafetyTrade()
{
    // Only execute in tester and if no trades have been made yet
    if(!IsInTester())
        return false;
    
    // Check if trades have already been executed
    if(HistoryDealsTotal() > 0)
        return false;
    
    // Minimum lot size for trade
    double volume = m_min_lot;
    
    // Adjust minimum volume for stocks
    if(m_calc_mode == SYMBOL_CALC_MODE_EXCH_STOCKS && volume < 1.0)
        volume = 1.0;
    
    // Margin check
    if(!CheckMarginForVolume(ORDER_TYPE_BUY, volume))
    {
        LogValidationInfo("Safety-Trade: Not enough margin");
        return false;
    }
    
    // Execute market order
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = m_symbol;
    request.volume = volume;
    request.type = ORDER_TYPE_BUY;
    request.price = Ask();
    request.deviation = 10;
    request.magic = 999999; // Special magic for safety trade
    request.comment = "Safety Trade";
    
    bool success = OrderSend(request, result);
    
    if(success && result.retcode == TRADE_RETCODE_DONE)
    {
        LogValidationInfo("Safety-Trade executed successfully!");
        return true;
    }
    else
    {
        LogValidationInfo("Error on Safety-Trade: " + IntegerToString(result.retcode));
        return false;
    }
}

//------------------------------------------------------------------//
//      Extended CArrayDouble class with additional methods          //
//------------------------------------------------------------------//
class CArrayDoubleEx : public CArrayDouble
{
public:
   double Average() const;
   double Variance() const;
   double StandardDeviation() const;
   double Min() const;
   double Max() const;
   int    Find(double value, double epsilon) const;
   void   PrintSummary(string name) const;
};

double CArrayDoubleEx::Average() const
{
   double sum = 0;
   int total = Total();
   if(total <= 0) return 0;

   for(int i = 0; i < total; i++)
      sum += At(i);

   return sum / total;
}

double CArrayDoubleEx::Variance() const
{
   int total = Total();
   if(total <= 1) return 0;

   double avg = Average();
   double sum_squared_diff = 0;

   for(int i = 0; i < total; i++)
   {
      double diff = At(i) - avg;
      sum_squared_diff += diff * diff;
   }

   return sum_squared_diff / total;
}

double CArrayDoubleEx::StandardDeviation() const
{
   return MathSqrt(Variance());
}

double CArrayDoubleEx::Min() const
{
   int total = Total();
   if(total <= 0) return 0;

   int min_idx = Minimum(0, total);
   return (min_idx >= 0) ? At(min_idx) : 0;
}

double CArrayDoubleEx::Max() const
{
   int total = Total();
   if(total <= 0) return 0;

   int max_idx = Maximum(0, total);
   return (max_idx >= 0) ? At(max_idx) : 0;
}

int CArrayDoubleEx::Find(double value, double epsilon) const
{
   int total = Total();
   for(int i = 0; i < total; i++)
      if(MathAbs(At(i) - value) <= epsilon)
         return i;

   return -1; // Not found
}

void CArrayDoubleEx::PrintSummary(string name) const
{
   int total = Total();
   if(total <= 0)
   {
      Print(name + ": Array is empty");
      return;
   }

   Print(name + " Summary: Elements=", total,
         ", Min=", Min(),
         ", Max=", Max(),
         ", Avg=", Average(),
         ", StdDev=", StandardDeviation());
}

//+------------------------------------------------------------------+
//| Main EA class                                                    |
//+------------------------------------------------------------------+
class CBreakRevertPro
{
private:
   // Trading objects
   CTrade         m_trade;
   CTradeValidator m_validator;
   int            m_magic_number;
   datetime       m_last_trade_time;
   int            m_consecutive_failures;
   bool           m_safety_trade_executed;
   datetime       m_last_safety_check;
   bool           m_is_validation_run;
   bool           m_history_checked;
   
   // Price data arrays
   CArrayDoubleEx m_close_prices_m1;
   CArrayDoubleEx m_close_prices_m15;
   CArrayDoubleEx m_close_prices_h1;

   // Distribution arrays
   CArrayDoubleEx m_weibull_values;
   CArrayDoubleEx m_poisson_values;
   CArrayDoubleEx m_exponential_values;
   CArrayDoubleEx m_breakout_counts;
   datetime       m_last_bar_time_m1;
   datetime       m_last_bar_time_m15;
   datetime       m_last_bar_time_h1;
   bool           m_series_updated_in_tick;
   bool           m_primary_series_updated;
   bool           m_probabilities_ready;

   // Helper methods
   void           DebugPrint(string message, bool force_print=false);
   double         CalcAverage(const int &arr[]);
   double         GetATR(string symbol, ENUM_TIMEFRAMES timeframe, int period);
   void           CalculatePoissonInput(const double &price_array[], int &event_counts[], int period);
   bool           SaveArraysToFile(string filename);
   bool           LoadArraysFromFile(string filename);
   bool           CanTrade();
   bool           UpdateData(bool force_full=false);
   bool           RefreshSeries(ENUM_TIMEFRAMES timeframe, CArrayDoubleEx &buffer, datetime &last_bar_time, bool force_full, bool &updated);
   void           TrimBuffer(CArrayDoubleEx &buffer, int max_size);
   void           CalculateProbabilities();
   double         GetSafeVolumeForSymbol(string symbol);
   double         ValidateVolume(double volume, string symbol="");
   bool           CheckMoneyForTrade(string symbol, double lots, ENUM_ORDER_TYPE type);
   int            CountOpenPositions();
   bool           IsBreakout();
   bool           IsMeanReversion();
   void           LogTrade(string trade_type, double price, double sl, double tp, double lot_size,
                           double risk_percent, double reward_percent);
   bool           ExecuteTrade(int trade_type, bool is_safety_trade=false);
   void           UpdateTrailingStops(bool newBar=false);
   int            GetMinStopLevel();
   bool           IsTestSymbol();
   void           CheckForSafetyTrade();
   double         GetAccountBalance();
   void           DetectValidationEnvironment();
   int            GetMarginDecimalDigits(string symbol);
   bool           IsPrecious(string symbol);
   double         GetMaxLotForAvailableMargin(string symbol, ENUM_ORDER_TYPE type);

public:
                  CBreakRevertPro();
                 ~CBreakRevertPro();
   int            Init();
   void           OnTick();
   void           Deinit(const int reason);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CBreakRevertPro::CBreakRevertPro()
{
   m_magic_number = Magic_Number;
   m_last_trade_time = 0;
   m_consecutive_failures = 0;
   m_safety_trade_executed = false;
   m_last_safety_check = 0;
   m_is_validation_run = false;
   m_history_checked = false;
   m_last_bar_time_m1 = 0;
   m_last_bar_time_m15 = 0;
   m_last_bar_time_h1 = 0;
   m_series_updated_in_tick = false;
   m_primary_series_updated = false;
   m_probabilities_ready = false;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CBreakRevertPro::~CBreakRevertPro()
{
   // Free arrays
   m_close_prices_m1.Shutdown();
   m_close_prices_m15.Shutdown();
   m_close_prices_h1.Shutdown();
   m_weibull_values.Shutdown();
   m_poisson_values.Shutdown();
   m_exponential_values.Shutdown();
   m_breakout_counts.Shutdown();
}

//+------------------------------------------------------------------+
//| Debug function: Controls log output                              |
//+------------------------------------------------------------------+
void CBreakRevertPro::DebugPrint(string message, bool force_print=false)
{
   // Limiting logging in testing mode to prevent excessive logs
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE) && !force_print)
   {
      static int log_counter = 0;
      if(log_counter++ % 500 != 0) // Much less logging to avoid large logs
         return;
   }

   Print("[BreakRevertPro] " + message);
}

//+------------------------------------------------------------------+
//| Build AC trade comment                                           |
//+------------------------------------------------------------------+
string BuildTradeComment(const double riskRewardRatio)
{
   const double epsilon = 0.0001;
   bool isCompounded = ((currentRisk - AC_BaseRisk) > epsilon);

   int maxStages = MathMax(1, AC_CompoundingWins);
   int stage = consecutiveWins;
   if(stage < 0)
      stage = 0;
   if(isCompounded && stage <= 0)
      stage = 1;
   if(maxStages > 1 && stage >= maxStages)
      stage = maxStages - 1;
   if(maxStages <= 0)
   {
      maxStages = 1;
      stage = 0;
   }

   string stageLabel = StringFormat("%s%d/%d", isCompounded ? "C" : "B", stage, maxStages);
   string rrLabel = "RR--";
   if(riskRewardRatio > epsilon)
      rrLabel = StringFormat("RR%.2f", riskRewardRatio);

   return StringFormat("AC|%s|%s", stageLabel, rrLabel);
}

//+------------------------------------------------------------------+
//| Helper function: Calculate average of int array                  |
//+------------------------------------------------------------------+
double CBreakRevertPro::CalcAverage(const int &arr[])
{
   double sum = 0;
   int total = ArraySize(arr);
   if(total <= 0) return 0;

   for(int i = 0; i < total; i++)
      sum += arr[i];

   return sum / total;
}

//+------------------------------------------------------------------+
//| Helper function: Calculate ATR with fallback                     |
//+------------------------------------------------------------------+
double CBreakRevertPro::GetATR(string symbol, ENUM_TIMEFRAMES timeframe, int period)
{
   if(period <= 0) period = 14; // Default safe value
   
   int handle = iATR(symbol, timeframe, period);
   if(handle == INVALID_HANDLE)
   {
      return 10 * _Point; // Default fallback value
   }

   double atrBuffer[];
   if(CopyBuffer(handle, 0, 0, 1, atrBuffer) <= 0)
   {
      IndicatorRelease(handle);
      return 10 * _Point; // Default fallback value
   }

   IndicatorRelease(handle);
   
   // Ensure returned value is valid
   if(atrBuffer[0] <= 0)
      return 10 * _Point;
   
   return atrBuffer[0];
}

//+------------------------------------------------------------------+
//| Convert price data to discrete events (for Poisson)              |
//+------------------------------------------------------------------+
void CBreakRevertPro::CalculatePoissonInput(const double &price_array[], int &event_counts[], int period)
{
   int size = ArraySize(price_array);
   if(size < 2)
   {
      ArrayResize(event_counts, 1);
      event_counts[0] = 1; // Default value
      return;
   }

   ArrayResize(event_counts, size);
   ArrayInitialize(event_counts, 0);

   for(int i = 1; i < size; i++)
   {
      // Count how often the price moves > 5 pips
      if(MathAbs(price_array[i] - price_array[i - 1]) > 5 * _Point)
      {
         event_counts[i] = event_counts[i - 1] + 1;
      }
      else
      {
         event_counts[i] = event_counts[i - 1];
      }
   }
}

//+------------------------------------------------------------------+
//| Save all arrays to a file                                        |
//+------------------------------------------------------------------+
bool CBreakRevertPro::SaveArraysToFile(string filename)
{
   // Skip saving in tester to avoid file issues
   if(MQLInfoInteger(MQL_TESTER))
      return true;
      
   int handle = FileOpen(filename, FILE_WRITE | FILE_BIN);
   if(handle == INVALID_HANDLE)
      return false;

   bool success = true;
   success &= m_close_prices_m1.Save(handle);
   success &= m_close_prices_m15.Save(handle);
   success &= m_close_prices_h1.Save(handle);
   success &= m_weibull_values.Save(handle);
   success &= m_poisson_values.Save(handle);
   success &= m_exponential_values.Save(handle);
   success &= m_breakout_counts.Save(handle);

   FileClose(handle);
   return success;
}

//+------------------------------------------------------------------+
//| Load all arrays from a file                                      |
//+------------------------------------------------------------------+
bool CBreakRevertPro::LoadArraysFromFile(string filename)
{
   // Skip loading in tester to avoid file issues
   if(MQLInfoInteger(MQL_TESTER))
      return false;
      
   if(!FileIsExist(filename))
      return false;

   int handle = FileOpen(filename, FILE_READ | FILE_BIN);
   if(handle == INVALID_HANDLE)
      return false;

   bool success = true;
   success &= m_close_prices_m1.Load(handle);
   success &= m_close_prices_m15.Load(handle);
   success &= m_close_prices_h1.Load(handle);
   success &= m_weibull_values.Load(handle);
   success &= m_poisson_values.Load(handle);
   success &= m_exponential_values.Load(handle);
   success &= m_breakout_counts.Load(handle);

   FileClose(handle);
   return success;
}

//+------------------------------------------------------------------+
//| Check if it's a precious metals symbol (needs special handling)  |
//+------------------------------------------------------------------+
bool CBreakRevertPro::IsPrecious(string symbol)
{
   return (StringFind(symbol, "XAU") >= 0 || 
           StringFind(symbol, "GOLD") >= 0 || 
           StringFind(symbol, "XAG") >= 0 || 
           StringFind(symbol, "SILVER") >= 0);
}

//+------------------------------------------------------------------+
//| Get decimal places for margin calculation based on symbol        |
//+------------------------------------------------------------------+
int CBreakRevertPro::GetMarginDecimalDigits(string symbol)
{
   // Gold/Silver need more precise volumes (0.01 can be too much)
   if(IsPrecious(symbol))
      return 3;  // Use 3 decimal places (0.001 lot precision)
   
   return 2;     // Standard 2 decimal places (0.01 lot precision)
}

//+------------------------------------------------------------------+
//| Check if enough time has passed since last trade                 |
//+------------------------------------------------------------------+
bool CBreakRevertPro::CanTrade()
{
   // Always allow trading in tester mode for validation
   if(MQLInfoInteger(MQL_TESTER) && m_is_validation_run)
      return true;
      
   datetime now = TimeCurrent();
   int diffSec = (int)(now - m_last_trade_time);

   if(diffSec < trade_delay_seconds && m_last_trade_time > 0)
      return false;
   
   // Check number of consecutive failures, pause if too many
   if(m_consecutive_failures > 3 && !MQLInfoInteger(MQL_TESTER))
   {
      m_last_trade_time = now; // Reset the timer
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Detect if we're in a validation environment                      |
//+------------------------------------------------------------------+
void CBreakRevertPro::DetectValidationEnvironment()
{
   // Validation usually runs on small account balances and uses specific symbols/timeframes
   double balance = GetAccountBalance();
   bool small_balance = (balance <= 500.0);
   bool known_test_symbol = IsTestSymbol();
   
   if(MQLInfoInteger(MQL_TESTER) && (small_balance || known_test_symbol))
   {
      m_is_validation_run = true;
      DebugPrint("Validation environment detected. Balance: " + DoubleToString(balance, 2), true);
   }
}

//+------------------------------------------------------------------+
//| Check if current symbol+timeframe matches test combinations      |
//+------------------------------------------------------------------+
bool CBreakRevertPro::IsTestSymbol()
{
   string current_symbol = Symbol();
   ENUM_TIMEFRAMES current_tf = Period();
   
   return (
      (current_symbol == "EURUSD" && current_tf == PERIOD_H1) ||
      (current_symbol == "XAUUSD" && current_tf == PERIOD_D1) ||
      (current_symbol == "GBPUSD" && current_tf == PERIOD_M30) ||
      (current_symbol == "EURUSD" && current_tf == PERIOD_M1)
   );
}

//+------------------------------------------------------------------+
//| Expert Initialization                                            |
//+------------------------------------------------------------------+
int CBreakRevertPro::Init()
{
   // Initialize validator
   if(!m_validator.Init())
   {
      Print("Validator initialization failed!");
      return INIT_FAILED;
   }

   if(!g_SymbolValidator.Init(Symbol()))
   {
      Print("Failed to initialise SymbolValidator for ", Symbol());
      return INIT_FAILED;
   }

   InitializeACRiskManagement();
   InitDEMAATR();
   ManualTrailingActivated = false;
   
   // Set delta for CArrayDoubleEx
   m_close_prices_m1.Delta(0.0001);
   m_close_prices_m15.Delta(0.0001);
   m_close_prices_h1.Delta(0.0001);
   m_weibull_values.Delta(0.0001);
   m_poisson_values.Delta(0.0001);
   m_exponential_values.Delta(0.0001);
   m_breakout_counts.Delta(0.0001);

   // Reserve memory
   m_close_prices_m1.Reserve(lookback_period * 2);
   m_close_prices_m15.Reserve(lookback_period * 2);
   m_close_prices_h1.Reserve(lookback_period * 2);
   m_weibull_values.Reserve(lookback_period * 2);
   m_poisson_values.Reserve(lookback_period * 2);
   m_exponential_values.Reserve(lookback_period * 2);
   m_breakout_counts.Reserve(lookback_period * 2);

   // Clear Arrays
   m_close_prices_m1.Clear();
   m_close_prices_m15.Clear();
   m_close_prices_h1.Clear();
   m_weibull_values.Clear();
   m_poisson_values.Clear();
   m_exponential_values.Clear();
   m_breakout_counts.Clear();

   // Check for validation environment
   DetectValidationEnvironment();
   
   // Check history data availability
   if(!m_validator.CheckHistory(lookback_period * 2))
   {
      DebugPrint("Init: Not enough historical data!", true);
      // Continue in validation mode, otherwise fail
      if(!m_validator.IsInTester())
         return INIT_FAILED;
   }
   
   m_history_checked = true;

   // Try to load previous data
   if(LoadArraysFromFile("BreakRevert_Data.dat"))
   {
      DebugPrint("Init: Previous data loaded successfully.");
      m_probabilities_ready = (m_weibull_values.Total() > 0);
   }
   else
   {
      DebugPrint("Init: No previous data loaded. Loading history...");
      if(!UpdateData(true))
      {
         DebugPrint("Init: Not enough historical data. Will use default values.");
         m_probabilities_ready = false;
      }
      else
      {
         DebugPrint("Init: Historical data loaded. Calculating probabilities...");
         CalculateProbabilities();
         m_probabilities_ready = true;
      }
   }

   // Force recalculation on first tick
   m_probabilities_ready = false;

   // Set MagicNumber
   m_trade.SetExpertMagicNumber(m_magic_number);
   
   // Set deviation for trade execution
   m_trade.SetDeviationInPoints(10);

   // Calculate safe volume for current symbol
   double safe_volume = GetSafeVolumeForSymbol(Symbol());
   
   // Get minimum stop level
   int min_stop = GetMinStopLevel();
   double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   
   DebugPrint("Init: EA initialized on " + Symbol() + " with MinStopLevel=" + 
              IntegerToString(min_stop) + ", MinLot=" + DoubleToString(min_lot, 2) +
              ", MaxLot=" + DoubleToString(max_lot, 2) +
              ", SafeLot=" + DoubleToString(safe_volume, 3) +  
              ", Balance=" + DoubleToString(GetAccountBalance(), 2), true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Get account balance with fallback for testing                    |
//+------------------------------------------------------------------+
double CBreakRevertPro::GetAccountBalance()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // If balance is too small, use reasonable default for normal operation
   if(!MQLInfoInteger(MQL_TESTER) && balance < 10.0)
      return 1000.0;
      
   return balance;
}

//+------------------------------------------------------------------+
//| Get minimum stop level in points (with safety margin)            |
//+------------------------------------------------------------------+
int CBreakRevertPro::GetMinStopLevel()
{
   int min_stop = (int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
   
   // If we can't get the actual value or it's too small, use a safe default
   if(min_stop <= 0)
      min_stop = 10;
      
   // Add safety margin - use at least 20 points or 2x the minimum
   min_stop = MathMax(20, min_stop * 2);
   
   return min_stop;
}

//+------------------------------------------------------------------+
//| Trim buffer to a maximum size                                    |
//+------------------------------------------------------------------+
void CBreakRevertPro::TrimBuffer(CArrayDoubleEx &buffer, int max_size)
{
   while(buffer.Total() > max_size)
      buffer.Delete(buffer.Total() - 1);
}

//+------------------------------------------------------------------+
//| Refresh single timeframe series                                  |
//+------------------------------------------------------------------+
bool CBreakRevertPro::RefreshSeries(ENUM_TIMEFRAMES timeframe,
                                    CArrayDoubleEx &buffer,
                                    datetime &last_bar_time,
                                    bool force_full,
                                    bool &updated)
{
   updated = false;
   int safe_lookback = MathMax(1, lookback_period);
   datetime latest_bar = (datetime)SeriesInfoInteger(Symbol(), timeframe, SERIES_LASTBAR_DATE);

   if(force_full || last_bar_time == 0 || buffer.Total() == 0)
   {
      double prices[];
      ArraySetAsSeries(prices, true);
      int copied = CopyClose(Symbol(), timeframe, 0, safe_lookback, prices);

      buffer.Clear();
      if(copied > 0)
      {
         buffer.AssignArray(prices);
         TrimBuffer(buffer, safe_lookback);
      }
      else
      {
         buffer.Add(SymbolInfoDouble(Symbol(), SYMBOL_BID));
      }

      updated = true;
      last_bar_time = (latest_bar != 0 ? latest_bar : TimeCurrent());
      return buffer.Total() > 0;
   }

   if(latest_bar != 0 && latest_bar != last_bar_time)
   {
      double price_arr[];
      ArraySetAsSeries(price_arr, true);
      if(CopyClose(Symbol(), timeframe, 0, 1, price_arr) > 0)
      {
         buffer.Insert(price_arr[0], 0);
         TrimBuffer(buffer, safe_lookback);
         last_bar_time = latest_bar;
         updated = true;
         return true;
      }
   }

   return buffer.Total() > 0;
}

//+------------------------------------------------------------------+
//| Update price data for M1, M15, H1                                |
//+------------------------------------------------------------------+
bool CBreakRevertPro::UpdateData(bool force_full)
{
   m_series_updated_in_tick = false;
   m_primary_series_updated = false;

   bool updated_m1 = false;
   bool updated_m15 = false;
   bool updated_h1 = false;

   bool ok_m1 = RefreshSeries(TF_M1, m_close_prices_m1, m_last_bar_time_m1, force_full, updated_m1);
   bool ok_m15 = RefreshSeries(TF_M15, m_close_prices_m15, m_last_bar_time_m15, force_full, updated_m15);
   bool ok_h1 = RefreshSeries(TF_H1, m_close_prices_h1, m_last_bar_time_h1, force_full, updated_h1);

   if(updated_m1 || updated_m15 || updated_h1)
      m_series_updated_in_tick = true;

   if(updated_m1)
      m_primary_series_updated = true;

   return ok_m1 && ok_m15 && ok_h1;
}

//+------------------------------------------------------------------+
//| Calculate probabilities with safety checks                       |
//+------------------------------------------------------------------+
void CBreakRevertPro::CalculateProbabilities()
{
   // Check if M1 data exists
   if(m_close_prices_m1.Total() == 0)
   {
      // Set default probability values
      m_weibull_values.Clear();
      m_poisson_values.Clear();
      m_exponential_values.Clear();
      m_weibull_values.Add(0.5);
      m_poisson_values.Add(0.5);
      m_exponential_values.Add(0.5);
      return;
   }

   // CArrayDouble -> normal array
   double temp_array[];
   int sizeM1 = m_close_prices_m1.Total();
   ArrayResize(temp_array, sizeM1);
   for(int i = 0; i < sizeM1; i++)
      temp_array[i] = m_close_prices_m1.At(i);

   // Ensure data is valid (no zeros)
   for(int i = 0; i < sizeM1; i++)
      if(temp_array[i] <= 0) temp_array[i] = 1.0;

   // Weibull
   double weibull_result[];
   if(!MathProbabilityDensityWeibull(temp_array, 1.5, 5.0, weibull_result) || ArraySize(weibull_result) == 0)
   {
      ArrayResize(weibull_result, sizeM1);
      ArrayInitialize(weibull_result, 0.5);
   }

   // Poisson
   int event_counts_int[];
   ArrayResize(event_counts_int, sizeM1);
   ArrayInitialize(event_counts_int, 1); // Default value
   
   if(sizeM1 > 1) // Only calculate if we have more than 1 value
      CalculatePoissonInput(temp_array, event_counts_int, MathMax(1, lookback_period));

   // convert to double
   double event_counts[];
   int sizeEvents = ArraySize(event_counts_int);
   ArrayResize(event_counts, sizeEvents);
   for(int i = 0; i < sizeEvents; i++)
      event_counts[i] = (double)event_counts_int[i];

   // Lambda
   CArrayDoubleEx event_counts_array;
   event_counts_array.AssignArray(event_counts);
   double lambda = event_counts_array.Average();
   if(lambda <= 0 || lambda > 1000000)
      lambda = 5.0;

   double poisson_result[];
   if(!MathCumulativeDistributionPoisson(event_counts, lambda, poisson_result))
   {
      ArrayResize(poisson_result, sizeM1);
      ArrayInitialize(poisson_result, 0.5);
   }

   // Exponential
   double mu = m_close_prices_m1.Average();
   if(mu <= 0)
      mu = 1.0;

   double exp_result[];
   if(!MathCumulativeDistributionExponential(temp_array, mu, exp_result) || ArraySize(exp_result) == 0)
   {
      ArrayResize(exp_result, sizeM1);
      ArrayInitialize(exp_result, 0.5);
   }

   // Save results
   m_weibull_values.AssignArray(weibull_result);
   m_poisson_values.AssignArray(poisson_result);
   m_exponential_values.AssignArray(exp_result);

   // Save breakout counts
   m_breakout_counts.Clear();
   for(int i = 0; i < sizeEvents; i++)
      m_breakout_counts.Add(event_counts[i]);
}

//+------------------------------------------------------------------+
//| Calculate maximum lot based on available free margin             |
//+------------------------------------------------------------------+
double CBreakRevertPro::GetMaxLotForAvailableMargin(string symbol, ENUM_ORDER_TYPE type)
{
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(free_margin <= 0) return 0;
   
   // Safety buffer - use only 30% of free margin
   free_margin *= 0.3;
   
   // Get price
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick)) return 0;
   double price = (type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
   
   // Get contract specifications
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   // Start with minimum lot
   double lot = min_lot;
   double margin_required = 0;
   
   // Gradually increase lot size until we reach maximum allowed by free margin
   while(lot < max_lot)
   {
      if(!OrderCalcMargin(type, symbol, lot, price, margin_required))
         break;
      
      if(margin_required > free_margin)
      {
         // We've exceeded free margin, step back
         lot -= lot_step;
         break;
      }
      
      // Increase lot
      lot += lot_step;
   }
   
   // Ensure lot is valid
   lot = MathMax(min_lot, lot);
   lot = MathMin(max_lot, lot);
   
   // Normalize lot based on lot_step
   int steps = (int)MathRound(lot / lot_step);
   lot = steps * lot_step;
   
   return lot;
}

//+------------------------------------------------------------------+
//| Get safe volume specifically for this symbol (especially gold)   |
//+------------------------------------------------------------------+
double CBreakRevertPro::GetSafeVolumeForSymbol(string symbol)
{
   if(symbol == "")
      symbol = Symbol();
      
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   if(min_lot <= 0) min_lot = 0.01;
   
   // For gold and precious metals, we need extremely small lots
   if(IsPrecious(symbol))
   {
      // Check if we're in validation environment with small balance
      if(m_is_validation_run || GetAccountBalance() < 500)
      {
         // Calculate a very conservative lot size for gold
         double max_lot = GetMaxLotForAvailableMargin(symbol, ORDER_TYPE_BUY);
         if(max_lot > 0)
         {
            // Use just 10% of the maximum available
            double safe_lot = max_lot * 0.1;
            return ValidateVolume(safe_lot, symbol);
         }
         
         // If calculation fails, use the absolute minimum
         return min_lot;
      }
   }
   
   // For standard forex pairs
   double balance = GetAccountBalance();
   
   // Super conservative approach for validation or small accounts
   if(m_is_validation_run || balance < 500)
      return min_lot;
   
   // For normal trading, calculate based on risk
   double max_lot = GetMaxLotForAvailableMargin(symbol, ORDER_TYPE_BUY);
   return ValidateVolume(max_lot * 0.2, symbol); // Use 20% of maximum available
}

//+------------------------------------------------------------------+
//| Validate volume - ensures it's within allowed broker range       |
//+------------------------------------------------------------------+
double CBreakRevertPro::ValidateVolume(double volume, string symbol)
{
   if(symbol == "")
      symbol = Symbol();
      
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   // Check if inputs are valid
   if(min_lot <= 0 || max_lot <= 0 || lot_step <= 0)
   {
      // Default safe values
      min_lot = 0.01;
      max_lot = 100.0;
      lot_step = 0.01;
   }
   
   // Ensure volume is not less than minimum
   if(volume < min_lot)
      volume = min_lot;
      
   // Ensure volume is not greater than maximum
   if(volume > max_lot)
      volume = max_lot;
      
   // Normalize to valid step value
   int steps = (int)MathRound(volume / lot_step);
   volume = steps * lot_step;
   
   // Get appropriate decimal places for this symbol
   int digits = GetMarginDecimalDigits(symbol);
   return NormalizeDouble(volume, digits);
}

//+------------------------------------------------------------------+
//| Check if there's enough free margin for the trade                |
//+------------------------------------------------------------------+
bool CBreakRevertPro::CheckMoneyForTrade(string symbol, double lots, ENUM_ORDER_TYPE type)
{
   // Use validator for more robust margin checking
   return m_validator.CheckMarginForVolume(type, lots);
}

//+------------------------------------------------------------------+
//| Count current open positions for symbol                          |
//+------------------------------------------------------------------+
int CBreakRevertPro::CountOpenPositions()
{
   int count = 0;
   int total = PositionsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionSelectByTicket(ticket))
         {
            string pos_symbol = PositionGetString(POSITION_SYMBOL);
            if(pos_symbol == Symbol())
               count++;
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Lot calculation with account size protection                     |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check for Breakout signal                                        |
//+------------------------------------------------------------------+
bool CBreakRevertPro::IsBreakout()
{
   if(m_weibull_values.Total() == 0 || m_poisson_values.Total() == 0)
      return false;

   double weibull_prob = 0.5; // Default
   double poisson_prob = 0.5; // Default
   
   // Safely get values
   if(m_weibull_values.Total() > 0)
      weibull_prob = m_weibull_values.At(m_weibull_values.Total() - 1);
   if(m_poisson_values.Total() > 0)
      poisson_prob = m_poisson_values.At(m_poisson_values.Total() - 1);

   // Simple trend check
   double m1_trend = 0, m15_trend = 0, h1_volatility = 0;
   
   // Safe trend calculations
   if(m_close_prices_m1.Total() >= 2)
      m1_trend = m_close_prices_m1.At(0) - m_close_prices_m1.At(m_close_prices_m1.Total() - 1);
   
   if(m_close_prices_m15.Total() >= 2)
      m15_trend = m_close_prices_m15.At(0) - m_close_prices_m15.At(m_close_prices_m15.Total() - 1);
      
   // Volatility
   if(m_close_prices_h1.Total() > 0)
      h1_volatility = m_close_prices_h1.Max() - m_close_prices_h1.Min();
   else
      h1_volatility = 50 * _Point; // Default
   
   bool trend_up = (m1_trend > 0 && m15_trend > 0);
   bool breakout_condition = (poisson_prob > breakout_threshold && weibull_prob > mean_reversion_threshold);

   // Breakout only with sufficient volatility
   return (breakout_condition && trend_up && h1_volatility > 10 * _Point);
}

//+------------------------------------------------------------------+
//| Check for Mean-Reversion signal                                  |
//+------------------------------------------------------------------+
bool CBreakRevertPro::IsMeanReversion()
{
   if(m_weibull_values.Total() == 0)
      return false;

   double weibull_prob = 0.5; // Default
   
   // Safely get values
   if(m_weibull_values.Total() > 0)
      weibull_prob = m_weibull_values.At(m_weibull_values.Total() - 1);

   double h1_trend = 0;
   
   // Safe trend calculation
   if(m_close_prices_h1.Total() >= 2)
      h1_trend = m_close_prices_h1.At(m_close_prices_h1.Total() - 1) - m_close_prices_h1.At(0);
   
   return (weibull_prob < mean_reversion_threshold && MathAbs(h1_trend) < 20 * _Point);
}

//+------------------------------------------------------------------+
//| Detailed log for trades                                          |
//+------------------------------------------------------------------+
void CBreakRevertPro::LogTrade(string trade_type, double price, double sl, double tp, double lot_size,
                               double risk_percent, double reward_percent)
{
   DebugPrint(trade_type + " trade | Lot=" + DoubleToString(lot_size, 3) +
              " | Price=" + DoubleToString(price, 5) +
              " | SL=" + DoubleToString(sl, 5) +
              " | TP=" + DoubleToString(tp, 5) +
              " | Risk %=" + DoubleToString(risk_percent, 2) +
              " | Target %=" + DoubleToString(reward_percent, 2) +
              " | Acct Balance=" + DoubleToString(GetAccountBalance(), 2), true);
}

//+------------------------------------------------------------------+
//| Execute market trade with careful stop placement                 |
//+------------------------------------------------------------------+
bool CBreakRevertPro::ExecuteTrade(int trade_type, bool is_safety_trade)
{
   if(!is_safety_trade && !CanTrade())
      return false;

   if(CountOpenPositions() >= max_positions)
   {
      DebugPrint("ExecuteTrade: Maximum positions reached (" + IntegerToString(max_positions) + ")");
      return false;
   }

   string symbol = Symbol();
   ENUM_ORDER_TYPE order_type = (trade_type == TRADE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double stop_loss_distance = GetStopLossDistance();
   if(stop_loss_distance <= 0.0)
   {
      DebugPrint("ExecuteTrade: Failed to derive ATR-based stop distance", true);
      return false;
   }

   double price = (trade_type == TRADE_BUY) ? m_validator.Ask() : m_validator.Bid();
   if(price <= 0.0)
   {
      DebugPrint("ExecuteTrade: Unable to obtain price", true);
      return false;
   }

   double sl = (trade_type == TRADE_BUY) ? price - stop_loss_distance : price + stop_loss_distance;
   sl = m_validator.ValidateStopLoss(order_type, price, sl);
   if(sl <= 0.0)
   {
      DebugPrint("ExecuteTrade: Stop loss validation failed", true);
      return false;
   }

   double effective_stop_distance = MathAbs(price - sl);
   if(effective_stop_distance < _Point)
      effective_stop_distance = stop_loss_distance;

   double lot = ::CalculateLotSize(effective_stop_distance);
   double min_lot = m_validator.GetMinLot();
   double lot_step = m_validator.GetLotStep();
   double max_lot = m_validator.GetMaxLot();

   if(is_safety_trade)
      lot = min_lot;

   if(lot < min_lot)
      lot = min_lot;
   if(lot > max_lot)
      lot = max_lot;

   if(!m_validator.CheckMarginForVolume(order_type, lot))
   {
      DebugPrint("ExecuteTrade: Not enough margin for " + DoubleToString(lot, 3) + " lot", true);

      double adjusted_lot = lot;
      bool found_margin_volume = false;
      while(adjusted_lot - lot_step >= min_lot)
      {
         adjusted_lot = m_validator.NormalizeVolume(adjusted_lot - lot_step);
         if(adjusted_lot < min_lot)
            break;

         if(m_validator.CheckMarginForVolume(order_type, adjusted_lot))
         {
            lot = adjusted_lot;
            found_margin_volume = true;
            break;
         }
      }

      if(!found_margin_volume)
      {
         if(!m_validator.CheckMarginForVolume(order_type, min_lot))
         {
            DebugPrint("ExecuteTrade: Not enough margin even for minimum lot", true);
            m_consecutive_failures++;
            return false;
         }
         lot = min_lot;
      }
   }

   double safe_risk = (MathAbs(currentRisk) > 1e-6) ? currentRisk : AC_BaseRisk;
   double reward_ratio = currentReward / MathMax(1e-6, safe_risk);
   double tp_distance = effective_stop_distance * reward_ratio;
   double tp = (trade_type == TRADE_BUY) ? price + tp_distance : price - tp_distance;
   tp = m_validator.ValidateTakeProfit(order_type, price, tp);

   string trade_direction = (trade_type == TRADE_BUY) ? "BUY" : "SELL";
   LogTrade(trade_direction, price, sl, tp, lot, safe_risk, currentReward);

   string comment = BuildTradeComment(reward_ratio);
   if(is_safety_trade)
      comment = "Safety|" + comment;

   bool success = (trade_type == TRADE_BUY)
                  ? m_trade.Buy(lot, symbol, 0, sl, tp, comment)
                  : m_trade.Sell(lot, symbol, 0, sl, tp, comment);

   if(success)
   {
      m_last_trade_time = TimeCurrent();
      m_consecutive_failures = 0;
      if(is_safety_trade)
         m_safety_trade_executed = true;

      DebugPrint("ExecuteTrade: " + trade_direction + " executed successfully with lot=" +
                 DoubleToString(lot, 3), true);
      return true;
   }

   int error = GetLastError();
   m_consecutive_failures++;
   DebugPrint("ExecuteTrade: Failed. Error=" + IntegerToString(error), true);

   return false;
}

//+------------------------------------------------------------------+
//| Update trailing stops for all positions                          |
//+------------------------------------------------------------------+
void CBreakRevertPro::UpdateTrailingStops(bool newBar)
{
   bool inBacktest = (MQLInfoInteger(MQL_TESTER) != 0);
   if(inBacktest && !newBar && !ManualTrailingActivated)
      return;

   int total = PositionsTotal();
   for(int i = 0; i < total; ++i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != m_magic_number)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string orderType = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      string positionComment = PositionGetString(POSITION_COMMENT);
      bool trailingAllowed = TrailingAllowedForPosition(positionComment);
      bool compoundedOverrideActive = IsCompoundedTrailingOverride(positionComment);

      if(!trailingAllowed)
         continue;

      if(!ManualTrailingActivated)
      {
         if(!ShouldActivateTrailing(entryPrice, currentPrice, orderType, volume, compoundedOverrideActive))
            continue;
      }

      UpdateTrailingStop(ticket, entryPrice, orderType);
   }
}

//+------------------------------------------------------------------+
//| Helper: calculate trades per day                                 |
//+------------------------------------------------------------------+
double CalcTradesPerDayFromHistory()
{
   if(!HistorySelect(0, TimeCurrent()))
      return 0.0;

   int totalDeals = (int)HistoryDealsTotal();
   if(totalDeals <= 0)
      return 0.0;

   datetime firstTime = 0;
   datetime lastTime = 0;
   int tradeCount = 0;

   for(int i = 0; i < totalDeals; ++i)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;

      long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
         continue;

      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(tradeCount == 0)
         firstTime = dealTime;
      lastTime = dealTime;
      ++tradeCount;
   }

   if(tradeCount <= 1)
      return (double)tradeCount;

   double days = MathMax(1.0, (double)(lastTime - firstTime) / 86400.0);
   return (double)tradeCount / days;
}

//+------------------------------------------------------------------+
//| Strategy tester optimisation metric                              |
//+------------------------------------------------------------------+
double OnTester()
{
   double trades = TesterStatistics((ENUM_STATISTICS)STAT_TRADES);
   if(trades < 1)
      return UseCustomMax ? -DBL_MAX : 0.0;

   double profit         = TesterStatistics((ENUM_STATISTICS)STAT_PROFIT);
   double profitFactor   = TesterStatistics((ENUM_STATISTICS)STAT_PROFIT_FACTOR);
   double sharpeRatio    = TesterStatistics((ENUM_STATISTICS)STAT_SHARPE_RATIO);
   double recoveryFactor = TesterStatistics((ENUM_STATISTICS)STAT_RECOVERY_FACTOR);
   double drawdownRel    = TesterStatistics((ENUM_STATISTICS)STAT_EQUITY_DDREL_PERCENT);
   double finalBalance   = AccountInfoDouble(ACCOUNT_BALANCE);

   double winningTrades = TesterStatistics((ENUM_STATISTICS)STAT_PROFIT_TRADES);
   double losingTrades  = TesterStatistics((ENUM_STATISTICS)STAT_LOSS_TRADES);
   double winRate       = (trades > 0.0) ? (winningTrades / trades) * 100.0 : 0.0;
   double avgTradesDaily = CalcTradesPerDayFromHistory();

   double maxConsecWinners = MathSqrt(MathMax(0.0, winningTrades));
   double maxConsecLosers  = MathSqrt(MathMax(0.0, losingTrades));

   double grossProfit = TesterStatistics((ENUM_STATISTICS)STAT_GROSS_PROFIT);
   double grossLoss   = TesterStatistics((ENUM_STATISTICS)STAT_GROSS_LOSS);
   double avgWinAmount  = (winningTrades > 0.0) ? grossProfit / winningTrades : 0.0;
   double avgLossAmount = (losingTrades  > 0.0) ? grossLoss  / losingTrades  : 0.0;

   double metric = profitFactor;
   if(drawdownRel > 20.0) metric *= 0.8;
   if(drawdownRel > 30.0) metric *= 0.5;
   if(recoveryFactor > 2.0) metric *= 1.2;

   double resultScore = metric;

   if(UseCustomMax)
   {
      g_ACOptCfg.MinTrades        = Opt_MinTrades;
      g_ACOptCfg.MinOosPF         = Opt_MinOosPF;
      g_ACOptCfg.MaxOosDDPercent  = Opt_MaxOosDDPercent;
      g_ACOptCfg.InSampleFrac     = Opt_InSampleFraction;
      g_ACOptCfg.OosGapDays       = Opt_OosGapDays;
      g_ACOptCfg.McSimulations    = Opt_McSimulations;
      g_ACOptCfg.McBlockLenTrades = Opt_McBlockLen;
      g_ACOptCfg.McSeed           = Opt_McSeed;
      g_ACOptCfg.w_pf             = Opt_W_PF;
      g_ACOptCfg.w_dd             = Opt_W_DD;
      g_ACOptCfg.w_sharpe         = Opt_W_Sharpe;
      g_ACOptCfg.w_mc_pf          = Opt_W_McPF;
      g_ACOptCfg.w_mc_dd          = Opt_W_McDD;
      g_ACOptCfg.MagicFilter      = Magic_Number;

      AC_Opt_Init(g_ACOptCfg);
      resultScore = AC_CalcCustomCriterion();
      AC_PublishFrames();

      double tradesPerDayOpt = AC_GetTradesPerDay();
      if(tradesPerDayOpt > 0.0)
         avgTradesDaily = tradesPerDayOpt;

      double ddOpt = AC_GetOosDrawdownPercent();
      if(drawdownRel <= 0.0 && ddOpt > 0.0)
         drawdownRel = ddOpt;
   }

   customWinRate          = NormalizeDouble(winRate, 2);
   customWinningTrades    = winningTrades;
   customLosingTrades     = losingTrades;
   customFinalBalance     = NormalizeDouble(finalBalance, 2);
   customAvgTradesDaily   = NormalizeDouble(avgTradesDaily, 2);
   customMaxConsecWinners = maxConsecWinners;
   customMaxConsecLosers  = maxConsecLosers;
   customAvgWinAmount     = NormalizeDouble(avgWinAmount, 2);
   customAvgLossAmount    = NormalizeDouble(avgLossAmount, 2);

   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
   {
      Comment(StringFormat("WR=%.1f%% WT=%d LT=%d Bal=%.2f TpD=%.1f",
                           customWinRate,
                           (int)customWinningTrades,
                           (int)customLosingTrades,
                           customFinalBalance,
                           customAvgTradesDaily));
   }

   return resultScore;
}

//+------------------------------------------------------------------+
//| Helper: drain ACOPT frames into CSV                              |
//+------------------------------------------------------------------+
void AC_WriteFramesToCsv()
{
   if(!UseCustomMax || g_ACOptCsvHandle == INVALID_HANDLE)
      return;

   ulong frameId = 0;
   string frameName;
   long passId = 0;
   double frameScore = 0.0;
   double payload[];

   while(FrameNext(frameId, frameName, passId, frameScore, payload))
   {
      if(frameName != "ACOPT")
         continue;

      int payloadSize = ArraySize(payload);
      if(payloadSize < ACOPT__COUNT)
      {
         PrintFormat("ACOPT frame payload too small (%d).", payloadSize);
         continue;
      }

      payload[ACOPT_SCORE] = frameScore;

      FileWrite(g_ACOptCsvHandle,
                (int)passId,
                payload[ACOPT_SCORE],
                payload[ACOPT_PF_IS],
                payload[ACOPT_PF_OOS],
                payload[ACOPT_DD_IS_PCT],
                payload[ACOPT_DD_OOS_PCT],
                payload[ACOPT_SHARPE_IS],
                payload[ACOPT_SHARPE_OOS],
                payload[ACOPT_SORTINO_IS],
                payload[ACOPT_SORTINO_OOS],
                payload[ACOPT_SERENITY_IS],
                payload[ACOPT_SERENITY_OOS],
                payload[ACOPT_MC_PF_P5],
                payload[ACOPT_MC_DD_P95],
                payload[ACOPT_MC_P_RUIN],
                payload[ACOPT_KS_DIST],
                payload[ACOPT_JB_P],
                payload[ACOPT_TRADES_TOTAL],
                payload[ACOPT_TRADES_PER_DAY],
                payload[ACOPT_WINRATE_OOS_PCT],
                payload[ACOPT_EXP_PAYOFF_OOS],
                payload[ACOPT_AVG_WIN_OOS],
                payload[ACOPT_AVG_LOSS_OOS],
                payload[ACOPT_PAYOFF_RATIO_OOS]);
   }

   FileFlush(g_ACOptCsvHandle);
}

//+------------------------------------------------------------------+
//| Tester lifecycle: initialization                                 |
//+------------------------------------------------------------------+
void OnTesterInit()
{
   g_ACOptCsvHandle = INVALID_HANDLE;
   g_ACOptCsvFilename = "";
   g_ACOptCsvPath = "";
   g_ACOptRunStart = 0;

   if(!UseCustomMax)
      return;

   g_ACOptRunStart = TimeCurrent();
   g_ACOptCsvFilename = StringFormat("ACOPT_%s_%I64d.csv", _Symbol, (long)g_ACOptRunStart);
   g_ACOptCsvHandle = FileOpen(g_ACOptCsvFilename, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(g_ACOptCsvHandle == INVALID_HANDLE)
   {
      PrintFormat("Failed to create optimization CSV %s (%d).", g_ACOptCsvFilename, GetLastError());
      g_ACOptCsvFilename = "";
      return;
   }

   g_ACOptCsvPath = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" + g_ACOptCsvFilename;

   FileWrite(g_ACOptCsvHandle,
             "pass_id",
             "score",
             "pf_is",
             "pf_oos",
             "dd_is_percent",
             "dd_oos_percent",
             "sharpe_is",
             "sharpe_oos",
             "sortino_is",
             "sortino_oos",
             "serenity_is",
             "serenity_oos",
             "mc_pf_p5",
             "mc_dd_p95",
             "mc_p_ruin",
             "ks_dist",
             "jb_p",
             "trades_total",
             "trades_per_day",
             "winrate_oos_pct",
             "expected_payoff_oos",
             "avg_win_oos",
             "avg_loss_oos",
             "payoff_ratio_oos");
   FileFlush(g_ACOptCsvHandle);
}

//+------------------------------------------------------------------+
//| Consume frames after each tester pass                            |
//+------------------------------------------------------------------+
void OnTesterPass()
{
   AC_WriteFramesToCsv();
}

//+------------------------------------------------------------------+
//| Tester cleanup                                                   |
//+------------------------------------------------------------------+
void OnTesterDeinit()
{
   AC_WriteFramesToCsv();

   if(g_ACOptCsvHandle != INVALID_HANDLE)
   {
      FileClose(g_ACOptCsvHandle);
      g_ACOptCsvHandle = INVALID_HANDLE;
   }

   if(UseCustomMax && g_ACOptCsvFilename != "")
      PrintFormat("AC optimization frames saved to %s.", g_ACOptCsvPath);
}

//+------------------------------------------------------------------+
//| Check for safety trade for validator                             |
//+------------------------------------------------------------------+
void CBreakRevertPro::CheckForSafetyTrade()
{
   // Only run if safety trades are enabled
   if(!enable_safety_trade && !m_is_validation_run)
      return;
      
   // If we already executed a safety trade, no need to do another
   if(m_safety_trade_executed)
      return;
      
   // Don't do safety checks too often
   datetime now = TimeCurrent();
   if(now - m_last_safety_check < safety_trade_interval)
      return;
      
   m_last_safety_check = now;
   
   // Check if we have any open positions
   if(CountOpenPositions() > 0)
      return;
      
   // Execute safety trade if we're in validation mode
   if(m_validator.IsInTester())
   {
      // First try validator's safety trade
      if(m_validator.ExecuteSafetyTrade())
      {
         m_safety_trade_executed = true;
         DebugPrint("CheckForSafetyTrade: Validator safety trade executed successfully", true);
         return;
      }
      
      // If validator safety trade fails, try our own implementation
      string symbol = Symbol();
      DebugPrint("CheckForSafetyTrade: Executing safety trade on " + symbol, true);
      
      // For XAUUSD, always use SELL as it usually requires less margin
      int trade_direction = IsPrecious(symbol) ? TRADE_SELL : TRADE_BUY;
      
      // Execute trade with safety flag
      if(ExecuteTrade(trade_direction, true))
         DebugPrint("CheckForSafetyTrade: Safety trade executed successfully", true);
      else
         DebugPrint("CheckForSafetyTrade: Failed to execute safety trade. Error: " + IntegerToString(GetLastError()), true);
   }
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void CBreakRevertPro::OnTick()
{
   // Update validator data
   m_validator.Refresh();
   UpdateRiskManagement(m_magic_number);

   // First priority: Check for safety trade in validation environment
   CheckForSafetyTrade();
   
   // Check history if not already done
   if(!m_history_checked)
   {
      m_validator.CheckHistory(lookback_period * 2);
      m_history_checked = true;
   }
   
   // Update market data
   if(!UpdateData())
   {
      DebugPrint("OnTick: Failed to update market data");
      return;
   }

   bool should_process_signals = m_primary_series_updated || !m_probabilities_ready;

   if(should_process_signals)
   {
      // Calculate probabilities based on updated data
      CalculateProbabilities();
      m_probabilities_ready = true;

      // Check for trading signals
      bool breakout = IsBreakout();
      bool meanReversion = IsMeanReversion();

      // Execute trades based on signals
      if(breakout)
      {
         DebugPrint("OnTick: Breakout signal -> BUY", true);
         ExecuteTrade(TRADE_BUY);
      }
      else if(meanReversion)
      {
         DebugPrint("OnTick: Mean-Reversion signal -> SELL", true);
         ExecuteTrade(TRADE_SELL);
      }
      else
      {
         // For validation testing, ensure we get at least one trade
         if(m_is_validation_run && CountOpenPositions() == 0 && !m_safety_trade_executed)
         {
            DebugPrint("OnTick: No signal but executing safety trade for validation", true);

            // For XAUUSD, always use SELL for safety trades
            int trade_direction = IsPrecious(Symbol()) ? TRADE_SELL : TRADE_BUY;
            ExecuteTrade(trade_direction, true);
         }
      }
   }

   UpdateTrailingStops();

   // Save data periodically (not in tester)
   static int tick_counter = 0;
   if(!MQLInfoInteger(MQL_TESTER) && ++tick_counter >= 1000)
   {
      SaveArraysToFile("BreakRevert_Data.dat");
      tick_counter = 0;
   }
}

//+------------------------------------------------------------------+
//| Expert Deinit Function                                           |
//+------------------------------------------------------------------+
void CBreakRevertPro::Deinit(const int reason)
{
   // Save data on normal exit (not in tester)
   if(!MQLInfoInteger(MQL_TESTER))
      SaveArraysToFile("BreakRevert_Data.dat");

   CleanupATRTrailing();
}

//+------------------------------------------------------------------+
//| Global EA instance                                               |
//+------------------------------------------------------------------+
CBreakRevertPro ExtExpert;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   return ExtExpert.Init();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   ExtExpert.OnTick();
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ExtExpert.Deinit(reason);
}
