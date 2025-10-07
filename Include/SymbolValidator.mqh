//+------------------------------------------------------------------+
//| SymbolValidator.mqh                                             |
//| Lightweight symbol environment + validation toolkit             |
//+------------------------------------------------------------------+
#ifndef __SYMBOL_VALIDATOR_MQH__
#define __SYMBOL_VALIDATOR_MQH__

class CSymbolValidator
{
private:
   string                m_symbol;
   double                m_min_lot;
   double                m_max_lot;
   double                m_lot_step;
   double                m_point;
   int                   m_digits;
   int                   m_stops_level;
   double                m_tick_size;
   double                m_tick_value;
   double                m_contract_size;
   ENUM_SYMBOL_CALC_MODE m_calc_mode;

   bool      LoadSymbolInfo();
   void      LogValidationInfo(const string message) const;

public:
   CSymbolValidator();
   ~CSymbolValidator() {}

   bool      Init(string symbol = NULL);
   void      Refresh();
   bool      CheckHistory(int minimum_bars = 100);
   bool      IsInTester() const { return (MQLInfoInteger(MQL_TESTER) != 0); }

   // Volume helpers
   double    NormalizeVolume(double volume) const;
   double    ValidateVolume(ENUM_ORDER_TYPE order_type, double requested_volume) const;
   bool      CheckMarginForVolume(ENUM_ORDER_TYPE order_type, double volume, double price = 0.0) const;

   // SL/TP helpers
   double    ValidateStopLoss(ENUM_ORDER_TYPE order_type, double open_price, double desired_sl) const;
   double    ValidateTakeProfit(ENUM_ORDER_TYPE order_type, double open_price, double desired_tp) const;

   // Accessors
   string    Symbol()       const { return m_symbol; }
   double    Point()        const { return m_point; }
   double    TickSize()     const { return m_tick_size; }
   double    TickValue()    const { return m_tick_value; }
   double    ContractSize() const { return m_contract_size; }
   double    MinLot()       const { return m_min_lot; }
   double    MaxLot()       const { return m_max_lot; }
   double    LotStep()      const { return m_lot_step; }
   int       Digits()       const { return m_digits; }
   int       StopsLevel()   const { return m_stops_level; }
   ENUM_SYMBOL_CALC_MODE CalcMode() const { return m_calc_mode; }
   double    Bid()          const { return SymbolInfoDouble(m_symbol, SYMBOL_BID); }
   double    Ask()          const { return SymbolInfoDouble(m_symbol, SYMBOL_ASK); }
};

//--- implementation -------------------------------------------------

CSymbolValidator::CSymbolValidator()
{
   m_symbol       = _Symbol;
   m_min_lot      = 0.01;
   m_max_lot      = 100.0;
   m_lot_step     = 0.01;
   m_point        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   m_digits       = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   m_stops_level  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   m_tick_size    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   m_tick_value   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   m_contract_size= SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   m_calc_mode    = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_CALC_MODE);
}

bool CSymbolValidator::Init(string symbol)
{
   if(symbol != NULL && symbol != "")
      m_symbol = symbol;
   else
      m_symbol = _Symbol;

   if(!SymbolSelect(m_symbol, true))
   {
      Print("[SymbolValidator] Unable to select symbol ", m_symbol);
      return false;
   }

   if(!LoadSymbolInfo())
   {
      Print("[SymbolValidator] Failed to load symbol properties for ", m_symbol);
      return false;
   }

   return true;
}

void CSymbolValidator::Refresh()
{
   LoadSymbolInfo();
}

bool CSymbolValidator::LoadSymbolInfo()
{
   m_digits       = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   m_point        = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   m_tick_size    = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   m_tick_value   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
   m_contract_size= SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   m_min_lot      = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   m_max_lot      = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   m_lot_step     = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   m_stops_level  = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   m_calc_mode    = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_CALC_MODE);

   if(m_point <= 0)
      m_point = _Point;

   if(m_min_lot <= 0)
      m_min_lot = 0.01;
   if(m_max_lot <= 0)
      m_max_lot = 100.0;
   if(m_lot_step <= 0)
      m_lot_step = 0.01;
   if(m_tick_size <= 0)
      m_tick_size = (m_point > 0.0 ? m_point : _Point);
   if(m_tick_value <= 0)
      m_tick_value = 1.0;
   if(m_contract_size <= 0)
      m_contract_size = 100000.0;
   if(m_stops_level < 0)
      m_stops_level = 0;

   return true;
}

bool CSymbolValidator::CheckHistory(int minimum_bars)
{
   if(Bars(m_symbol, PERIOD_CURRENT) < minimum_bars)
   {
      LogValidationInfo("WARNING: Not enough historical data. Required: " + IntegerToString(minimum_bars) +
                        ", available: " + IntegerToString(Bars(m_symbol, PERIOD_CURRENT)));
      return false;
   }
   return true;
}

double CSymbolValidator::NormalizeVolume(double volume) const
{
   if(volume <= 0.0)
      return 0.0;

   if(volume < m_min_lot)
      volume = m_min_lot;
   if(volume > m_max_lot)
      volume = m_max_lot;

   if(m_lot_step > 0.0)
   {
      int steps = (int)MathRound((volume - m_min_lot) / m_lot_step);
      volume = NormalizeDouble(m_min_lot + steps * m_lot_step, 8);
   }

   if(volume > m_max_lot)
      volume = m_max_lot;
   if(volume < m_min_lot)
      volume = m_min_lot;

   return volume;
}

double CSymbolValidator::ValidateVolume(ENUM_ORDER_TYPE order_type, double requested_volume) const
{
   double volume = NormalizeVolume(requested_volume);
   if(!CheckMarginForVolume(order_type, volume))
   {
      double adjusted = volume;
      while(adjusted >= m_min_lot)
      {
         adjusted -= m_lot_step;
         adjusted = NormalizeVolume(adjusted);
         if(adjusted < m_min_lot)
            break;
         if(CheckMarginForVolume(order_type, adjusted))
            return adjusted;
      }

      LogValidationInfo("Not enough margin for requested volume");
      return 0.0;
   }

   return volume;
}

bool CSymbolValidator::CheckMarginForVolume(ENUM_ORDER_TYPE order_type, double volume, double price) const
{
   if(volume <= 0.0)
      return false;

   if(price <= 0.0)
   {
      bool is_buy = (order_type == ORDER_TYPE_BUY || order_type == ORDER_TYPE_BUY_LIMIT ||
                     order_type == ORDER_TYPE_BUY_STOP || order_type == ORDER_TYPE_BUY_STOP_LIMIT);
      price = is_buy ? Ask() : Bid();
   }

   double margin = 0.0;
   if(!OrderCalcMargin(order_type, m_symbol, volume, price, margin))
   {
      LogValidationInfo("OrderCalcMargin failed: " + IntegerToString(GetLastError()));
      return false;
   }

   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double required    = margin * 1.05; // add 5% safety buffer

   return (free_margin >= required);
}

double CSymbolValidator::ValidateStopLoss(ENUM_ORDER_TYPE order_type, double open_price, double desired_sl) const
{
   if(open_price <= 0.0)
      return 0.0;

   if(desired_sl <= 0.0)
      return 0.0;

   bool is_buy = (order_type == ORDER_TYPE_BUY || order_type == ORDER_TYPE_BUY_LIMIT ||
                  order_type == ORDER_TYPE_BUY_STOP || order_type == ORDER_TYPE_BUY_STOP_LIMIT);

   if(is_buy && desired_sl >= open_price)
   {
      LogValidationInfo("Invalid SL for buy — must be below entry");
      return 0.0;
   }
   if(!is_buy && desired_sl <= open_price)
   {
      LogValidationInfo("Invalid SL for sell — must be above entry");
      return 0.0;
   }

   double min_distance = m_stops_level * m_point;
   double distance = MathAbs(open_price - desired_sl);

   if(distance < min_distance)
   {
      double adjusted = is_buy ? open_price - min_distance : open_price + min_distance;
      return NormalizeDouble(adjusted, m_digits);
   }

   return NormalizeDouble(desired_sl, m_digits);
}

double CSymbolValidator::ValidateTakeProfit(ENUM_ORDER_TYPE order_type, double open_price, double desired_tp) const
{
   if(open_price <= 0.0)
      return 0.0;

   if(desired_tp <= 0.0)
      return 0.0;

   bool is_buy = (order_type == ORDER_TYPE_BUY || order_type == ORDER_TYPE_BUY_LIMIT ||
                  order_type == ORDER_TYPE_BUY_STOP || order_type == ORDER_TYPE_BUY_STOP_LIMIT);

   if(is_buy && desired_tp <= open_price)
   {
      LogValidationInfo("Invalid TP for buy — must be above entry");
      return 0.0;
   }
   if(!is_buy && desired_tp >= open_price)
   {
      LogValidationInfo("Invalid TP for sell — must be below entry");
      return 0.0;
   }

   double min_distance = m_stops_level * m_point;
   double distance = MathAbs(open_price - desired_tp);

   if(distance < min_distance)
   {
      double adjusted = is_buy ? open_price + min_distance : open_price - min_distance;
      return NormalizeDouble(adjusted, m_digits);
   }

   return NormalizeDouble(desired_tp, m_digits);
}

void CSymbolValidator::LogValidationInfo(const string message) const
{
   if(!IsInTester() || MQLInfoInteger(MQL_VISUAL_MODE) != 0)
      Print("[SymbolValidator] ", message);
}

extern CSymbolValidator g_SymbolValidator;

#endif // __SYMBOL_VALIDATOR_MQH__
