//+------------------------------------------------------------------+
//|                                  T3.mqh                          |
//|              Copyright © 2025 Salman Soltaniyan                 |
//|                                                                 |
//+------------------------------------------------------------------+

#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| T3 (Tillson T3) Indicator Class                                 |
//+------------------------------------------------------------------+
class CT3Indicator
{
private:
   // T3 settings
   int           m_length;          // Period length for T3 calculation
   double        m_factor;          // Volume factor for T3 calculation 
   ENUM_APPLIED_PRICE m_price_type; // Price type for T3
   
   // Buffers for calculations
   double        m_ema1[];          // First EMA buffer
   double        m_ema2[];          // Second EMA buffer
   double        m_ema3[];          // Third EMA buffer
   double        m_ema4[];          // Fourth EMA buffer
   double        m_ema5[];          // Fifth EMA buffer
   double        m_ema6[];          // Sixth EMA buffer
   
   // Tick-level variables
   bool          m_use_tick_precision; // Whether to use tick-level precision
   
   // Private methods
   void          InitArrays(int size);
   
public:
   // Constructor and destructor
                 CT3Indicator();
                ~CT3Indicator();
                
   // Initialization methods
   void          Init(int length, double factor, ENUM_APPLIED_PRICE price_type, bool use_tick_precision = false);
   
   // Calculation methods
   double        CalculateOnBar(double &prices[], int shift); // Bar-level calculation
   double        CalculateOnTick(double &prices[], int length, double factor, int shift); // Tick-level calculation
   double        Calculate(double &prices[], int shift); // Main calculation method
   
   // Getter methods
   int           GetLength() const { return m_length; }
   double        GetFactor() const { return m_factor; }
   bool          IsTickPrecision() const { return m_use_tick_precision; }
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CT3Indicator::CT3Indicator()
{
   m_length = 12;
   m_factor = 0.7;
   m_price_type = PRICE_CLOSE;
   m_use_tick_precision = false;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CT3Indicator::~CT3Indicator()
{
   // No dynamic memory to free
}

//+------------------------------------------------------------------+
//| Initialize the T3 indicator                                     |
//+------------------------------------------------------------------+
void CT3Indicator::Init(int length, double factor, ENUM_APPLIED_PRICE price_type, bool use_tick_precision = false)
{
   m_length = length;
   m_factor = factor;
   m_price_type = price_type;
   m_use_tick_precision = use_tick_precision;
   
   // Initialize arrays for calculations
   InitArrays(length * 2);
}

//+------------------------------------------------------------------+
//| Initialize calculation arrays                                    |
//+------------------------------------------------------------------+
void CT3Indicator::InitArrays(int size)
{
   ArrayResize(m_ema1, size);
   ArrayResize(m_ema2, size);
   ArrayResize(m_ema3, size);
   ArrayResize(m_ema4, size);
   ArrayResize(m_ema5, size);
   ArrayResize(m_ema6, size);
   
   // Set all arrays as time-descending
   ArraySetAsSeries(m_ema1, true);
   ArraySetAsSeries(m_ema2, true);
   ArraySetAsSeries(m_ema3, true);
   ArraySetAsSeries(m_ema4, true);
   ArraySetAsSeries(m_ema5, true);
   ArraySetAsSeries(m_ema6, true);
}

//+------------------------------------------------------------------+
//| Calculate T3 using bar level precision                          |
//+------------------------------------------------------------------+
double CT3Indicator::CalculateOnBar(double &prices[], int shift)
{
   // Make sure prices array is set as time-descending
   ArraySetAsSeries(prices, true);
   
   // Allocate memory for EMA arrays if needed
   if(ArraySize(m_ema1) < m_length + shift + 10) {
      InitArrays(m_length + shift + 10);
   }
   
   // Check for valid input data
   if(ArraySize(prices) < m_length + shift) {
      Print("WARNING: Not enough price data for T3 calculation. Need ", m_length + shift, " bars, have ", ArraySize(prices));
      return 0.0;
   }
   
   // Simple EMA calculations for the cascaded EMAs
   double alpha = 2.0 / (m_length + 1.0);
   
   // Calculate first EMA (on the raw price)
   for(int i = shift + m_length - 1; i >= shift; i--) {
      // For the first EMA, use the selected price as input
      if(i == shift + m_length - 1)
         m_ema1[i] = prices[i];
      else
         m_ema1[i] = alpha * prices[i] + (1 - alpha) * m_ema1[i+1];
   }
   
   // Calculate second EMA (using first EMA as input)
   for(int i = shift + m_length - 1; i >= shift; i--) {
      if(i == shift + m_length - 1)
         m_ema2[i] = m_ema1[i];
      else
         m_ema2[i] = alpha * m_ema1[i] + (1 - alpha) * m_ema2[i+1];
   }
   
   // Calculate third EMA (using second EMA as input)
   for(int i = shift + m_length - 1; i >= shift; i--) {
      if(i == shift + m_length - 1)
         m_ema3[i] = m_ema2[i];
      else
         m_ema3[i] = alpha * m_ema2[i] + (1 - alpha) * m_ema3[i+1];
   }
   
   // Calculate fourth EMA (using third EMA as input)
   for(int i = shift + m_length - 1; i >= shift; i--) {
      if(i == shift + m_length - 1)
         m_ema4[i] = m_ema3[i];
      else
         m_ema4[i] = alpha * m_ema3[i] + (1 - alpha) * m_ema4[i+1];
   }
   
   // Calculate fifth EMA (using fourth EMA as input)
   for(int i = shift + m_length - 1; i >= shift; i--) {
      if(i == shift + m_length - 1)
         m_ema5[i] = m_ema4[i];
      else
         m_ema5[i] = alpha * m_ema4[i] + (1 - alpha) * m_ema5[i+1];
   }
   
   // Calculate sixth EMA (using fifth EMA as input)
   for(int i = shift + m_length - 1; i >= shift; i--) {
      if(i == shift + m_length - 1)
         m_ema6[i] = m_ema5[i];
      else
         m_ema6[i] = alpha * m_ema5[i] + (1 - alpha) * m_ema6[i+1];
   }
   
   // Calculate the T3 coefficients based on the factor
   double c1 = -m_factor * m_factor * m_factor;
   double c2 = 3 * m_factor * m_factor + 3 * m_factor * m_factor * m_factor;
   double c3 = -6 * m_factor * m_factor - 3 * m_factor - 3 * m_factor * m_factor * m_factor;
   double c4 = 1 + 3 * m_factor + m_factor * m_factor * m_factor + 3 * m_factor * m_factor;
   
   // Apply the T3 formula
   return c1 * m_ema6[shift] + c2 * m_ema5[shift] + c3 * m_ema4[shift] + c4 * m_ema3[shift];
}

//+------------------------------------------------------------------+
//| Calculate T3 using tick level precision                         |
//+------------------------------------------------------------------+
double CT3Indicator::CalculateOnTick(double &prices[], int length, double factor, int shift)
{
   // This method is similar to CalculateOnBar but optimized for tick data
   // Make sure prices array is set as time-descending
   ArraySetAsSeries(prices, true);
   
   // Allocate memory for EMA arrays if needed
   if(ArraySize(m_ema1) < length + shift + 10) {
      ArrayResize(m_ema1, length + shift + 10);
      ArrayResize(m_ema2, length + shift + 10);
      ArrayResize(m_ema3, length + shift + 10);
      ArrayResize(m_ema4, length + shift + 10);
      ArrayResize(m_ema5, length + shift + 10);
      ArrayResize(m_ema6, length + shift + 10);
      
      // Set all arrays as time-descending
      ArraySetAsSeries(m_ema1, true);
      ArraySetAsSeries(m_ema2, true);
      ArraySetAsSeries(m_ema3, true);
      ArraySetAsSeries(m_ema4, true);
      ArraySetAsSeries(m_ema5, true);
      ArraySetAsSeries(m_ema6, true);
   }
   
   // Check for valid input data
   if(ArraySize(prices) < length + shift) {
      Print("WARNING: Not enough price data for T3 calculation. Need ", length + shift, " ticks, have ", ArraySize(prices));
      return 0.0;
   }
   
   // Simple EMA calculations for the cascaded EMAs
   double alpha = 2.0 / (length + 1.0);
   
   // Calculate first EMA (on the raw price)
   for(int i = shift + length - 1; i >= shift; i--) {
      // For the first EMA, use the price as input
      if(i == shift + length - 1)
         m_ema1[i] = prices[i];
      else
         m_ema1[i] = alpha * prices[i] + (1 - alpha) * m_ema1[i+1];
   }
   
   // Calculate second EMA (using first EMA as input)
   for(int i = shift + length - 1; i >= shift; i--) {
      if(i == shift + length - 1)
         m_ema2[i] = m_ema1[i];
      else
         m_ema2[i] = alpha * m_ema1[i] + (1 - alpha) * m_ema2[i+1];
   }
   
   // Calculate third EMA (using second EMA as input)
   for(int i = shift + length - 1; i >= shift; i--) {
      if(i == shift + length - 1)
         m_ema3[i] = m_ema2[i];
      else
         m_ema3[i] = alpha * m_ema2[i] + (1 - alpha) * m_ema3[i+1];
   }
   
   // Calculate fourth EMA (using third EMA as input)
   for(int i = shift + length - 1; i >= shift; i--) {
      if(i == shift + length - 1)
         m_ema4[i] = m_ema3[i];
      else
         m_ema4[i] = alpha * m_ema3[i] + (1 - alpha) * m_ema4[i+1];
   }
   
   // Calculate fifth EMA (using fourth EMA as input)
   for(int i = shift + length - 1; i >= shift; i--) {
      if(i == shift + length - 1)
         m_ema5[i] = m_ema4[i];
      else
         m_ema5[i] = alpha * m_ema4[i] + (1 - alpha) * m_ema5[i+1];
   }
   
   // Calculate sixth EMA (using fifth EMA as input)
   for(int i = shift + length - 1; i >= shift; i--) {
      if(i == shift + length - 1)
         m_ema6[i] = m_ema5[i];
      else
         m_ema6[i] = alpha * m_ema5[i] + (1 - alpha) * m_ema6[i+1];
   }
   
   // Calculate the T3 coefficients based on the factor
   double c1 = -factor * factor * factor;
   double c2 = 3 * factor * factor + 3 * factor * factor * factor;
   double c3 = -6 * factor * factor - 3 * factor - 3 * factor * factor * factor;
   double c4 = 1 + 3 * factor + factor * factor * factor + 3 * factor * factor;
   
   // Apply the T3 formula
   return c1 * m_ema6[shift] + c2 * m_ema5[shift] + c3 * m_ema4[shift] + c4 * m_ema3[shift];
}

//+------------------------------------------------------------------+
//| Main calculation method - chooses between bar or tick precision  |
//+------------------------------------------------------------------+
double CT3Indicator::Calculate(double &prices[], int shift)
{
   if(m_use_tick_precision)
      return CalculateOnTick(prices, m_length, m_factor, shift);
   else
      return CalculateOnBar(prices, shift);
} 