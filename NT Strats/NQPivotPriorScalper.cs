#region Using declarations
using System;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using NinjaTrader.Cbi;
using NinjaTrader.NinjaScript;
using NinjaTrader.NinjaScript.Indicators;
using NinjaTrader.Custom.AC;
#endregion

namespace NinjaTrader.NinjaScript.Strategies
{
    public class NQ_PivotPrior_Scalper_v2 : Strategy
    {
        // ---- enums ----
        public enum PivotStyleOption { Classic, Camarilla, Fibonacci }
        public enum EntryModeOption { Fade, Breakout }

        // ---- indicators ----
        private Pivots pivClassic;
        private CamarillaPivots pivCamarilla;
        private FibonacciPivots pivFibo;
        private PriorDayOHLC prior;
        private ATR atr;

        // AC helpers
        private ACRiskManager acRisk;
        private ACATRPositionSizer acSizer;
        private ACTrailingManager acTrailing;
        private double acCurrentStop;
        private int acLastQuantity;
        private MarketPosition acLastPosition = MarketPosition.Flat;
        private double acLastCumProfit;
        private const string ACSignalLong = "AC_Long";
        private const string ACSignalShort = "AC_Short";

        // ---- state ----
        private int lastEntryBar = int.MinValue;
        private bool sessionPrinted = false; // throttle session-level prints

        // ----------------- Inputs -----------------
        [NinjaScriptProperty]
        [Display(Name = "Pivot Style", Order = 1, GroupName = "Setup")]
        public PivotStyleOption PivotStyle { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Pivot Range", Order = 2, GroupName = "Setup")]
        public PivotRange PivotRangeType { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Entry Mode", Order = 3, GroupName = "Setup")]
        public EntryModeOption EntryMode { get; set; }

        [NinjaScriptProperty]
        [Range(1, 4)]
        [Display(Name = "Level (R/S index)", Description = "Classic/Fibo: 1..3, Camarilla: 1..4", Order = 4, GroupName = "Setup")]
        public int LevelIndex { get; set; }

        [NinjaScriptProperty]
        [Range(1, 200)]
        [Display(Name = "Pivot Line Width (bars)", Order = 5, GroupName = "Setup")]
        public int PivotWidth { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Use Prior OHLC Confluence", Order = 1, GroupName = "Confluence")]
        public bool UsePriorConfluence { get; set; }

        [NinjaScriptProperty]
        [Range(0, 100)]
        [Display(Name = "Confluence Max Distance (ticks)", Order = 2, GroupName = "Confluence")]
        public int ConfluenceTicks { get; set; }

        [NinjaScriptProperty]
        [Range(0, 50)]
        [Display(Name = "Entry Buffer (ticks)", Order = 3, GroupName = "Signals")]
        public int EntryBufferTicks { get; set; }

        [NinjaScriptProperty]
        [Range(1, 200)]
        [Display(Name = "Stop Loss (ticks)", Order = 1, GroupName = "Risk")]
        public int StopLossTicks { get; set; }

        [NinjaScriptProperty]
        [Range(1, 400)]
        [Display(Name = "Profit Target (ticks)", Order = 2, GroupName = "Risk")]
        public int ProfitTargetTicks { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Allow Longs", Order = 1, GroupName = "Permissions")]
        public bool AllowLongs { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Allow Shorts", Order = 2, GroupName = "Permissions")]
        public bool AllowShorts { get; set; }

        [NinjaScriptProperty]
        [Range(0, 50)]
        [Display(Name = "Cooldown (bars) after entry", Order = 3, GroupName = "Permissions")]
        public int CooldownBars { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Enable Debug Prints", Order = 99, GroupName = "Diagnostics")]
        public bool EnableDebug { get; set; }

        [NinjaScriptProperty, Display(Name = "Use AC Position Management", GroupName = "AC Risk", Order = 200)]
        public bool UseACPositionManagement { get; set; }

        [NinjaScriptProperty, Range(0.01, 25.0), Display(Name = "AC Base Risk Percent", GroupName = "AC Risk", Order = 201)]
        public double ACBaseRiskPercent { get; set; }

        [NinjaScriptProperty, Range(0.5, 20.0), Display(Name = "AC Base Reward Multiple", GroupName = "AC Risk", Order = 202)]
        public double ACBaseRewardMultiple { get; set; }

        [NinjaScriptProperty, Range(1, 10), Display(Name = "AC Compounding Wins", GroupName = "AC Risk", Order = 203)]
        public int ACCompoundingWins { get; set; }

        [NinjaScriptProperty, Display(Name = "AC Use Partial Compounding", GroupName = "AC Risk", Order = 204)]
        public bool ACUsePartialCompounding { get; set; }

        [NinjaScriptProperty, Range(0.0, 100.0), Display(Name = "AC Partial Compounding Percent", GroupName = "AC Risk", Order = 205)]
        public double ACPartialCompoundingPercent { get; set; }

        [NinjaScriptProperty, Range(0.1, 100.0), Display(Name = "AC Trailing Activation Percent", GroupName = "AC Risk", Order = 206)]
        public double ACTrailingActivationPercent { get; set; }

        [NinjaScriptProperty, Range(0.0, 100.0), Display(Name = "AC Minimum Stop Ticks", GroupName = "AC Risk", Order = 207)]
        public double ACMinimumStopTicks { get; set; }

        [NinjaScriptProperty, Range(0.1, 50.0), Display(Name = "AC Max Risk Percent", GroupName = "AC Risk", Order = 208)]
        public double ACMaxRiskPercent { get; set; }

        [NinjaScriptProperty, Range(1, 20), Display(Name = "AC Minimum Contracts", GroupName = "AC Risk", Order = 209)]
        public int ACMinContracts { get; set; }

        [NinjaScriptProperty, Range(1, 200), Display(Name = "AC Maximum Contracts", GroupName = "AC Risk", Order = 210)]
        public int ACMaxContracts { get; set; }

        [NinjaScriptProperty, Range(1, 10), Display(Name = "AC Contract Step", GroupName = "AC Risk", Order = 211)]
        public int ACContractStep { get; set; }

        [NinjaScriptProperty, Range(100, 1000000), Display(Name = "AC Account Risk Budget", GroupName = "AC Risk", Order = 212)]
        public double ACAccountRiskBudget { get; set; }

        [NinjaScriptProperty, Range(0.5, 10.0), Display(Name = "AC ATR Stop Multiplier", GroupName = "AC Risk", Order = 213)]
        public double ACATRStopMultiplier { get; set; }

        [NinjaScriptProperty, Range(5, 100), Display(Name = "AC ATR Period", GroupName = "AC Risk", Order = 214)]
        public int ACATRPeriod { get; set; }

        // ----------------- Defaults -----------------
        protected override void OnStateChange()
        {
            if (State == State.SetDefaults)
            {
                Name                         = "NQ_PivotPrior_Scalper_v2";
                Calculate                    = Calculate.OnBarClose;   // for reproducible backtests; change in UI if desired
                EntriesPerDirection          = 1;
                EntryHandling                = EntryHandling.AllEntries;
                IsExitOnSessionCloseStrategy = true;
                ExitOnSessionCloseSeconds    = 5;
                IsInstantiatedOnEachOptimizationIteration = true;
                DefaultQuantity              = 1;

                PivotStyle          = PivotStyleOption.Classic;    // more interactions by default
                PivotRangeType      = PivotRange.Daily;
                EntryMode           = EntryModeOption.Fade;
                LevelIndex          = 1;                           // Classic R1/S1
                PivotWidth          = 20;

                UsePriorConfluence  = false;                      // OFF by default (prevents 0-trade days)
                ConfluenceTicks     = 8;

                EntryBufferTicks    = 1;

                StopLossTicks       = 12;
                ProfitTargetTicks   = 24;

                AllowLongs          = true;
                AllowShorts         = true;
                CooldownBars        = 0;

                EnableDebug         = true;  // per user preference for detailed logs

                if (EnableDebug)
                    Print($"{Name}: State.SetDefaults completed. IsOverlay: {IsOverlay}");

                UseACPositionManagement = true;
                ACBaseRiskPercent = 1.0;
                ACBaseRewardMultiple = 3.0;
                ACCompoundingWins = 2;
                ACUsePartialCompounding = false;
                ACPartialCompoundingPercent = 25.0;
                ACTrailingActivationPercent = 1.0;
                ACMinimumStopTicks = 4.0;
                ACMaxRiskPercent = 10.0;
                ACMinContracts = 1;
                ACMaxContracts = 10;
                ACContractStep = 1;
                ACAccountRiskBudget = 10000;
                ACATRStopMultiplier = 1.5;
                ACATRPeriod = 14;
            }
            else if (State == State.Configure)
            {
                if (EnableDebug)
                    Print($"{Name}: State.Configure entered.");
            }
            else if (State == State.DataLoaded)
            {
                // instantiate system indicators with intraday-derived H/L/C
                pivClassic   = Pivots(PivotRangeType, HLCCalculationMode.CalcFromIntradayData, 0, 0, 0, PivotWidth);
                pivCamarilla = CamarillaPivots(PivotRangeType, HLCCalculationMode.CalcFromIntradayData, 0, 0, 0, PivotWidth);
                pivFibo      = FibonacciPivots(PivotRangeType, HLCCalculationMode.CalcFromIntradayData, 0, 0, 0, PivotWidth);
                prior        = PriorDayOHLC(); // prior.PriorHigh / prior.PriorLow, etc.
                atr          = ATR(ACATRPeriod);

                AddChartIndicator(atr);

                if (EnableDebug)
                    Print($"{Name}: State.DataLoaded completed. PivotStyle={PivotStyle}, Range={PivotRangeType}, EntryMode={EntryMode}");

                InitializeAcComponents();
            }
            else if (State == State.Historical)
            {
                sessionPrinted = false;
                if (EnableDebug)
                    Print($"{Name}: State.Historical entered.");
            }
            else if (State == State.Realtime)
            {
                sessionPrinted = false;
                if (EnableDebug)
                    Print($"{Name}: State.Realtime entered.");
            }
            else if (State == State.Terminated)
            {
                if (EnableDebug)
                    Print($"{Name}: State.Terminated entered.");
            }
        }

        // ---- helper: ensure indicator values are valid (per NT docs) ----
        private bool PivotsReady()
        {
            switch (PivotStyle)
            {
                case PivotStyleOption.Classic:   return pivClassic.R1.IsValidDataPoint(0);     // use R1 since we trade R/S
                case PivotStyleOption.Camarilla: return pivCamarilla.R1.IsValidDataPoint(0);
                case PivotStyleOption.Fibonacci: return pivFibo.R1.IsValidDataPoint(0);
                default: return false;
            }
        }

        private bool TryGetPivotLevels(out double upper, out double lower)
        {
            upper = lower = double.NaN;

            if (!PivotsReady())
            {
                if (EnableDebug && !sessionPrinted)
                {
                    Print($"[{Time[0]:yyyy-MM-dd HH:mm}] Pivots not ready for {PivotStyle}.");
                    sessionPrinted = true;
                }
                return false;
            }

            int lvl = LevelIndex;
            if (PivotStyle != PivotStyleOption.Camarilla && lvl > 3) lvl = 3;

            switch (PivotStyle)
            {
                case PivotStyleOption.Classic:
                    upper = (lvl == 1) ? pivClassic.R1[0] : (lvl == 2 ? pivClassic.R2[0] : pivClassic.R3[0]);
                    lower = (lvl == 1) ? pivClassic.S1[0] : (lvl == 2 ? pivClassic.S2[0] : pivClassic.S3[0]);
                    break;

                case PivotStyleOption.Camarilla:
                    if (lvl == 1) { upper = pivCamarilla.R1[0]; lower = pivCamarilla.S1[0]; }
                    else if (lvl == 2) { upper = pivCamarilla.R2[0]; lower = pivCamarilla.S2[0]; }
                    else if (lvl == 3) { upper = pivCamarilla.R3[0]; lower = pivCamarilla.S3[0]; }
                    else { upper = pivCamarilla.R4[0]; lower = pivCamarilla.S4[0]; }
                    break;

                case PivotStyleOption.Fibonacci:
                    upper = (lvl == 1) ? pivFibo.R1[0] : (lvl == 2 ? pivFibo.R2[0] : pivFibo.R3[0]);
                    lower = (lvl == 1) ? pivFibo.S1[0] : (lvl == 2 ? pivFibo.S2[0] : pivFibo.S3[0]);
                    break;
            }

            bool ok = !(double.IsNaN(upper) || double.IsNaN(lower) || upper == 0 || lower == 0);
            if (EnableDebug && !sessionPrinted)
            {
                Print($"[{Time[0]:yyyy-MM-dd}] {PivotStyle} L{lvl} levels: U={upper:F2}, L={lower:F2}, ok={ok}");
                sessionPrinted = true;
            }
            return ok;
        }

        private bool IsNear(double a, double b, int ticks) => Math.Abs(a - b) <= ticks * TickSize;

        protected override void OnBarUpdate()
        {
            if (Bars.IsFirstBarOfSession) sessionPrinted = false;

            if (CurrentBar < 2) return;
            if (CooldownBars > 0 && lastEntryBar != int.MinValue && CurrentBar - lastEntryBar < CooldownBars) return;

            if (UseACPositionManagement && acTrailing != null && atr != null)
                acTrailing.UpdateAtr(atr[0]);

            if (!TryGetPivotLevels(out double upper, out double lower))
            {
                return;
            }

            // Optional confluence: upper with prior high, lower with prior low
            bool okLong  = true;
            bool okShort = true;
            if (UsePriorConfluence)
            {
                okShort = IsNear(upper, prior.PriorHigh[0], ConfluenceTicks);
                okLong  = IsNear(lower, prior.PriorLow[0],  ConfluenceTicks);
                if (EnableDebug && !sessionPrinted)
                {
                    Print($"Confluence check: okShort={okShort} (U vs PriorHigh {prior.PriorHigh[0]:F2}), okLong={okLong} (L vs PriorLow {prior.PriorLow[0]:F2})");
                    sessionPrinted = true;
                }
            }

            double buf = EntryBufferTicks * TickSize;

            if (Position.MarketPosition == MarketPosition.Flat)
            {
                if (!UseACPositionManagement)
                {
                    // Attach OCO stop/target before entry (per NT guidance)
                    SetStopLoss(CalculationMode.Ticks, StopLossTicks);
                    SetProfitTarget(CalculationMode.Ticks, ProfitTargetTicks);
                }
            }

            if (EntryMode == EntryModeOption.Fade)
            {
                // SHORT fade at upper level: poke above + close back below
                if (AllowShorts && okShort && Position.MarketPosition == MarketPosition.Flat
                    && High[0] >= upper + buf && Close[0] < upper)
                {
                    if (EnableDebug) Print($"EnterShort FADE @ {Close[0]:F2} (High {High[0]:F2} vs U {upper:F2} buf {buf:F2})");
                    if (UseACPositionManagement && TrySubmitAcEntry(MarketPosition.Short, Close[0]))
                    {
                        lastEntryBar = CurrentBar;
                        return;
                    }
                    if (UseACPositionManagement)
                        ApplyDefaultStops();
                    EnterShort();
                    lastEntryBar = CurrentBar;
                    return;
                }

                // LONG fade at lower level: poke below + close back above
                if (AllowLongs && okLong && Position.MarketPosition == MarketPosition.Flat
                    && Low[0] <= lower - buf && Close[0] > lower)
                {
                    if (EnableDebug) Print($"EnterLong FADE @ {Close[0]:F2} (Low {Low[0]:F2} vs L {lower:F2}) buf {buf:F2}");
                    if (UseACPositionManagement && TrySubmitAcEntry(MarketPosition.Long, Close[0]))
                    {
                        lastEntryBar = CurrentBar;
                        return;
                    }
                    if (UseACPositionManagement)
                        ApplyDefaultStops();
                    EnterLong();
                    lastEntryBar = CurrentBar;
                    return;
                }
            }
            else // Breakout
            {
                // LONG breakout above upper level
                if (AllowLongs && okShort && Position.MarketPosition == MarketPosition.Flat
                    && Close[1] <= upper && Close[0] > upper + buf)
                {
                    if (EnableDebug) Print($"EnterLong BO @ {Close[0]:F2} crossed U {upper:F2} (prev {Close[1]:F2})");
                    if (UseACPositionManagement && TrySubmitAcEntry(MarketPosition.Long, Close[0]))
                    {
                        lastEntryBar = CurrentBar;
                        return;
                    }
                    if (UseACPositionManagement)
                        ApplyDefaultStops();
                    EnterLong();
                    lastEntryBar = CurrentBar;
                    return;
                }

                // SHORT breakout below lower level
                if (AllowShorts && okLong && Position.MarketPosition == MarketPosition.Flat
                    && Close[1] >= lower && Close[0] < lower - buf)
                {
                    if (EnableDebug) Print($"EnterShort BO @ {Close[0]:F2} crossed L {lower:F2} (prev {Close[1]:F2})");
                    if (UseACPositionManagement && TrySubmitAcEntry(MarketPosition.Short, Close[0]))
                    {
                        lastEntryBar = CurrentBar;
                        return;
                    }
                    if (UseACPositionManagement)
                        ApplyDefaultStops();
                    EnterShort();
                    lastEntryBar = CurrentBar;
                    return;
                }
            }

            if (UseACPositionManagement && Position.MarketPosition != MarketPosition.Flat)
            {
                ManageActivePosition();
            }
        }

        private void InitializeAcComponents()
        {
            if (!UseACPositionManagement)
            {
                acRisk = null;
                acSizer = null;
                acTrailing = null;
                acCurrentStop = double.NaN;
                acLastQuantity = 0;
                acLastPosition = MarketPosition.Flat;
                acLastCumProfit = SystemPerformance.AllTrades.TradesPerformance.Currency.CumProfit;
                return;
            }

            var settings = new ACRiskSettings
            {
                BaseRiskPercent = ACBaseRiskPercent,
                BaseRewardMultiple = ACBaseRewardMultiple,
                CompoundingWins = ACCompoundingWins,
                UsePartialCompounding = ACUsePartialCompounding,
                PartialCompoundingPercent = ACPartialCompoundingPercent,
                RequireTargetHitForCompounding = true,
                MaxRiskPercent = Math.Max(ACBaseRiskPercent, ACMaxRiskPercent),
                MinRiskPercent = Math.Max(0.01, Math.Min(ACBaseRiskPercent, 0.1))
            };

            acRisk = new ACRiskManager();
            acRisk.Initialize(settings);

            acSizer = new ACATRPositionSizer(ACATRStopMultiplier, ACMinimumStopTicks, TickSize, Instrument.MasterInstrument.PointValue);
            acTrailing = new ACTrailingManager(ACATRStopMultiplier, ACTrailingActivationPercent, ACMinimumStopTicks, TickSize, Instrument.MasterInstrument.PointValue, ACATRPeriod);
            acTrailing.Reset();

            acCurrentStop = double.NaN;
            acLastQuantity = 0;
            acLastPosition = Position != null ? Position.MarketPosition : MarketPosition.Flat;
            acLastCumProfit = SystemPerformance.AllTrades.TradesPerformance.Currency.CumProfit;
        }

        private bool TrySubmitAcEntry(MarketPosition direction, double entryPrice)
        {
            if (acRisk == null || acSizer == null)
                return false;

            double rewardMultiple = acRisk.RewardToRiskMultiple;
            ACPositionSizingResult sizing = acSizer.Calculate(direction, entryPrice, atr[0], rewardMultiple);

            double equity = GetAccountEquity();
            int minContracts = Math.Max(1, ACMinContracts);
            int maxContracts = ACMaxContracts < minContracts ? minContracts : ACMaxContracts;
            int step = Math.Max(1, ACContractStep);
            int quantity = acRisk.ComputePositionQuantity(equity, sizing.RiskPerContract, minContracts, maxContracts, step);
            if (quantity <= 0)
                return false;

            string signal = direction == MarketPosition.Long ? ACSignalLong : ACSignalShort;
            double stopPrice = Instrument.MasterInstrument.Round2TickSize(sizing.StopPrice);
            double targetPrice = Instrument.MasterInstrument.Round2TickSize(sizing.TargetPrice);

            SetStopLoss(signal, CalculationMode.Price, stopPrice, false);
            SetProfitTarget(signal, CalculationMode.Price, targetPrice);

            acCurrentStop = stopPrice;
            acLastQuantity = quantity;

            if (direction == MarketPosition.Long)
                EnterLong(quantity, signal);
            else
                EnterShort(quantity, signal);

            return true;
        }

        private void ManageActivePosition()
        {
            if (acTrailing == null || acRisk == null)
                return;

            int qty = Math.Abs(Position.Quantity);
            if (qty <= 0)
                return;

            double equity = GetAccountEquity();
            if (!acTrailing.ShouldActivate(Position.MarketPosition, Position.AveragePrice, Close[0], qty, equity))
                return;

            if (acTrailing.TryGetTrailingStop(Position.MarketPosition, Close[0], acCurrentStop, out double newStop))
            {
                double rounded = Instrument.MasterInstrument.Round2TickSize(newStop);
                string signal = Position.MarketPosition == MarketPosition.Long ? ACSignalLong : ACSignalShort;
                SetStopLoss(signal, CalculationMode.Price, rounded, false);
                acCurrentStop = rounded;
                if (EnableDebug)
                    Print($"{Time[0]} AC trailing stop -> {rounded:F2}");
            }
        }

        private double GetAccountEquity()
        {
            double equityEstimate = Math.Max(1.0, ACAccountRiskBudget);

            if (Account != null)
            {
                try
                {
                    double accountEquity = Account.Get(AccountItem.NetLiquidationByCurrency, Currency.UsDollar);
                    if (!double.IsNaN(accountEquity) && accountEquity > 0)
                        equityEstimate = accountEquity;
                }
                catch
                {
                    // ignore, fall back below
                }
            }
            else
            {
                double cumulative = SystemPerformance.AllTrades.TradesPerformance.Currency.CumProfit;
                equityEstimate = Math.Max(1.0, ACAccountRiskBudget + cumulative);
            }

            return Math.Max(1.0, equityEstimate);
        }

        private void ApplyDefaultStops()
        {
            SetStopLoss(CalculationMode.Ticks, StopLossTicks);
            SetProfitTarget(CalculationMode.Ticks, ProfitTargetTicks);
        }

        protected override void OnPositionUpdate(PositionEventArgs args)
        {
            if (args == null || args.Position == null)
                return;

            if (!UseACPositionManagement || acRisk == null)
            {
                acLastPosition = args.Position.MarketPosition;
                return;
            }

            if (args.Position.Instrument != Instrument)
            {
                acLastPosition = args.Position.MarketPosition;
                return;
            }

            if (acLastPosition != MarketPosition.Flat && args.Position.MarketPosition == MarketPosition.Flat)
            {
                double cumulative = SystemPerformance.AllTrades.TradesPerformance.Currency.CumProfit;
                double delta = cumulative - acLastCumProfit;
                bool isWin = delta > 0.0;
                double equity = GetAccountEquity();
                double profitPercent = equity > 0.0 ? (Math.Abs(delta) / equity) * 100.0 : 0.0;

                acRisk.OnTradeClosed(isWin, profitPercent);

                acLastCumProfit = cumulative;
                acCurrentStop = double.NaN;
                acLastQuantity = 0;
            }

            acLastPosition = args.Position.MarketPosition;
        }
    }
}
