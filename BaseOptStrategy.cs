#region Using declarations
using System;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;

using System.Collections.Generic;
using NinjaTrader.Cbi;
using NinjaTrader.Gui;
using NinjaTrader.Gui.Tools;
using NinjaTrader.NinjaScript;
using NinjaTrader.NinjaScript.Indicators;
using NinjaTrader.NinjaScript.Strategies;
#endregion

namespace NinjaTrader.NinjaScript.Strategies
{
    public class BaseOptStrategy : Strategy
    {
        // --- indicator refs
        private SMA sma;
        private EMA emaFast, emaSlow;
        private RSI rsi;
        private MACD macd;
        private ATR atr;

        // --- internal
        private bool stopSet, targetSet;
        private int maxSignalSlots; // number of enabled indicator families (SMA/EMA/RSI/MACD)


        #region Defaults
        protected override void OnStateChange()
        {
            if (State == State.SetDefaults)
            {
                Name = "BaseOptStrategy";
                Calculate = Calculate.OnBarClose;
                IsOverlay = false;
                EntriesPerDirection = 1;
                EntryHandling = EntryHandling.AllEntries;
                IsExitOnSessionCloseStrategy = true;
                ExitOnSessionCloseSeconds = 60;
                BarsRequiredToTrade = 50;
                IsInstantiatedOnEachOptimizationIteration = true;

                // Toggles
                UseSMA = true;
                UseEMA = true;
                UseRSI = true;
                UseMACD = true;

                // Signal control
                Bias = TradeBias.Both;
                MinSignalsToEnterLong = 2;
                MinSignalsToEnterShort = 2;

                // Indicator params
                SmaPeriod = 50;
                EmaFast = 12;
                EmaSlow = 26;
                RsiPeriod = 14;
                RsiSmooth = 3;
                RsiLongThreshold = 55;
                RsiShortThreshold = 45;
                MacdFast = 12;
                MacdSlow = 26;
                MacdSmooth = 9;
                AtrPeriod = 14;

                // Risk params
                StopType = StopKind.ATR;
                AtrStopMult = 2.0;
                StopTicks = 40;
                TargetType = TargetKind.ATR;
                AtrTargetMult = 3.0;
                TargetTicks = 60;

                TrailType = TrailKind.None;
                AtrTrailMult = 1.5;
                TrailTicks = 20;

                UseBreakEven = true;
                BreakEvenTriggerTicks = 30;
                BreakEvenPlusTicks = 2;

                Debug = false;
            }
            else if (State == State.Configure)
            {
                // optional: log parameters once per iteration for diagnostics
                if (Debug)
                {
                    Print($"PARAMS: Bias={Bias}, MinLong={MinSignalsToEnterLong}, MinShort={MinSignalsToEnterShort}, UseSMA={UseSMA}, SmaPeriod={SmaPeriod}, UseEMA={UseEMA}, EmaFast={EmaFast}, EmaSlow={EmaSlow}, UseRSI={UseRSI}, RsiPeriod={RsiPeriod}, RsiSmooth={RsiSmooth}, RsiLong={RsiLongThreshold}, RsiShort={RsiShortThreshold}, UseMACD={UseMACD}, MacdFast={MacdFast}, MacdSlow={MacdSlow}, MacdSmooth={MacdSmooth}, AtrPeriod={AtrPeriod}, StopType={StopType}, StopTicks={StopTicks}, AtrStopMult={AtrStopMult}, TargetType={TargetType}, TargetTicks={TargetTicks}, AtrTargetMult={AtrTargetMult}, TrailType={TrailType}, TrailTicks={TrailTicks}, AtrTrailMult={AtrTrailMult}, UseBreakEven={UseBreakEven}, BETriggerTicks={BreakEvenTriggerTicks}, BEPlusTicks={BreakEvenPlusTicks}");
                }
            }
            else if (State == State.DataLoaded)
            {
                if (UseSMA) sma = SMA(Close, SmaPeriod);
                if (UseEMA) { emaFast = EMA(Close, EmaFast); emaSlow = EMA(Close, EmaSlow); }
                if (UseRSI) rsi = RSI(Close, RsiPeriod, RsiSmooth);
                if (UseMACD) macd = MACD(Close, MacdFast, MacdSlow, MacdSmooth);
                atr = ATR(AtrPeriod);

                if (UseSMA) AddChartIndicator(sma);
                if (UseEMA) { AddChartIndicator(emaFast); AddChartIndicator(emaSlow); }
                if (UseRSI) AddChartIndicator(rsi);
                if (UseMACD) AddChartIndicator(macd);
                AddChartIndicator(atr);

				// Compute how many indicator families are enabled so we can cap required votes safely
				maxSignalSlots = (UseSMA ? 1 : 0) + (UseEMA ? 1 : 0) + (UseRSI ? 1 : 0) + (UseMACD ? 1 : 0);
				if (maxSignalSlots <= 0) maxSignalSlots = 1; // prevent zero causing impossible thresholds
				if (Debug && (MinSignalsToEnterLong > maxSignalSlots || MinSignalsToEnterShort > maxSignalSlots))
					Print($"WARN: MinSignals exceeds enabled indicators; capping in runtime. slots={maxSignalSlots} effMinL={Math.Min(MinSignalsToEnterLong, maxSignalSlots)} effMinS={Math.Min(MinSignalsToEnterShort, maxSignalSlots)}");

            }
        }
        #endregion

        protected override void OnBarUpdate()
        {
            if (CurrentBar < BarsRequiredToTrade)
                return;

            // Build signals
            int longVotes = 0, shortVotes = 0;

            if (UseSMA)
            {
                bool longCond = Close[0] > sma[0] && sma[0] > sma[1];
                bool shortCond = Close[0] < sma[0] && sma[0] < sma[1];
                if (longCond) longVotes++;
                if (shortCond) shortVotes++;
            }

            if (UseEMA)
            {
                bool longCond = emaFast[0] > emaSlow[0];
                bool shortCond = emaFast[0] < emaSlow[0];
                if (longCond) longVotes++;
                if (shortCond) shortVotes++;
            }

            if (UseRSI)
            {
                bool longCond = CrossAbove(rsi.Avg, RsiLongThreshold, 1);
                bool shortCond = CrossBelow(rsi.Avg, RsiShortThreshold, 1);
                if (longCond) longVotes++;
                if (shortCond) shortVotes++;
            }

            if (UseMACD)
            {
                double hist = macd.Default[0] - macd.Avg[0];
                if (hist > 0) longVotes++;
                if (hist < 0) shortVotes++;
            }

            int effMinLong = Math.Max(1, Math.Min(MinSignalsToEnterLong, maxSignalSlots));
            int effMinShort = Math.Max(1, Math.Min(MinSignalsToEnterShort, maxSignalSlots));
            bool canLong = (Bias == TradeBias.Both || Bias == TradeBias.LongOnly) && longVotes >= effMinLong;
            bool canShort = (Bias == TradeBias.Both || Bias == TradeBias.ShortOnly) && shortVotes >= effMinShort;

            // Manage orders
            if (Position.MarketPosition == MarketPosition.Flat)
            {
                stopSet = targetSet = false;

                if (canLong)
                {
                    if (Debug) Print($"{Time[0]} EnterLong() votes={longVotes} effMin={effMinLong}");
                    EnterLong();
                }
                else if (canShort)
                {
                    if (Debug) Print($"{Time[0]} EnterShort() votes={shortVotes} effMin={effMinShort}");
                    EnterShort();
                }
            }
            else
            {
                UpdateStopsTargets();

                // Optional trailing stop tightening each bar/tick
                if (TrailType != TrailKind.None)
                    ApplyTrailing();
            }

            if (Debug)
                Print($"{Time[0]} votes L/S: {longVotes}/{shortVotes} canL={canLong} canS={canShort} bias={Bias} minL={MinSignalsToEnterLong}->{effMinLong} minS={MinSignalsToEnterShort}->{effMinShort} Pos:{Position.MarketPosition}");
        }

        private void UpdateStopsTargets()
        {
            if (!stopSet)
            {
                // Stop
                if (StopType == StopKind.ATR)
                {
                    int ticks = (int)Math.Round((atr[0] * AtrStopMult) / TickSize);
                    SetStopLoss(CalculationMode.Ticks, ticks);
                    if (Debug) Print($"{Time[0]} Init Stop (ATR): {ticks} ticks");
                }
                else
                {
                    SetStopLoss(CalculationMode.Ticks, StopTicks);
                    if (Debug) Print($"{Time[0]} Init Stop (Ticks): {StopTicks}");
                }
                stopSet = true;
            }

            if (!targetSet)
            {
                // Profit Target
                if (TargetType == TargetKind.ATR)
                {
                    int ticks = (int)Math.Round((atr[0] * AtrTargetMult) / TickSize);
                    SetProfitTarget(CalculationMode.Ticks, ticks);
                    if (Debug) Print($"{Time[0]} Init Target (ATR): {ticks} ticks");
                }
                else
                {
                    SetProfitTarget(CalculationMode.Ticks, TargetTicks);
                    if (Debug) Print($"{Time[0]} Init Target (Ticks): {TargetTicks}");
                }
                targetSet = true;
            }

            // BreakEven
            if (UseBreakEven && Position.MarketPosition != MarketPosition.Flat)
            {
                try
                {
                    double entry = Position.AveragePrice;
                    if (Position.MarketPosition == MarketPosition.Long &&
                        Close[0] >= entry + BreakEvenTriggerTicks * TickSize)
                    {
                        double be = entry + BreakEvenPlusTicks * TickSize;
                        if (Debug) Print($"{Time[0]} BE LONG trigger: entry={entry:F2} close={Close[0]:F2} be={be:F2}");
                        SetStopLoss(CalculationMode.Price, be);
                    }
                    else if (Position.MarketPosition == MarketPosition.Short &&
                             Close[0] <= entry - BreakEvenTriggerTicks * TickSize)
                    {
                        double be = entry - BreakEvenPlusTicks * TickSize;
                        if (Debug) Print($"{Time[0]} BE SHORT trigger: entry={entry:F2} close={Close[0]:F2} be={be:F2}");
                        SetStopLoss(CalculationMode.Price, be);
                    }
                }
                catch (Exception ex)
                {
                    Print($"[ERROR] BreakEven block: {ex.Message} at {Time[0]}");
                }
            }
        }

        private void ApplyTrailing()
        {
            if (Position.MarketPosition == MarketPosition.Flat)
                return;

            if (TrailType == TrailKind.Ticks)
            {
                SetTrailStop(CalculationMode.Ticks, TrailTicks);
            }
            else if (TrailType == TrailKind.ATR)
            {
                int ticks = (int)Math.Round((atr[0] * AtrTrailMult) / TickSize);
                SetTrailStop(CalculationMode.Ticks, Math.Max(1, ticks));
            }
        }

        #region Params

        public enum TradeBias { Both, LongOnly, ShortOnly }
        public enum StopKind { Ticks, ATR }
        public enum TargetKind { Ticks, ATR }
        public enum TrailKind { None, Ticks, ATR }

        [NinjaScriptProperty, Display(Name = "Bias", GroupName = "Parameters", Order = 0)]
        public TradeBias Bias { get; set; }

        [NinjaScriptProperty, Range(1, 10), Display(Name = "MinSignalsToEnterLong", GroupName = "Parameters", Order = 1)]
        public int MinSignalsToEnterLong { get; set; }

        [NinjaScriptProperty, Range(1, 10), Display(Name = "MinSignalsToEnterShort", GroupName = "Parameters", Order = 2)]
        public int MinSignalsToEnterShort { get; set; }

        [NinjaScriptProperty, Display(Name = "UseSMA", GroupName = "Parameters", Order = 10)]
        public bool UseSMA { get; set; }

        [NinjaScriptProperty, Range(2, 400), Display(Name = "SmaPeriod", GroupName = "Parameters", Order = 11)]
        public int SmaPeriod { get; set; }

        [NinjaScriptProperty, Display(Name = "UseEMA", GroupName = "Parameters", Order = 20)]
        public bool UseEMA { get; set; }

        [NinjaScriptProperty, Range(2, 200), Display(Name = "EmaFast", GroupName = "Parameters", Order = 21)]
        public int EmaFast { get; set; }

        [NinjaScriptProperty, Range(2, 400), Display(Name = "EmaSlow", GroupName = "Parameters", Order = 22)]
        public int EmaSlow { get; set; }

        [NinjaScriptProperty, Display(Name = "UseRSI", GroupName = "Parameters", Order = 30)]
        public bool UseRSI { get; set; }

        [NinjaScriptProperty, Range(2, 100), Display(Name = "RsiPeriod", GroupName = "Parameters", Order = 31)]
        public int RsiPeriod { get; set; }

        [NinjaScriptProperty, Range(1, 10), Display(Name = "RsiSmooth", GroupName = "Parameters", Order = 32)]
        public int RsiSmooth { get; set; }

        [NinjaScriptProperty, Range(50, 90), Display(Name = "RsiLongThreshold", GroupName = "Parameters", Order = 33)]
        public int RsiLongThreshold { get; set; }

        [NinjaScriptProperty, Range(10, 50), Display(Name = "RsiShortThreshold", GroupName = "Parameters", Order = 34)]
        public int RsiShortThreshold { get; set; }

        [NinjaScriptProperty, Display(Name = "UseMACD", GroupName = "Parameters", Order = 40)]
        public bool UseMACD { get; set; }

        [NinjaScriptProperty, Range(2, 50), Display(Name = "MacdFast", GroupName = "Parameters", Order = 41)]
        public int MacdFast { get; set; }

        [NinjaScriptProperty, Range(5, 100), Display(Name = "MacdSlow", GroupName = "Parameters", Order = 42)]
        public int MacdSlow { get; set; }

        [NinjaScriptProperty, Range(1, 50), Display(Name = "MacdSmooth", GroupName = "Parameters", Order = 43)]
        public int MacdSmooth { get; set; }

        [NinjaScriptProperty, Range(2, 100), Display(Name = "AtrPeriod", GroupName = "Parameters", Order = 50)]
        public int AtrPeriod { get; set; }

        [NinjaScriptProperty, Display(Name = "StopType", GroupName = "Parameters", Order = 51)]
        public StopKind StopType { get; set; }

        [NinjaScriptProperty, Range(1, 200), Display(Name = "StopTicks", GroupName = "Parameters", Order = 52)]
        public int StopTicks { get; set; }

        [NinjaScriptProperty, Range(0.5, 10.0), Display(Name = "AtrStopMult", GroupName = "Parameters", Order = 53)]
        public double AtrStopMult { get; set; }

        [NinjaScriptProperty, Display(Name = "TargetType", GroupName = "Parameters", Order = 54)]
        public TargetKind TargetType { get; set; }

        [NinjaScriptProperty, Range(1, 400), Display(Name = "TargetTicks", GroupName = "Parameters", Order = 55)]
        public int TargetTicks { get; set; }

        [NinjaScriptProperty, Range(0.5, 20.0), Display(Name = "AtrTargetMult", GroupName = "Parameters", Order = 56)]
        public double AtrTargetMult { get; set; }

        [NinjaScriptProperty, Display(Name = "TrailType", GroupName = "Parameters", Order = 57)]
        public TrailKind TrailType { get; set; }

        [NinjaScriptProperty, Range(1, 200), Display(Name = "TrailTicks", GroupName = "Parameters", Order = 58)]
        public int TrailTicks { get; set; }

        [NinjaScriptProperty, Range(0.5, 10.0), Display(Name = "AtrTrailMult", GroupName = "Parameters", Order = 59)]
        public double AtrTrailMult { get; set; }

        [NinjaScriptProperty, Display(Name = "UseBreakEven", GroupName = "Parameters", Order = 60)]
        public bool UseBreakEven { get; set; }

        [NinjaScriptProperty, Range(1, 400), Display(Name = "BreakEvenTriggerTicks", GroupName = "Parameters", Order = 61)]
        public int BreakEvenTriggerTicks { get; set; }

        [NinjaScriptProperty, Range(0, 100), Display(Name = "BreakEvenPlusTicks", GroupName = "Parameters", Order = 62)]
        public int BreakEvenPlusTicks { get; set; }

        [NinjaScriptProperty, Display(Name = "Debug", GroupName = "Parameters", Order = 90)]
        public bool Debug { get; set; }

        #endregion
    }
}

