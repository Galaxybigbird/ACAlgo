//+------------------------------------------------------------------+
//|                              MainACAlgorithm_CustomCriterion.mq5 |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.45"
#property strict
#property description "Main trading EA with Asymmetrical Compounding Risk Management"

// Include necessary libraries
#include <Trade/Trade.mqh>
#include <ACFunctions.mqh>      // Position sizing and risk management
#include <ATRtrailing.mqh>      // Trailing stop functionality
// Include indicators as direct calculation libraries
#include <T3.mqh>               // T3 indicator calculations
#include <vwap_lite.mqh>        // VWAP indicator calculations
#include <EngulfingSignals.mqh>       // Engulfing pattern detection
#include <EngulfingStochastic.mqh>    // Engulfing + Stochastic combo
#include <QQEIndicator.mqh>           // QQE signal calculations
#include <SuperTrendIndicator.mqh>    // SuperTrend trend detection
#include <FiboZigZag.mqh>             // Fibonacci ZigZag detection
#include <IntrabarVolume.mqh>         // Intrabar volume filter
#include <TotalPowerIndicator.mqh>    // Total power indicator filter
#include <AC_OptCriterion.mqh>        // Custom optimization criterion
#include <SymbolValidator.mqh>


CSymbolValidator g_SymbolValidator;   // Shared symbol environment helper
ACOptConfig g_ACOptCfg;               // Configuration for custom optimization criterion

// Custom enum for VWAP timeframes with DISABLED option
enum ENUM_VWAP_TIMEFRAMES
{
   VWAP_DISABLED = -1,      // Disabled (Don't use this timeframe)
   VWAP_M1 = PERIOD_M1,     // 1 Minute
   VWAP_M2 = PERIOD_M2,     // 2 Minutes
   VWAP_M3 = PERIOD_M3,     // 3 Minutes
   VWAP_M4 = PERIOD_M4,     // 4 Minutes
   VWAP_M5 = PERIOD_M5,     // 5 Minutes
   VWAP_M6 = PERIOD_M6,     // 6 Minutes
   VWAP_M10 = PERIOD_M10,   // 10 Minutes
   VWAP_M12 = PERIOD_M12,   // 12 Minutes
   VWAP_M15 = PERIOD_M15,   // 15 Minutes
   VWAP_M20 = PERIOD_M20,   // 20 Minutes
   VWAP_M30 = PERIOD_M30,   // 30 Minutes
   VWAP_H1 = PERIOD_H1,     // 1 Hour
   VWAP_H2 = PERIOD_H2,     // 2 Hours
   VWAP_H3 = PERIOD_H3,     // 3 Hours
   VWAP_H4 = PERIOD_H4,     // 4 Hours
   VWAP_H6 = PERIOD_H6,     // 6 Hours
   VWAP_H8 = PERIOD_H8,     // 8 Hours
   VWAP_H12 = PERIOD_H12,   // 12 Hours
   VWAP_D1 = PERIOD_D1,     // Daily
   VWAP_W1 = PERIOD_W1,     // Weekly
   VWAP_MN1 = PERIOD_MN1    // Monthly
};

// Trade direction bias control
enum ENUM_TRADE_BIAS
{
   Both      = 0,   // Both
   LongOnly  = 1,   // LongOnly
   ShortOnly = 2    // ShortOnly
};

//--- Performance Optimization Settings
input group "==== Performance Settings ===="
input bool     OptimizationMode = true;  // Enable optimization mode for faster backtesting
input int      UpdateFrequency = 5;      // Update indicators every X ticks in backtest mode

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

//--- Input Parameters for Trading
input group "==== Trading Settings ===="
input double   DefaultLot = 0.01;       // Default lot size if risk calculation fails
input int      Slippage = 20;           // Allowed slippage in points
input int      MagicNumber = 12345;     // Magic number for this EA
input bool     UseTakeProfit = true;   // Enable TP at reward?

//--- Risk Management Settings
input group "==== Risk Management Settings ===="
input bool     UseACRiskManagement = true; // Enable AC risk management (false = use fixed lot size)

//--- Stop Tightening Settings
input group "==== Stop Tightening Settings ===="
input int      MaxHoldBars = 0;            // Max bars of ATR range to allow for initial stop (0 = disabled)

// Note: AC risk parameters are defined in ACFunctions.mqh
// They will appear in the inputs dialog automatically
// AC_BaseRisk, AC_BaseReward, AC_CompoundingWins, ATRPeriod, ATRMultiplier, MaxStopLossDistance

//--- T3 Indicator Settings
input group "==== T3 Indicator Settings ===="
input bool     UseT3Indicator = true;   // Use T3 indicator for entry signals
input int      T3_Length = 12;          // Period length for T3 calculation
input double   T3_Factor = 0.7;         // Volume factor for T3 calculation
input ENUM_APPLIED_PRICE T3_Applied_Price = PRICE_CLOSE; // Price type for T3
input bool     T3_UseTickPrecision = false; // Use tick-level precision for T3 (slower but more accurate)
input bool     UseT3VWAPFilter = true;  // Use T3 vs VWAP crossover as a signal filter

//--- VWAP Indicator Settings
input group "==== VWAP Indicator Settings ===="
input bool     UseVWAPIndicator = true; // Use VWAP indicator for entry signals
input bool     Enable_Daily_VWAP = true;     // Enable Daily VWAP
input ENUM_VWAP_TIMEFRAMES VWAP_Timeframe1 = VWAP_M1;  // VWAP Timeframe 1
input ENUM_VWAP_TIMEFRAMES VWAP_Timeframe2 = VWAP_M5;   // VWAP Timeframe 2
input ENUM_VWAP_TIMEFRAMES VWAP_Timeframe3 = VWAP_M15;   // VWAP Timeframe 3
input ENUM_VWAP_TIMEFRAMES VWAP_Timeframe4 = VWAP_DISABLED; // VWAP Timeframe 4 (DISABLED = don't use)
input ENUM_VWAP_TIMEFRAMES VWAP_Timeframe5 = VWAP_DISABLED; // VWAP Timeframe 5
input ENUM_VWAP_TIMEFRAMES VWAP_Timeframe6 = VWAP_DISABLED; // VWAP Timeframe 6
input ENUM_VWAP_TIMEFRAMES VWAP_Timeframe7 = VWAP_DISABLED; // VWAP Timeframe 7
input ENUM_VWAP_TIMEFRAMES VWAP_Timeframe8 = VWAP_DISABLED; // VWAP Timeframe 8
input ENUM_APPLIED_PRICE VWAP_Price_Type = PRICE_CLOSE; // Price type for VWAP
input bool     VWAP_UseTickPrecision = false; // Use tick-level precision for VWAP (slower but more accurate)

//--- Entry Signal Settings
input group "==== Entry Signal Settings ===="
input int      SignalConfirmationBars = 2;  // Number of bars to confirm signal
input int      MinSignalsToEnterLong = 1;     // Minimum aligned signals required for long entries
input int      MinSignalsToEnterShort = 1;    // Minimum aligned signals required for short entries
input int      MinSignalsToEnterBoth = 1;     // Minimum aligned signals when both directions allowed
input ENUM_TRADE_BIAS TradeDirectionBias = Both; // Directional bias filter

//--- Engulfing Pattern Settings
input group "==== Engulfing Pattern Settings ===="
input bool     UseEngulfingPattern = false;           // Enable basic engulfing pattern signal

//--- Engulfing + Stochastic Settings
input group "==== Engulfing Stochastic Settings ===="
input bool     UseEngulfingStochastic = false;        // Enable engulfing + stochastic confirmation
input int      EngulfingStoch_OverSold = 20;          // Oversold threshold
input int      EngulfingStoch_OverBought = 80;        // Overbought threshold
input int      EngulfingStoch_KPeriod = 5;            // Stochastic K period
input int      EngulfingStoch_DPeriod = 3;            // Stochastic D period
input int      EngulfingStoch_Slowing = 3;            // Stochastic slowing
input ENUM_MA_METHOD EngulfingStoch_MAMethod = MODE_SMA; // Smoothing method
input ENUM_STO_PRICE EngulfingStoch_PriceField = STO_LOWHIGH; // Price field for stochastic
input ENUM_TIMEFRAMES EngulfingStoch_Timeframe = PERIOD_CURRENT; // Timeframe override

//--- QQE Indicator Settings
input group "==== QQE Indicator Settings ===="
input bool     UseQQEIndicator = false;               // Enable QQE filter
input int      QQE_RSI_Period = 14;                   // RSI period
input int      QQE_SmoothingFactor = 5;               // QQE smoothing factor (SF)
input double   QQE_AlertLevel = 50.0;                 // Alert level threshold
input bool     QQE_RequireLevelFilter = true;         // Require level alignment with alert level
input ENUM_TIMEFRAMES QQE_Timeframe = PERIOD_CURRENT; // QQE timeframe

//--- SuperTrend Settings
input group "==== SuperTrend Settings ===="
input bool     UseSuperTrendIndicator = false;        // Enable SuperTrend direction filter
input int      SuperTrend_ATRPeriod = 22;             // ATR period for SuperTrend
input double   SuperTrend_Multiplier = 3.0;           // ATR multiplier
input ENUM_APPLIED_PRICE SuperTrend_PriceSource = PRICE_MEDIAN; // Base price
input bool     SuperTrend_TakeWicks = true;           // Include full wick range
input ENUM_TIMEFRAMES SuperTrend_Timeframe = PERIOD_CURRENT;    // Timeframe override

//--- Fibo ZigZag Settings
input group "==== Fibo ZigZag Settings ===="
input bool     UseFiboZigZagFilter = false;         // Enable Fibonacci ZigZag confirmation
input double   FiboRetracement = 23.6;              // Minimum retracement percentage to flip trend
input double   FiboMinWaveATR = 0.5;                // Minimum wave size in ATR units
input int      FiboATRPeriod = 14;                  // ATR lookback for wave sizing
input bool     FiboUseHighLowPrice = true;          // Use high/low extremes instead of closes
input bool     FiboUseATRFilter = true;             // Enforce ATR-sized wave threshold
input bool     FiboRequireConfirmation = false;     // Require signal to persist for N bars
input int      FiboConfirmationBars = 1;            // Bars required for confirmation (if enabled)

//--- Intrabar Volume Settings
input group "==== Intrabar Volume Settings ===="
input bool     UseIntrabarVolumeFilter = false;     // Enable intrabar volume confirmation
input int      IntrabarVolumePeriod = 20;           // Moving average period for trend detection
input int      IntrabarVolumeLookback = 20;         // Lookback for volume threshold
input bool     IntrabarGranularTrend = false;       // Use granular trend (close vs previous close)
input bool     IntrabarRequireVolume = true;        // Require tick volume to exceed threshold

//--- Total Power Indicator Settings
input group "==== Total Power Indicator Settings ===="
input bool     UseTotalPowerFilter = false;         // Enable Total Power confirmation
input int      TPILookbackPeriod = 45;              // Lookback period for power calculation
input int      TPIPowerPeriod = 10;                 // Power period for Bears/Bulls
input bool     TPIUseHundredSignal = false;         // Signal on 100% dominance
input bool     TPIUseCrossoverSignal = false;       // Signal on bull/bear crossover
input int      TPITriggerCandle = 1;                // Candle shift for evaluation (0=current,1=previous)

//--- Custom Results For Optimization (These will show in optimization results)
//input group "==== Custom Optimization Results ===="
// These are now just display items, we'll use actual globals for calculations
string _OptimizationNote = "Optimization statistics are shown in the Experts tab";  // Note about optimization results

// Global variables to store optimization results (not inputs)
double g_WinRate = 0;            // Win rate for optimization results
double g_WinTrades = 0;          // Number of winning trades
double g_LossTrades = 0;         // Number of losing trades
double g_FinalBalance = 0;       // Final account balance
double g_AvgTradesDaily = 0;     // Average trades per day
double g_MaxConsecWins = 0;      // Maximum consecutive winners
double g_MaxConsecLoss = 0;      // Maximum consecutive losers
double g_AvgWinAmount = 0;       // Average win amount
double g_AvgLossAmount = 0;      // Average loss amount
int      g_ACOptCsvHandle = INVALID_HANDLE;
string   g_ACOptCsvFilename = "";
string   g_ACOptCsvPath = "";
datetime g_ACOptRunStart = 0;

//--- Global Variables
CTrade trade;                      // Trade object for executing trades
// Indicator instances
CT3Indicator T3;                // T3 indicator instance
CVWAPIndicator VWAP;            // VWAP indicator instance
CEngulfingSignalDetector EngulfingDetector;        // Basic engulfing pattern helper
CEngulfingStochasticSignal EngulfingStochSignal;   // Engulfing + stochastic combo
CQQEIndicator QQESignal;                           // QQE signal helper
CSuperTrendIndicator SuperTrendSignal;             // SuperTrend helper
CFiboZigZag FiboZigZagSignal;                      // Fibonacci ZigZag helper
CIntrabarVolumeIndicator IntrabarVolumeSignal;      // Intrabar volume helper
CTotalPowerIndicator TotalPowerSignal;              // Total power indicator helper

// Indicator buffers
double T3Buffer[];                 // Buffer for T3 indicator values
double VWAPDailyBuffer[];          // Buffer for VWAP Daily values
double VWAPTF1Buffer[];            // Buffer for VWAP Timeframe 1 values
double VWAPTF2Buffer[];            // Buffer for VWAP Timeframe 2 values
double VWAPTF3Buffer[];            // Buffer for VWAP Timeframe 3 values
double VWAPTF4Buffer[];            // Buffer for VWAP Timeframe 4 values
double VWAPTF5Buffer[];            // Buffer for VWAP Timeframe 5 values
double VWAPTF6Buffer[];            // Buffer for VWAP Timeframe 6 values
double VWAPTF7Buffer[];            // Buffer for VWAP Timeframe 7 values
double VWAPTF8Buffer[];            // Buffer for VWAP Timeframe 8 values

// Price arrays for indicators
double priceDataT3[];
double priceDataVWAP[];
MqlRates priceRates[];  // Renamed from 'rates' to avoid conflicts

// Previous indicator values for signal detection
double prevT3 = 0;
double currT3 = 0;
double prevVWAPDaily = 0;
double currVWAPDaily = 0;
double prevVWAPTF1 = 0;
double currVWAPTF1 = 0;
double prevVWAPTF2 = 0;
double currVWAPTF2 = 0;
double prevVWAPTF3 = 0;
double currVWAPTF3 = 0;
double prevVWAPTF4 = 0;
double currVWAPTF4 = 0;
double prevVWAPTF5 = 0;
double currVWAPTF5 = 0;
double prevVWAPTF6 = 0;
double currVWAPTF6 = 0;
double prevVWAPTF7 = 0;
double currVWAPTF7 = 0;
double prevVWAPTF8 = 0;
double currVWAPTF8 = 0;

// Additional indicator state
int    g_T3VWAPSignal = 0;
int    g_EngulfingSignal = 0;
int    g_EngulfingStochSignal = 0;
int    g_QQESignal = 0;
int    g_SuperTrendSignal = 0;
int    g_FiboZigZagSignal = 0;
int    g_IntrabarVolumeSignal = 0;
int    g_TotalPowerSignal = 0;
double g_QQERsiMA = 0.0;
double g_QQETrLevel = 0.0;
double g_SuperTrendValue = 0.0;

bool   g_EngulfingStochReady = false;
bool   g_QQEReady = false;
bool   g_SuperTrendReady = false;
bool   g_FiboZigZagReady = false;
bool   g_TotalPowerReady = false;

// Optimization variables
datetime lastBarTime = 0;           // Time of the last processed bar
int tickCounter = 0;                // Counter for updating on specific ticks
bool isInBacktest = false;          // Flag for backtest mode
bool isForwardTest = false;         // Flag for forward test stage during optimization
bool isFastModeContext = false;     // Indicates optimization/forward contexts where we throttle work
bool processEveryTick = false;      // Controls whether we evaluate logic on every tick

// Custom optimization reporting parameters
double customWinRate = 0;            // Win rate for optimization results
double customWinningTrades = 0;      // Number of winning trades
double customLosingTrades = 0;       // Number of losing trades
double customFinalBalance = 0;       // Final account balance
double customAvgTradesDaily = 0;     // Average trades per day
double customMaxConsecWinners = 0;   // Maximum consecutive winners
double customMaxConsecLosers = 0;    // Maximum consecutive losers
double customAvgWinAmount = 0;       // Average win amount
double customAvgLossAmount = 0;      // Average loss amount

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Determine tester context flags up front
   bool isOptimizationPass = (MQLInfoInteger(MQL_OPTIMIZATION) == 1);
   bool isTesterPass = (MQLInfoInteger(MQL_TESTER) == 1);
   isForwardTest = (MQLInfoInteger(MQL_FORWARD) == 1);
   
   // Treat both optimization and forward phases as "fast mode" to throttle heavy work
   isInBacktest = isOptimizationPass || isTesterPass;
   isFastModeContext = isInBacktest && (OptimizationMode || isForwardTest);
   processEveryTick = !isFastModeContext;
   
   // Initialize the trade object
   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Initialize risk management system
   InitializeACRiskManagement();
   
   // Initialize ATR trailing stop system
   InitDEMAATR();
   
   // Initialize T3 indicator
   if(UseT3Indicator)
   {
      // Initialize price arrays for T3
      ArraySetAsSeries(priceDataT3, true);
      ArrayResize(priceDataT3, isFastModeContext ? 200 : 1000);
      
      // Initialize the T3 indicator class
      T3.Init(T3_Length, T3_Factor, T3_Applied_Price, T3_UseTickPrecision);
      
      // Allocate memory for T3 buffer
      ArraySetAsSeries(T3Buffer, true);
      ArrayResize(T3Buffer, isFastModeContext ? 10 : 100);
   }
   
   // Initialize VWAP indicator
   if(UseVWAPIndicator)
   {
      // Map ENUM_APPLIED_PRICE to PRICE_TYPE for VWAP
      PRICE_TYPE priceType;
      switch(VWAP_Price_Type)
      {
         case PRICE_OPEN:  priceType = OPEN; break;
         case PRICE_CLOSE: priceType = CLOSE; break;
         case PRICE_HIGH:  priceType = HIGH; break;
         case PRICE_LOW:   priceType = LOW; break;
         case PRICE_MEDIAN: priceType = HIGH_LOW; break;
         case PRICE_TYPICAL: priceType = CLOSE_HIGH_LOW; break;
         case PRICE_WEIGHTED: priceType = OPEN_CLOSE_HIGH_LOW; break;
         default: priceType = CLOSE; break;
      }
      
      // In backtest mode, force disable tick precision for VWAP to improve performance
      bool useTickPrecision = isFastModeContext ? false : VWAP_UseTickPrecision;
      
      // Convert custom timeframe enums to standard ENUM_TIMEFRAMES
      ENUM_TIMEFRAMES tf1 = (VWAP_Timeframe1 == VWAP_DISABLED) ? 
                           PERIOD_CURRENT : (ENUM_TIMEFRAMES)VWAP_Timeframe1;
      ENUM_TIMEFRAMES tf2 = (VWAP_Timeframe2 == VWAP_DISABLED) ? 
                           PERIOD_CURRENT : (ENUM_TIMEFRAMES)VWAP_Timeframe2;
      ENUM_TIMEFRAMES tf3 = (VWAP_Timeframe3 == VWAP_DISABLED) ? 
                           PERIOD_CURRENT : (ENUM_TIMEFRAMES)VWAP_Timeframe3;
      ENUM_TIMEFRAMES tf4 = (VWAP_Timeframe4 == VWAP_DISABLED) ? 
                           PERIOD_CURRENT : (ENUM_TIMEFRAMES)VWAP_Timeframe4;
      ENUM_TIMEFRAMES tf5 = (VWAP_Timeframe5 == VWAP_DISABLED) ? 
                           PERIOD_CURRENT : (ENUM_TIMEFRAMES)VWAP_Timeframe5;
      ENUM_TIMEFRAMES tf6 = (VWAP_Timeframe6 == VWAP_DISABLED) ? 
                           PERIOD_CURRENT : (ENUM_TIMEFRAMES)VWAP_Timeframe6;
      ENUM_TIMEFRAMES tf7 = (VWAP_Timeframe7 == VWAP_DISABLED) ? 
                           PERIOD_CURRENT : (ENUM_TIMEFRAMES)VWAP_Timeframe7;
      ENUM_TIMEFRAMES tf8 = (VWAP_Timeframe8 == VWAP_DISABLED) ? 
                           PERIOD_CURRENT : (ENUM_TIMEFRAMES)VWAP_Timeframe8;
      
      // Initialize the VWAP indicator class
      VWAP.Init(priceType, Enable_Daily_VWAP, tf1, tf2, tf3, tf4, tf5, tf6, tf7, tf8, useTickPrecision);
      
      // Initialize price arrays for VWAP and prepare MqlRates for bar data
      ArraySetAsSeries(priceRates, true);
      
      // Allocate memory for VWAP buffers
      ArraySetAsSeries(VWAPDailyBuffer, true);
      ArraySetAsSeries(VWAPTF1Buffer, true);
      ArraySetAsSeries(VWAPTF2Buffer, true);
      ArraySetAsSeries(VWAPTF3Buffer, true);
      ArraySetAsSeries(VWAPTF4Buffer, true);
      ArraySetAsSeries(VWAPTF5Buffer, true);
      ArraySetAsSeries(VWAPTF6Buffer, true);
      ArraySetAsSeries(VWAPTF7Buffer, true);
      ArraySetAsSeries(VWAPTF8Buffer, true);
      
      int bufferSize = isFastModeContext ? 10 : 100;
      
      ArrayResize(VWAPDailyBuffer, bufferSize);
      ArrayResize(VWAPTF1Buffer, bufferSize);
      ArrayResize(VWAPTF2Buffer, bufferSize);
      ArrayResize(VWAPTF3Buffer, bufferSize);
      ArrayResize(VWAPTF4Buffer, bufferSize);
      ArrayResize(VWAPTF5Buffer, bufferSize);
      ArrayResize(VWAPTF6Buffer, bufferSize);
      ArrayResize(VWAPTF7Buffer, bufferSize);
      ArrayResize(VWAPTF8Buffer, bufferSize);
   }

   // Initialize additional signal modules
   EngulfingDetector.Reset();
   g_EngulfingSignal = 0;

   EngulfingStochSignal.Shutdown();
   g_EngulfingStochSignal = 0;
   g_EngulfingStochReady = false;
   if(UseEngulfingStochastic)
   {
      g_EngulfingStochReady = EngulfingStochSignal.Init(_Symbol,
                                                        EngulfingStoch_Timeframe,
                                                        EngulfingStoch_OverSold,
                                                        EngulfingStoch_OverBought,
                                                        EngulfingStoch_KPeriod,
                                                        EngulfingStoch_DPeriod,
                                                        EngulfingStoch_Slowing,
                                                        EngulfingStoch_MAMethod,
                                                        EngulfingStoch_PriceField);

      if(!g_EngulfingStochReady)
         Print("[Init] Engulfing stochastic module failed to initialise - signal disabled.");
   }

   QQESignal.Shutdown();
   g_QQEReady = false;
   g_QQESignal = 0;
   if(UseQQEIndicator)
   {
      g_QQEReady = QQESignal.Init(_Symbol,
                                   QQE_Timeframe,
                                   QQE_RSI_Period,
                                   QQE_SmoothingFactor,
                                   QQE_AlertLevel,
                                   QQE_RequireLevelFilter);

      if(!g_QQEReady)
         Print("[Init] QQE module failed to initialise - signal disabled.");
   }

   SuperTrendSignal.Shutdown();
   g_SuperTrendReady = false;
   g_SuperTrendSignal = 0;
   if(UseSuperTrendIndicator)
   {
      g_SuperTrendReady = SuperTrendSignal.Init(_Symbol,
                                                SuperTrend_Timeframe,
                                                SuperTrend_ATRPeriod,
                                                SuperTrend_Multiplier,
                                                SuperTrend_PriceSource,
                                                SuperTrend_TakeWicks);

      if(!g_SuperTrendReady)
         Print("[Init] SuperTrend module failed to initialise - signal disabled.");
   }

   g_FiboZigZagSignal = 0;
   g_IntrabarVolumeSignal = 0;
   g_TotalPowerSignal = 0;
   g_FiboZigZagReady = false;
   g_TotalPowerReady = false;
   if(UseFiboZigZagFilter)
   {
      FiboZigZagSignal.Init(FiboRetracement, FiboMinWaveATR, FiboATRPeriod,
                            FiboUseHighLowPrice, FiboUseATRFilter,
                            FiboRequireConfirmation, FiboConfirmationBars);
      g_FiboZigZagReady = true;
   }

   IntrabarVolumeSignal.Init(IntrabarVolumePeriod, IntrabarVolumeLookback,
                             IntrabarGranularTrend, IntrabarRequireVolume);

   if(UseTotalPowerFilter)
   {
      g_TotalPowerReady = TotalPowerSignal.Init(_Symbol, PERIOD_CURRENT,
                                                TPILookbackPeriod, TPIPowerPeriod,
                                                TPIUseHundredSignal, TPIUseCrossoverSignal,
                                                TPITriggerCandle);
      if(!g_TotalPowerReady)
         Print("[Init] Total Power Indicator failed to initialise - signal disabled.");
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Set the optimization inputs to display our custom metrics in optimization results
   // Release ATR trailing resources
   CleanupATRTrailing();

   // Release aux indicator resources
   EngulfingStochSignal.Shutdown();
   QQESignal.Shutdown();
   SuperTrendSignal.Shutdown();
   FiboZigZagSignal.ResetState();
   g_FiboZigZagReady = false;
   g_FiboZigZagSignal = 0;
   TotalPowerSignal.Shutdown();
   g_TotalPowerReady = false;
   g_TotalPowerSignal = 0;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only update trailing stops when necessary
   if(isFastModeContext)
   {
      tickCounter++;
      // Only update on specific ticks to reduce processing load during backtesting
      if(tickCounter < UpdateFrequency)
         return;
         
      tickCounter = 0;
   }
   
   // Get the current bar time
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // Check if we have a new bar or if we should process this tick
   bool newBar = currentBarTime != lastBarTime;
   
   // Update trailing stops for all open positions
   UpdateAllTrailingStops(newBar);
   
   // Update indicators only on new bars or when not in optimization mode
   if(newBar || processEveryTick)
   {
      lastBarTime = currentBarTime;
      UpdateIndicators();
   
      // Evaluate strategy signals each new bar
      CheckForTradingSignals();
   }
}

//+------------------------------------------------------------------+
//| Update indicator values                                          |
//+------------------------------------------------------------------+
void UpdateIndicators()
{
   // Get current price data - optimized to use smaller buffer in backtest mode
   int barsToRequest = isFastModeContext ? 20 : 100;
   int requiredBars = 0;
   requiredBars = MathMax(requiredBars, FiboATRPeriod + FiboConfirmationBars + 5);
   requiredBars = MathMax(requiredBars, IntrabarVolumeLookback + IntrabarVolumePeriod + 5);
   requiredBars = MathMax(requiredBars, TPILookbackPeriod + TPIPowerPeriod + TPITriggerCandle + 5);
   requiredBars = MathMax(requiredBars, T3_Length + 5);
   if(barsToRequest < requiredBars)
      barsToRequest = requiredBars;
   
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, barsToRequest, priceRates) <= 0)
   {
      Print("Error copying rates data: ", GetLastError());
      return;
   }
   ArraySetAsSeries(priceRates, true);
   int ratesCount = ArraySize(priceRates);
   
   // Update T3 indicator values if enabled
   if(UseT3Indicator)
   {
      // Prepare price array based on selected price type - only resize if absolutely necessary
      if(ArraySize(priceDataT3) < ratesCount)
         ArrayResize(priceDataT3, ratesCount);
      
      for(int i = 0; i < ratesCount; i++)
      {
         switch(T3_Applied_Price)
         {
            case PRICE_CLOSE:  priceDataT3[i] = priceRates[i].close; break;
            case PRICE_OPEN:   priceDataT3[i] = priceRates[i].open; break;
            case PRICE_HIGH:   priceDataT3[i] = priceRates[i].high; break;
            case PRICE_LOW:    priceDataT3[i] = priceRates[i].low; break;
            case PRICE_MEDIAN: priceDataT3[i] = (priceRates[i].high + priceRates[i].low) / 2; break;
            case PRICE_TYPICAL: priceDataT3[i] = (priceRates[i].high + priceRates[i].low + priceRates[i].close) / 3; break;
            case PRICE_WEIGHTED: priceDataT3[i] = (priceRates[i].high + priceRates[i].low + priceRates[i].close + priceRates[i].open) / 4; break;
            default: priceDataT3[i] = priceRates[i].close;
         }
      }
      
      // Calculate T3 values for positions we need (at least current and previous)
      double t3Value = T3.Calculate(priceDataT3, 0); // Current value
      double prevT3Value = T3.Calculate(priceDataT3, 1); // Previous value
      
      // Store for signal detection
      prevT3 = currT3;
      currT3 = prevT3Value; // Use previous bar for signal confirmation
      
      // Store in buffer (though we're not really using this anymore)
      T3Buffer[0] = t3Value;
      T3Buffer[1] = prevT3Value;
   }
   
   // Update VWAP indicator values if enabled
   if(UseVWAPIndicator)
   {
      // In backtest/optimization mode, always use bar precision for better performance
      bool useTickPrecision = isFastModeContext ? false : VWAP_UseTickPrecision;
      
      if(useTickPrecision)
      {
         // For tick precision mode, we need to simulate ticks from bar data
         datetime tickTimes[];
         double tickPrices[];
         long tickVolumes[];
         
         ArrayResize(tickTimes, ratesCount);
         ArrayResize(tickPrices, ratesCount);
         ArrayResize(tickVolumes, ratesCount);
         
         for(int i = 0; i < ratesCount; i++)
         {
            tickTimes[i] = priceRates[i].time;
            
            // Calculate price based on the selected price type
            switch(VWAP_Price_Type)
            {
               case PRICE_CLOSE:  tickPrices[i] = priceRates[i].close; break;
               case PRICE_OPEN:   tickPrices[i] = priceRates[i].open; break;
               case PRICE_HIGH:   tickPrices[i] = priceRates[i].high; break;
               case PRICE_LOW:    tickPrices[i] = priceRates[i].low; break;
               case PRICE_MEDIAN: tickPrices[i] = (priceRates[i].high + priceRates[i].low) / 2; break;
               case PRICE_TYPICAL: tickPrices[i] = (priceRates[i].high + priceRates[i].low + priceRates[i].close) / 3; break;
               case PRICE_WEIGHTED: tickPrices[i] = (priceRates[i].high + priceRates[i].low + priceRates[i].close + priceRates[i].open) / 4; break;
               default: tickPrices[i] = (priceRates[i].high + priceRates[i].low + priceRates[i].close) / 3;
            }
            
            tickVolumes[i] = priceRates[i].tick_volume > 0 ? priceRates[i].tick_volume : 1;
         }
         
         // Calculate VWAP using tick-level precision with safety check
         SafeCalculateVWAP(tickTimes, tickPrices, tickVolumes, ratesCount);
      }
      else
      {
         // Calculate VWAP using bar-level precision - much faster
         SafeCalculateVWAPOnBar(priceRates, ratesCount);
      }
      
      // Update VWAP values for signal detection
      prevVWAPDaily = currVWAPDaily;
      currVWAPDaily = VWAPDailyBuffer[1]; // Use previous bar for signal confirmation
      
      if(VWAP_Timeframe1 != VWAP_DISABLED)
      {
         prevVWAPTF1 = currVWAPTF1;
         currVWAPTF1 = VWAPTF1Buffer[1];
      }
      
      if(VWAP_Timeframe2 != VWAP_DISABLED)
      {
         prevVWAPTF2 = currVWAPTF2;
         currVWAPTF2 = VWAPTF2Buffer[1];
      }
      
      if(VWAP_Timeframe3 != VWAP_DISABLED)
      {
         prevVWAPTF3 = currVWAPTF3;
         currVWAPTF3 = VWAPTF3Buffer[1];
      }
      
      if(VWAP_Timeframe4 != VWAP_DISABLED)
      {
         prevVWAPTF4 = currVWAPTF4;
         currVWAPTF4 = VWAPTF4Buffer[1];
      }

      if(VWAP_Timeframe5 != VWAP_DISABLED)
      {
         prevVWAPTF5 = currVWAPTF5;
         currVWAPTF5 = VWAPTF5Buffer[1];
      }

      if(VWAP_Timeframe6 != VWAP_DISABLED)
      {
         prevVWAPTF6 = currVWAPTF6;
         currVWAPTF6 = VWAPTF6Buffer[1];
      }

      if(VWAP_Timeframe7 != VWAP_DISABLED)
      {
         prevVWAPTF7 = currVWAPTF7;
         currVWAPTF7 = VWAPTF7Buffer[1];
      }

      if(VWAP_Timeframe8 != VWAP_DISABLED)
      {
         prevVWAPTF8 = currVWAPTF8;
         currVWAPTF8 = VWAPTF8Buffer[1];
      }
   }
   
   // Update auxiliary signals after core indicators are refreshed
   if(UseEngulfingPattern)
      g_EngulfingSignal = EngulfingDetector.Evaluate(priceRates, ratesCount);
   else
      g_EngulfingSignal = 0;

   if(UseEngulfingStochastic && g_EngulfingStochReady)
      g_EngulfingStochSignal = EngulfingStochSignal.Evaluate(priceRates, ratesCount);
   else
      g_EngulfingStochSignal = 0;

   if(UseQQEIndicator && g_QQEReady)
      g_QQESignal = QQESignal.Evaluate(priceRates, ratesCount, g_QQERsiMA, g_QQETrLevel);
   else
   {
      g_QQESignal = 0;
      g_QQERsiMA = 0.0;
      g_QQETrLevel = 0.0;
   }

   if(UseSuperTrendIndicator && g_SuperTrendReady)
      g_SuperTrendSignal = SuperTrendSignal.Evaluate(priceRates, ratesCount, g_SuperTrendValue);
   else
   {
      g_SuperTrendSignal = 0;
      g_SuperTrendValue = 0.0;
   }

   if(UseFiboZigZagFilter && g_FiboZigZagReady)
      g_FiboZigZagSignal = FiboZigZagSignal.Evaluate(priceRates, ratesCount);
   else
      g_FiboZigZagSignal = 0;

   if(UseIntrabarVolumeFilter)
      g_IntrabarVolumeSignal = IntrabarVolumeSignal.Evaluate(priceRates, ratesCount);
   else
      g_IntrabarVolumeSignal = 0;

   if(UseTotalPowerFilter && g_TotalPowerReady)
      g_TotalPowerSignal = TotalPowerSignal.Evaluate(priceRates, ratesCount);
   else
      g_TotalPowerSignal = 0;
}

//+------------------------------------------------------------------+
//| Safe wrapper for VWAP calculation to avoid array out of bounds   |
//+------------------------------------------------------------------+
void SafeCalculateVWAP(const datetime &time[], const double &price[], 
                      long &volume[], int data_count)
{
   // First verify the buffer sizes are sufficient
   int bufferSize = ArraySize(VWAPDailyBuffer);
   
   // Ensure all buffers are properly sized
   if(bufferSize < data_count)
   {
      bufferSize = MathMax(bufferSize, data_count);
      ArrayResize(VWAPDailyBuffer, bufferSize);
      ArrayResize(VWAPTF1Buffer, bufferSize);
      ArrayResize(VWAPTF2Buffer, bufferSize);
      ArrayResize(VWAPTF3Buffer, bufferSize);
      ArrayResize(VWAPTF4Buffer, bufferSize);
      ArrayResize(VWAPTF5Buffer, bufferSize);
      ArrayResize(VWAPTF6Buffer, bufferSize);
      ArrayResize(VWAPTF7Buffer, bufferSize);
      ArrayResize(VWAPTF8Buffer, bufferSize);
   }
   
   // For safety during optimization, limit data_count to buffer size
   int safe_count = MathMin(data_count, bufferSize);
   
   // Call the actual VWAP calculation with the safe count
   VWAP.CalculateOnTick(time, price, volume, safe_count,
                       VWAPDailyBuffer, VWAPTF1Buffer, VWAPTF2Buffer, 
                       VWAPTF3Buffer, VWAPTF4Buffer, VWAPTF5Buffer,
                       VWAPTF6Buffer, VWAPTF7Buffer, VWAPTF8Buffer);
}

//+------------------------------------------------------------------+
//| Safe wrapper for VWAP bar calculation to avoid array out of bounds|
//+------------------------------------------------------------------+
void SafeCalculateVWAPOnBar(const MqlRates &rates[], int rates_count)
{
   // First verify the buffer sizes are sufficient
   int bufferSize = ArraySize(VWAPDailyBuffer);
   
   // Ensure all buffers are properly sized
   if(bufferSize < rates_count)
   {
      bufferSize = MathMax(bufferSize, rates_count);
      ArrayResize(VWAPDailyBuffer, bufferSize);
      ArrayResize(VWAPTF1Buffer, bufferSize);
      ArrayResize(VWAPTF2Buffer, bufferSize);
      ArrayResize(VWAPTF3Buffer, bufferSize);
      ArrayResize(VWAPTF4Buffer, bufferSize);
      ArrayResize(VWAPTF5Buffer, bufferSize);
      ArrayResize(VWAPTF6Buffer, bufferSize);
      ArrayResize(VWAPTF7Buffer, bufferSize);
      ArrayResize(VWAPTF8Buffer, bufferSize);
   }
   
   // For safety during optimization, limit rates_count to buffer size
   int safe_count = MathMin(rates_count, bufferSize);
   
   // Call the actual VWAP calculation with the safe count
   VWAP.CalculateOnBar(rates, safe_count, VWAPDailyBuffer, VWAPTF1Buffer, 
                      VWAPTF2Buffer, VWAPTF3Buffer, VWAPTF4Buffer,
                      VWAPTF5Buffer, VWAPTF6Buffer, VWAPTF7Buffer, VWAPTF8Buffer);
}

//+------------------------------------------------------------------+
//| Helper: accumulate signal votes                                   |
//+------------------------------------------------------------------+
void RegisterSignalVote(const int signal, int &buyVotes, int &sellVotes, int &voteCount)
{
   if(signal > 0)
   {
      buyVotes++;
      voteCount++;
   }
   else if(signal < 0)
   {
      sellVotes++;
      voteCount++;
   }
}

//+------------------------------------------------------------------+
//| Helper: resolve directional signal based on configuration        |
//+------------------------------------------------------------------+
int CombineSignalVotes(const int &signals[], const bool &enabled[], const int moduleCount)
{
   int buyVotes = 0;
   int sellVotes = 0;
   int voteCount = 0;

   for(int i = 0; i < moduleCount; ++i)
   {
      if(!enabled[i])
         continue;
      RegisterSignalVote(signals[i], buyVotes, sellVotes, voteCount);
   }

   int resolvedSignal = 0;

   // Determine applicable thresholds based on bias configuration
   bool allowLongs  = (TradeDirectionBias != ShortOnly);
   bool allowShorts = (TradeDirectionBias != LongOnly);

   int longThreshold  = MathMax(1, (TradeDirectionBias == LongOnly)
                                   ? MinSignalsToEnterLong
                                   : MinSignalsToEnterBoth);
   int shortThreshold = MathMax(1, (TradeDirectionBias == ShortOnly)
                                   ? MinSignalsToEnterShort
                                   : MinSignalsToEnterBoth);

   // Evaluate long bias first if permitted
   if(allowLongs && buyVotes >= longThreshold && sellVotes == 0)
      resolvedSignal = 1;

   // Evaluate short bias, ensuring no conflicting long decision
   if(allowShorts && sellVotes >= shortThreshold && buyVotes == 0)
   {
      if(resolvedSignal != 0)
         resolvedSignal = 0; // Conflict - skip trade
      else
         resolvedSignal = -1;
   }

   return(resolvedSignal);
}

//+------------------------------------------------------------------+
//| Helper: build descriptive trade comments                         |
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
//| Helper: compute the T3/VWAP crossover signal with filters        |
//+------------------------------------------------------------------+
int ComputeT3VWAPSignal(const MqlRates &signalRates[])
{
   if(!UseT3VWAPFilter || !UseT3Indicator || !UseVWAPIndicator)
      return(0);

   int signal = 0;

   bool bullishCross = (prevT3 < prevVWAPDaily && currT3 > currVWAPDaily);
   bool bearishCross = (prevT3 > prevVWAPDaily && currT3 < currVWAPDaily);

   bool bullishPriceConfirm = (signalRates[1].close > signalRates[1].open && signalRates[2].close > signalRates[2].open);
   bool bearishPriceConfirm = (signalRates[1].close < signalRates[1].open && signalRates[2].close < signalRates[2].open);

   if(bullishCross && bullishPriceConfirm)
   {
      bool passesFilters = true;

      if(VWAP_Timeframe1 != VWAP_DISABLED && signalRates[1].close < currVWAPTF1)
         passesFilters = false;
      if(VWAP_Timeframe2 != VWAP_DISABLED && signalRates[1].close < currVWAPTF2)
         passesFilters = false;
      if(VWAP_Timeframe3 != VWAP_DISABLED && signalRates[1].close < currVWAPTF3)
         passesFilters = false;
      if(VWAP_Timeframe4 != VWAP_DISABLED && signalRates[1].close < currVWAPTF4)
         passesFilters = false;
      if(VWAP_Timeframe5 != VWAP_DISABLED && signalRates[1].close < currVWAPTF5)
         passesFilters = false;
      if(VWAP_Timeframe6 != VWAP_DISABLED && signalRates[1].close < currVWAPTF6)
         passesFilters = false;
      if(VWAP_Timeframe7 != VWAP_DISABLED && signalRates[1].close < currVWAPTF7)
         passesFilters = false;
      if(VWAP_Timeframe8 != VWAP_DISABLED && signalRates[1].close < currVWAPTF8)
         passesFilters = false;

      if(passesFilters)
         signal = 1;
   }
   else if(bearishCross && bearishPriceConfirm)
   {
      bool passesFilters = true;

      if(VWAP_Timeframe1 != VWAP_DISABLED && signalRates[1].close > currVWAPTF1)
         passesFilters = false;
      if(VWAP_Timeframe2 != VWAP_DISABLED && signalRates[1].close > currVWAPTF2)
         passesFilters = false;
      if(VWAP_Timeframe3 != VWAP_DISABLED && signalRates[1].close > currVWAPTF3)
         passesFilters = false;
      if(VWAP_Timeframe4 != VWAP_DISABLED && signalRates[1].close > currVWAPTF4)
         passesFilters = false;
      if(VWAP_Timeframe5 != VWAP_DISABLED && signalRates[1].close > currVWAPTF5)
         passesFilters = false;
      if(VWAP_Timeframe6 != VWAP_DISABLED && signalRates[1].close > currVWAPTF6)
         passesFilters = false;
      if(VWAP_Timeframe7 != VWAP_DISABLED && signalRates[1].close > currVWAPTF7)
         passesFilters = false;
      if(VWAP_Timeframe8 != VWAP_DISABLED && signalRates[1].close > currVWAPTF8)
         passesFilters = false;

      if(passesFilters)
         signal = -1;
   }

   return(signal);
}

//+------------------------------------------------------------------+
//| Check for trading signals based on indicators                    |
//+------------------------------------------------------------------+
void CheckForTradingSignals()
{
   MqlRates signalRates[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, SignalConfirmationBars + 2, signalRates) <= 0)
   {
      Print("Error copying price data for signal check. Error code: ", GetLastError());
      return;
   }
   ArraySetAsSeries(signalRates, true);

   bool hasOpenPosition = false;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         hasOpenPosition = true;
         break;
      }
   }

   if(hasOpenPosition)
      return;

   const int MAX_MODULES = 10;
   int moduleSignals[];
   bool moduleEnabled[];
   ArrayResize(moduleSignals, MAX_MODULES);
   ArrayResize(moduleEnabled, MAX_MODULES);
   int moduleCount = 0;

   bool t3Enabled = (UseT3VWAPFilter && UseT3Indicator && UseVWAPIndicator);
   int t3Signal = 0;
   if(t3Enabled)
      t3Signal = ComputeT3VWAPSignal(signalRates);
   g_T3VWAPSignal = t3Signal;
   moduleSignals[moduleCount] = t3Signal;
   moduleEnabled[moduleCount] = t3Enabled;
   moduleCount++;

   moduleSignals[moduleCount] = g_EngulfingSignal;
   moduleEnabled[moduleCount] = UseEngulfingPattern;
   moduleCount++;

   moduleSignals[moduleCount] = g_EngulfingStochSignal;
   moduleEnabled[moduleCount] = (UseEngulfingStochastic && g_EngulfingStochReady);
   moduleCount++;

   moduleSignals[moduleCount] = g_QQESignal;
   moduleEnabled[moduleCount] = (UseQQEIndicator && g_QQEReady);
   moduleCount++;

   moduleSignals[moduleCount] = g_SuperTrendSignal;
   moduleEnabled[moduleCount] = (UseSuperTrendIndicator && g_SuperTrendReady);
   moduleCount++;

   moduleSignals[moduleCount] = g_FiboZigZagSignal;
   moduleEnabled[moduleCount] = (UseFiboZigZagFilter && g_FiboZigZagReady);
   moduleCount++;

   moduleSignals[moduleCount] = g_IntrabarVolumeSignal;
   moduleEnabled[moduleCount] = UseIntrabarVolumeFilter;
   moduleCount++;

   moduleSignals[moduleCount] = g_TotalPowerSignal;
   moduleEnabled[moduleCount] = (UseTotalPowerFilter && g_TotalPowerReady);
   moduleCount++;

   int combinedSignal = CombineSignalVotes(moduleSignals, moduleEnabled, moduleCount);

   if(combinedSignal > 0)
   {
      ExecuteTrade(ORDER_TYPE_BUY);
   }
   else if(combinedSignal < 0)
   {
      ExecuteTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Execute a trade with proper risk management                       |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
   // Calculate stop loss distance based on ATR
   double stopLossDistance = GetStopLossDistance();
   if(stopLossDistance <= 0)
   {
      Print("ERROR: Could not calculate stop loss distance. Trade aborted.");
      return;
   }
   
   double symbolPoint = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double stopLossPoints = (symbolPoint > 0.0) ? stopLossDistance / symbolPoint : 0.0;
   // Get account equity and risk amount in account currency
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (currentRisk / 100.0);
   
   // Get current price for order
   double price = SymbolInfoDouble(_Symbol, orderType == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
   
   // Calculate stop loss level based on order type
   double stopLossLevel = (orderType == ORDER_TYPE_BUY) ? 
                          price - stopLossDistance : 
                          price + stopLossDistance;
   
   // Get the minimum allowed stop distance from the broker
   double minStopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   
   // Ensure our stop is at least the minimum distance required by broker
   if(stopLossPoints < minStopLevel && symbolPoint > 0.0)
   {
      stopLossDistance = minStopLevel * symbolPoint;
      stopLossPoints = stopLossDistance / symbolPoint;

      if(orderType == ORDER_TYPE_BUY)
         stopLossLevel = price - stopLossDistance;
      else
         stopLossLevel = price + stopLossDistance;

      Print("WARNING: Stop distance adjusted to broker minimum: ", stopLossPoints, " points");
   }

   // Apply MaxHoldBars/MaxStopLossDistance clamp before sizing the trade
   double minStopDistanceAbs = (symbolPoint > 0.0) ? MathMax(symbolPoint, minStopLevel * symbolPoint) : 0.0;
   double trailingMinAbs = MinimumStopDistance * symbolPoint;
   if(trailingMinAbs > minStopDistanceAbs)
      minStopDistanceAbs = trailingMinAbs;

   double maxStopDistanceFromTime = (MaxStopLossDistance > 0.0 && symbolPoint > 0.0)
                                    ? MaxStopLossDistance * symbolPoint
                                    : 0.0;

   if(MaxHoldBars > 0 && symbolPoint > 0.0)
   {
      double atr = iATR(_Symbol, PERIOD_CURRENT, ATRPeriod);
      if(atr > 0.0)
      {
         double averageBarRangePoints = atr / symbolPoint;
         double candidateDistancePoints = averageBarRangePoints * MaxHoldBars;
         double candidateDistanceAbs = candidateDistancePoints * symbolPoint;
         if(candidateDistanceAbs > 0.0 &&
            (maxStopDistanceFromTime <= 0.0 || candidateDistanceAbs < maxStopDistanceFromTime))
         {
            maxStopDistanceFromTime = candidateDistanceAbs;
         }
      }
   }

   if(maxStopDistanceFromTime > 0.0)
   {
      if(minStopDistanceAbs > 0.0 && maxStopDistanceFromTime < minStopDistanceAbs)
         maxStopDistanceFromTime = minStopDistanceAbs;

      if(stopLossDistance > maxStopDistanceFromTime + 1e-8)
      {
         stopLossDistance = maxStopDistanceFromTime;
         stopLossPoints = stopLossDistance / symbolPoint;
         stopLossLevel = (orderType == ORDER_TYPE_BUY) ?
                         price - stopLossDistance :
                         price + stopLossDistance;

         PrintFormat("Stop distance clamped to %.2f points using MaxHoldBars/MaxStopLossDistance", stopLossPoints);
      }
   }

   // Align stop distance with tick size if possible
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize > 0.0 && stopLossDistance >= tickSize)
   {
      double ticks = MathFloor(stopLossDistance / tickSize);
      if(ticks < 1.0)
         ticks = 1.0;
      double alignedDistance = ticks * tickSize;
      if(alignedDistance < minStopDistanceAbs && minStopDistanceAbs > 0.0)
         alignedDistance = minStopDistanceAbs;
      if(alignedDistance > 0.0)
      {
         stopLossDistance = alignedDistance;
         stopLossPoints = (symbolPoint > 0.0) ? stopLossDistance / symbolPoint : stopLossPoints;
         stopLossLevel = (orderType == ORDER_TYPE_BUY)
                         ? price - stopLossDistance
                         : price + stopLossDistance;
      }
   }
   // DETERMINE ACCURATE POINT VALUE AND LOT SIZE
   // ---------------------------------------------
   double lotSize = DefaultLot; // Start with default
   
   if(UseACRiskManagement)
   {
      // DETERMINE TRUE FINANCIAL VALUE OF POINTS FOR THIS SYMBOL
      // We use a practical approach: calculate the exact money value of a 1-lot position with 1-point stop
      // Get contract specifications
      double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSizeVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      
      // Calculate how many ticks are in one point (guard against zero tick size)
      double ticksPerPoint = (tickSizeVal > 0.0 ? pointSize / tickSizeVal : 1.0);
      if(ticksPerPoint <= 0.0)
         ticksPerPoint = 1.0;

      // Calculate money value of one point for 1.0 lot
      double onePointValue = tickValue * ticksPerPoint;
      if(onePointValue <= 0.0)
         onePointValue = pointSize * contractSize; // conservative fallback
      
      // Calculate money value of one point for our desired lot size
      double onePointPerLotValue = onePointValue; // Value of one point for 1.0 lot
      
      // Calculate lot size to achieve desired risk
      // Formula: lotSize = riskAmount / (stopLossPoints * onePointPerLotValue)
      lotSize = riskAmount / (stopLossPoints * onePointPerLotValue);
      
      // Get symbol volume constraints for validation
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      
      // Round to the nearest lot step and apply constraints
      lotSize = MathFloor(lotSize / lotStep) * lotStep;
      if(lotSize < minLot) lotSize = minLot;
      if(lotSize > maxLot) lotSize = maxLot;
      
      // Re-verify risk with the adjusted lot size
      double actualRiskAmount = lotSize * stopLossPoints * onePointPerLotValue;
      double actualRiskPercent = (actualRiskAmount / equity) * 100.0;
      if(MathAbs(actualRiskPercent - currentRisk) > 0.5)
         PrintFormat("Risk adjusted to %.2f%% because of broker constraints.", actualRiskPercent);
   }
   // Fixed-lot mode intentionally suppresses additional messaging.
   
   // Calculate take profit based on reward target
   double takeProfitDistance = 0.0;
   double takeProfitLevel = 0.0;
   double riskToRewardRatio = 0.0;
   
   // Calculate take profit based on risk-to-reward ratio and the stop loss distance
   if(UseACRiskManagement)
   {
      double safeRisk = (MathAbs(currentRisk) < 1e-6 ? AC_BaseRisk : currentRisk);
      if(MathAbs(safeRisk) > 1e-6)
         riskToRewardRatio = currentReward / safeRisk;
      else
         riskToRewardRatio = AC_BaseReward;
      // Calculate take profit points based on the R:R ratio
      double takeProfitPoints = stopLossPoints * riskToRewardRatio;
      takeProfitDistance = takeProfitPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   }
   else
   {
      // Use a fixed R:R based on stop loss (default 3:1)
      double takeProfitPoints = stopLossPoints * AC_BaseReward;
      takeProfitDistance = takeProfitPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      riskToRewardRatio = AC_BaseReward;
   }
   
   if(orderType == ORDER_TYPE_BUY)
      takeProfitLevel = price + takeProfitDistance;
   else
      takeProfitLevel = price - takeProfitDistance;
   // Set takeProfitLevel to 0 to disable automatic take profit if not using take profit
   if(!UseTakeProfit)
   {
      takeProfitLevel = 0;
      Print("Take profit disabled - manual close required");
   }
   
   string tradeComment = BuildTradeComment(riskToRewardRatio);
   trade.PositionOpen(_Symbol, orderType, lotSize, price, stopLossLevel, takeProfitLevel, tradeComment);
   
   if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      ulong ticket = trade.ResultOrder();
      PrintFormat("Trade executed (%s) %.2f lots @ %.5f, ticket %I64u",
                  orderType == ORDER_TYPE_BUY ? "BUY" : "SELL",
                  lotSize,
                  price,
                  ticket);
   }
   else
   {
      Print("ERROR: Trade execution failed. Error code: ", trade.ResultRetcode(),
            ", Description: ", trade.ResultComment());
   }
}

//+------------------------------------------------------------------+
//| Update trailing stops for all positions                          |
//+------------------------------------------------------------------+
void UpdateAllTrailingStops(bool newBar = false)
{
   if(isInBacktest && !newBar && !ManualTrailingActivated)
      return;
  
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionSelectByTicket(ticket))
      {
         // Only update trailing stops for positions opened by this EA
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
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
            
            // Respect trailing activation threshold unless manual override is active
            if(!ManualTrailingActivated)
            {
               if(!ShouldActivateTrailing(entryPrice, currentPrice, orderType, volume, compoundedOverrideActive))
                  continue;
            }
            
            // Update trailing stop for this position
            UpdateTrailingStop(ticket, entryPrice, orderType);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Calculate average trades per day from deal history       |
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
//| OnTester function - required for strategy tester optimization     |
//+------------------------------------------------------------------+
double OnTester()
{
   // Get account statistics
   double profit        = TesterStatistics((ENUM_STATISTICS)STAT_PROFIT);
   double trades        = TesterStatistics((ENUM_STATISTICS)STAT_TRADES);
   double profitFactor  = TesterStatistics((ENUM_STATISTICS)STAT_PROFIT_FACTOR);
   double sharpeRatio   = TesterStatistics((ENUM_STATISTICS)STAT_SHARPE_RATIO);
   double recoveryFactor= TesterStatistics((ENUM_STATISTICS)STAT_RECOVERY_FACTOR);
   double drawdown_rel = TesterStatistics((ENUM_STATISTICS)STAT_EQUITY_DDREL_PERCENT);
   double finalBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Skip if no trades were made
   if(trades < 1)
      return UseCustomMax ? -DBL_MAX : 0.0;
      
   // Get additional statistics
   double winningTrades = TesterStatistics((ENUM_STATISTICS)STAT_PROFIT_TRADES);
   double losingTrades = TesterStatistics((ENUM_STATISTICS)STAT_LOSS_TRADES);
   double winRate = (trades > 0) ? (winningTrades / trades) * 100.0 : 0;
   double avgTradesDaily = CalcTradesPerDayFromHistory();
   
   // Get consecutive winners and losers - use estimates based on total trades
   double maxConsecWinners = MathSqrt(winningTrades); // Estimate based on square root of winning trades
   double maxConsecLosers = MathSqrt(losingTrades);   // Estimate based on square root of losing trades
   
   // Get average win and loss amounts
   double grossProfit = TesterStatistics((ENUM_STATISTICS)STAT_GROSS_PROFIT);
   double grossLoss = TesterStatistics((ENUM_STATISTICS)STAT_GROSS_LOSS);
   double avgWinAmount = (winningTrades > 0) ? grossProfit / winningTrades : 0;
   double avgLossAmount = (losingTrades > 0) ? grossLoss / losingTrades : 0;
   
   double metric = profitFactor;

   // Apply penalties for high drawdowns
   if(drawdown_rel > 20)
      metric *= 0.8;
   if(drawdown_rel > 30)
      metric *= 0.5;

   // Bonus for good recovery factor
   if(recoveryFactor > 2)
      metric *= 1.2;

   double resultScore = metric;

   if(UseCustomMax)
   {
      g_ACOptCfg.MinTrades          = Opt_MinTrades;
      g_ACOptCfg.MinOosPF           = Opt_MinOosPF;
      g_ACOptCfg.MaxOosDDPercent    = Opt_MaxOosDDPercent;
      g_ACOptCfg.InSampleFrac       = Opt_InSampleFraction;
      g_ACOptCfg.OosGapDays         = Opt_OosGapDays;
      g_ACOptCfg.McSimulations      = Opt_McSimulations;
      g_ACOptCfg.McBlockLenTrades   = Opt_McBlockLen;
      g_ACOptCfg.McSeed             = Opt_McSeed;
      g_ACOptCfg.w_pf               = Opt_W_PF;
      g_ACOptCfg.w_dd               = Opt_W_DD;
      g_ACOptCfg.w_sharpe           = Opt_W_Sharpe;
      g_ACOptCfg.w_mc_pf            = Opt_W_McPF;
      g_ACOptCfg.w_mc_dd            = Opt_W_McDD;
      g_ACOptCfg.MagicFilter        = MagicNumber;

      AC_Opt_Init(g_ACOptCfg);
      const double compositeScore = AC_CalcCustomCriterion();
      AC_PublishFrames();
      resultScore = compositeScore;

      double tradesPerDayOpt = AC_GetTradesPerDay();
      if(tradesPerDayOpt > 0.0)
         avgTradesDaily = tradesPerDayOpt;

      double ddFromCriterion = AC_GetOosDrawdownPercent();
      if(drawdown_rel <= 0.0 && ddFromCriterion > 0.0)
         drawdown_rel = ddFromCriterion;
   }

   // Store values in global variables for optimization results display
   customWinRate = NormalizeDouble(winRate, 2);
   customWinningTrades = winningTrades;
   customLosingTrades = losingTrades;
   customFinalBalance = NormalizeDouble(finalBalance, 2);
   customAvgTradesDaily = NormalizeDouble(avgTradesDaily, 2);
   customMaxConsecWinners = maxConsecWinners;
   customMaxConsecLosers = maxConsecLosers;
   customAvgWinAmount = NormalizeDouble(avgWinAmount, 2);
   customAvgLossAmount = NormalizeDouble(avgLossAmount, 2);

   string customStats = StringFormat(
      "WR=%.1f%% WT=%d LT=%d Bal=%.2f TpD=%.1f CW=%d CL=%d AW=%.2f AL=%.2f",
      customWinRate, (int)customWinningTrades, (int)customLosingTrades,
      customFinalBalance, customAvgTradesDaily,
      (int)customMaxConsecWinners, (int)customMaxConsecLosers,
      customAvgWinAmount, customAvgLossAmount
   );

   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
   {
      Print("=== STRATEGY PERFORMANCE METRICS ===");
      Print("Profit: ", profit);
      Print("Drawdown %: ", drawdown_rel);
      Print("Total Trades: ", trades);
      Print("Profit Factor: ", profitFactor);
      Print("Sharpe Ratio: ", sharpeRatio);
      Print("Recovery Factor: ", recoveryFactor);
      Print("Win Rate: ", customWinRate, "%");
      Print("Winning Trades: ", (int)customWinningTrades);
      Print("Losing Trades: ", (int)customLosingTrades);
      Print("Final Balance: ", customFinalBalance);
      Print("Avg Trades Per Day: ", customAvgTradesDaily);
      Print("Max Consecutive Winners: ", (int)customMaxConsecWinners);
      Print("Max Consecutive Losers: ", (int)customMaxConsecLosers);
      Print("Avg Win Amount: ", customAvgWinAmount);
      Print("Avg Loss Amount: ", customAvgLossAmount);
      Print("====================================");
      Comment(customStats);
   }

   if(MQLInfoInteger(MQL_OPTIMIZATION))
   {
      g_WinRate = customWinRate;
      g_WinTrades = customWinningTrades;
      g_LossTrades = customLosingTrades;
      g_FinalBalance = customFinalBalance;
      g_AvgTradesDaily = customAvgTradesDaily;
      g_MaxConsecWins = customMaxConsecWinners;
      g_MaxConsecLoss = customMaxConsecLosers;
      g_AvgWinAmount = customAvgWinAmount;
      g_AvgLossAmount = customAvgLossAmount;
   }

   return resultScore;
}

//+------------------------------------------------------------------+
//| Print detailed optimization metrics to the tester log            |
//+------------------------------------------------------------------+
void PrintOptimizationMetrics(
   double t3Length,
   double t3Factor,
   double baseRisk, 
   double baseReward,
   double atrPeriod,
   double atrMultiplier,
   double profit,
   double drawdown,
   double profitFactor,
   double trades,
   double winRate,
   double winningTrades,
   double losingTrades,
   double finalBalance,
   double avgTradesDaily,
   double maxConsecWinners,
   double maxConsecLosers,
   double avgWinAmount,
   double avgLossAmount
)
{
   // Create a formatted string with all the statistics
   string stats = StringFormat(
      "OPT-METRICS|Symbol=%s|TF=%s|T3L=%.0f|T3F=%.2f|Risk=%.2f|Reward=%.2f|ATRPeriod=%.0f|ATRMult=%.2f|" +
      "Profit=%.2f|DD=%.2f|PF=%.2f|Trades=%.0f|WinRate=%.2f|Wins=%.0f|Losses=%.0f|" +
      "Balance=%.2f|TradesPerDay=%.2f|ConsecWins=%.0f|ConsecLosses=%.0f|AvgWin=%.2f|AvgLoss=%.2f",
      _Symbol, EnumToString((ENUM_TIMEFRAMES)Period()), 
      t3Length, t3Factor, baseRisk, baseReward, atrPeriod, atrMultiplier,
      profit, drawdown, profitFactor, trades, winRate, winningTrades, losingTrades,
      finalBalance, avgTradesDaily, maxConsecWinners, maxConsecLosers, avgWinAmount, avgLossAmount
   );
   
   // Print to the log - this will appear in the Journal tab
   Print(stats);
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
