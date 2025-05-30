//+------------------------------------------------------------------+
//|                                                VolumeProfile.mq5 |
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                      https://www.metaquotes.net/ |
//+------------------------------------------------------------------+
#property copyright "André Luís Lopes da Silva"
#property link      "https://github.com/Andre-Luis-Lopes-da-Silva"
#property version   "2.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
#property indicator_label1  "POC"

#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGreen
#property indicator_style2  STYLE_DOT
#property indicator_width2  1
#property indicator_label2  "VAH"

#property indicator_type3   DRAW_LINE
#property indicator_color3  clrRed
#property indicator_style3  STYLE_DOT
#property indicator_width3  1
#property indicator_label3  "VAL"

//--- Parâmetros de entrada
input double ValueAreaPercent = 70.0;  // Percentual da Área de Valor (70% padrão)
input bool   ShowLabels      = true;   // Mostrar rótulos
input color  LabelColor      = clrWhite; // Cor dos rótulos
input bool   UseRealVolume   = true;   // Usar volume real (se disponível)

//--- Buffers do indicador
double POCBuffer[];
double VAHBuffer[];
double VALBuffer[];

//--- Variáveis globais
double pocPrice, vahPrice, valPrice;
datetime lastCalculatedDay = 0;

//+------------------------------------------------------------------+
//| Função de inicialização do indicador                             |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Definir buffers do indicador
   SetIndexBuffer(0, POCBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, VAHBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, VALBuffer, INDICATOR_DATA);
   
   //--- Definir nomes para exibição
   IndicatorSetString(INDICATOR_SHORTNAME, "VolumeProfile (" + DoubleToString(ValueAreaPercent, 1) + "%)");
   
   //--- Definir deslocamento temporal para desenhar no futuro
   PlotIndexSetInteger(0, PLOT_SHIFT, 1);
   PlotIndexSetInteger(1, PLOT_SHIFT, 1);
   PlotIndexSetInteger(2, PLOT_SHIFT, 1);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Função de iteração do indicador                                  |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   //--- Verificar se é um novo dia
   MqlDateTime currentTime, lastTime;
   TimeToStruct(time[rates_total-1], currentTime);
   
   if(lastCalculatedDay != 0)
      TimeToStruct(lastCalculatedDay, lastTime);
   else
      lastTime.day = -1;
   
   //--- Se mesmo dia e já calculado, apenas atualizar buffers
   if(currentTime.day == lastTime.day && lastCalculatedDay != 0)
   {
      UpdateBuffers(rates_total, time);
      return(rates_total);
   }
   
   //--- Calcular perfil do dia anterior
   CalculatePreviousDayProfile();
   
   //--- Atualizar buffers com os novos valores
   UpdateBuffers(rates_total, time);
   
   //--- Atualizar o último dia calculado
   lastCalculatedDay = time[rates_total-1];
   
   //--- Desenhar rótulos se habilitado
   if(ShowLabels)
      DrawLabels();
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Calcular o volume profile do dia anterior                        |
//+------------------------------------------------------------------+
void CalculatePreviousDayProfile()
{
   //--- Encontrar o início e fim do dia anterior
   datetime startTime = iTime(NULL, PERIOD_D1, 1);
   datetime endTime = iTime(NULL, PERIOD_D1, 0) - 1;
   
   //--- Obter dados de 1 minuto para cálculo preciso
   MqlRates rates[];
   int copied = CopyRates(Symbol(), PERIOD_M1, startTime, endTime, rates);
   if(copied <= 0)
   {
      Print("Falha ao obter dados de 1 minuto! Erro: ", GetLastError());
      return;
   }
   
   //--- Criar mapa de preço-volume
   double uniquePrices[];
   long priceVolumes[];
   
   for(int i = 0; i < copied; i++)
   {
      double price = (rates[i].high + rates[i].low) / 2.0;
      double roundedPrice = NormalizeDouble(price, _Digits);
      long vol = (UseRealVolume && rates[i].real_volume > 0) ? rates[i].real_volume : rates[i].tick_volume;
      
      // Adicionar ao mapa de volume
      bool found = false;
      for(int j = 0; j < ArraySize(uniquePrices); j++)
      {
         if(roundedPrice == uniquePrices[j])
         {
            priceVolumes[j] += vol;
            found = true;
            break;
         }
      }
      
      if(!found)
      {
         int size = ArraySize(uniquePrices);
         ArrayResize(uniquePrices, size+1);
         ArrayResize(priceVolumes, size+1);
         uniquePrices[size] = roundedPrice;
         priceVolumes[size] = vol;
      }
   }
   
   if(ArraySize(priceVolumes) == 0) return;
   
   //--- Encontrar o POC (preço com maior volume)
   long maxVolume = 0;
   for(int i = 0; i < ArraySize(priceVolumes); i++)
   {
      if(priceVolumes[i] > maxVolume)
      {
         maxVolume = priceVolumes[i];
         pocPrice = uniquePrices[i];
      }
   }
   
   //--- Calcular a Área de Valor (70% do volume total)
   long totalVolume = 0;
   for(int i = 0; i < ArraySize(priceVolumes); i++)
      totalVolume += priceVolumes[i];
   
   long valueAreaVolume = (long)(totalVolume * ValueAreaPercent / 100.0);
   
   //--- Ordenar por volume (decrescente)
   for(int i = 0; i < ArraySize(priceVolumes)-1; i++)
   {
      for(int j = i+1; j < ArraySize(priceVolumes); j++)
      {
         if(priceVolumes[i] < priceVolumes[j])
         {
            // Trocar volumes
            long tempVol = priceVolumes[i];
            priceVolumes[i] = priceVolumes[j];
            priceVolumes[j] = tempVol;
            
            // Trocar preços
            double tempPrice = uniquePrices[i];
            uniquePrices[i] = uniquePrices[j];
            uniquePrices[j] = tempPrice;
         }
      }
   }
   
   //--- Encontrar VAH e VAL
   long accumulatedVolume = 0;
   double highestPrice = 0;
   double lowestPrice = DBL_MAX;
   
   for(int i = 0; i < ArraySize(priceVolumes); i++)
   {
      accumulatedVolume += priceVolumes[i];
      
      if(uniquePrices[i] > highestPrice) highestPrice = uniquePrices[i];
      if(uniquePrices[i] < lowestPrice) lowestPrice = uniquePrices[i];
      
      if(accumulatedVolume >= valueAreaVolume)
      {
         vahPrice = highestPrice;
         valPrice = lowestPrice;
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Atualizar buffers do indicador                                   |
//+------------------------------------------------------------------+
void UpdateBuffers(int rates_total, const datetime &time[])
{
   //--- Preencher buffers com os valores calculados
   for(int i = 0; i < rates_total; i++)
   {
      POCBuffer[i] = pocPrice;
      VAHBuffer[i] = vahPrice;
      VALBuffer[i] = valPrice;
   }
   
   //--- Deslocar os valores para o dia atual (visualização)
   datetime currentDayStart = iTime(NULL, PERIOD_D1, 0);
   for(int i = 0; i < rates_total; i++)
   {
      if(time[i] >= currentDayStart)
      {
         POCBuffer[i] = pocPrice;
         VAHBuffer[i] = vahPrice;
         VALBuffer[i] = valPrice;
      }
   }
}

//+------------------------------------------------------------------+
//| Desenhar rótulos no gráfico                                      |
//+------------------------------------------------------------------+
void DrawLabels()
{
   //--- Remover objetos antigos
   ObjectsDeleteAll(0, "VP_");
   
   //--- Criar rótulos
   CreateLabel("VP_POC", "POC: " + DoubleToString(pocPrice, _Digits), pocPrice, LabelColor);
   CreateLabel("VP_VAH", "VAH: " + DoubleToString(vahPrice, _Digits), vahPrice, LabelColor);
   CreateLabel("VP_VAL", "VAL: " + DoubleToString(valPrice, _Digits), valPrice, LabelColor);
}

//+------------------------------------------------------------------+
//| Criar um rótulo de texto                                         |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, double price, color clr)
{
   ObjectCreate(0, name, OBJ_TEXT, 0, TimeCurrent(), price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}