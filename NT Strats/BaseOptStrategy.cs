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
using NinjaTrader.Custom.AC;
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

        // --- AC helpers
        private ACATRPositionSizer acSizer;
        private ACRiskManager acRisk;
        private ACTrailingManager acTrailing;

        // --- internal
        private int maxSignalSlots; // number of enabled indicator families (SMA/EMA/RSI/MACD)
        private ACPositionSizingResult pendingSizing;
        private double currentStopPrice;
        private double currentTargetPrice;
        private int lastEntryQuantity;
        private double lastCumProfit;
        private MarketPosition lastPositionState = MarketPosition.Flat;

        private const string LongSignal = "ACLong";
        private const string ShortSignal = "ACShort";


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
                AccountRiskBudget = 10000;
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

                InitializeAcComponents();

            }
            else if (State == State.Historical || State == State.Realtime)
            {
                lastCumProfit = SystemPerformance.AllTrades.TradesPerformance.Currency.CumProfit;
                lastPositionState = Position.MarketPosition;
            }
            else if (State == State.Terminated)
            {
                acTrailing?.Reset();
            }
        }
        #endregion

        private void InitializeAcComponents()
        {
            if (!UseACPositionManagement)
            {
                acRisk = null;
                acSizer = null;
                acTrailing = null;
                return;
            }

            var riskSettings = new ACRiskSettings
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
            acRisk.Initialize(riskSettings);

            acSizer = new ACATRPositionSizer(AtrStopMult, ACMinimumStopTicks, TickSize, Instrument.MasterInstrument.PointValue);
            acTrailing = new ACTrailingManager(AtrTrailMult, ACTrailingActivationPercent, ACMinimumStopTicks, TickSize, Instrument.MasterInstrument.PointValue, AtrPeriod);
            acTrailing.Reset();

            pendingSizing = null;
            currentStopPrice = double.NaN;
            currentTargetPrice = double.NaN;
            lastEntryQuantity = 0;
        }

        protected override void OnBarUpdate()
        {
            if (CurrentBar < BarsRequiredToTrade)
                return;

            double atrValue = atr[0];
            acTrailing?.UpdateAtr(atrValue);

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
                currentStopPrice = double.NaN;
                currentTargetPrice = double.NaN;
                pendingSizing = null;
                lastEntryQuantity = 0;

                if (UseACPositionManagement)
                {
                    if (canLong && TrySubmitEntry(MarketPosition.Long, atrValue))
                        return;

                    if (canShort && TrySubmitEntry(MarketPosition.Short, atrValue))
                        return;
                }
                else
                {
                    if (canLong)
                    {
                        SetStopLoss(CalculationMode.Ticks, StopTicks);
                        SetProfitTarget(CalculationMode.Ticks, TargetTicks);
                        EnterLong();
                    }
                    else if (canShort)
                    {
                        SetStopLoss(CalculationMode.Ticks, StopTicks);
                        SetProfitTarget(CalculationMode.Ticks, TargetTicks);
                        EnterShort();
                    }
                }
            }
            else
            {
                if (UseACPositionManagement)
                {
                    ManageActivePosition();
                }
            }

            if (Debug)
                Print($"{Time[0]} votes L/S: {longVotes}/{shortVotes} canL={canLong} canS={canShort} bias={Bias} minL={MinSignalsToEnterLong}->{effMinLong} minS={MinSignalsToEnterShort}->{effMinShort} Pos:{Position.MarketPosition}");
        }

        private bool TrySubmitEntry(MarketPosition direction, double atrValue)
        {
            if (acRisk == null || acSizer == null)
                return false;

            double entryPrice = Instrument.MasterInstrument.Round2TickSize(Close[0]);
            double rewardMultiple = acRisk.RewardToRiskMultiple;

            ACPositionSizingResult sizing = acSizer.Calculate(direction, entryPrice, atrValue, rewardMultiple);

            double equity = GetAccountEquity();
            int minContracts = Math.Max(1, ACMinContracts);
            int maxContracts = ACMaxContracts < minContracts ? minContracts : ACMaxContracts;
            int step = Math.Max(1, ACContractStep);
            int quantity = acRisk.ComputePositionQuantity(equity, sizing.RiskPerContract, minContracts, maxContracts, step);
            if (quantity <= 0)
                return false;

            sizing.StopPrice = Instrument.MasterInstrument.Round2TickSize(sizing.StopPrice);
            sizing.TargetPrice = Instrument.MasterInstrument.Round2TickSize(sizing.TargetPrice);

            string signal = direction == MarketPosition.Long ? LongSignal : ShortSignal;
            SetStopLoss(signal, CalculationMode.Price, sizing.StopPrice, false);
            SetProfitTarget(signal, CalculationMode.Price, sizing.TargetPrice);

            pendingSizing = sizing;
            currentStopPrice = sizing.StopPrice;
            currentTargetPrice = sizing.TargetPrice;
            lastEntryQuantity = quantity;

            if (direction == MarketPosition.Long)
            {
                if (Debug) Print($"{Time[0]} EnterLong qty={quantity} stop={sizing.StopPrice:F2} target={sizing.TargetPrice:F2} risk/contract={sizing.RiskPerContract:F2}");
                EnterLong(quantity, LongSignal);
            }
            else
            {
                if (Debug) Print($"{Time[0]} EnterShort qty={quantity} stop={sizing.StopPrice:F2} target={sizing.TargetPrice:F2} risk/contract={sizing.RiskPerContract:F2}");
                EnterShort(quantity, ShortSignal);
            }

            return true;
        }

        private void ManageActivePosition()
        {
            if (acTrailing == null || acRisk == null)
                return;

            int quantity = Math.Abs(Position.Quantity);
            if (quantity <= 0)
                return;

            double equity = GetAccountEquity();
            bool activate = acTrailing.ShouldActivate(Position.MarketPosition, Position.AveragePrice, Close[0], quantity, equity);
            if (!activate)
                return;

            if (acTrailing.TryGetTrailingStop(Position.MarketPosition, Close[0], currentStopPrice, out double newStop))
            {
                string signal = Position.MarketPosition == MarketPosition.Long ? LongSignal : ShortSignal;
                double rounded = Instrument.MasterInstrument.Round2TickSize(newStop);
                SetStopLoss(signal, CalculationMode.Price, rounded, false);
                currentStopPrice = rounded;

                if (Debug)
                    Print($"{Time[0]} Trailing stop adjusted to {rounded:F2}");
            }
        }

        private double GetAccountEquity()
        {
            double equityEstimate = Math.Max(1.0, AccountRiskBudget);

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
                    // fall back to budget below
                }
            }
            else
            {
                double cumulative = SystemPerformance.AllTrades.TradesPerformance.Currency.CumProfit;
                equityEstimate = Math.Max(1.0, AccountRiskBudget + cumulative);
            }

            return Math.Max(1.0, equityEstimate);
        }

        protected override void OnPositionUpdate(PositionEventArgs args)
        {
            if (args == null || args.Position == null)
                return;

            if (!UseACPositionManagement || acRisk == null)
            {
                lastPositionState = args.Position.MarketPosition;
                return;
            }

            if (args.Position.Instrument != Instrument)
            {
                lastPositionState = args.Position.MarketPosition;
                return;
            }

            if (lastPositionState != MarketPosition.Flat && args.Position.MarketPosition == MarketPosition.Flat)
            {
                double cumulative = SystemPerformance.AllTrades.TradesPerformance.Currency.CumProfit;
                double delta = cumulative - lastCumProfit;
                bool isWin = delta > 0.0;
                double equity = GetAccountEquity();
                double profitPercent = equity > 0.0 ? (Math.Abs(delta) / equity) * 100.0 : 0.0;

                acRisk.OnTradeClosed(isWin, profitPercent);

                lastCumProfit = cumulative;
                currentStopPrice = double.NaN;
                currentTargetPrice = double.NaN;
                pendingSizing = null;
                lastEntryQuantity = 0;
            }

            lastPositionState = args.Position.MarketPosition;
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

        [NinjaScriptProperty, Range(100, 1000000), Display(Name = "Account Risk Budget", GroupName = "AC Risk", Order = 212)]
        public double AccountRiskBudget { get; set; }

        #endregion
    }
}

