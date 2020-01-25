#include <stdlib.mqh>
#include <stderror.mqh>

#define LOG_LEVEL_ERR 1
#define LOG_LEVEL_WARN 2
#define LOG_LEVEL_INFO 3
#define LOG_LEVEL_DBG 4


#import "MT4.Tools.Emailer.dll"
	//int XEmailerInit( string pop_server, int port, int use_ssl, string login, string password );
	int XEmailerInit( uchar &pop_server[], int port, int use_ssl, uchar &login[], uchar &password[] );	
	void XEmailerFree();
	int XEmailerCheckMailAccount();
	void XEmailerFinishCheck();
	bool XEmailerSelectMailMessage( int index );
	void XEmailerGetMailBody( int& body[] );
	int XEmailerGetMailBodyLen();
	void XEmailerGetMailSubject( int& subject[] );
	int XEmailerGetMailSubjectLen();
	void XEmailerGetMailUID( int& uid[] );
	int XEmailerGetMailUIDLen();
//	bool XEmailerDeleteMail( string uid );

#import

int retry_attempts 		= 10; 
double sleep_time 		= 4.0;
double sleep_maximum 	= 25.0;  // in seconds
bool shown_version_info = false;
int ErrorLevel 	= LOG_LEVEL_DBG;
int _OR_err 		= 0;

#define E_NONE 1
#define E_TRIAL_EXPIRED 2
#define E_INTERNAL_ERROR 3
#define E_SEND 4
#define E_SMTP_CLOSE 5

#define VERSION 1														// Minor version
bool DEBUG = true;														// Debug flag

extern string _ = "- Main variables ---------------------------";
//extern string Pairs = "EUR/USD;USD/CHF;GBP/USD;USD/JPY;USD/CAD;AUD/USD;EUR/JPY;NZD/USD;GPB/CHF;";
extern string Pairs = "AUD/CAD;AUD/CHF;AUD/JPY;AUD/NZD;AUD/USD;CAD/CHF;CHF/JPY;EUR/AUD;EUR/CAD;EUR/CHF;EUR/GPY;EUR/NZD;EUR/USD;GBP/AUD;GBP/CAD;GBP/CHF;GBP/JPY;GBP/NZD;GBP/USD;NZD/CAD;NZD/CHF;NZD/JPY;NZD/USD;USD/CAD;USD/CHF;USD/JPY;";
extern string PairsIgnoreSL_TP = "AUDCAD;";
extern string SystemsToShow = "";
int MagicNumber = 123213;									// Magic number
extern double Slippage = 3;
extern int NumberOfTries = 10;												// NUmber of tries for action with server
extern int NumberOfFailsToNtf = 3;

extern int MaxOrdersPerDirection = 1;
extern double Takeprofit = 50;
extern double Stoploss = 50;

bool AutoBreakeven = false;
int AutoBreakProfit = 200; //(if market moves 10 pips in my favor Move my stop to Auto Break Even)
int AutoBreakEvenPoints = 10; // (+1 means break even + 1 pip) -1 means Breakeven -1 pip. Etc)

bool TrailStop = false;
int TrailStopPips = 10;

bool IsUseLotsManagement = false;
extern double LotSize = 0.1;										// Default lot size
double RiskPercent = 3;

extern string __ = "- Mail variables (POP3) -";
extern string Server = "pop.gmail.com";											// Server name or IP
extern int Port = 995;												// POP port for connection
extern bool IsUseSSL = true;										// If true then connection use SSL
extern string Login = "ys.tradesignal@gmail.com";											// Login name, f.e. "joe.doe@gmail.com"
extern string Password = "mikhail14";										// Passphrase
extern int CheckMailEveryXSeconds = 3600;							// Timeout
extern int CheckMailNumberOfTime = 10;							// Timeout
extern int ReCheckMailEveryXSeconds = 1;							// Timeout


int LastBars;															// Count of last bars
bool IsFirstTick;														// First tick flag
bool IsInited;
int cntFails = 0;
// -------------------------------------------------------------
// Orders info stuff
// -------------------------------------------------------------

#define NOF_KEYS 9

#define KEY_PAIR 0
#define KEY_ORDER_TYPE 1
#define KEY_PRICE 2
#define KEY_SL 3
#define KEY_TP 4
#define KEY_FROM 5
#define KEY_TO 6
#define KEY_LOTS 7
#define KEY_COMM 8

string OrdersInfo[][NOF_KEYS];

string VersionGet() {
	return( WindowExpertName() + " v0.0." + VERSION );
} // VersionGet

void ShowError( int errorCode ) {

	if ( errorCode < 0 )  {
		Print( WindowExpertName(), " Error> Internal error!" );
		return;
	} // if

	switch( errorCode ) {
		case ERR_NO_RESULT: break;
		default:
			Print( WindowExpertName(), " Error> ", ErrorDescription( errorCode ) );
			break;
	} // switch

} // ShowError

void DrawComments() {
  string info;

	info = VersionGet() + "\n";
	Comment( info );

} // DrawComments

int do_flat( string pair ) {
  int total;
  
    total = OrdersTotal();
   
    for ( int i = 0; i < total; i++ )  {
    
      if ( OrderSelect( i, SELECT_BY_POS, MODE_TRADES) == false ) {
         Print("Access to open orders failed with error(" + GetLastError() + ")");
         break;
      }
    
      if(OrderSymbol() == pair ) {
          exit( pair );
          break;
      }
    }
    
    return 0;    
}

int do_open( string symbol, int type, double lots, string comm ) {
	double price, sl = 0, tp = 0, digits, points, myPoint;	
	int t;
	datetime exp;

  lots = getLots( symbol, lots, RiskPercent );
 
   RefreshRates();
  
  points = MarketInfo( symbol, MODE_POINT );
  digits = MarketInfo( symbol, MODE_DIGITS );
  
  if(digits == 3 || digits == 5) {
   myPoint = points*10;
  } else
   myPoint = points;
  
  if(digits == 5 || digits == 3)
    points = points*10;
    
  if(type == OP_SELL) {
    price = MarketInfo( symbol, MODE_BID );
    
    if(StringLen(PairsIgnoreSL_TP) > 1)
     if(StringFind(PairsIgnoreSL_TP, symbol) == -1) {
            
      if(Stoploss != 0)
        sl =  price + Stoploss*myPoint;
      
      if(Takeprofit != 0)
        tp =  price - Takeprofit*myPoint;
     }
  } 
  
  if(type == OP_BUY) {
    price = MarketInfo( symbol, MODE_ASK );
    
    if(StringLen(PairsIgnoreSL_TP) > 1)
     if(StringFind(PairsIgnoreSL_TP, symbol) == -1) {    
        if(Stoploss != 0)
          sl =  price - Stoploss*myPoint;
        if(Takeprofit != 0)
          tp =  price + Takeprofit*myPoint;
      }
  } 
  
  if(StringLen(SystemsToShow) > 1)
   if(StringFind(SystemsToShow, comm) == -1)
      comm = "";
  
  t = XOrderSend( symbol, type, lots, price, Slippage, sl, tp, comm, MagicNumber );
	
  return 0;
}

int MailProcessing( string& info[NOF_KEYS] ) {	
	
	if(StringLen(PairsIgnoreSL_TP) > 1)
     if(StringFind(PairsIgnoreSL_TP, info[KEY_PAIR]) != -1) {
        if(info[KEY_ORDER_TYPE] == "FLAT") {
          return do_flat(info[KEY_PAIR]);
        }
  }
  
  if(info[KEY_ORDER_TYPE] == "SHORT") {
  
    if( CountOrders( info[KEY_PAIR], OP_SELL) >= MaxOrdersPerDirection )
      return 0;
  
    if(CountOrders( info[KEY_PAIR], OP_BUY) > 0)
      do_flat(info[KEY_PAIR]);
    return do_open(info[KEY_PAIR], OP_SELL, info[KEY_LOTS], info[KEY_COMM]);
  }    
  
  if(info[KEY_ORDER_TYPE] == "LONG") {
  
    if( CountOrders( info[KEY_PAIR], OP_BUY) >= MaxOrdersPerDirection )
      return 0;
        
    if(CountOrders( info[KEY_PAIR], OP_SELL) > 0)
      do_flat(info[KEY_PAIR]);  
    return do_open(info[KEY_PAIR], OP_BUY, info[KEY_LOTS], info[KEY_COMM]);
  }        
  
  return 0;
} // MailProcessing

int MailCheck( string& mails[] ) {
   int nof, len, buff[];
   string mailBody;

	nof = XEmailerCheckMailAccount();
	
//	if(DEBUG) {
//	   if(nof == -1)
//	      nof = 0;	
//	}
	Print("unread emails: ", nof);
	
	if(NumberOfFailsToNtf > 0) {
   	if(nof >= 0)
   	   cntFails = 0;	   
   	else
   	   cntFails = cntFails + 1;
   	   
   	if(cntFails >= NumberOfFailsToNtf) {
   	   SendNotification("Failed to check email for " + NumberOfFailsToNtf + " number of time");
   	   cntFails = 0;	   
   	}
	}
		
	for( int i = 0; i < nof; i++ ) {
		
      if( XEmailerSelectMailMessage( i ) == true ) {
			
			len = XEmailerGetMailBodyLen();
			if ( len == 0 ) continue;

			ArrayResize( buff, len );
			ArrayInitialize( buff, 0 );
			
			XEmailerGetMailBody( buff );
			mailBody = IntArray2String( buff );

			mailBody = StringTrimLeft( StringTrimRight( mailBody ) );
			int handle;
      handle=FileOpen("log.txt", FILE_WRITE|FILE_CSV);
      if(handle!=INVALID_HANDLE){
			Print(mailBody);
         
        FileWrite(handle, mailBody);
        FileClose(handle);
      }

			if ( StringLen( mailBody ) > 0 ) {

				ArrayResize( mails, i + 1 );
				mails[ i ] = mailBody;

			} // if
					
		} // if
						
	} // for i

	XEmailerFinishCheck();

	return( 0 );
}


bool MailParse( string mailBody, string& info[NOF_KEYS] ) {
   string array[], t[];
   string f, to;
         
   int N = 28;
   int M = 55;

  int handle=FileOpen("email.txt", FILE_ANSI|FILE_WRITE);
  if(handle!=INVALID_HANDLE){
    FileWrite(handle, mailBody);
    FileClose(handle);
  }

	if ( SplitString( mailBody, "\n", t ) == false )
		return( false );

  handle=FileOpen("log2.txt", FILE_BIN|FILE_WRITE);
  if(handle!=INVALID_HANDLE){
    FileWriteArray(handle, t, 0, 5);
    FileClose(handle);
  }
 
   string pair = StringSubstr( t[0], 0, 7 );
   StringReplace( pair, "/", "" );
   info[ KEY_PAIR ] = StringTrimRight( StringTrimLeft(pair));
   info[ KEY_COMM ] = StringTrimRight( StringTrimLeft(t[1]));
   
   string type = t[4];
   string t1[];
   
   StringSplit( type, ' ', t1 );

	info[ KEY_ORDER_TYPE ] = StringTrimRight( StringTrimLeft(t1[1]) );   
   
   if(t1[1] != "FLAT") {
   	info[ KEY_LOTS ] = t1[3];
   }
	
	return true;
} // MailParse

// -------------------------------------------------------------
// Main stuff
// -------------------------------------------------------------

int init() {
   int result;

	IsInited = true;
	IsFirstTick = true;
	retry_attempts = NumberOfTries;
	cntFails = 0;

   if ( IsDllsAllowed() == false ) {
      Print( WindowExpertName(), "Fatal error> You have to enable import dll for this Expert!" );
      IsInited = false;
      return( -1 );
   } // if

	result = __XEmailerInit( Server, Port, IsUseSSL, Login, Password );
	if ( result != E_NONE ) {
		IsInited = false;
		Print( WindowExpertName(), " Fatal error> Error initialization of the e-mail library!" );
		return( -1 );
	} // if 
	
	EventSetTimer( CheckMailEveryXSeconds );
	OnTimer();
	
	return( 0 );
} // init

int deinit() {
	
	EventKillTimer();
	
	Comment( "" );
	XEmailerFree();
	
	return( 0 );
} // deinit

int start() {
   
   return 0;
}

void OnTimer() {
   int result = 0;
   int i = 0;
  
  if( IsInited == false )
   return 0;
   
  while(1) {
     run();
     doManagement();
     Sleep(ReCheckMailEveryXSeconds*1000);
     i = i + 1;
      if(i >= CheckMailNumberOfTime )
         break;
  }

}


int run() {
   int ErrorCode, nof;
   string mails[], info[NOF_KEYS];
   

	ErrorCode = 0;
	ArrayResize( mails, 0 );
	
	if ( MailCheck( mails ) == 0 ) {
	
		nof = ArraySize( mails );

		for( int i = 0; i < nof; i++ ) {
			if ( MailParse( mails[ i ], info ) == true ) {
				ErrorCode = MailProcessing( info );
				if ( ErrorCode != 0 )
					break;
			} // if
			
		} // for i
	
	} // if
	
	if ( ErrorCode != 0 )
		ShowError( ErrorCode );
	else
		DrawComments();

	return( ErrorCode );
} // _start

bool SplitString(string stringValue, string separatorSymbol, string& results[], int expectedResultCount = 0)
{

   if (StringFind(stringValue, separatorSymbol) < 0)
   {// No separators found, the entire string is the result.
      ArrayResize(results, 1);
      results[0] = stringValue;
   }
   else
   {   
      int separatorPos = 0;
      int newSeparatorPos = 0;
      int size = 0;

      while(newSeparatorPos > -1)
      {
         size = size + 1;
         newSeparatorPos = StringFind(stringValue, separatorSymbol, separatorPos);
         
         ArrayResize(results, size);
         if (newSeparatorPos > -1)
         {
            if (newSeparatorPos - separatorPos > 0)
            {// Evade filling empty positions, since 0 size is considered by the StringSubstr as entire string to the end.
               results[size-1] = StringSubstr(stringValue, separatorPos, newSeparatorPos - separatorPos);
            }
         }
         else
         {// Reached final element.
            results[size-1] = StringSubstr(stringValue, separatorPos, 0);
         }
         
         
         //Alert(results[size-1]);
         separatorPos = newSeparatorPos + 1;
      }
   }   
   
   if (expectedResultCount == 0 || expectedResultCount == ArraySize(results))
   {// Results OK.
      return (true);
   }
   else
   {// Results are WRONG.
      return (false);
   }
}

void XPrint( int log_level, string text, bool is_show_comments = false ) {
   string prefix, message;
   
   if( log_level > ErrorLevel )
      return;

   switch(log_level) {
      case LOG_LEVEL_ERR:
         prefix = "Error";
         break;
      case LOG_LEVEL_WARN:
         prefix = "Warning";
         break;
      case LOG_LEVEL_INFO:
         prefix = "Info";
         break;
      case LOG_LEVEL_DBG:
         prefix = "Debug";
         break;                  
   }
   
   message = StringConcatenate( prefix, ": ", text );
   
   if( is_show_comments )
      Comment( message );
   
   Print(message);
}

int XOrderSend(string symbol, int cmd, double volume, double price,
					  int slippage, double stoploss, double takeprofit,
					  string comment, int magic, datetime expiration = 0, 
					  color arrow_color = CLR_NONE) {

   int digits;
   
	XPrint( LOG_LEVEL_INFO, "Attempted " + XCommandString(cmd) + " " + volume + 
						" lots @" + price + " sl:" + stoploss + " tp:" + takeprofit); 
						
	if (IsStopped()) {
		XPrint( LOG_LEVEL_WARN, "Expert was stopped while processing order. Order was canceled.");
		_OR_err = ERR_COMMON_ERROR; 
		return(-1);
	}
	
	int cnt = 0;
	while(!IsTradeAllowed() && cnt < retry_attempts) {
		XSleepRandomTime(sleep_time, sleep_maximum); 
		cnt++;
	}
	
	if (!IsTradeAllowed()) 
	{
		XPrint( LOG_LEVEL_WARN, "No operation possible because Trading not allowed for this Expert, even after retries.");
		_OR_err = ERR_TRADE_CONTEXT_BUSY; 

		return(-1);  
	}

   digits = MarketInfo( symbol, MODE_DIGITS);

   if( price == 0 ) {
      RefreshRates();
      if( cmd == OP_BUY ) {
			price = Ask;      
      }
      if( cmd == OP_SELL ) {
			price = Bid;      
      }      
   }

	if (digits > 0) {
		price = NormalizeDouble(price, digits);
		stoploss = NormalizeDouble(stoploss, digits);
		takeprofit = NormalizeDouble(takeprofit, digits); 
	}
	
	if (stoploss != 0) 
		XEnsureValidStop(symbol, price, stoploss); 

	int err = GetLastError(); // clear the global variable.  
	err = 0; 
	_OR_err = 0; 
	bool exit_loop = false;
	bool limit_to_market = false; 
	
	// limit/stop order. 
	int ticket=-1;

	if ((cmd == OP_BUYSTOP) || (cmd == OP_SELLSTOP) || (cmd == OP_BUYLIMIT) || (cmd == OP_SELLLIMIT)) {
		cnt = 0;
		while (!exit_loop) {
			if (IsTradeAllowed()) {
				ticket = OrderSend(symbol, cmd, volume, price, slippage, stoploss, takeprofit, comment, magic, expiration, arrow_color);
				err = GetLastError();
				_OR_err = err; 
			} else {
				cnt++;
			} 
			
			switch (err) {
				case ERR_NO_ERROR:
					exit_loop = true;
					break;
				
				// retryable errors
				case ERR_SERVER_BUSY:
				case ERR_NO_CONNECTION:
				case ERR_INVALID_PRICE:
				case ERR_OFF_QUOTES:
				case ERR_BROKER_BUSY:
				case ERR_TRADE_CONTEXT_BUSY: 
					cnt++; 
					break;
					
				case ERR_PRICE_CHANGED:
				case ERR_REQUOTE:
					RefreshRates();
					continue;	// we can apparently retry immediately according to MT docs.
					
				case ERR_INVALID_STOPS:
					double servers_min_stop = MarketInfo(symbol, MODE_STOPLEVEL) * XGetPoint(symbol); 
					if (cmd == OP_BUYSTOP) {
						// If we are too close to put in a limit/stop order so go to market.
						if (MathAbs(Ask - price) <= servers_min_stop)	
							limit_to_market = true; 
							
					} 
					else if (cmd == OP_SELLSTOP) 
					{
						// If we are too close to put in a limit/stop order so go to market.
						if (MathAbs(Bid - price) <= servers_min_stop)
							limit_to_market = true; 
					}
					exit_loop = true; 
					break; 
					
				default:
					// an apparently serious error.
					exit_loop = true;
					break; 
					
			}  // end switch 

			if (cnt > retry_attempts) 
				exit_loop = true; 
			 	
			if (exit_loop) {
				if (err != ERR_NO_ERROR) {
					XPrint( LOG_LEVEL_ERR, "Non-retryable error - " + XErrorDescription(err)); 
				}
				if (cnt > retry_attempts) {
					XPrint( LOG_LEVEL_INFO, "Retry attempts maxed at " + retry_attempts); 
				}
			}
			 
			if (!exit_loop) {
				XPrint( LOG_LEVEL_DBG, "Retryable error (" + cnt + "/" + retry_attempts + 
									"): " + XErrorDescription(err)); 
				XSleepRandomTime(sleep_time, sleep_maximum); 
				RefreshRates(); 
			}
		}
		 
		// We have now exited from loop. 
		if (err == ERR_NO_ERROR) {
			XPrint( LOG_LEVEL_INFO, "apparently successful order placed.");
			return(ticket); // SUCCESS! 
		} 
		if (!limit_to_market) {
			XPrint( LOG_LEVEL_ERR, "failed to execute stop or limit order after " + cnt + " retries");
			XPrint( LOG_LEVEL_INFO, "failed trade: " + XCommandString(cmd) + " " + symbol + 
								"@" + price + " tp@" + takeprofit + " sl@" + stoploss); 
			XPrint( LOG_LEVEL_INFO, "last error: " + XErrorDescription(err)); 
			return(-1); 
		}
	}  // end	  
  
	if (limit_to_market) {
		XPrint( LOG_LEVEL_DBG, "going from limit order to market order because market is too close." );
		RefreshRates();
		if ((cmd == OP_BUYSTOP) || (cmd == OP_BUYLIMIT)) {
			cmd = OP_BUY;
			price = Ask;
		} 
		else if ((cmd == OP_SELLSTOP) || (cmd == OP_SELLLIMIT)) 
		{
			cmd = OP_SELL;
			price = Bid;
		}	
	}
	
	// we now have a market order.
	err = GetLastError(); // so we clear the global variable.  
	err = 0; 
	_OR_err = 0; 
	ticket = -1;

	if ((cmd == OP_BUY) || (cmd == OP_SELL)) {
		cnt = 0;
		while (!exit_loop) {
			if (IsTradeAllowed()) {
				ticket = OrderSend(symbol, cmd, volume, price, slippage, stoploss, takeprofit, comment, magic, expiration, arrow_color);
				err = GetLastError();
				_OR_err = err; 
			} else {
				cnt++;
			} 
			switch (err) {
				case ERR_NO_ERROR:
					exit_loop = true;
					break;
					
				case ERR_SERVER_BUSY:
				case ERR_NO_CONNECTION:
				case ERR_INVALID_PRICE:
				case ERR_OFF_QUOTES:
				case ERR_BROKER_BUSY:
				case ERR_TRADE_CONTEXT_BUSY: 
					cnt++; // a retryable error
					break;
					
				case ERR_PRICE_CHANGED:
				case ERR_REQUOTE:
					RefreshRates();
					continue; // we can apparently retry immediately according to MT docs.
					
				default:
					// an apparently serious, unretryable error.
					exit_loop = true;
					break; 
					
			}  // end switch 

			if (cnt > retry_attempts) 
			 	exit_loop = true; 
			 	
			if (!exit_loop) {
				XPrint( LOG_LEVEL_DBG, "retryable error (" + cnt + "/" + 
									retry_attempts + "): " + XErrorDescription(err)); 
				XSleepRandomTime(sleep_time,sleep_maximum); 
				RefreshRates(); 
			}
			
			if (exit_loop) {
				if (err != ERR_NO_ERROR) {
					XPrint( LOG_LEVEL_ERR, "non-retryable error: " + XErrorDescription(err)); 
				}
				if (cnt > retry_attempts) {
					XPrint( LOG_LEVEL_INFO, "retry attempts maxed at " + retry_attempts); 
				}
			}
		}
		
		// we have now exited from loop. 
		if (err == ERR_NO_ERROR) {
			XPrint( LOG_LEVEL_INFO, "apparently successful order placed, details follow.");
//			OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES); 
//			OrderPrint(); 
			return(ticket); // SUCCESS! 
		} 
		XPrint( LOG_LEVEL_ERR, "failed to execute OP_BUY/OP_SELL, after " + cnt + " retries");
		XPrint( LOG_LEVEL_INFO, "failed trade: " + XCommandString(cmd) + " " + symbol + 
							"@" + price + " tp@" + takeprofit + " sl@" + stoploss); 
		XPrint( LOG_LEVEL_INFO, "last error: " + XErrorDescription(err)); 
		return(-1); 
	}
}

int XOrderSend2Step(string symbol, int cmd, double volume, double price,
					  int slippage, double stoploss, double takeprofit,
					  string comment, int magic, datetime expiration = 0, 
					  color arrow_color = CLR_NONE) {

   int mkt_ticket = XOrderSend(symbol,cmd,volume,price,slippage,0,0,comment,magic,expiration,arrow_color);
   if (mkt_ticket > 0 && (stoploss!=0 || takeprofit!=0)) {   
      OrderSelect(mkt_ticket,SELECT_BY_TICKET);
      XOrderModify(mkt_ticket,OrderOpenPrice(),stoploss,takeprofit,OrderExpiration(),arrow_color);
   }
   return (mkt_ticket);
}

bool XOrderModify(int ticket, double price, double stoploss, 
						 double takeprofit, datetime expiration, 
						 color arrow_color = CLR_NONE) {

	XPrint( LOG_LEVEL_INFO, " attempted modify of #" + ticket + " price:" + price + " sl:" + stoploss + " tp:" + takeprofit); 

	if (IsStopped()) {
		XPrint( LOG_LEVEL_WARN, "Expert was stopped while processing order. Order was canceled.");
		return(false);
	}
	
	int cnt = 0;
	while(!IsTradeAllowed() && cnt < retry_attempts) {
		XSleepRandomTime(sleep_time,sleep_maximum); 
		cnt++;
	}
	if (!IsTradeAllowed()) {
		XPrint( LOG_LEVEL_WARN, "No operation possible because Trading not allowed for this Expert, even after retries.");
		_OR_err = ERR_TRADE_CONTEXT_BUSY; 
		return(false);  
	}

	int err = GetLastError(); // so we clear the global variable.  
	err = 0; 
	_OR_err = 0; 
	bool exit_loop = false;
	cnt = 0;
	bool result = false;
	
	while (!exit_loop) {
		if (IsTradeAllowed()) {
			result = OrderModify(ticket, price, stoploss, takeprofit, expiration, arrow_color);
			err = GetLastError();
			_OR_err = err; 
		} 
		else 
			cnt++;

		if (result == true) 
			exit_loop = true;

		switch (err) {
			case ERR_NO_ERROR:
				exit_loop = true;
				break;
				
			case ERR_NO_RESULT:
				// modification without changing a parameter. 
				// if you get this then you may want to change the code.
				exit_loop = true;
				break;
				
			case ERR_SERVER_BUSY:
			case ERR_NO_CONNECTION:
			case ERR_INVALID_PRICE:
			case ERR_OFF_QUOTES:
			case ERR_BROKER_BUSY:
			case ERR_TRADE_CONTEXT_BUSY: 
			case ERR_TRADE_TIMEOUT:		// for modify this is a retryable error, I hope. 
				cnt++; 	// a retryable error
				break;
				
			case ERR_PRICE_CHANGED:
			case ERR_REQUOTE:
				RefreshRates();
				continue; 	// we can apparently retry immediately according to MT docs.
				
			default:
				// an apparently serious, unretryable error.
				exit_loop = true;
				break; 
				
		}  // end switch 

		if (cnt > retry_attempts) 
			exit_loop = true; 
			
		if (!exit_loop) 
		{
			XPrint( LOG_LEVEL_DBG, "retryable error (" + cnt + "/" + retry_attempts + "): "  +  XErrorDescription(err)); 
			XSleepRandomTime(sleep_time,sleep_maximum); 
			RefreshRates(); 
		}
		
		if (exit_loop) {
			if ((err != ERR_NO_ERROR) && (err != ERR_NO_RESULT)) 
				XPrint( LOG_LEVEL_ERR, "non-retryable error: "  + XErrorDescription(err)); 

			if (cnt > retry_attempts) 
				XPrint( LOG_LEVEL_INFO, "retry attempts maxed at " + retry_attempts); 
		}
	}  
	
	// we have now exited from loop. 
	if ((result == true) || (err == ERR_NO_ERROR)) 	{
		XPrint( LOG_LEVEL_INFO, "apparently successful modification order.");
		return(true); // SUCCESS! 
	} 
	
	if (err == ERR_NO_RESULT) {
		XPrint( LOG_LEVEL_WARN, "Server reported modify order did not actually change parameters.");
		return(true);
	}
	
	XPrint( LOG_LEVEL_ERR, "failed to execute modify after " + cnt + " retries");
	XPrint( LOG_LEVEL_INFO, "failed modification: "  + ticket + " @" + price + " tp@" + takeprofit + " sl@" + stoploss); 
	XPrint( LOG_LEVEL_INFO, "last error: " + XErrorDescription(err)); 
	
	return(false);  
}

bool XOrderClose(int ticket, double lots, double price, int slippage, color arrow_color = CLR_NONE) {
	int nOrderType;
	string strSymbol;
	
	XPrint( LOG_LEVEL_INFO, " attempted close of #" + ticket + " price:" + price + " lots:" + lots + " slippage:" + slippage); 

	// collect details of order so that we can use GetMarketInfo later if needed
	if (!OrderSelect(ticket,SELECT_BY_TICKET)) {
		_OR_err = GetLastError();		
		XPrint( LOG_LEVEL_ERR, XErrorDescription(_OR_err));
		return(false);
	} else {
		nOrderType = OrderType();
		strSymbol = Symbol();
	}

	if (nOrderType != OP_BUY && nOrderType != OP_SELL)	{
		_OR_err = ERR_INVALID_TICKET;
		XPrint( LOG_LEVEL_WARN, "trying to close ticket #" + ticket + ", which is " + XCommandString(nOrderType) + ", not BUY or SELL");
		return(false);
	}

	if (IsStopped()) {
		XPrint( LOG_LEVEL_WARN, "Expert was stopped while processing order. Order processing was canceled.");
		return(false);
	}

	
	int cnt = 0;
	int err = GetLastError(); // so we clear the global variable.  
	err = 0; 
	_OR_err = 0; 
	bool exit_loop = false;
	cnt = 0;
	bool result = false;
	
	if( lots == 0)
	  lots = OrderLots();
	
	if( price == 0 ) {
	  RefreshRates();
	  if (nOrderType == OP_BUY)  
		  price = NormalizeDouble(MarketInfo(strSymbol, MODE_BID), MarketInfo(strSymbol, MODE_DIGITS));
	  if (nOrderType == OP_SELL) 
		  price = NormalizeDouble(MarketInfo(strSymbol, MODE_ASK), MarketInfo(strSymbol, MODE_DIGITS));
	}
	
	while (!exit_loop) 
	{
		if (IsTradeAllowed()) 
		{
			result = OrderClose(ticket, lots, price, slippage, arrow_color);
			err = GetLastError();
			_OR_err = err; 
		} 
		else 
			cnt++;

		if (result == true) 
			exit_loop = true;

		switch (err) {
			case ERR_NO_ERROR:
				exit_loop = true;
				break;
				
			case ERR_SERVER_BUSY:
			case ERR_NO_CONNECTION:
			case ERR_INVALID_PRICE:
			case ERR_OFF_QUOTES:
			case ERR_BROKER_BUSY:
			case ERR_TRADE_CONTEXT_BUSY: 
			case ERR_TRADE_TIMEOUT:		// for modify this is a retryable error, I hope. 
				cnt++; 	// a retryable error
				break;
				
			case ERR_PRICE_CHANGED:
			case ERR_REQUOTE:
				continue; 	// we can apparently retry immediately according to MT docs.
				
			default:
				// an apparently serious, unretryable error.
				exit_loop = true;
				break; 
				
		}  // end switch 

		if (cnt > retry_attempts) 
			exit_loop = true; 
			
		if (!exit_loop) 
		{
			XPrint( LOG_LEVEL_DBG, "retryable error (" + cnt + "/" + retry_attempts + "): "  +  XErrorDescription(err)); 
			XSleepRandomTime(sleep_time,sleep_maximum); 
			
			// Added by Paul Hampton-Smith to ensure that price is updated for each retry
			if (nOrderType == OP_BUY)  
				price = NormalizeDouble(MarketInfo(strSymbol, MODE_BID), MarketInfo(strSymbol, MODE_DIGITS));
			if (nOrderType == OP_SELL) 
				price = NormalizeDouble(MarketInfo(strSymbol, MODE_ASK), MarketInfo(strSymbol, MODE_DIGITS));
		}
		
		if (exit_loop) 
		{
			if ((err != ERR_NO_ERROR) && (err != ERR_NO_RESULT)) 
				XPrint( LOG_LEVEL_ERR, "non-retryable error: " + XErrorDescription(err)); 

			if (cnt > retry_attempts) 
				XPrint( LOG_LEVEL_INFO, "retry attempts maxed at " + retry_attempts); 
		}
	}  
	
	// we have now exited from loop. 
	if ((result == true) || (err == ERR_NO_ERROR)) 
	{
		XPrint( LOG_LEVEL_INFO, "apparently successful close order.");
		return(true); // SUCCESS! 
	} 
	
	XPrint( LOG_LEVEL_ERR, "failed to execute close after " + cnt + " retries");
	XPrint( LOG_LEVEL_INFO, "failed close: Ticket #" + ticket + ", Price: " + price + ", Slippage: " + slippage); 
	XPrint( LOG_LEVEL_INFO, "last error: " + XErrorDescription(err)); 
	
	return(false);  
}

string XCommandString(int cmd) {
	if (cmd == OP_BUY) 
		return("BUY");

	if (cmd == OP_SELL) 
		return("SELL");

	if (cmd == OP_BUYSTOP) 
		return("BUY STOP");

	if (cmd == OP_SELLSTOP) 
		return("SELL STOP");

	if (cmd == OP_BUYLIMIT) 
		return("BUY LIMIT");

	if (cmd == OP_SELLLIMIT) 
		return("SELL LIMIT");

	return("(" + cmd + ")"); 
}

void XEnsureValidStop(string symbol, double price, double& sl) {
	// Return if no S/L
	if (sl == 0) 
		return;
	
	double servers_min_stop = MarketInfo(symbol, MODE_STOPLEVEL) * XGetPoint(symbol); 
	
	if (MathAbs(price - sl) <= servers_min_stop) {
		// we have to adjust the stop.
		if (price > sl)
			sl = price - servers_min_stop;	// we are long
			
		else if (price < sl)
			sl = price + servers_min_stop;	// we are short			
		else
			XPrint( LOG_LEVEL_WARN, "Passed Stoploss which equal to price"); 
			
		sl = NormalizeDouble(sl, MarketInfo(symbol, MODE_DIGITS)); 
	}
}

double XGetPoint( string symbol ) {
   double point;
   
   point = MarketInfo( symbol, MODE_POINT );
   double digits = NormalizeDouble( MarketInfo( symbol, MODE_DIGITS ),0 );
   
   if( digits == 3 || digits == 5 ) {
      return(point*10.0);
   }
   
   return(point);
}


void XSleepRandomTime(double mean_time, double max_time) {
	if (IsTesting()) 
		return; 	// return immediately if backtesting.

	double tenths = MathCeil(mean_time / 0.1);
	if (tenths <= 0) 
		return; 
	 
	int maxtenths = MathRound(max_time/0.1); 
	double p = 1.0 - 1.0 / tenths; 
	  
	Sleep(100); 	// one tenth of a second PREVIOUS VERSIONS WERE STUPID HERE. 
	
	for(int i=0; i < maxtenths; i++) {
		if (MathRand() > p*32768) 
			break; 
			
		// MathRand() returns in 0..32767
		Sleep(100); 
	}
}  
 
string XErrorDescription(int err) {
   return(ErrorDescription(err)); 
}

int CountOrders( string pair, int cmd ) {
   int cnt = 0;
   
   for( int i = 0; i < OrdersTotal(); i++ ) {
      if( false == OrderSelect( i, SELECT_BY_POS, MODE_TRADES ) )
         continue;
      
      if(OrderSymbol() != pair)
         continue;
         
      if( OrderMagicNumber() != MagicNumber || OrderCloseTime() != 0 )
         continue;

      if( cmd == -1 )
         cnt++;
      else
         if( OrderType() == cmd )
            cnt++;
   }
   
   return(cnt);
}

string _typeToString( int type ) {
  switch( type ) {
    case OP_BUY:
      return("Buy");
    case OP_SELL:
      return("Sell");      
    case OP_BUYSTOP:
      return("BuyStop");      
    case OP_BUYLIMIT:
      return("BuyLimit");      
    case OP_SELLSTOP:
      return("SellStop");      
    case OP_SELLLIMIT:
      return("SellLimit");            
  }
}

int mults [10000][2];
int index = 0;
int getOrderMult( int ticket ) {
   
   for( int i = 0; i < index; i++  ) {
      if( mults[i][0] == ticket ) {
//         Print("found ticket: ", ticket);
         return( mults[i][1] );
      }
   }
   
//   Print("not found ticket: ", ticket);
   mults[index][0] = ticket;
   mults[index][1] = 1;
   index++;
      
   return(1);
}

void setOrderMult( int ticket, int value ) {
   for( int i = 0; i < index; i++  ) {
      if( mults[i][0] == ticket ) {
         mults[i][1] = value;
         break;
      }
   }
   
}

bool doBreakeven() {
   double sl = 0;
   double bid, ask, point, digits;
   
   bid = MarketInfo( OrderSymbol(), MODE_BID );
   ask = MarketInfo( OrderSymbol(), MODE_ASK );
   point = MarketInfo( OrderSymbol(), MODE_POINT );
   
   if( OrderType() == OP_BUY ) {
      if( bid - OrderOpenPrice() >= AutoBreakProfit*point ) {
         sl = OrderOpenPrice() + AutoBreakEvenPoints*point;
      }
   } else {
      if( OrderOpenPrice() - ask >= AutoBreakProfit*point ) {
         sl = OrderOpenPrice() - AutoBreakEvenPoints*point;
      }   
   }
   
   if( OrderType() == OP_BUY && sl <= OrderStopLoss() ) {
      return(true);
   }
   
   if( OrderType() == OP_SELL && sl >= OrderStopLoss() ) {
      return(true);
   }
   if( 0 != sl ) {
      return( XOrderModify( OrderTicket(), OrderOpenPrice(), sl, OrderTakeProfit(), OrderExpiration() ) );
   }   
}

void doTrailStop() {
   double bid, ask, point, digits, sl, sl1;
   int m;
   
   bid = MarketInfo( OrderSymbol(), MODE_BID );
   ask = MarketInfo( OrderSymbol(), MODE_ASK );
   point = MarketInfo( OrderSymbol(), MODE_POINT );
   digits =  MarketInfo(OrderSymbol(),MODE_DIGITS);
   m = getOrderMult( OrderTicket() );
   
   if(digits == 3 || digits ==5) {
    point = point*10;
   }
      
  // Print( "m: ", m );      
   if( OrderType() == OP_BUY ) {
      
      if( bid - OrderOpenPrice() >= TrailStopPips*point*m ) {
      
         sl = OrderStopLoss() + TrailStopPips*point;
         
         if( XOrderModify( OrderTicket(), OrderOpenPrice(), sl, OrderTakeProfit(), OrderExpiration()) ) {
            m++;
            setOrderMult( OrderTicket(), m );            
         }
      }
   } else { 
      if( OrderOpenPrice() - ask >= TrailStopPips*point*m ) {
         sl = OrderStopLoss() - TrailStopPips*point;
         
         if( XOrderModify( OrderTicket(), OrderOpenPrice(), sl, OrderTakeProfit(), OrderExpiration() ) ) {
            m++;
            setOrderMult( OrderTicket(), m );
         }
      }
   }
}

void doManagement() {
  bool beDone;  
  
  for( int i = 0; i < OrdersTotal(); i++ ) {
   
    if( false == OrderSelect( i, SELECT_BY_POS, MODE_TRADES ) )
      continue;

    if( OrderType() > OP_SELL )
       continue;
   
    if( AutoBreakeven )
      beDone = doBreakeven();
   
    if( TrailStop && ( false == AutoBreakeven || (AutoBreakeven && beDone ) ) )
      doTrailStop();
      
  }
}

string IntArray2String( int &arr[] ) {
   string res = "";
   int nof;

	nof = ArraySize( arr );
   for( int j = 0; j < nof; j++ )
		res = res + CharToStr( arr[ j ]      & 0x000000FF )
    				 + CharToStr( arr[ j ] >> 8 & 0x000000FF )
   				 + CharToStr( arr[ j ] >>16 & 0x000000FF )
   				 + CharToStr( arr[ j ] >>24 & 0x000000FF );

	return( res );
} // IntArray2String

double getLots( string symbol, double lot, double riskPercent ) {
   int dg;
   
   if(LotSize != 0)
      return LotSize;
   
   dg = LotPrecision();
   
   if( IsUseLotsManagement ) {  
      if(riskPercent < 0.1 || riskPercent > 100 ) { 
         Print( "Invalid Risk Value. Used default value=", lot );
         return(NormalizeDouble( lot,dg ) );
      } else {  
         return ( NormalizeDouble( MathFloor((AccountFreeMargin()*AccountLeverage()*riskPercent*XGetPoint(symbol)*100)/(MarketInfo(symbol,MODE_ASK)*MarketInfo(symbol,MODE_LOTSIZE)*MarketInfo(symbol,MODE_MINLOT)))*MarketInfo(symbol,MODE_MINLOT), dg ) );
      }
   } else {
      return(NormalizeDouble( lot,dg ) );
   }
}

int LotPrecision(){
   double lotstep = MarketInfo(Symbol(),MODE_LOTSTEP);
   if(lotstep==1)     return(0);
   if(lotstep==0.1)   return(1);
   if(lotstep==0.01)  return(2);
   if(lotstep==0.001) return(3);
}

string FormatDate( string time, string date ) {
  string h, m, d, mm, y, t;
  //StrToTime
  
  d = StringSubstr( date, 0, 2 );
  mm = StringSubstr( date, 3, 2 );
  y = StringSubstr( date, 6, 4 );
  
  return(y + "." + mm + "." + d + " " + time);
}

string __StringReplace( string haystack, string needle, string replace = "" ){
string left, right;
int start=0;
int rlen = StringLen(replace);
int nlen = StringLen(needle);

   while ( start > -1 ){

      start = StringFind( haystack, needle, start );

      if ( start > -1 ){
         
         if( start > 0 )
            left = StringSubstr(haystack, 0, start);
         else
            left="";

         right = StringSubstr(haystack, start + nlen);
         haystack = left + replace + right;
         start = start + rlen;

      } // if

   } // while
   
   return( haystack );  
} // __StringReplace

int __XEmailerInit( string pop_server, int port, int use_ssl, string login, string password ) {
   uchar __pop_server[], __login[], __password[];
 
   StringToCharArray( pop_server, __pop_server );
   StringToCharArray( login, __login );
   StringToCharArray( password, __password );
   
   
   return XEmailerInit( __pop_server, port, use_ssl, __login, __password );
} 

bool exit( string symbol, double lots = 0 ) {
  double price;

  if(lots == 0 )
    lots = OrderLots();

  RefreshRates();
  if( OrderType() == OP_BUY || OrderType() == OP_SELL ) {
    if( OrderType() == OP_BUY )
       price = NormalizeDouble( MarketInfo( symbol, MODE_BID ), MarketInfo( symbol, MODE_DIGITS ) );
    else
       price = NormalizeDouble( MarketInfo( symbol, MODE_ASK ), MarketInfo( symbol, MODE_DIGITS ) );
  
    return( XOrderClose( OrderTicket(), lots, price, Slippage ) );
  } else {
    OrderDelete( OrderTicket() );
    return(true);
  }

}