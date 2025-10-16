using System;
using NinjaTrader.Cbi;

namespace NinjaTrader.Custom.AC
{
    public class ACTrailingManager
    {
        private readonly double atrMultiplier;
        private readonly double activationPercent;
        private readonly double minimumStopTicks;
        private readonly double tickSize;
        private readonly double pointValue;
        private readonly int atrPeriod;

        private bool emaInitialized;
        private double ema1;
        private double ema2;
        private double lastDemaAtr;

        public ACTrailingManager(double atrMultiplier, double activationPercent, double minimumStopTicks, double tickSize, double pointValue, int atrPeriod)
        {
            this.atrMultiplier = Math.Max(0.01, atrMultiplier);
            this.activationPercent = Math.Max(0.0, activationPercent);
            this.minimumStopTicks = Math.Max(0.0, minimumStopTicks);
            this.tickSize = Math.Max(1e-8, tickSize);
            this.pointValue = Math.Max(1e-8, pointValue);
            this.atrPeriod = Math.Max(1, atrPeriod);
        }

        public void Reset()
        {
            emaInitialized = false;
            ema1 = ema2 = lastDemaAtr = 0.0;
        }

        public double UpdateAtr(double atrValue)
        {
            double value = Math.Max(0.0, atrValue);
            double alpha = 2.0 / (atrPeriod + 1.0);

            if (!emaInitialized)
            {
                ema1 = value;
                ema2 = value;
                emaInitialized = true;
            }
            else
            {
                ema1 = ema1 + alpha * (value - ema1);
                ema2 = ema2 + alpha * (ema1 - ema2);
            }

            lastDemaAtr = Math.Max(0.0, 2.0 * ema1 - ema2);
            return lastDemaAtr;
        }

        public bool ShouldActivate(MarketPosition position, double entryPrice, double currentPrice, int quantity, double accountEquity)
        {
            if (activationPercent <= 0.0)
                return true;

            if (position == MarketPosition.Flat || quantity <= 0 || accountEquity <= 0.0)
                return false;

            double priceDelta = position == MarketPosition.Long
                ? currentPrice - entryPrice
                : entryPrice - currentPrice;

            if (priceDelta <= 0.0)
                return false;

            double profitCurrency = priceDelta * pointValue * quantity;
            double profitPercent = (profitCurrency / accountEquity) * 100.0;
            return profitPercent >= activationPercent - 1e-8;
        }

        public bool TryGetTrailingStop(MarketPosition position, double currentPrice, double currentStopPrice, out double newStopPrice)
        {
            newStopPrice = currentStopPrice;

            if (position == MarketPosition.Flat)
                return false;

            double trailingDistance = Math.Max(lastDemaAtr * atrMultiplier, minimumStopTicks * tickSize);
            if (trailingDistance <= 0.0)
                return false;

            double candidate = position == MarketPosition.Long
                ? currentPrice - trailingDistance
                : currentPrice + trailingDistance;

            if (position == MarketPosition.Long)
            {
                if (currentStopPrice <= double.Epsilon || candidate > currentStopPrice + tickSize * 0.5)
                {
                    newStopPrice = candidate;
                    return true;
                }
            }
            else
            {
                if (currentStopPrice <= double.Epsilon || candidate < currentStopPrice - tickSize * 0.5)
                {
                    newStopPrice = candidate;
                    return true;
                }
            }

            return false;
        }
    }
}
