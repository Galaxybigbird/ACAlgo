using System;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using NinjaTrader.NinjaScript;
using NinjaTrader.NinjaScript.Strategies;
using NinjaTrader.Data;
using NinjaTrader.Gui.NinjaScript;
using NinjaTrader.NinjaScript.Indicators;
using NinjaTrader.Cbi;
using NinjaTrader.Custom.AC;


namespace NinjaTrader.NinjaScript.Strategies
{
    public class VWAPBandMeanReversionScalper : Strategy
    {
        // --- runtime fields
        private RSI rsi;
        private ATR atr;

        // AC helpers
        private ACRiskManager acRisk;
        private ACATRPositionSizer acSizer;
        private ACTrailingManager acTrailing;
        private ACPositionSizingResult acPendingSizing;
        private double acCurrentStop;
        private int acLastQuantity;
        private MarketPosition acLastPosition = MarketPosition.Flat;
        private double acLastCumProfit;
        private const string ACSignalLong = "AC_Long";
        private const string ACSignalShort = "AC_Short";

        // session-anchored VWAP vars (tick-aware, incremental by volume delta)
        private double cumPV, cumV;
        private double lastBarVolume; // track incremental volume
        private int sessionBars;
        private double welfordMean, welfordM2; // for std of (typ - vwap)

        // bands
        private double vwap, std, upper, lower;

        // state machine
        private bool touchedUpper, touchedLower;
        private int touchedUpperBar, touchedLowerBar;
        private int tradesToday;
        private double sessionProfitStart;

        // built-in VWAP availability toggle (Order Flow+ not required)
        private bool useBuiltInOk; // placeholder flag; built-in VWAP not referenced at compile time

        // constants / signals
        private const string SigLongA = "L_A"; // scale-out A
        private const string SigLongB = "L_B";
        private const string SigShortA = "S_A";
        private const string SigShortB = "S_B";

        protected override void OnStateChange()
        {
            if (State == State.SetDefaults)
            {
                Name = "VWAPBandMeanReversionScalper";
                Calculate = Calculate.OnEachTick;
                EntriesPerDirection = 1;
                EntryHandling = EntryHandling.UniqueEntries;
                IsInstantiatedOnEachOptimizationIteration = false;
                BarsRequiredToTrade = 20;
                DefaultQuantity = 1;

                // Defaults
                DevMult = 2.0;
                UseBuiltInVWAPBands = false;

                RsiPeriod = 14; RsiOverbought = 70; RsiOversold = 30;

                StopMode = StopChoice.BandBuffer;
                StopBufferTicks = 6; TpBufferTicks = 2;
                AtrPeriod = 14; AtrStopMult = 1.8;
                UseScaleOut = false;

                ReentryTicks = 1; EntryOffsetTicks = 0; CooldownBars = 3;

                UseVwapBiasFilter = true; UseTimeFilter = true;
                StartTime = new TimeSpan(9, 35, 0); EndTime = new TimeSpan(15, 50, 0);
                EndFlatMinutesBeforeClose = 10;

                MaxDailyLossCurrency = -600.0; MaxDailyTrades = 20;
                EnableBreakeven = true; BreakevenTriggerTicks = 10; BreakevenPlusTicks = 1;

                DebugPrints = false;
                EventLogs = true;

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
            }
            else if (State == State.Configure)
            {
            }
            else if (State == State.DataLoaded)
            {
                rsi = RSI(Close, RsiPeriod, 1);
                atr = ATR(AtrPeriod);
                AddChartIndicator(rsi);
                AddChartIndicator(atr);

                useBuiltInOk = false; // Order Flow VWAP skipped to avoid compile-time dependency; anchored VWAP is used instead.

                InitializeAcComponents();
                ResetSession();
                Log($"Init: DevMult={DevMult} RSI={RsiPeriod}/{RsiOverbought}/{RsiOversold} Stop={StopMode} StopBuf={StopBufferTicks} ATR={AtrPeriod}x{AtrStopMult} TPBuf={TpBufferTicks} Reentry={ReentryTicks} Offset={EntryOffsetTicks} Cooldown={CooldownBars} UseBias={UseVwapBiasFilter} UseTime={UseTimeFilter} MaxTrades={MaxDailyTrades} MaxLoss={MaxDailyLossCurrency}", false);

            }
        }

        protected override void OnBarUpdate()
        {
            if (CurrentBar < BarsRequiredToTrade)
                return;

            if (UseACPositionManagement && acTrailing != null)
            {
                acTrailing.UpdateAtr(atr[0]);
            }

            // Session reset
            if (Bars.IsFirstBarOfSession && IsFirstTickOfBar)
                ResetSession();

            // Update anchored VWAP cumulants using incremental volume
            double typ = (High[0] + Low[0] + Close[0]) / 3.0;
            double vol = Volume[0];
            double dVol = Math.Max(0, vol - lastBarVolume);
            lastBarVolume = vol;
            cumPV += typ * dVol;
            cumV += dVol;
            vwap = cumV > 0 ? cumPV / cumV : Close[0];

            // Welford of deviations (unweighted) — keep it simple and robust
            // sample x = typ - vwap at this tick; clamp std later
            sessionBars++;
            double x = typ - vwap;
            double delta = x - welfordMean;
            welfordMean += delta / Math.Max(1, sessionBars);
            double delta2 = x - welfordMean;
            welfordM2 += delta * delta2;
            double variance = sessionBars > 1 ? (welfordM2 / (sessionBars - 1)) : 0.0;
            std = Math.Max(Math.Sqrt(Math.Max(0, variance)), TickSize);

            // Bands
            upper = vwap + DevMult * std;
            lower = vwap - DevMult * std;

            // Daily guardrails and time filter
            if (UseTimeFilter)
            {
                var tod = Time[0].TimeOfDay;
                if (tod < StartTime || tod > EndTime)
                { Log($"{Time[0]} TimeFilter: outside window ({StartTime}-{EndTime})", false); DisarmFlags(); return; }
                // flat and stop new entries EndFlatMinutesBeforeClose before EndTime
                var flatCut = EndTime - TimeSpan.FromMinutes(Math.Max(0, EndFlatMinutesBeforeClose));
                if (tod >= flatCut)
                {
                    Log($"{Time[0]} TimeFilter: flattening before close (cut={flatCut})", false);
                    if (Position.MarketPosition == MarketPosition.Long) ExitLong("TimeFlat");
                    if (Position.MarketPosition == MarketPosition.Short) ExitShort("TimeFlat");
                    DisarmFlags();
                    return;
                }
            }

            double sessionPnL = SystemPerformance.AllTrades.TradesPerformance.Currency.CumProfit - sessionProfitStart;
            if (sessionPnL <= MaxDailyLossCurrency || tradesToday >= MaxDailyTrades)
            { Log($"{Time[0]} Guardrail: block entries (PnL={sessionPnL:F2} thr={MaxDailyLossCurrency:F2}, trades={tradesToday}/{MaxDailyTrades})", false); DisarmFlags(); return; }

            // Touch detection (intrabar)
            if (High[0] >= upper) { touchedUpper = true; touchedUpperBar = CurrentBar; Log($"{Time[0]} TouchUpper: High={High[0]:F2} >= upper={upper:F2}", false); }
            if (Low[0]  <= lower) { touchedLower = true; touchedLowerBar = CurrentBar; Log($"{Time[0]} TouchLower: Low={Low[0]:F2} <= lower={lower:F2}", false); }

            // Disarm after cooldown
            if (touchedUpper && CurrentBar - touchedUpperBar >= CooldownBars) { Log($"{Time[0]} TouchUpper expired: cooldown {CooldownBars} bars", false); touchedUpper = false; }
            if (touchedLower && CurrentBar - touchedLowerBar >= CooldownBars) { Log($"{Time[0]} TouchLower expired: cooldown {CooldownBars} bars", false); touchedLower = false; }

            // Decide eligibility
            bool allowShort = !UseVwapBiasFilter || Close[0] > vwap;
            bool allowLong  = !UseVwapBiasFilter || Close[0] < vwap;

            // If revert level is reached but blocked by filters, log why
            if (Position.MarketPosition == MarketPosition.Flat && touchedUpper)
            {
                bool revert = Close[0] <= upper - ReentryTicks * TickSize;
                if (revert)
                {
                    if (!allowShort) Log($"{Time[0]} BlockedShort: bias filter (price<=vwap)", false);
                    else if (rsi[0] < RsiOverbought) Log($"{Time[0]} BlockedShort: RSI {rsi[0]:F1} < OB {RsiOverbought}", false);
                }
            }
            if (Position.MarketPosition == MarketPosition.Flat && touchedLower)
            {
                bool revert = Close[0] >= lower + ReentryTicks * TickSize;
                if (revert)
                {
                    if (!allowLong) Log($"{Time[0]} BlockedLong: bias filter (price>=vwap)", false);
                    else if (rsi[0] > RsiOversold) Log($"{Time[0]} BlockedLong: RSI {rsi[0]:F1} > OS {RsiOversold}", false);
                }
            }

            // Exits are now set at the moment of entry inside PlaceLongEntry/PlaceShortEntry

            // Short: touch then revert below upper - reentry*Tick
            if (Position.MarketPosition == MarketPosition.Flat && touchedUpper && allowShort && rsi[0] >= RsiOverbought && Close[0] <= upper - ReentryTicks * TickSize)
            {
                PlaceShortEntry();
                touchedUpper = false;
            }
            // Long: touch then revert above lower + reentry*Tick
            if (Position.MarketPosition == MarketPosition.Flat && touchedLower && allowLong && rsi[0] <= RsiOversold && Close[0] >= lower + ReentryTicks * TickSize)
            {
                PlaceLongEntry();
                touchedLower = false;
            }

            // Breakeven management (simple)
            if (EnableBreakeven && !UseACPositionManagement && Position.MarketPosition != MarketPosition.Flat)
            {
                double avg = Position.AveragePrice;
                if (Position.MarketPosition == MarketPosition.Long)
                {
                    double ticks = (Close[0] - avg) / TickSize;
                    if (ticks >= BreakevenTriggerTicks)
                    {
                        Log($"{Time[0]} BE long: stop -> {avg + BreakevenPlusTicks * TickSize:F2}", false);
                        SetStopLoss(CalculationMode.Price, avg + BreakevenPlusTicks * TickSize);
                    }
                }
                else if (Position.MarketPosition == MarketPosition.Short)
                {
                    double ticks = (avg - Close[0]) / TickSize;
                    if (ticks >= BreakevenTriggerTicks)
                    {
                        Log($"{Time[0]} BE short: stop -> {avg - BreakevenPlusTicks * TickSize:F2}", false);
                        SetStopLoss(CalculationMode.Price, avg - BreakevenPlusTicks * TickSize);
                    }
                }
            }

            if (UseACPositionManagement && !UseScaleOut && Position.MarketPosition != MarketPosition.Flat)
            {
                ManageActivePosition();
            }

            Log($"{Time[0]} typ={typ:F2} vwap={vwap:F2} std={std:F2} up={upper:F2} lo={lower:F2} RSI={rsi[0]:F1} Pos={Position.MarketPosition}", true);
        }

        private void InitializeAcComponents()
        {
            if (!UseACPositionManagement)
            {
                acRisk = null;
                acSizer = null;
                acTrailing = null;
                acPendingSizing = null;
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

            acSizer = new ACATRPositionSizer(AtrStopMult, ACMinimumStopTicks, TickSize, Instrument.MasterInstrument.PointValue);
            acTrailing = new ACTrailingManager(AtrStopMult, ACTrailingActivationPercent, ACMinimumStopTicks, TickSize, Instrument.MasterInstrument.PointValue, AtrPeriod);
            acTrailing.Reset();

            acPendingSizing = null;
            acCurrentStop = double.NaN;
            acLastQuantity = 0;
            acLastPosition = MarketPosition.Flat;
            acLastCumProfit = SystemPerformance.AllTrades.TradesPerformance.Currency.CumProfit;
        }

        private void PrepareExits()
        {
            // Profit target at VWAP +/- buffer ticks
            double tpLong = vwap - TpBufferTicks * TickSize;
            double tpShort = vwap + TpBufferTicks * TickSize;

            if (!UseScaleOut)
            {
                SetProfitTarget(CalculationMode.Price, double.NaN); // clear
                SetStopLoss(CalculationMode.Price, double.NaN);

                SetProfitTarget(CalculationMode.Price, Position.MarketPosition == MarketPosition.Short ? tpShort : tpLong);

                if (StopMode == StopChoice.BandBuffer)
                {
                    // place just beyond bands
                    double stopL = lower - StopBufferTicks * TickSize;
                    double stopS = upper + StopBufferTicks * TickSize;
                    SetStopLoss(CalculationMode.Price, Position.MarketPosition == MarketPosition.Short ? stopS : stopL);
                }
                else // ATR
                {
                    int ticks = (int)Math.Round((atr[0] * AtrStopMult) / TickSize);
                    SetStopLoss(CalculationMode.Ticks, Math.Max(1, ticks));
                }
            }
            else // UseScaleOut = true
            {
                // Signal-specific targets: A scales at VWAP, B trails via ATR stop distance
                double stopL = lower - StopBufferTicks * TickSize;
                double stopS = upper + StopBufferTicks * TickSize;

                SetProfitTarget(SigLongA, CalculationMode.Price, tpLong);
                SetProfitTarget(SigShortA, CalculationMode.Price, tpShort);

                if (StopMode == StopChoice.BandBuffer)
                {
                    SetStopLoss(SigLongA, CalculationMode.Price, stopL, false);
                    SetStopLoss(SigShortA, CalculationMode.Price, stopS, false);
                    SetStopLoss(SigLongB, CalculationMode.Price, stopL, false);
                    SetStopLoss(SigShortB, CalculationMode.Price, stopS, false);
                }
                else
                {
                    int ticks = (int)Math.Round((atr[0] * AtrStopMult) / TickSize);
                    SetStopLoss(SigLongA, CalculationMode.Ticks, Math.Max(1, ticks), false);
                    SetStopLoss(SigShortA, CalculationMode.Ticks, Math.Max(1, ticks), false);
                    SetTrailStop(SigLongB, CalculationMode.Ticks, Math.Max(1, ticks), false);
                    SetTrailStop(SigShortB, CalculationMode.Ticks, Math.Max(1, ticks), false);
                }
            }
        }

        private void PlaceLongEntry()
        {
            double limitPrice = lower + EntryOffsetTicks * TickSize;
            bool useLimit = EntryOffsetTicks > 0;

            if (UseACPositionManagement && acRisk != null && acSizer != null && !UseScaleOut)
            {
                double plannedPrice = useLimit ? limitPrice : Close[0];
                if (TrySubmitAcEntry(MarketPosition.Long, plannedPrice, useLimit))
                {
                    tradesToday++;
                    Log($"{Time[0]} EnterLong AC qty={acLastQuantity} at {plannedPrice:F2} vwap={vwap:F2} up={upper:F2} lo={lower:F2} rsi={rsi[0]:F1}", false);
                    return;
                }
            }

            double price = useLimit ? limitPrice : 0.0;
            double tpLong = vwap - TpBufferTicks * TickSize;

            if (!UseScaleOut)
            {
                if (StopMode == StopChoice.BandBuffer)
                {
                    double stopL = lower - StopBufferTicks * TickSize;
                    SetStopLoss(CalculationMode.Price, stopL);
                    Log($"{Time[0]} Set stops/targets (LONG): stopL={stopL:F2} tp={tpLong:F2}", false);
                }
                else
                {
                    int ticks = (int)Math.Round((atr[0] * AtrStopMult) / TickSize);
                    SetStopLoss(CalculationMode.Ticks, Math.Max(1, ticks));
                    Log($"{Time[0]} Set stops/targets (LONG): stopTicks={ticks} tp={tpLong:F2}", false);
                }
                SetProfitTarget(CalculationMode.Price, tpLong);

                if (useLimit) EnterLongLimit(price);
                else EnterLong();
            }
            else
            {
                int qtyA = DefaultQuantity / 2; int qtyB = DefaultQuantity - qtyA;

                SetProfitTarget(SigLongA, CalculationMode.Price, tpLong);
                if (StopMode == StopChoice.BandBuffer)
                {
                    double stopL = lower - StopBufferTicks * TickSize;
                    SetStopLoss(SigLongA, CalculationMode.Price, stopL, false);
                    SetStopLoss(SigLongB, CalculationMode.Price, stopL, false);
                }
                else
                {
                    int ticks = (int)Math.Round((atr[0] * AtrStopMult) / TickSize);
                    SetStopLoss(SigLongA, CalculationMode.Ticks, Math.Max(1, ticks), false);
                    SetTrailStop(SigLongB, CalculationMode.Ticks, Math.Max(1, ticks), false);
                }
                Log($"{Time[0]} Set exits (LONG scale-out): tpA={tpLong:F2}", false);

                if (useLimit) { EnterLongLimit(qtyA, price, SigLongA); EnterLongLimit(qtyB, price, SigLongB); }
                else { EnterLong(qtyA, SigLongA); EnterLong(qtyB, SigLongB); }
            }
            tradesToday++;
            Log($"{Time[0]} EnterLong qty={DefaultQuantity} at {(useLimit?price:Close[0]):F2} vwap={vwap:F2} up={upper:F2} lo={lower:F2} rsi={rsi[0]:F1}", false);
        }

        private void PlaceShortEntry()
        {
            double limitPrice = upper - EntryOffsetTicks * TickSize;
            bool useLimit = EntryOffsetTicks > 0;

            if (UseACPositionManagement && acRisk != null && acSizer != null && !UseScaleOut)
            {
                double plannedPrice = useLimit ? limitPrice : Close[0];
                if (TrySubmitAcEntry(MarketPosition.Short, plannedPrice, useLimit))
                {
                    tradesToday++;
                    Log($"{Time[0]} EnterShort AC qty={acLastQuantity} at {plannedPrice:F2} vwap={vwap:F2} up={upper:F2} lo={lower:F2} rsi={rsi[0]:F1}", false);
                    return;
                }
            }

            double price = useLimit ? limitPrice : 0.0;
            double tpShort = vwap + TpBufferTicks * TickSize;

            if (!UseScaleOut)
            {
                if (StopMode == StopChoice.BandBuffer)
                {
                    double stopS = upper + StopBufferTicks * TickSize;
                    SetStopLoss(CalculationMode.Price, stopS);
                    Log($"{Time[0]} Set stops/targets (SHORT): stopS={stopS:F2} tp={tpShort:F2}", false);
                }
                else
                {
                    int ticks = (int)Math.Round((atr[0] * AtrStopMult) / TickSize);
                    SetStopLoss(CalculationMode.Ticks, Math.Max(1, ticks));
                    Log($"{Time[0]} Set stops/targets (SHORT): stopTicks={ticks} tp={tpShort:F2}", false);
                }
                SetProfitTarget(CalculationMode.Price, tpShort);

                if (useLimit) EnterShortLimit(price);
                else EnterShort();
            }
            else
            {
                int qtyA = DefaultQuantity / 2; int qtyB = DefaultQuantity - qtyA;

                SetProfitTarget(SigShortA, CalculationMode.Price, tpShort);
                if (StopMode == StopChoice.BandBuffer)
                {
                    double stopS = upper + StopBufferTicks * TickSize;
                    SetStopLoss(SigShortA, CalculationMode.Price, stopS, false);
                    SetStopLoss(SigShortB, CalculationMode.Price, stopS, false);
                }
                else
                {
                    int ticks = (int)Math.Round((atr[0] * AtrStopMult) / TickSize);
                    SetStopLoss(SigShortA, CalculationMode.Ticks, Math.Max(1, ticks), false);
                    SetTrailStop(SigShortB, CalculationMode.Ticks, Math.Max(1, ticks), false);
                }
                Log($"{Time[0]} Set exits (SHORT scale-out): tpA={tpShort:F2}", false);

                if (useLimit) { EnterShortLimit(qtyA, price, SigShortA); EnterShortLimit(qtyB, price, SigShortB); }
                else { EnterShort(qtyA, SigShortA); EnterShort(qtyB, SigShortB); }
            }
            tradesToday++;
            Log($"{Time[0]} EnterShort qty={DefaultQuantity} at {(useLimit?price:Close[0]):F2} vwap={vwap:F2} up={upper:F2} lo={lower:F2} rsi={rsi[0]:F1}", false);
        }

        private bool TrySubmitAcEntry(MarketPosition direction, double plannedPrice, bool useLimit)
        {
            if (acRisk == null || acSizer == null)
                return false;

            double rewardMultiple = acRisk.RewardToRiskMultiple;
            ACPositionSizingResult sizing = acSizer.Calculate(direction, plannedPrice, atr[0], rewardMultiple);

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

            acPendingSizing = sizing;
            acCurrentStop = stopPrice;
            acLastQuantity = quantity;

            if (direction == MarketPosition.Long)
            {
                if (useLimit)
                    EnterLongLimit(quantity, plannedPrice, signal);
                else
                    EnterLong(quantity, signal);
            }
            else
            {
                if (useLimit)
                    EnterShortLimit(quantity, plannedPrice, signal);
                else
                    EnterShort(quantity, signal);
            }

            return true;
        }

        private void ManageActivePosition()
        {
            if (acTrailing == null || acRisk == null)
                return;

            if (UseScaleOut)
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
                if (DebugPrints)
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
                    // ignore and fall back
                }
            }
            else
            {
                double cumulative = SystemPerformance.AllTrades.TradesPerformance.Currency.CumProfit;
                equityEstimate = Math.Max(1.0, ACAccountRiskBudget + cumulative);
            }

            return Math.Max(1.0, equityEstimate);
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
                acPendingSizing = null;
                acCurrentStop = double.NaN;
                acLastQuantity = 0;
            }

            acLastPosition = args.Position.MarketPosition;
        }
        protected override void OnOrderUpdate(Order order, double limitPrice, double stopPrice, int quantity, int filled, double averageFillPrice, OrderState orderState, DateTime time, ErrorCode error, string nativeError)
        {
            Log($"{time} ORDER {order?.OrderAction} {order?.Name} state={orderState} filled={filled}/{quantity} avg={averageFillPrice:F2} err={error} nerr={nativeError}", false);
        }

        protected override void OnExecutionUpdate(Execution execution, string executionId, double price, int quantity, MarketPosition marketPosition, string orderId, DateTime time)
        {
            if (execution == null) return;
            Log($"{time} EXEC {marketPosition} qty={quantity} price={price:F2} id={executionId} orderId={orderId}", false);
        }


        private void ResetSession()
        {
            cumPV = cumV = 0; lastBarVolume = 0; sessionBars = 0;
            welfordMean = 0; welfordM2 = 0; vwap = Close[0]; std = TickSize;
            upper = vwap + DevMult * std; lower = vwap - DevMult * std;
            touchedUpper = touchedLower = false; touchedUpperBar = touchedLowerBar = CurrentBar;
            tradesToday = 0;
            sessionProfitStart = SystemPerformance.AllTrades.TradesPerformance.Currency.CumProfit;
            acLastCumProfit = sessionProfitStart;
            acLastPosition = Position != null ? Position.MarketPosition : MarketPosition.Flat;
            acPendingSizing = null;
            acCurrentStop = double.NaN;
            acLastQuantity = 0;
            Log($"{Time[0]} Session reset", false);
        }

        private void Log(string msg, bool verbose = false)
        {
            if ((verbose && DebugPrints) || (!verbose && EventLogs))
                Print(msg);
        }

        private void DisarmFlags()
        { touchedUpper = touchedLower = false; }

        // ---------- Helpers & Properties ----------
        public enum StopChoice { BandBuffer, ATR }

        [NinjaScriptProperty, Range(1.25, 3.0), Display(Name = "DevMult", GroupName = "Parameters", Order = 1)]
        public double DevMult { get; set; }

        [NinjaScriptProperty, Display(Name = "UseBuiltInVWAPBands", GroupName = "Parameters", Order = 2)]
        public bool UseBuiltInVWAPBands { get; set; }

        [NinjaScriptProperty, Range(7, 21), Display(Name = "RsiPeriod", GroupName = "Parameters", Order = 10)]
        public int RsiPeriod { get; set; }

        [NinjaScriptProperty, Range(60, 80), Display(Name = "RsiOverbought", GroupName = "Parameters", Order = 11)]
        public int RsiOverbought { get; set; }

        [NinjaScriptProperty, Range(20, 40), Display(Name = "RsiOversold", GroupName = "Parameters", Order = 12)]
        public int RsiOversold { get; set; }

        [NinjaScriptProperty, Display(Name = "StopType", GroupName = "Parameters", Order = 20)]
        public StopChoice StopMode { get; set; }

        [NinjaScriptProperty, Range(2, 12), Display(Name = "StopBufferTicks", GroupName = "Parameters", Order = 21)]
        public int StopBufferTicks { get; set; }

        [NinjaScriptProperty, Range(0, 6), Display(Name = "TpBufferTicks", GroupName = "Parameters", Order = 22)]
        public int TpBufferTicks { get; set; }

        [NinjaScriptProperty, Range(7, 21), Display(Name = "AtrPeriod", GroupName = "Parameters", Order = 23)]
        public int AtrPeriod { get; set; }

        [NinjaScriptProperty, Range(1.0, 3.0), Display(Name = "AtrStopMult", GroupName = "Parameters", Order = 24)]
        public double AtrStopMult { get; set; }

        [NinjaScriptProperty, Display(Name = "UseScaleOut", GroupName = "Parameters", Order = 25)]
        public bool UseScaleOut { get; set; }

        [NinjaScriptProperty, Range(0, 3), Display(Name = "ReentryTicks", GroupName = "Parameters", Order = 30)]
        public int ReentryTicks { get; set; }

        [NinjaScriptProperty, Range(0, 3), Display(Name = "EntryOffsetTicks", GroupName = "Parameters", Order = 31)]
        public int EntryOffsetTicks { get; set; }

        [NinjaScriptProperty, Range(1, 8), Display(Name = "CooldownBars", GroupName = "Parameters", Order = 32)]
        public int CooldownBars { get; set; }

        [NinjaScriptProperty, Display(Name = "UseVwapBiasFilter", GroupName = "Parameters", Order = 40)]
        public bool UseVwapBiasFilter { get; set; }

        [NinjaScriptProperty, Display(Name = "UseTimeFilter", GroupName = "Parameters", Order = 41)]
        public bool UseTimeFilter { get; set; }

        [NinjaScriptProperty, Display(Name = "StartTime", GroupName = "Parameters", Order = 42)]
        public TimeSpan StartTime { get; set; }

        [NinjaScriptProperty, Display(Name = "EndTime", GroupName = "Parameters", Order = 43)]
        public TimeSpan EndTime { get; set; }

        [NinjaScriptProperty, Range(0, 60), Display(Name = "EndFlatMinutesBeforeClose", GroupName = "Parameters", Order = 44)]
        public int EndFlatMinutesBeforeClose { get; set; }

        [NinjaScriptProperty, Display(Name = "EnableBreakeven", GroupName = "Parameters", Order = 50)]
        public bool EnableBreakeven { get; set; }
        [NinjaScriptProperty, Display(Name = "EventLogs", GroupName = "Parameters", Order = 89)]
        public bool EventLogs { get; set; }


        [NinjaScriptProperty, Range(1, 30), Display(Name = "BreakevenTriggerTicks", GroupName = "Parameters", Order = 51)]
        public int BreakevenTriggerTicks { get; set; }

        [NinjaScriptProperty, Range(0, 10), Display(Name = "BreakevenPlusTicks", GroupName = "Parameters", Order = 52)]
        public int BreakevenPlusTicks { get; set; }

        [NinjaScriptProperty, Display(Name = "MaxDailyLossCurrency", GroupName = "Parameters", Order = 60)]
        public double MaxDailyLossCurrency { get; set; }

        [NinjaScriptProperty, Range(1, 200), Display(Name = "MaxDailyTrades", GroupName = "Parameters", Order = 61)]
        public int MaxDailyTrades { get; set; }

        [NinjaScriptProperty, Display(Name = "DebugPrints", GroupName = "Parameters", Order = 90)]
        public bool DebugPrints { get; set; }

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
    }
}

