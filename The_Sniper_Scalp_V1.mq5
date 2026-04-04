//+------------------------------------------------------------------+
//|                                              The Sniper Scalp V1 |
//|                                         Automating SMC with MQL5 |
//|                                                   Author: alfayun|
//|    Version: 1.13 (Bayesian Optimized - DNA Trial 91)             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Papa Clement"
#property version   "1.13"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| ENUM & STRUCT UNTUK BAYESIAN LOGIC                               |
//+------------------------------------------------------------------+
enum ENUM_VOLATILITY_STATE { VOL_LOW = 0, VOL_HIGH = 1 };
enum ENUM_TREND_STATE      { TREND_NEAR = 0, TREND_FAR = 1 };

struct MarketCondition {
   ENUM_VOLATILITY_STATE volState;
   ENUM_TREND_STATE      trendState;
};

struct TradeMemory {
   ENUM_VOLATILITY_STATE volState;
   ENUM_TREND_STATE      trendState;
   bool                  isWin;
};

// --- PARAMETER DNA JUARA (Hardcoded agar tidak bentrok saat backtest) ---
double LotSize = 0.01;      
bool   UseATR_Logic = true;       
int    ATR_Period = 12;           // Hasil Optimasi Trial 91
double ATR_Multiplier_SL = 1.69;  // Hasil Optimasi Trial 91
double ATR_Multiplier_TP = 4.43;  // Hasil Optimasi Trial 91
int    Fallback_SL = 150;         
int    Fallback_TP = 300;         
bool   UseTrendFilter = true;     
int    EMA_Period = 55;           // Hasil Optimasi Trial 91
int    MaxWaitBars = 24;          

// --- FILTER BAYESIAN ADAPTIF ---
input int    MinBayesianTrades = 14;   // Belajar minimal dari 14 kejadian
input double MinWinRate = 36.9;        // Syarat tembak: Probabilitas minimal 36.9%

// --- GLOBAL VARIABLES ---
CTrade  trade; 
int     handleEMA, handleATR;      
double  targetOBPrice = 0;
bool    isWaitingForEntry = false;
int     activeOrderType = -1; 
int     rectCounter = 0;
int     waitingTimer = 0;
datetime lastBarTime = 0;

// Variabel Bayesian Memory
TradeMemory memoryBank[100];
int memoryCount = 0;
int memoryIndex = 0;
ulong lastTicket = 0;
MarketCondition lastEntryCondition;

//+------------------------------------------------------------------+
int OnInit()
{
   handleEMA = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleATR = iATR(_Symbol, _Period, ATR_Period);
   if(handleEMA == INVALID_HANDLE || handleATR == INVALID_HANDLE) return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { IndicatorRelease(handleEMA); IndicatorRelease(handleATR); }

//+------------------------------------------------------------------+
void OnTick()
{
   // --- FITUR TRAUMA HEALING (Amnesia Jangka Pendek) ---
   static datetime lastTradeTime = 0;
   
   if(PositionsTotal() > 0) 
   {
      lastTradeTime = TimeCurrent(); 
   }
   else if(lastTradeTime > 0 && (TimeCurrent() - lastTradeTime) > (86400 * 14)) 
   {
      memoryCount = 0;
      memoryIndex = 0;
      lastTradeTime = TimeCurrent(); 
      Print("Trauma Healed! Meriset memori untuk adaptasi market baru.");
   }

   // --- PENCATATAN HASIL KE MEMORI ---
   if(PositionsTotal() > 0)
   {
      isWaitingForEntry = false; 
      if(lastTicket == 0) lastTicket = PositionGetTicket(0); 
      Comment("Sniper Status: IN TRADE\nMenunggu Hasil Eksekusi...");
      return;
   }
   else if(lastTicket > 0)
   {
      HistorySelect(TimeCurrent() - 604800, TimeCurrent()); 
      ulong dealTicket = HistoryDealGetTicket(HistoryDealsTotal()-1);
      if(dealTicket > 0)
      {
         double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         bool isWin = (profit > 0);

         memoryBank[memoryIndex].volState = lastEntryCondition.volState;
         memoryBank[memoryIndex].trendState = lastEntryCondition.trendState;
         memoryBank[memoryIndex].isWin = isWin;

         memoryIndex = (memoryIndex + 1) % 100;
         if(memoryCount < 100) memoryCount++;
      }
      lastTicket = 0;
   }
   
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      if(isWaitingForEntry) waitingTimer++;
   }

   if(isWaitingForEntry && waitingTimer > MaxWaitBars) isWaitingForEntry = false;

   double emaBuffer[], atrBuffer[];
   ArraySetAsSeries(emaBuffer, true); ArraySetAsSeries(atrBuffer, true);
   if(CopyBuffer(handleEMA, 0, 1, 1, emaBuffer) < 1) return;
   if(CopyBuffer(handleATR, 0, 0, 1, atrBuffer) < 1) return;
   
   double prevEMA = emaBuffer[0], currentATR = atrBuffer[0];
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // --- RADAR CUACA & KALKULATOR BAYESIAN ---
   MarketCondition currentMarket = GetMarketCondition(currentPrice, prevEMA, currentATR);
   double winProbability = CalculateBayesianProbability(currentMarket);
   
   string strVol = (currentMarket.volState == VOL_HIGH) ? "HIGH" : "LOW";
   string strTrend = (currentMarket.trendState == TREND_FAR) ? "FAR" : "NEAR";
   string strProb = (memoryCount >= MinBayesianTrades) ? DoubleToString(winProbability, 1) + "%" : "Learning Market...";

   if(!isWaitingForEntry)
   {
      Comment("Sniper Status: ACTIVE (Hunting for BOS)",
              "\n--- BAYESIAN RADAR ---",
              "\nVolatility: ", strVol, " | Trend: ", strTrend,
              "\nProb. Win: ", strProb,
              "\nExperience: ", memoryCount, "/100 Trades");

      double close1 = iClose(_Symbol, _Period, 1), high2 = iHigh(_Symbol, _Period, 2), low2 = iLow(_Symbol, _Period, 2);

      // Logika Keputusan Berbasis Probabilitas
      bool isProbOK = (memoryCount < MinBayesianTrades || winProbability >= MinWinRate);

      if(close1 > high2 && isProbOK) 
      {
         if(!UseTrendFilter || close1 > prevEMA) {
            targetOBPrice = high2; DrawOBRect("Bullish", clrLightBlue, 2);
            isWaitingForEntry = true; activeOrderType = 0; waitingTimer = 0;
            lastEntryCondition = currentMarket; 
         }
      }
      else if(close1 < low2 && isProbOK) 
      {
         if(!UseTrendFilter || close1 < prevEMA) {
            targetOBPrice = low2; DrawOBRect("Bearish", clrLightPink, 2);
            isWaitingForEntry = true; activeOrderType = 1; waitingTimer = 0;
            lastEntryCondition = currentMarket; 
         }
      }
   }

   if(isWaitingForEntry) CheckEntryTrigger(currentATR, currentPrice);
}

//+------------------------------------------------------------------+
void CheckEntryTrigger(double currentATR, double currentPrice)
{
   double sl, tp;
   if(UseATR_Logic && currentATR > 0) {
      sl = (activeOrderType == 0) ? targetOBPrice - (currentATR * ATR_Multiplier_SL) : targetOBPrice + (currentATR * ATR_Multiplier_SL);
      tp = (activeOrderType == 0) ? targetOBPrice + (currentATR * ATR_Multiplier_TP) : targetOBPrice - (currentATR * ATR_Multiplier_TP);
   } else {
      sl = (activeOrderType == 0) ? targetOBPrice - (Fallback_SL * _Point) : targetOBPrice + (Fallback_SL * _Point);
      tp = (activeOrderType == 0) ? targetOBPrice + (Fallback_TP * _Point) : targetOBPrice - (Fallback_TP * _Point);
   }

   if(activeOrderType == 0 && currentPrice <= targetOBPrice) 
      if(trade.Buy(LotSize, _Symbol, currentPrice, sl, tp, "DNA 91 Buy")) isWaitingForEntry = false;
   if(activeOrderType == 1 && currentPrice >= targetOBPrice) 
      if(trade.Sell(LotSize, _Symbol, currentPrice, sl, tp, "DNA 91 Sell")) isWaitingForEntry = false;
}

//+------------------------------------------------------------------+
MarketCondition GetMarketCondition(double currentPrice, double currentEMA, double currentATR)
{
   MarketCondition cond;
   cond.trendState = (MathAbs(currentPrice - currentEMA) > (currentATR * 1.5)) ? TREND_FAR : TREND_NEAR;
   
   double atrHist[]; ArraySetAsSeries(atrHist, true);
   double sum = 0;
   if(CopyBuffer(handleATR, 0, 1, 50, atrHist) == 50) {
      for(int i = 0; i < 50; i++) sum += atrHist[i];
      cond.volState = (currentATR > (sum / 50.0)) ? VOL_HIGH : VOL_LOW;
   } else {
      cond.volState = VOL_LOW;
   }
   return cond;
}

double CalculateBayesianProbability(MarketCondition &cond) 
{
   if(memoryCount == 0) return 50.0;
   int matchCount = 0, winCount = 0;
   for(int i = 0; i < memoryCount; i++) {
      if(memoryBank[i].volState == cond.volState && memoryBank[i].trendState == cond.trendState) {
         matchCount++;
         if(memoryBank[i].isWin) winCount++;
      }
   }
   return (matchCount == 0) ? 50.0 : ((double)winCount / matchCount) * 100.0;
}

void DrawOBRect(string type, color zoneColor, int index) {
   string name = "Sniper_Zone_" + IntegerToString(rectCounter++);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, iTime(_Symbol,_Period,index), iHigh(_Symbol,_Period,index), iTime(_Symbol,_Period,0)+3600*24, iLow(_Symbol,_Period,index));
   ObjectSetInteger(0, name, OBJPROP_COLOR, zoneColor);
   ObjectSetInteger(0, name, OBJPROP_FILL, true); ObjectSetInteger(0, name, OBJPROP_BACK, true);
}