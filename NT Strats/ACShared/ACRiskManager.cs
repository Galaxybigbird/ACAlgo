using System;

namespace NinjaTrader.Custom.AC
{
    /// <summary>
    /// Settings payload for configuring the asymmetrical compounding risk manager.
    /// </summary>
    public sealed class ACRiskSettings
    {
        public double BaseRiskPercent { get; set; } = 1.0;
        public double BaseRewardMultiple { get; set; } = 3.0;
        public int CompoundingWins { get; set; } = 2;
        public bool UsePartialCompounding { get; set; } = false;
        public double PartialCompoundingPercent { get; set; } = 100.0;
        public bool RequireTargetHitForCompounding { get; set; } = true;
        public double MaxRiskPercent { get; set; } = 25.0;
        public double MinRiskPercent { get; set; } = 0.01;
    }

    /// <summary>
    /// Runtime state for the asymmetrical compounding risk model used by the AC algorithms.
    /// </summary>
    public class ACRiskManager
    {
        private ACRiskSettings settings;
        private double baseRisk;
        private double rewardMultiple;
        private double currentRisk;
        private double currentReward;
        private int compoundingWins;
        private int consecutiveWins;

        public void Initialize(ACRiskSettings config)
        {
            settings = config ?? throw new ArgumentNullException(nameof(config));

            baseRisk = Math.Max(config.MinRiskPercent, config.BaseRiskPercent);
            rewardMultiple = Math.Max(0.01, config.BaseRewardMultiple);
            compoundingWins = Math.Max(1, config.CompoundingWins);

            ResetToBase();
        }

        public double CurrentRiskPercent => currentRisk;
        public double CurrentRewardPercent => currentReward;
        public int ConsecutiveWins => consecutiveWins;
        public double RewardToRiskMultiple => currentRisk > 0.0 ? currentReward / currentRisk : rewardMultiple;

        /// <summary>
        /// Reset all cycle counters back to the base risk configuration.
        /// </summary>
        public void ResetToBase()
        {
            currentRisk = Math.Max(settings.MinRiskPercent, baseRisk);
            currentReward = currentRisk * rewardMultiple;
            consecutiveWins = 0;
        }

        public void OnTradeClosed(bool wasWin, double realizedProfitPercent)
        {
            if (!wasWin)
            {
                ResetToBase();
                return;
            }

            consecutiveWins++;

            if (settings.RequireTargetHitForCompounding && realizedProfitPercent + 1e-8 < currentReward)
            {
                return; // Win recorded but target not met – keep risk static.
            }

            if (consecutiveWins >= compoundingWins)
            {
                ResetToBase();
                return;
            }

            double rewardContribution = settings.UsePartialCompounding
                ? currentReward * Math.Max(0.0, Math.Min(100.0, settings.PartialCompoundingPercent)) / 100.0
                : currentReward;

            currentRisk = Math.Min(settings.MaxRiskPercent, currentRisk + rewardContribution);
            currentRisk = Math.Max(settings.MinRiskPercent, currentRisk);
            currentReward = currentRisk * rewardMultiple;
        }

        /// <summary>
        /// Calculate the nearest valid contract quantity given the account budget and per-contract risk.
        /// </summary>
        public int ComputePositionQuantity(double accountEquity, double riskPerContract, int minimumContracts, int maximumContracts, int contractStep)
        {
            if (riskPerContract <= 0 || accountEquity <= 0)
                return Math.Max(0, minimumContracts);

            double allowedRiskCurrency = (currentRisk / 100.0) * accountEquity;
            if (allowedRiskCurrency <= 0)
                return Math.Max(0, minimumContracts);

            double rawContracts = allowedRiskCurrency / riskPerContract;
            if (contractStep <= 0) contractStep = 1;

            int rounded = (int)Math.Round(rawContracts / contractStep) * contractStep;
            if (rounded < minimumContracts)
                rounded = minimumContracts;
            if (maximumContracts > 0 && rounded > maximumContracts)
                rounded = maximumContracts;

            return Math.Max(0, rounded);
        }
    }
}
