//+------------------------------------------------------------------+
//|                                              vwap_lite.mqh       |
//|                     Copyright 2016, SOL Digital Consultoria LTDA |
//|                          http://www.soldigitalconsultoria.com.br |
//+------------------------------------------------------------------+
#property copyright         "Copyright 2016, SOL Digital Consultoria LTDA"
#property link              "http://www.soldigitalconsultoria.com.br"
#property version           "1.50"
#property strict

#include <Trade/Trade.mqh>
#include <Object.mqh>

//+------------------------------------------------------------------+
//| Date type enumeration                                            |
//+------------------------------------------------------------------+
enum PRICE_TYPE
{
   OPEN,               // Open price
   CLOSE,              // Close price
   HIGH,               // High price
   LOW,                // Low price
   HIGH_LOW,           // (High + Low) / 2
   CLOSE_HIGH_LOW,     // (Close + High + Low) / 3
   OPEN_CLOSE_HIGH_LOW // (Open + Close + High + Low) / 4
};

//+------------------------------------------------------------------+
//| VWAP Indicator Class                                             |
//+------------------------------------------------------------------+
class CVWAPIndicator : public CObject
{
private:
   // Daily VWAP variables
   double m_daily_sum_pv;        // Sum of price * volume for Daily
   double m_daily_sum_v;         // Sum of volume for Daily
   datetime m_last_day;          // Last processed day

   // Timeframe specific variables
   double m_tf1_sum_pv;          // Sum of price * volume for Timeframe 1
   double m_tf1_sum_v;           // Sum of volume for Timeframe 1
   datetime m_last_tf1_time;     // Last processed time for Timeframe 1
   
   double m_tf2_sum_pv;          // Sum of price * volume for Timeframe 2
   double m_tf2_sum_v;           // Sum of volume for Timeframe 2
   datetime m_last_tf2_time;     // Last processed time for Timeframe 2
   
   double m_tf3_sum_pv;          // Sum of price * volume for Timeframe 3
   double m_tf3_sum_v;           // Sum of volume for Timeframe 3
   datetime m_last_tf3_time;     // Last processed time for Timeframe 3
   
   double m_tf4_sum_pv;          // Sum of price * volume for Timeframe 4
   double m_tf4_sum_v;           // Sum of volume for Timeframe 4
   datetime m_last_tf4_time;     // Last processed time for Timeframe 4
   
   // Configuration
   bool m_enable_daily;          // Enable Daily VWAP
   ENUM_TIMEFRAMES m_timeframe1; // First additional timeframe
   ENUM_TIMEFRAMES m_timeframe2; // Second additional timeframe
   ENUM_TIMEFRAMES m_timeframe3; // Third additional timeframe
   ENUM_TIMEFRAMES m_timeframe4; // Fourth additional timeframe
   bool m_tick_precision;        // Enable tick precision
   PRICE_TYPE m_price_type;      // Price type for calculation
   
   // Helper method to create datetime for specific timeframe
   datetime CreateDateTime(datetime time, ENUM_TIMEFRAMES timeframe) 
   {
      MqlDateTime dt;
      TimeToStruct(time, dt);
      
      // Reset time components based on timeframe
      switch(timeframe) 
      {
         case PERIOD_M1:
            // Round to nearest minute
            dt.sec = 0;
            break;
            
         case PERIOD_M5:
            // Round to nearest 5 minutes
            dt.sec = 0;
            dt.min = (dt.min / 5) * 5;
            break;
            
         case PERIOD_M15:
            // Round to nearest 15 minutes
            dt.sec = 0;
            dt.min = (dt.min / 15) * 15;
            break;
            
         case PERIOD_M30:
            // Round to nearest 30 minutes
            dt.sec = 0;
            dt.min = (dt.min / 30) * 30;
            break;
            
         case PERIOD_H1:
            // Round to nearest hour
            dt.sec = 0;
            dt.min = 0;
            break;
            
         case PERIOD_H4:
            // Round to nearest 4 hours
            dt.sec = 0;
            dt.min = 0;
            dt.hour = (dt.hour / 4) * 4;
            break;
            
         case PERIOD_H8:
            // Round to nearest 8 hours
            dt.sec = 0;
            dt.min = 0;
            dt.hour = (dt.hour / 8) * 8;
            break;
            
         case PERIOD_D1:
            // Round to start of day
            dt.sec = 0;
            dt.min = 0;
            dt.hour = 0;
            break;
            
         case PERIOD_W1:
            // Round to start of week (Monday)
            dt.sec = 0;
            dt.min = 0;
            dt.hour = 0;
            dt.day = dt.day - dt.day_of_week + 1;
            break;
            
         case PERIOD_MN1:
            // Round to start of month
            dt.sec = 0;
            dt.min = 0;
            dt.hour = 0;
            dt.day = 1;
            break;
            
         default:
            // For Daily VWAP, round to start of day
            dt.sec = 0;
            dt.min = 0;
            dt.hour = 0;
            break;
      }
      
      return StructToTime(dt);
   }
   
public:
   // Constructor
   CVWAPIndicator() 
   {
      m_daily_sum_pv = 0;
      m_daily_sum_v = 0;
      m_last_day = 0;
      
      m_tf1_sum_pv = 0;
      m_tf1_sum_v = 0;
      m_last_tf1_time = 0;
      
      m_tf2_sum_pv = 0;
      m_tf2_sum_v = 0;
      m_last_tf2_time = 0;
      
      m_tf3_sum_pv = 0;
      m_tf3_sum_v = 0;
      m_last_tf3_time = 0;
      
      m_tf4_sum_pv = 0;
      m_tf4_sum_v = 0;
      m_last_tf4_time = 0;
      
      m_enable_daily = true;
      m_timeframe1 = PERIOD_CURRENT;
      m_timeframe2 = PERIOD_CURRENT;
      m_timeframe3 = PERIOD_CURRENT;
      m_timeframe4 = PERIOD_CURRENT;
      m_tick_precision = false;
      m_price_type = CLOSE;
   }
   
   // Initialize the indicator with settings
   void Init(PRICE_TYPE priceType, 
             bool enableDaily, 
             ENUM_TIMEFRAMES timeframe1,
             ENUM_TIMEFRAMES timeframe2,
             ENUM_TIMEFRAMES timeframe3,
             ENUM_TIMEFRAMES timeframe4,
             bool tickPrecision)
   {
      m_price_type = priceType;
      m_enable_daily = enableDaily;
      m_timeframe1 = timeframe1;
      m_timeframe2 = timeframe2;
      m_timeframe3 = timeframe3;
      m_timeframe4 = timeframe4;
      m_tick_precision = tickPrecision;
      
      // Reset all VWAP calculations
      m_daily_sum_pv = 0;
      m_daily_sum_v = 0;
      m_last_day = 0;
      
      m_tf1_sum_pv = 0;
      m_tf1_sum_v = 0;
      m_last_tf1_time = 0;
      
      m_tf2_sum_pv = 0;
      m_tf2_sum_v = 0;
      m_last_tf2_time = 0;
      
      m_tf3_sum_pv = 0;
      m_tf3_sum_v = 0;
      m_last_tf3_time = 0;
      
      m_tf4_sum_pv = 0;
      m_tf4_sum_v = 0;
      m_last_tf4_time = 0;
   }
   
   // Calculate VWAP based on bar data
   void CalculateOnBar(const MqlRates &rates[], int rates_count,
                      double &vwapDailyBuffer[],
                      double &vwapTF1Buffer[],
                      double &vwapTF2Buffer[],
                      double &vwapTF3Buffer[],
                      double &vwapTF4Buffer[])
   {
      // Process bars from oldest to newest
      for(int i = rates_count - 1; i >= 0; i--)
      {
         // Get price based on selected type
         double price = 0;
         switch(m_price_type)
         {
            case CLOSE:
               price = rates[i].close;
               break;
            case OPEN:
               price = rates[i].open;
               break;
            case HIGH:
               price = rates[i].high;
               break;
            case LOW:
               price = rates[i].low;
               break;
            case HIGH_LOW:
               price = (rates[i].high + rates[i].low) / 2;
               break;
            case CLOSE_HIGH_LOW:
               price = (rates[i].close + rates[i].high + rates[i].low) / 3;
               break;
            case OPEN_CLOSE_HIGH_LOW:
               price = (rates[i].open + rates[i].close + rates[i].high + rates[i].low) / 4;
               break;
            default:
               price = rates[i].close;
               break;
         }
         
         // Calculate VWAP for each timeframe
         double pv = price * (double)rates[i].tick_volume;
         
         // Calculate Daily VWAP if enabled
         if(m_enable_daily)
         {
            datetime current_day = CreateDateTime(rates[i].time, PERIOD_D1);
            
            // Check if we need to reset for a new day
            if(current_day != m_last_day && m_last_day != 0)
            {
               m_daily_sum_pv = 0;
               m_daily_sum_v = 0;
            }
            
            m_last_day = current_day;
            m_daily_sum_pv += pv;
            m_daily_sum_v += (double)rates[i].tick_volume;
            
            if(m_daily_sum_v > 0)
               vwapDailyBuffer[i] = m_daily_sum_pv / m_daily_sum_v;
            else
               vwapDailyBuffer[i] = price;
         }
         
         // Calculate Timeframe 1 VWAP if enabled
         if(m_timeframe1 != PERIOD_CURRENT)
         {
            datetime current_time = CreateDateTime(rates[i].time, m_timeframe1);
            
            // Check if we need to reset for a new timeframe period
            if(current_time != m_last_tf1_time && m_last_tf1_time != 0)
            {
               m_tf1_sum_pv = 0;
               m_tf1_sum_v = 0;
            }
            
            m_last_tf1_time = current_time;
            m_tf1_sum_pv += pv;
            m_tf1_sum_v += (double)rates[i].tick_volume;
            
            if(m_tf1_sum_v > 0)
               vwapTF1Buffer[i] = m_tf1_sum_pv / m_tf1_sum_v;
            else
               vwapTF1Buffer[i] = price;
         }
         
         // Calculate Timeframe 2 VWAP if enabled
         if(m_timeframe2 != PERIOD_CURRENT)
         {
            datetime current_time = CreateDateTime(rates[i].time, m_timeframe2);
            
            // Check if we need to reset for a new timeframe period
            if(current_time != m_last_tf2_time && m_last_tf2_time != 0)
            {
               m_tf2_sum_pv = 0;
               m_tf2_sum_v = 0;
            }
            
            m_last_tf2_time = current_time;
            m_tf2_sum_pv += pv;
            m_tf2_sum_v += (double)rates[i].tick_volume;
            
            if(m_tf2_sum_v > 0)
               vwapTF2Buffer[i] = m_tf2_sum_pv / m_tf2_sum_v;
            else
               vwapTF2Buffer[i] = price;
         }
         
         // Calculate Timeframe 3 VWAP if enabled
         if(m_timeframe3 != PERIOD_CURRENT)
         {
            datetime current_time = CreateDateTime(rates[i].time, m_timeframe3);
            
            // Check if we need to reset for a new timeframe period
            if(current_time != m_last_tf3_time && m_last_tf3_time != 0)
            {
               m_tf3_sum_pv = 0;
               m_tf3_sum_v = 0;
            }
            
            m_last_tf3_time = current_time;
            m_tf3_sum_pv += pv;
            m_tf3_sum_v += (double)rates[i].tick_volume;
            
            if(m_tf3_sum_v > 0)
               vwapTF3Buffer[i] = m_tf3_sum_pv / m_tf3_sum_v;
            else
               vwapTF3Buffer[i] = price;
         }
         
         // Calculate Timeframe 4 VWAP if enabled
         if(m_timeframe4 != PERIOD_CURRENT)
         {
            datetime current_time = CreateDateTime(rates[i].time, m_timeframe4);
            
            // Check if we need to reset for a new timeframe period
            if(current_time != m_last_tf4_time && m_last_tf4_time != 0)
            {
               m_tf4_sum_pv = 0;
               m_tf4_sum_v = 0;
            }
            
            m_last_tf4_time = current_time;
            m_tf4_sum_pv += pv;
            m_tf4_sum_v += (double)rates[i].tick_volume;
            
            if(m_tf4_sum_v > 0)
               vwapTF4Buffer[i] = m_tf4_sum_pv / m_tf4_sum_v;
            else
               vwapTF4Buffer[i] = price;
         }
      }
   }
   
   // Calculate VWAP based on tick data (more precise)
   void CalculateOnTick(const datetime &time[], 
                       const double &price[], 
                       long &volume[], 
                       int data_count,
                       double &vwapDailyBuffer[],
                       double &vwapTF1Buffer[],
                       double &vwapTF2Buffer[],
                       double &vwapTF3Buffer[],
                       double &vwapTF4Buffer[])
   {
      // Process ticks from oldest to newest
      for(int i = data_count - 1; i >= 0; i--)
      {
         // Calculate price * volume for this tick
         double pv = price[i] * (double)volume[i];
         
         // Daily VWAP calculation
         if(m_enable_daily)
         {
            datetime current_day = CreateDateTime(time[i], PERIOD_D1);
            
            // Reset sums at the start of a new day
            if(current_day != m_last_day && m_last_day != 0)
            {
               m_daily_sum_pv = 0;
               m_daily_sum_v = 0;
            }
            
            m_last_day = current_day;
            m_daily_sum_pv += pv;
            m_daily_sum_v += (double)volume[i];
            
            if(m_daily_sum_v > 0)
               vwapDailyBuffer[i] = m_daily_sum_pv / m_daily_sum_v;
            else
               vwapDailyBuffer[i] = price[i];
         }
         
         // Timeframe 1 VWAP calculation
         if(m_timeframe1 != PERIOD_CURRENT)
         {
            datetime current_time = CreateDateTime(time[i], m_timeframe1);
            
            // Reset sums at the start of a new period
            if(current_time != m_last_tf1_time && m_last_tf1_time != 0)
            {
               m_tf1_sum_pv = 0;
               m_tf1_sum_v = 0;
            }
            
            m_last_tf1_time = current_time;
            m_tf1_sum_pv += pv;
            m_tf1_sum_v += (double)volume[i];
            
            if(m_tf1_sum_v > 0)
               vwapTF1Buffer[i] = m_tf1_sum_pv / m_tf1_sum_v;
            else
               vwapTF1Buffer[i] = price[i];
         }
         
         // Timeframe 2 VWAP calculation
         if(m_timeframe2 != PERIOD_CURRENT)
         {
            datetime current_time = CreateDateTime(time[i], m_timeframe2);
            
            // Reset sums at the start of a new period
            if(current_time != m_last_tf2_time && m_last_tf2_time != 0)
            {
               m_tf2_sum_pv = 0;
               m_tf2_sum_v = 0;
            }
            
            m_last_tf2_time = current_time;
            m_tf2_sum_pv += pv;
            m_tf2_sum_v += (double)volume[i];
            
            if(m_tf2_sum_v > 0)
               vwapTF2Buffer[i] = m_tf2_sum_pv / m_tf2_sum_v;
            else
               vwapTF2Buffer[i] = price[i];
         }
         
         // Timeframe 3 VWAP calculation
         if(m_timeframe3 != PERIOD_CURRENT)
         {
            datetime current_time = CreateDateTime(time[i], m_timeframe3);
            
            // Reset sums at the start of a new period
            if(current_time != m_last_tf3_time && m_last_tf3_time != 0)
            {
               m_tf3_sum_pv = 0;
               m_tf3_sum_v = 0;
            }
            
            m_last_tf3_time = current_time;
            m_tf3_sum_pv += pv;
            m_tf3_sum_v += (double)volume[i];
            
            if(m_tf3_sum_v > 0)
               vwapTF3Buffer[i] = m_tf3_sum_pv / m_tf3_sum_v;
            else
               vwapTF3Buffer[i] = price[i];
         }
         
         // Timeframe 4 VWAP calculation
         if(m_timeframe4 != PERIOD_CURRENT)
         {
            datetime current_time = CreateDateTime(time[i], m_timeframe4);
            
            // Reset sums at the start of a new period
            if(current_time != m_last_tf4_time && m_last_tf4_time != 0)
            {
               m_tf4_sum_pv = 0;
               m_tf4_sum_v = 0;
            }
            
            m_last_tf4_time = current_time;
            m_tf4_sum_pv += pv;
            m_tf4_sum_v += (double)volume[i];
            
            if(m_tf4_sum_v > 0)
               vwapTF4Buffer[i] = m_tf4_sum_pv / m_tf4_sum_v;
            else
               vwapTF4Buffer[i] = price[i];
         }
      }
   }
   
   // Get Daily VWAP status
   bool IsDailyEnabled()
   {
      return m_enable_daily;
   }
   
   // Get Timeframe 1 status
   ENUM_TIMEFRAMES GetTimeframe1()
   {
      return m_timeframe1;
   }
   
   // Get Timeframe 2 status
   ENUM_TIMEFRAMES GetTimeframe2()
   {
      return m_timeframe2;
   }
   
   // Get Timeframe 3 status
   ENUM_TIMEFRAMES GetTimeframe3()
   {
      return m_timeframe3;
   }
   
   // Get Timeframe 4 status
   ENUM_TIMEFRAMES GetTimeframe4()
   {
      return m_timeframe4;
   }
};