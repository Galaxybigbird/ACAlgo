using System;
using NinjaTrader.Cbi;

namespace NinjaTrader.Custom.AC
{
    public sealed class ACPositionSizingResult
    {
        public MarketPosition Direction { get; set; }
        public double EntryPrice { get; set; }
        public double StopPrice { get; set; }
        public double TargetPrice { get; set; }
        public double StopDistance { get; set; }
        public double RewardDistance { get; set; }
        public double RiskPerContract { get; set; }
        public double RewardPerContract { get; set; }
        public double RewardMultiple { get; set; }
    }

    public class ACATRPositionSizer
    {
        private readonly double atrStopMultiplier;
        private readonly double minimumStopTicks;
        private readonly double tickSize;
        private readonly double pointValue;

        public ACATRPositionSizer(double atrStopMultiplier, double minimumStopTicks, double tickSize, double pointValue)
        {
            this.atrStopMultiplier = Math.Max(0.01, atrStopMultiplier);
            this.minimumStopTicks = Math.Max(0.0, minimumStopTicks);
            this.tickSize = Math.Max(1e-8, tickSize);
            this.pointValue = Math.Max(1e-8, pointValue);
        }

        public ACPositionSizingResult Calculate(MarketPosition direction, double entryPrice, double atrValue, double rewardMultiple)
        {
            if (direction == MarketPosition.Flat)
                throw new ArgumentException("Direction cannot be flat when sizing.");

            double atrDistance = Math.Max(0.0, atrValue);
            double stopDistance = Math.Max(atrDistance * atrStopMultiplier, minimumStopTicks * tickSize);

            if (stopDistance <= 0.0)
                stopDistance = tickSize * Math.Max(1.0, minimumStopTicks);

            double rewardMult = Math.Max(0.1, rewardMultiple);
            double rewardDistance = stopDistance * rewardMult;

            double stopPrice = direction == MarketPosition.Long
                ? entryPrice - stopDistance
                : entryPrice + stopDistance;

            double targetPrice = direction == MarketPosition.Long
                ? entryPrice + rewardDistance
                : entryPrice - rewardDistance;

            double riskPerContract = stopDistance * pointValue;
            double rewardPerContract = rewardDistance * pointValue;

            return new ACPositionSizingResult
            {
                Direction = direction,
                EntryPrice = entryPrice,
                StopPrice = stopPrice,
                TargetPrice = targetPrice,
                StopDistance = stopDistance,
                RewardDistance = rewardDistance,
                RiskPerContract = riskPerContract,
                RewardPerContract = rewardPerContract,
                RewardMultiple = rewardMult
            };
        }
    }
}
