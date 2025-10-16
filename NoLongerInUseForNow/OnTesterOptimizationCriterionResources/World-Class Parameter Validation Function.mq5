//+------------------------------------------------------------------+
//| World-Class Parameter Validation Function                        |
//+------------------------------------------------------------------+
double OnTester()
{
    //--- Get deals history
    HistorySelect(0, TimeCurrent());
    int total_deals = HistoryDealsTotal();
    if(total_deals < 50) return -DBL_MAX; // Minimum 50 trades required

    //--- Get initial deposit from tester
    double deposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
    if(deposit <= 0) deposit = 500;

    //--- Calculate time ranges with proper validation
    ulong first_deal_ticket = HistoryDealGetTicket(0);
    ulong last_deal_ticket = HistoryDealGetTicket(total_deals-1);
    
    datetime first_deal_time = (datetime)HistoryDealGetInteger(first_deal_ticket, DEAL_TIME);
    datetime last_deal_time = (datetime)HistoryDealGetInteger(last_deal_ticket, DEAL_TIME);
    
    if(first_deal_time >= last_deal_time) return -DBL_MAX;

    // Use 70/30 split with 1-day gap between IS and OOS
    long total_seconds = last_deal_time - first_deal_time;
    datetime IS_end = first_deal_time + (datetime)(total_seconds * 0.7);
    datetime OOS_start = IS_end + 86400; // 1-day gap
    datetime OOS_end = last_deal_time;

    // Adjust if OOS period is too short
    if(OOS_end <= OOS_start) 
    {
        OOS_start = first_deal_time + (datetime)(total_seconds * 0.65);
        if(OOS_end <= OOS_start) return -DBL_MAX;
    }

    //--- Initialize metrics
    double IS_profit = 0, OOS_profit = 0;
    int IS_trades = 0, OOS_trades = 0;
    double IS_dd = 0, OOS_dd = 0;
    double balance = deposit, max_balance = deposit;
    
    // Arrays for advanced analysis
    double IS_returns[], OOS_returns[];
    ArrayResize(IS_returns, total_deals);
    ArrayResize(OOS_returns, total_deals);
    int is_idx = 0, oos_idx = 0;

    //--- Process all deals
    for(int p = 0; p < total_deals; p++)
    {
        ulong ticket = HistoryDealGetTicket(p);
        if(ticket == 0) continue;
        
        // Skip non-closing deals
        if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
            continue;

        datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
        double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
        double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
        double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
        double total = profit + commission + swap;
        
        balance += total;
        if(balance > max_balance) max_balance = balance;
        double dd = max_balance - balance;

        // Classify as IS or OOS
        if(time <= IS_end)
        {
            IS_profit += total;
            IS_trades++;
            IS_dd = MathMax(IS_dd, dd);
            IS_returns[is_idx++] = total;
        }
        else if(time >= OOS_start && time <= OOS_end)
        {
            OOS_profit += total;
            OOS_trades++;
            OOS_dd = MathMax(OOS_dd, dd);
            OOS_returns[oos_idx++] = total;
        }
    }

    // Resize arrays to actual values
    ArrayResize(IS_returns, is_idx);
    ArrayResize(OOS_returns, oos_idx);

    //--- Validate minimum requirements
    if(OOS_trades < 15 || IS_trades < 35) return -DBL_MAX;
    if(OOS_profit <= 0 || OOS_dd > deposit * 0.4) return -DBL_MAX;

    //--- Calculate advanced metrics for IS period
    double IS_sharpe = CalculateSharpeRatio(IS_returns);
    double IS_sortino = CalculateSortinoRatio(IS_returns);
    double IS_calmar = (IS_dd > 0) ? IS_profit / IS_dd : 0;
    double IS_win_rate = CalculateWinRate(IS_returns);
    double IS_profit_factor = CalculateProfitFactor(IS_returns);
    double IS_expected_payoff = CalculateExpectedPayoff(IS_returns);
    double IS_skewness = CalculateSkewness(IS_returns);
    double IS_kurtosis = CalculateKurtosis(IS_returns);
    double IS_serenity = CalculateSerenityRatio(IS_returns, IS_dd);

    //--- Calculate advanced metrics for OOS period
    double OOS_sharpe = CalculateSharpeRatio(OOS_returns);
    double OOS_sortino = CalculateSortinoRatio(OOS_returns);
    double OOS_calmar = (OOS_dd > 0) ? OOS_profit / OOS_dd : 0;
    double OOS_win_rate = CalculateWinRate(OOS_returns);
    double OOS_profit_factor = CalculateProfitFactor(OOS_returns);
    double OOS_expected_payoff = CalculateExpectedPayoff(OOS_returns);
    double OOS_skewness = CalculateSkewness(OOS_returns);
    double OOS_kurtosis = CalculateKurtosis(OOS_returns);
    double OOS_serenity = CalculateSerenityRatio(OOS_returns, OOS_dd);

    //--- Statistical tests
    double ks_test = KolmogorovSmirnovTest(IS_returns, OOS_returns);
    double is_normal = JarqueBeraTest(IS_returns);
    double oos_normal = JarqueBeraTest(OOS_returns);
    double distribution_stability = 1.0 - ks_test;

    //--- Strategy Quality Score
    double score = 0;

    // Base profitability (30%)
    score += 15.0 * MathLog(OOS_profit/deposit + 1);
    score += 15.0 * MathLog(OOS_calmar + 1);

    // Consistency (30%)
    double consistency = 0;
    consistency += 5.0 * MathMin(OOS_profit_factor/IS_profit_factor, 2.0);
    consistency += 5.0 * MathMin(OOS_win_rate/IS_win_rate, 2.0);
    consistency += 5.0 * MathMin(OOS_sharpe/IS_sharpe, 2.0);
    consistency += 5.0 * MathMin(OOS_sortino/IS_sortino, 2.0);
    consistency += 5.0 * MathMin(OOS_calmar/IS_calmar, 2.0);
    consistency += 5.0 * distribution_stability;
    score += consistency;

    // Risk-adjusted performance (25%)
    score += 7.5 * MathLog(OOS_sharpe + 2);
    score += 7.5 * MathLog(OOS_sortino + 2);
    score += 5.0 * MathLog(OOS_serenity + 1);
    score += 5.0 * (1.0 - MathMin(OOS_dd/deposit, 1.0));

    // Statistical quality (15%)
    score += 5.0 * (1.0 - MathMin(ks_test, 1.0));
    score += 5.0 * (0.7 + 0.3 * (is_normal > 0.05 ? 1.0 : 0));
    score += 5.0 * (0.7 + 0.3 * (oos_normal > 0.05 ? 1.0 : 0));

    //--- Apply penalties
    if(OOS_trades < 20) score *= 0.7;
    if(OOS_win_rate < 0.4) score *= 0.8;
    if(OOS_profit_factor < 1.2) score *= 0.6;
    if(OOS_skewness < -0.5) score *= 0.9;
    if(OOS_kurtosis > 3.5) score *= 0.9;

    //--- Final validation
    if(OOS_profit <= 0 || OOS_dd > deposit * 0.35 || OOS_trades < 10)
        return -DBL_MAX;

    return MathMax(score, -DBL_MAX);
}

//+------------------------------------------------------------------+
//| Calculate Sharpe Ratio                                           |
//+------------------------------------------------------------------+
double CalculateSharpeRatio(double &returns[])
{
    double mean = 0;
    for(int p = 0; p < ArraySize(returns); p++)
        mean += returns[p];
    mean /= ArraySize(returns);

    double stddev = 0;
    for(int p = 0; p < ArraySize(returns); p++)
        stddev += MathPow(returns[p] - mean, 2);
    stddev = MathSqrt(stddev/ArraySize(returns));

    return (stddev != 0) ? mean / stddev * MathSqrt(365) : 0;
}

//+------------------------------------------------------------------+
//| Calculate Sortino Ratio                                          |
//+------------------------------------------------------------------+
double CalculateSortinoRatio(double &returns[])
{
    double mean = 0;
    for(int p = 0; p < ArraySize(returns); p++)
        mean += returns[p];
    mean /= ArraySize(returns);

    double downside_dev = 0;
    int count = 0;
    for(int p = 0; p < ArraySize(returns); p++)
    {
        if(returns[p] < 0)
        {
            downside_dev += MathPow(returns[p], 2);
            count++;
        }
    }
    if(count == 0) return 100;
    downside_dev = MathSqrt(downside_dev/count);

    return (downside_dev != 0) ? mean / downside_dev * MathSqrt(365) : 0;
}

//+------------------------------------------------------------------+
//| Calculate Win Rate                                               |
//+------------------------------------------------------------------+
double CalculateWinRate(double &returns[])
{
    int wins = 0;
    for(int p = 0; p < ArraySize(returns); p++)
        if(returns[p] > 0) wins++;
    
    return (double)wins / ArraySize(returns);
}

//+------------------------------------------------------------------+
//| Calculate Profit Factor                                          |
//+------------------------------------------------------------------+
double CalculateProfitFactor(double &returns[])
{
    double gross_profit = 0, gross_loss = 0;
    for(int p = 0; p < ArraySize(returns); p++)
    {
        if(returns[p] > 0)
            gross_profit += returns[p];
        else
            gross_loss += MathAbs(returns[p]);
    }
    
    return (gross_loss != 0) ? gross_profit / gross_loss : 100;
}

//+------------------------------------------------------------------+
//| Calculate Expected Payoff                                        |
//+------------------------------------------------------------------+
double CalculateExpectedPayoff(double &returns[])
{
    double mean = 0;
    for(int p = 0; p < ArraySize(returns); p++)
        mean += returns[p];
    return mean / ArraySize(returns);
}

//+------------------------------------------------------------------+
//| Calculate Skewness                                               |
//+------------------------------------------------------------------+
double CalculateSkewness(double &returns[])
{
    double mean = 0;
    for(int p = 0; p < ArraySize(returns); p++)
        mean += returns[p];
    mean /= ArraySize(returns);

    double sum3 = 0;
    double sum2 = 0;
    for(int p = 0; p < ArraySize(returns); p++)
    {
        double diff = returns[p] - mean;
        sum3 += MathPow(diff, 3);
        sum2 += MathPow(diff, 2);
    }
    
    double variance = sum2 / ArraySize(returns);
    double stddev = MathSqrt(variance);
    
    return (stddev != 0) ? (sum3 / ArraySize(returns)) / MathPow(stddev, 3) : 0;
}

//+------------------------------------------------------------------+
//| Calculate Kurtosis                                               |
//+------------------------------------------------------------------+
double CalculateKurtosis(double &returns[])
{
    double mean = 0;
    for(int p = 0; p < ArraySize(returns); p++)
        mean += returns[p];
    mean /= ArraySize(returns);

    double sum4 = 0;
    double sum2 = 0;
    for(int p = 0; p < ArraySize(returns); p++)
    {
        double diff = returns[p] - mean;
        sum4 += MathPow(diff, 4);
        sum2 += MathPow(diff, 2);
    }
    
    double variance = sum2 / ArraySize(returns);
    
    return (variance != 0) ? (sum4 / ArraySize(returns)) / MathPow(variance, 2) - 3 : 0;
}

//+------------------------------------------------------------------+
//| Calculate Serenity Ratio                                         |
//+------------------------------------------------------------------+
double CalculateSerenityRatio(double &returns[], double max_dd)
{
    double mean = 0;
    for(int p = 0; p < ArraySize(returns); p++)
        mean += returns[p];
    mean /= ArraySize(returns);

    double stddev = 0;
    for(int p = 0; p < ArraySize(returns); p++)
        stddev += MathPow(returns[p] - mean, 2);
    stddev = MathSqrt(stddev/ArraySize(returns));

    return (max_dd != 0) ? (mean * stddev) / max_dd : 0;
}

//+------------------------------------------------------------------+
//| Kolmogorov-Smirnov Test for distribution comparison              |
//+------------------------------------------------------------------+
double KolmogorovSmirnovTest(double &sample1[], double &sample2[])
{
    ArraySort(sample1);
    ArraySort(sample2);
    
    int n1 = ArraySize(sample1);
    int n2 = ArraySize(sample2);
    
    // Calculate empirical distribution functions
    double cdf1[], cdf2[];
    ArrayResize(cdf1, n1);
    ArrayResize(cdf2, n2);
    
    for(int p = 0; p < n1; p++)
        cdf1[p] = (double)(p + 1) / n1;
        
    for(int p = 0; p < n2; p++)
        cdf2[p] = (double)(p + 1) / n2;
    
    // Find maximum difference between CDFs
    double max_diff = 0;
    int i1 = 0, i2 = 0;
    
    while(i1 < n1 && i2 < n2)
    {
        if(sample1[i1] <= sample2[i2])
        {
            double diff = MathAbs(cdf1[i1] - ((i2 > 0) ? cdf2[i2-1] : 0));
            max_diff = MathMax(max_diff, diff);
            i1++;
        }
        else
        {
            double diff = MathAbs(((i1 > 0) ? cdf1[i1-1] : 0) - cdf2[i2]);
            max_diff = MathMax(max_diff, diff);
            i2++;
        }
    }
    
    return max_diff;
}

//+------------------------------------------------------------------+
//| Jarque-Bera Test for normality                                   |
//+------------------------------------------------------------------+
double JarqueBeraTest(double &returns[])
{
    int n = ArraySize(returns);
    if(n < 2) return 0;
    
    double mean = 0;
    for(int p = 0; p < n; p++)
        mean += returns[p];
    mean /= n;

    double s = 0;
    double k = 0;
    double variance = 0;
    
    for(int p = 0; p < n; p++)
    {
        double diff = returns[p] - mean;
        variance += MathPow(diff, 2);
        s += MathPow(diff, 3);
        k += MathPow(diff, 4);
    }
    
    variance /= (n - 1);
    s = s / n / MathPow(variance, 1.5);
    k = k / n / MathPow(variance, 2);
    
    double jb = n * (MathPow(s, 2) / 6 + MathPow(k - 3, 2) / 24);
    
    // Calculate p-value (approximation)
    double p_value = MathExp(-0.5 * jb);
    
    return p_value;
}