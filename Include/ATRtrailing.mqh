//+------------------------------------------------------------------+
//|                                                ATRtrailing.mqh |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.01"
#property strict

#include <SymbolValidator.mqh>

// Input parameters for DEMA-ATR trailing stop
input group    "==== DEMA-ATR Trailing ====";
input int      DEMA_ATR_Period = 14;       // DEMA ATR Period
input double   DEMA_ATR_Multiplier = 1.5;  // DEMA ATR Multiplier
input double   TrailingActivationPercent = 1.0; // Activate trailing at this profit %
input bool     UseATRTrailing = true;      // Enable DEMA-ATRTrailing
input bool     UseTrailingOnCompoundedTrades = false; // UseTrailingOnCompoundedTrades
input bool     UseTimedDelayedTrailing = false; // UseTimedDelayedTrailing
input int      TrailingDelayMinutes = 5;   // TrailingDelayMinutes
input double   MinimumStopDistance = 400.0; // MINIMUMStopDistance in points

// Retained constant name for compatibility with legacy modules/tests
string         ButtonName = "StartTrailing";

// Manual activation flag (legacy toggle kept for compatibility with helper functions)
bool           ManualTrailingActivated = false;  // Flag for manual trailing activation

// Visual feedback colours for the manual trailing button
const color    ButtonColorActive   = clrLimeGreen;
const color    ButtonColorInactive = clrDimGray;

// Buffers for DEMA ATR calculation
double AtrDEMA[], Ema1[], Ema2[];  // buffers for DEMA ATR, and intermediate EMAs

// Variables to store modifiable versions of input parameters
double CurrentATRMultiplier;            // Current ATR multiplier (can be modified)
int CurrentATRPeriod;                   // Current ATR period (can be modified)

// Statistics tracking
int SuccessfulTrailingUpdates = 0;
int FailedTrailingUpdates = 0;
double WorstCaseSlippage = 0;
double BestCaseProfit = 0;

// Timed delayed trailing state tracking
ulong    TimedTrailingTickets[];
double   TimedTrailingRemainingSeconds[];
bool     TimedTrailingTriggered[];
bool     TimedTrailingTimerRunning[];
datetime TimedTrailingLastUpdate[];

//+------------------------------------------------------------------+
//| Reset trailing stop statistics                                    |
//+------------------------------------------------------------------+
void ResetTrailingStats()
{
    SuccessfulTrailingUpdates = 0;
    FailedTrailingUpdates = 0;
    WorstCaseSlippage = 0;
    BestCaseProfit = 0;
}

//+------------------------------------------------------------------+
//| Reset all timed trailing states                                   |
//+------------------------------------------------------------------+
void ResetTimedTrailingStates()
{
    ArrayResize(TimedTrailingTickets, 0);
    ArrayResize(TimedTrailingRemainingSeconds, 0);
    ArrayResize(TimedTrailingTriggered, 0);
    ArrayResize(TimedTrailingTimerRunning, 0);
    ArrayResize(TimedTrailingLastUpdate, 0);
}

//+------------------------------------------------------------------+
//| Find the index of a ticket in the timed trailing arrays           |
//+------------------------------------------------------------------+
int FindTimedTrailingStateIndex(ulong ticket)
{
    for(int i = 0; i < ArraySize(TimedTrailingTickets); ++i)
    {
        if(TimedTrailingTickets[i] == ticket)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Ensure a timed trailing state exists for the ticket               |
//+------------------------------------------------------------------+
int EnsureTimedTrailingState(ulong ticket, double initialSeconds)
{
    int idx = FindTimedTrailingStateIndex(ticket);
    if(idx >= 0)
        return idx;

    int newSize = ArraySize(TimedTrailingTickets) + 1;
    ArrayResize(TimedTrailingTickets, newSize);
    ArrayResize(TimedTrailingRemainingSeconds, newSize);
    ArrayResize(TimedTrailingTriggered, newSize);
    ArrayResize(TimedTrailingTimerRunning, newSize);
    ArrayResize(TimedTrailingLastUpdate, newSize);

    idx = newSize - 1;
    TimedTrailingTickets[idx] = ticket;
    TimedTrailingRemainingSeconds[idx] = MathMax(0.0, initialSeconds);
    TimedTrailingTriggered[idx] = false;
    TimedTrailingTimerRunning[idx] = false;
    TimedTrailingLastUpdate[idx] = TimeCurrent();

    return idx;
}

//+------------------------------------------------------------------+
//| Remove timed trailing state when position is gone                |
//+------------------------------------------------------------------+
void RemoveTimedTrailingState(ulong ticket)
{
    int idx = FindTimedTrailingStateIndex(ticket);
    if(idx < 0)
        return;

    int last = ArraySize(TimedTrailingTickets) - 1;
    if(last < 0)
        return;

    if(idx != last)
    {
        TimedTrailingTickets[idx] = TimedTrailingTickets[last];
        TimedTrailingRemainingSeconds[idx] = TimedTrailingRemainingSeconds[last];
        TimedTrailingTriggered[idx] = TimedTrailingTriggered[last];
        TimedTrailingTimerRunning[idx] = TimedTrailingTimerRunning[last];
        TimedTrailingLastUpdate[idx] = TimedTrailingLastUpdate[last];
    }

    ArrayResize(TimedTrailingTickets, last);
    ArrayResize(TimedTrailingRemainingSeconds, last);
    ArrayResize(TimedTrailingTriggered, last);
    ArrayResize(TimedTrailingTimerRunning, last);
    ArrayResize(TimedTrailingLastUpdate, last);
}

//+------------------------------------------------------------------+
//| Check if timed trailing has forced activation for ticket          |
//+------------------------------------------------------------------+
bool TimedTrailingIsForced(ulong ticket)
{
    if(ticket == 0)
        return false;

    int idx = FindTimedTrailingStateIndex(ticket);
    if(idx < 0)
        return false;

    return TimedTrailingTriggered[idx];
}

//+------------------------------------------------------------------+
//| Update timed trailing state and return activation status          |
//+------------------------------------------------------------------+
bool UpdateTimedDelayedTrailing(ulong ticket, bool thresholdReached, double profitPercent)
{
    if(ticket == 0)
        return false;

    if(!UseTimedDelayedTrailing)
    {
        RemoveTimedTrailingState(ticket);
        return false;
    }

    if(UseATRTrailing)
    {
        RemoveTimedTrailingState(ticket);
        return false;
    }

    double delaySeconds = MathMax(0, TrailingDelayMinutes) * 60.0;
    datetime now = TimeCurrent();

    int idx = FindTimedTrailingStateIndex(ticket);

    if(idx < 0)
    {
        if(!thresholdReached)
            return false;

        idx = EnsureTimedTrailingState(ticket, delaySeconds);

        if(TimedTrailingRemainingSeconds[idx] <= 0.0)
        {
            TimedTrailingTriggered[idx] = true;
            PrintFormat("Timed delayed trailing activated immediately for ticket %I64u at %.2f%% profit (no delay).", ticket, profitPercent);
            return true;
        }

        TimedTrailingTimerRunning[idx] = true;
        TimedTrailingLastUpdate[idx] = now;
        PrintFormat("Timed trailing countdown started for ticket %I64u at %.2f%% profit. Delay: %d minutes.",
                    ticket,
                    profitPercent,
                    TrailingDelayMinutes);
    }

    if(TimedTrailingTriggered[idx])
        return true;

    if(thresholdReached)
    {
        if(!TimedTrailingTimerRunning[idx])
        {
            TimedTrailingTimerRunning[idx] = true;
            TimedTrailingLastUpdate[idx] = now;
            PrintFormat("Timed trailing countdown resumed for ticket %I64u. Remaining %.0f seconds.",
                        ticket,
                        TimedTrailingRemainingSeconds[idx]);
        }
        else
        {
            double elapsed = (double)(now - TimedTrailingLastUpdate[idx]);
            if(elapsed > 0.0)
            {
                TimedTrailingRemainingSeconds[idx] = MathMax(0.0, TimedTrailingRemainingSeconds[idx] - elapsed);
                TimedTrailingLastUpdate[idx] = now;
            }
        }

        if(TimedTrailingRemainingSeconds[idx] <= 0.0)
        {
            TimedTrailingTriggered[idx] = true;
            TimedTrailingTimerRunning[idx] = false;
            PrintFormat("Timed trailing delay met for ticket %I64u. Activating ATR trailing.", ticket);
            return true;
        }
    }
    else
    {
        if(TimedTrailingTimerRunning[idx])
        {
            TimedTrailingTimerRunning[idx] = false;
            TimedTrailingLastUpdate[idx] = now;
            PrintFormat("Timed trailing paused for ticket %I64u. Remaining %.0f seconds.",
                        ticket,
                        TimedTrailingRemainingSeconds[idx]);
        }
    }

    return TimedTrailingTriggered[idx];
}

//+------------------------------------------------------------------+
//| Helper: detect whether a trade comment marks a compounded trade  |
//+------------------------------------------------------------------+
bool CommentIndicatesCompounding(const string comment)
{
    if(StringLen(comment) == 0)
        return false;

    // Trade comments follow the pattern "AC|C#/#|RR#" for compounded stages
    return (StringFind(comment, "AC|C") == 0);
}

//+------------------------------------------------------------------+
//| Helper: determine if trailing is allowed for the position        |
//+------------------------------------------------------------------+
bool TrailingAllowedForPosition(const string positionComment, ulong positionTicket = 0)
{
    if(ManualTrailingActivated)
        return true;

    if(UseATRTrailing)
        return true;

    if(positionTicket != 0 && TimedTrailingIsForced(positionTicket))
        return true;

    if(!UseTrailingOnCompoundedTrades)
        return false;

    return CommentIndicatesCompounding(positionComment);
}

//+------------------------------------------------------------------+
//| Helper: detect compounded override activation                    |
//+------------------------------------------------------------------+
bool IsCompoundedTrailingOverride(const string positionComment)
{
    if(ManualTrailingActivated)
        return false;

    if(UseATRTrailing)
        return false;

    if(!UseTrailingOnCompoundedTrades)
        return false;

    return CommentIndicatesCompounding(positionComment);
}

//+------------------------------------------------------------------+
//| Clean up all objects when EA is removed                           |
//+------------------------------------------------------------------+
void CleanupATRTrailing()
{
    // Print final statistics when available
    if(SuccessfulTrailingUpdates > 0 || FailedTrailingUpdates > 0)
    {
        Print("=== ATR Trailing Summary ===");
        Print("Successful trailing updates: ", SuccessfulTrailingUpdates);
        Print("Failed trailing updates: ", FailedTrailingUpdates);
        
        if(SuccessfulTrailingUpdates > 0)
        {
            double successRate = 100.0 * SuccessfulTrailingUpdates / (SuccessfulTrailingUpdates + FailedTrailingUpdates);
            Print("Success rate: ", DoubleToString(successRate, 2), "%");
            Print("Worst-case slippage distance: ", DoubleToString(WorstCaseSlippage * Point(), _Digits), " points");
            Print("Best-case profit distance: ", DoubleToString(BestCaseProfit * Point(), _Digits), " points");
        }
        Print("==========================");
    }

    // No chart objects to manage - visual output removed for tester compatibility
    ClearVisualization();

    // Clear timed trailing state cache
    ResetTimedTrailingStates();
}

//+------------------------------------------------------------------+
//| Initialize DEMA-ATR arrays and settings                          |
//+------------------------------------------------------------------+
void InitDEMAATR()
{
    // Initialize working parameters with input values
    CurrentATRMultiplier = DEMA_ATR_Multiplier;
    CurrentATRPeriod = DEMA_ATR_Period;
    
    // Initialize arrays
    ArrayResize(AtrDEMA, 100);
    ArrayResize(Ema1, 100);
    ArrayResize(Ema2, 100);
    ArrayInitialize(AtrDEMA, 0);
    ArrayInitialize(Ema1, 0);
    ArrayInitialize(Ema2, 0);

    // Reset statistics
    ResetTrailingStats();

    // Reset timed trailing states for clean session start
    ResetTimedTrailingStates();
}

//+------------------------------------------------------------------+
//| Calculate DEMA-ATR value for the current bar                     |
//+------------------------------------------------------------------+
double CalculateDEMAATR(int period = 0)
{
    int atrPeriod = (period > 0) ? period : CurrentATRPeriod;
    
    // Get price data for calculation
    MqlRates rates[];
    int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, atrPeriod + 1 + period, rates);
    
    if(copied < atrPeriod + 1 + period)
    {
        Print("Error copying rates data: ", GetLastError());
        return 0.0;
    }
    
    double alpha = 2.0 / (atrPeriod + 1);  // EMA smoothing factor for DEMA
    
    // Calculate initial ATR if needed
    if(Ema1[0] == 0)
    {
        double sumTR = 0.0;
        for(int j = 0; j < atrPeriod; j++)
        {
            int idx = copied - 1 - j;
            double trj;
            if(j == 0)
                trj = rates[idx].high - rates[idx].low;
            else
            {
                double tr1 = rates[idx].high - rates[idx].low;
                double tr2 = MathAbs(rates[idx].high - rates[idx+1].close);
                double tr3 = MathAbs(rates[idx].low - rates[idx+1].close);
                trj = MathMax(tr1, MathMax(tr2, tr3));
            }
            sumTR += trj;
        }
        double initialATR = sumTR / atrPeriod;
        Ema1[0] = initialATR;
        Ema2[0] = initialATR;
        AtrDEMA[0] = initialATR;
    }
    
    // Calculate current TR
    double TR_current;
    int current = copied - 1 - period;
    int prev = copied - 2 - period;
    
    if(prev < 0)
    {
        TR_current = rates[current].high - rates[current].low;
    }
    else
    {
        double tr1 = rates[current].high - rates[current].low;
        double tr2 = MathAbs(rates[current].high - rates[prev].close);
        double tr3 = MathAbs(rates[current].low - rates[prev].close);
        TR_current = MathMax(tr1, MathMax(tr2, tr3));
    }
    
    // Update EMA1, EMA2, and DEMA-ATR
    double ema1_current = Ema1[0] + alpha * (TR_current - Ema1[0]);
    double ema2_current = Ema2[0] + alpha * (ema1_current - Ema2[0]);
    double dema_atr = 2.0 * ema1_current - ema2_current;
    
    // Store values for next calculation
    Ema1[0] = ema1_current;
    Ema2[0] = ema2_current;
    AtrDEMA[0] = dema_atr;
    
    return dema_atr;
}

//+------------------------------------------------------------------+
//| Check if trailing stop should be activated                       |
//+------------------------------------------------------------------+
bool ShouldActivateTrailing(double entryPrice, double currentPrice, string orderType, double volume,
                            bool compoundedOverride = false, ulong positionTicket = 0)
{
    // Manual override always activates trailing regardless of settings
    if(ManualTrailingActivated)
        return true;

    bool trailingEnabled = UseATRTrailing || compoundedOverride;

    static double lastTrackedEntryPrice = 0.0;
    static bool activationLogged = false;
    
    // Calculate profit metrics
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double pointValue = g_SymbolValidator.Point();
    double tickValue = g_SymbolValidator.TickValue();
    double tickSize = g_SymbolValidator.TickSize();
    
    if(accountBalance <= 0.0 || pointValue <= 0.0)
        return false;
    
    double pipValue = tickValue;
    if(tickSize > 0.0)
        pipValue = tickValue * (pointValue / tickSize);
    if(pipValue == 0.0)
        pipValue = tickValue;
    if(pipValue == 0.0)
        pipValue = 1.0;
    
    // Calculate profit in account currency
    double priceDiff = (orderType == "BUY" ? currentPrice - entryPrice : entryPrice - currentPrice);
    double profitPoints = priceDiff / pointValue;
    double profitCurrency = profitPoints * pipValue * volume;
    
    // Calculate profit as percentage of account balance
    double profitPercent = (profitCurrency / accountBalance) * 100.0;
    
    double threshold = TrailingActivationPercent - 0.0000001;
    bool reached = (profitPercent >= threshold);

    bool timedTriggered = false;
    if(!UseATRTrailing && !compoundedOverride)
        timedTriggered = UpdateTimedDelayedTrailing(positionTicket, reached, profitPercent);

    if(timedTriggered)
        trailingEnabled = true;
    
    if(!trailingEnabled)
        return false;
    
    if(MathAbs(entryPrice - lastTrackedEntryPrice) > pointValue * 0.5)
    {
        activationLogged = false;
        lastTrackedEntryPrice = entryPrice;
    }
    
    if(!reached && activationLogged && profitPercent < threshold * 0.5)
        activationLogged = false;
    
    if(reached && !activationLogged)
    {
        PrintFormat("ATR trailing activation triggered at %.2f%% profit (%.1f pts, %.2f %s) ≥ %.2f%% threshold",
                    profitPercent,
                    profitPoints,
                    profitCurrency,
                    AccountInfoString(ACCOUNT_CURRENCY),
                    TrailingActivationPercent);
        activationLogged = true;
    }
    
    // Check if profit percentage exceeds activation threshold
    // Add a small epsilon (0.0000001) to handle floating-point precision issues
    return (reached || timedTriggered);
}

//+------------------------------------------------------------------+
//| Calculate trailing stop level based on DEMA-ATR                  |
//+------------------------------------------------------------------+
double CalculateTrailingStop(string orderType, double currentPrice, double originalStop = 0.0)
{
    double demaAtr = CalculateDEMAATR();
    double trailingDistance = MathMax(demaAtr * CurrentATRMultiplier, MinimumStopDistance * Point());
    
    // Calculate theoretical trailing stop level based on order type
    double theoreticalStop;
    
    if(orderType == "BUY")
        theoreticalStop = currentPrice - trailingDistance;
    else
        theoreticalStop = currentPrice + trailingDistance;
    
    // If we have an original stop, only move in favorable direction
    if(originalStop > 0.0) 
    {
        // *** EXTREME VOLATILITY CHECK ***
        // Detect extreme volatility - when ATR is abnormally high (over 500 points)
        if(demaAtr/Point() > 500)
        {
            bool extremeVolatilityDetected = true;
            
            // During extreme volatility, always keep the more conservative stop
            if(orderType == "BUY" && originalStop > theoreticalStop)
            {
                return originalStop;
            }
            else if(orderType == "SELL" && originalStop < theoreticalStop)
            {
                return originalStop;
            }
        }
        
        // *** VERY DISTANT STOP CHECK ***
        // For stops that are already very far from current price (conservative stops)
        double entryPrice = 0; // We don't have entry price here, use current price as reference
        if(orderType == "BUY")
        {
            // If stop is more than 1500 points from current price, consider it a very distant stop
            if(MathAbs(originalStop - currentPrice)/Point() > 1500) 
            {
                // If the original stop is more conservative than theoretical stop
                if(originalStop < theoreticalStop) 
                {
                    return originalStop;
                }
            }
        }
        else if(orderType == "SELL")
        {
            // If stop is more than 1500 points from current price, consider it a very distant stop
            if(MathAbs(originalStop - currentPrice)/Point() > 1500) 
            {
                // If the original stop is more conservative than theoretical stop
                if(originalStop > theoreticalStop) 
                {
                    return originalStop;
                }
            }
        }
        
        // Normal direction checks
        if(orderType == "BUY")
        {
            // For buy positions, only move the stop up, never down
            if(theoreticalStop <= originalStop)
            {
                return originalStop;
            }
            
            // During extreme volatility, the stop might move too close to entry
            // If the original stop is very far (conservative), keep it
            if(MathAbs(currentPrice - theoreticalStop) < MathAbs(currentPrice - originalStop) * 0.5)
            {
                // If extreme volatility would make stop less conservative, keep original
                return originalStop;
            }
        }
        else if(orderType == "SELL")
        {
            // For sell positions, only move the stop down, never up
            if(theoreticalStop >= originalStop)
            {
                return originalStop;
            }
            
            // During extreme volatility, the stop might move too close to entry
            // If the original stop is very far (conservative), keep it
            if(MathAbs(currentPrice - theoreticalStop) < MathAbs(currentPrice - originalStop) * 0.5)
            {
                // If extreme volatility would make stop less conservative, keep original
                return originalStop;
            }
        }
    }
    
    // Return the new stop level
    return theoreticalStop;
}

//+------------------------------------------------------------------+
//| Update trailing stop for a position                              |
//+------------------------------------------------------------------+
bool UpdateTrailingStop(ulong ticket, double entryPrice, string orderType)
{
    // Get position information - try select by ticket first
    if(!PositionSelectByTicket(ticket))
    {
        Print("ERROR: Cannot select position ticket ", ticket, " - ", GetLastError());
        RemoveTimedTrailingState(ticket);
        return false;
    }

    string positionComment = PositionGetString(POSITION_COMMENT);
    if(!TrailingAllowedForPosition(positionComment, ticket))
        return false;
    
    // Get current position data
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double currentTP = PositionGetDouble(POSITION_TP);
    
    // Calculate new trailing stop level
    double newSL = CalculateTrailingStop(orderType, currentPrice, currentSL);
    
    // AGGRESSIVE MANUAL TRAILING: Force it to move on manual activation
    if(ManualTrailingActivated)
    {
        double atrValue = CalculateDEMAATR();
        double trailingDistance = MathMax(atrValue * CurrentATRMultiplier, MinimumStopDistance * Point());
        
        if(orderType == "BUY")
        {
            // For BUY orders, consider a forced tighter stop when manually activated
            double forcedStop = currentPrice - trailingDistance * 0.8;  // 20% tighter
            
            // Only move stop up for BUY orders
            if(forcedStop > currentSL)
            {
                newSL = forcedStop;
                Print("MANUAL TRAILING FORCE: Moving BUY stop to ", newSL);
            }
            else
            {
                // If we can't move the stop favorably, avoid setting it to the raw ATR value
                // and simply maintain the current stop
                Print("MANUAL TRAILING: Cannot move BUY stop up further");
                return false;
            }
        }
        else if(orderType == "SELL")
        {
            // For SELL orders, consider a forced tighter stop when manually activated
            double forcedStop = currentPrice + trailingDistance * 0.8;  // 20% tighter
            
            // Only move stop down for SELL orders
            if(forcedStop < currentSL)
            {
                newSL = forcedStop;
                Print("MANUAL TRAILING FORCE: Moving SELL stop to ", newSL);
            }
            else
            {
                // If we can't move the stop favorably, avoid setting it to the raw ATR value
                // and simply maintain the current stop
                Print("MANUAL TRAILING: Cannot move SELL stop down further");
                return false;
            }
        }
    }
    
    // Only update if there's a meaningful change (more than 1 point)
    if(MathAbs(newSL - currentSL) < Point())
    {
        return false;
    }
    
    // Verify the stop is moving in the correct direction
    bool shouldUpdateStop = false;
    
    if(orderType == "BUY" && newSL > currentSL)
    {
        shouldUpdateStop = true;
        Print("Moving BUY stop up from ", currentSL, " to ", newSL);
    }
    else if(orderType == "SELL" && newSL < currentSL)
    {
        shouldUpdateStop = true;
        Print("Moving SELL stop down from ", currentSL, " to ", newSL);
    }
    
    // Only update if stop should move
    if(!shouldUpdateStop)
    {
        return false;
    }
    
    // Prepare the trade request
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.symbol = _Symbol;
    request.sl = newSL;
    request.tp = currentTP;  // Keep existing TP
    
    // Log the trade request
    Print("SENDING STOP UPDATE: Position ", ticket, ", New SL: ", newSL);
    
    // Send the request directly without additional checks
    if(!OrderSend(request, result))
    {
        Print("ERROR updating trailing stop: ", GetLastError(), " - ", 
              result.retcode, " ", result.comment);
        FailedTrailingUpdates++;
        return false;
    }
    
    // Success - log the update and update stats
    Print("✓ TRAILING STOP UPDATED: Position ", ticket, " - New SL: ", newSL, 
          ManualTrailingActivated ? " (Manual)" : " (Auto)");
    
    // Update statistics
    SuccessfulTrailingUpdates++;
    
    // Update tracking stats
    double potentialSlippage = MathAbs(currentPrice - newSL) / Point();
    if(potentialSlippage > WorstCaseSlippage)
        WorstCaseSlippage = potentialSlippage;
        
    double profitInPoints = MathAbs(currentPrice - entryPrice) / Point();
    if(profitInPoints > BestCaseProfit)
        BestCaseProfit = profitInPoints;
    
    return true;
}

//+------------------------------------------------------------------+
//| Update visualization of ATR trailing stop levels                  |
//+------------------------------------------------------------------+
void UpdateVisualization()
{
    // Visualization removed for tester compatibility
}

//+------------------------------------------------------------------+
//| Clear all visualization objects                                   |
//+------------------------------------------------------------------+
void ClearVisualization()
{
    // Visualization removed for tester compatibility
}

//+------------------------------------------------------------------+
//| Set custom ATR parameters                                         |
//+------------------------------------------------------------------+
void SetATRParameters(double atrMultiplier, int atrPeriod)
{
    // Save original values to revert if needed
    double originalMultiplier = CurrentATRMultiplier;
    int originalPeriod = CurrentATRPeriod;
    
    // Update with new values
    CurrentATRMultiplier = atrMultiplier;
    CurrentATRPeriod = atrPeriod;
    
    // Reset ATR arrays when changing period
    if(originalPeriod != atrPeriod)
    {
        ArrayInitialize(AtrDEMA, 0);
        ArrayInitialize(Ema1, 0);
        ArrayInitialize(Ema2, 0);
    }
    
    Print("ATR Parameters updated - Multiplier: ", atrMultiplier, ", Period: ", atrPeriod);
    
    // Update visualization if enabled
    UpdateVisualization();
}

//+------------------------------------------------------------------+
//| Utility function to get string order type from enum               |
//+------------------------------------------------------------------+
string OrderTypeToString(ENUM_ORDER_TYPE orderType)
{
    switch(orderType)
    {
        case ORDER_TYPE_BUY:
        case ORDER_TYPE_BUY_LIMIT:
        case ORDER_TYPE_BUY_STOP:
        case ORDER_TYPE_BUY_STOP_LIMIT:
            return "BUY";
        case ORDER_TYPE_SELL:
        case ORDER_TYPE_SELL_LIMIT:
        case ORDER_TYPE_SELL_STOP:
        case ORDER_TYPE_SELL_STOP_LIMIT:
            return "SELL";
        default:
            return "UNKNOWN";
    }
}
