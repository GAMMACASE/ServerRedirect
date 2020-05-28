#include "sourcemod"
#include "sdktools"
#include "dhooks"
#include "regex"

#undef REQUIRE_EXTENSIONS
#include "socket"
#define REQUIRE_EXTENSIONS

#include "glib/memutils"
#include "glib/commandutils"

#define OVERRIDE_DEFAULT
#include "glib/colorutils"
#include "glib/convarutils"
#undef OVERRIDE_DEFAULT

#define SNAME "[Server Redirect] "
#define SERVER_REDIRECT_CFG "configs/server_redirect.cfg"

#include "server_redirect/net.sp"
#include "server_redirect/redirect.sp"

public Plugin myinfo = 
{
	name = "Server redirect",
	author = "GAMMA CASE",
	description = "Allows to connect to other servers.",
	version = "1.2.0",
	url = "https://steamcommunity.com/id/_GAMMACASE_/"
};

enum struct ServerEntry
{
	char ip[32];
	ArrayList players;
	Menu menu;
	Handle socket;
	char display_name[128];
	char map[PLATFORM_MAX_PATH];
	int maxplayers;
	int curr_players_info;
	int curr_players;
	bool password_protected;
	int challenge;
	
	void Delete()
	{
		delete this.players;
		delete this.menu;
		delete this.socket;
	}
	
	void Clear()
	{
		//display_name skipped intentionally
		this.map[0] = '\0';
		this.maxplayers = 0;
		this.curr_players = 0;
		this.password_protected = false;
		this.challenge = 0;
	}
	
	char CutIp()
	{
		char _ip[32];
		strcopy(_ip, sizeof(_ip), this.ip);
		_ip[FindCharInString(_ip, ':', true)] = '\0';
		return _ip;
	}
	
	int CutPort()
	{
		return StringToInt(this.ip[FindCharInString(this.ip, ':', true) + 1]);
	}
}

enum struct PlayerData
{
	char name[MAX_NAME_LENGTH];
	float time;
}

enum struct SocketData
{
	char ip[32];
	int num_of_recv;
	bool got_answer;
	bool got_player_data;
	int challenge_retries;
	Handle timeout;
}

methodmap ServerList < ArrayList
{
	public ServerList()
	{
		return view_as<ServerList>(new ArrayList(sizeof(ServerEntry)));
	}
	
	public void DeleteServers()
	{
		ServerEntry se;
		for(int i = 0; i < this.Length; i++)
		{
			this.GetArray(i, se);
			se.Delete();
		}
	}
	
	public int GetServer(const char[] ip, ServerEntry se)
	{
		int idx = this.FindString(ip);
		
		if(idx == -1)
			ThrowError(SNAME..."Unknown server ip (%s) is found in ServerList.", ip);
		else
			this.GetArray(idx, se);
		
		return idx;
	}
	
	public int GetServerByMenu(Menu menu, ServerEntry se)
	{
		for(int i = 0; i < this.Length; i++)
		{
			this.GetArray(i, se);
			if(menu == se.menu)
				return i;
		}
		
		return -1;
	}
}

ConVar gServerCommands,
	gSocketTimeoutTime,
	gShowPlayerInfo,
	gLogIfServerIsUnavailable,
	gDisableConnect,
	gCommandSpamTimeout,
	gAdvertisementTime,
	gAdvertisementMinPlayers,
	gAdvertisementOrder,
	gAdvertiseThis,
	gRemoveThis,
	gShowConfirmationMenu,
	gAnnounceLeave;

Menu gServersMenu,
	gActiveMenu[MAXPLAYERS];

int gMenuLastPos[MAXPLAYERS],
	gMenuServersLastItem[MAXPLAYERS];

ServerList gServers;
ArrayList gUpdateQueue,
	gAdvertisementList;

Handle gAdvertisementTimer;

char gThisServerIp[32];
bool gSocketAvaliable;
float gServersCooldown[MAXPLAYERS];

public void OnPluginStart()
{
	gServerCommands = CreateConVar("server_redirect_commands", "sm_servers;sm_serv;sm_project;sm_list;", "Commands that invoke servers redirect menu.\n(Note: Map change required for changes to take effect! There's also a 128 character limit per command.)");
	gSocketTimeoutTime = CreateConVar("server_redirect_socket_timeout", "10.0", "Socket timeout time.\n(Note: Unused if you don't use socket extension)", .hasMin = true, .min = 2.0);
	gShowPlayerInfo = CreateConVar("server_redirect_show_player_info", "1", "Show players info when you select server in servers redirect menu.\n(Note: Unused if you don't use socket extension)", .hasMin = true, .hasMax = true, .max = 1.0);
	gLogIfServerIsUnavailable = CreateConVar("server_redirect_log_if_server_is_unavailable", "0", "If communication with other servers is timed out, should this be logged?\n(Note: Unused if you don't use socket extension)", .hasMin = true, .hasMax = true, .max = 1.0);
	gDisableConnect = CreateConVar("server_redirect_disable_connect_button", "3", "Server connect button state:\n(Note: Unused if you don't use socket extension)\n0 - Always enabled;\n1 - Disabled if server is password protected, enabled otherwise;\n2 - Disabled if server is unavailable, enabled otherwise;\n3 - Enabled only if server is not password protected and avaliable.", .hasMin = true, .hasMax = true, .max = 3.0);
	gCommandSpamTimeout = CreateConVar("server_redirect_command_spam_timeout", "1.0", "Will prevent execution of a command if previous execution was less then this seconds before.", .hasMin = true);
	gAdvertisementTime = CreateConVar("server_redirect_advertisement_time", "60.0", "Server advertisement time in seconds (Map change required for this to take effect).\n(Note: set to 0 to disable)\n(Note2: this value should be bigger than server_redirect_socket_timeout by one second or more (Only if you have socket extension installed))", .hasMin = true);
	gAdvertisementMinPlayers = CreateConVar("server_redirect_advertisement_min_players", "0", "Minimum players required to advertise server in chat.\n(Note: Unused if you don't use socket extension)", .hasMin = true);
	gAdvertisementOrder = CreateConVar("server_redirect_advertisement_order", "0", "Order at which servers gonna be advertised.\n0 - Order at which servers are defined in config file;\n1 - Random order.", .hasMin = true, .hasMax = true, .max = 1.0);
	gAdvertiseThis = CreateConVar("server_redirect_advertise_this", "0", "If set, this current server will also be advertised in chat.\n(Note: Unused if server_redirect_remove_this set to 1!)", .hasMin = true, .hasMax = true, .max = 1.0);
	gRemoveThis = CreateConVar("server_redirect_remove_this", "0", "If set, this current server will be removed from servers menu.", .hasMin = true, .hasMax = true, .max = 1.0);
	gShowConfirmationMenu = CreateConVar("server_redirect_show_confirmation_menu", "0", "If set, will show confirmation menu when players will try to connect to some server via servers menu.", .hasMin = true, .hasMax = true, .max = 1.0);
	gAnnounceLeave = CreateConVar("server_redirect_show_advertisement_leave", "0", "If set, will show message to alert players a player has connected to another server.", .hasMin = true, .hasMax = true, .max = 1.0);
	AutoExecConfig();
	
	LoadTranslations("server_redirect.phrases");
	
	RegAdminCmd("sm_refresh_servers", SM_RefreshServers, ADMFLAG_ROOT, "Reloads server_redirect.cfg file.");
	
	int hostip = FindConVar("hostip").IntValue;
	Format(gThisServerIp, sizeof(gThisServerIp), "%i.%i.%i.%i:%i", hostip >>> 24, hostip >> 16 & 0xFF, hostip >> 8 & 0xFF, hostip & 0xFF, FindConVar("hostport").IntValue);
	
	gUpdateQueue = new ArrayList();
	gShouldReconnect = new StringMap();
	gServers = new ServerList();
	
	GameData gd = new GameData("server_redirect.games");
	ASSERT_MSG(gd, "Can't open \"server_redirect.games.txt\" gamedata file.");
	
	InitNet(gd);
	SetupSDKCalls(gd);
	SetupDhooks(gd);
	
	delete gd;
}

public void OnAllPluginsLoaded()
{
	gSocketAvaliable = GetExtensionFileStatus("socket.ext") == 1;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("RedirectClient", RedirectClient_Native);
	RegPluginLibrary("server_redirect");
}

public void OnClientDisconnect(int client)
{
	gActiveMenu[client] = null;
	gMenuLastPos[client] = 0;
	gMenuServersLastItem[client] = 0;
	gServersCooldown[client] = 0.0;
	int idx = gUpdateQueue.FindValue(GetClientUserId(client));
	if(idx != -1)
		gUpdateQueue.Erase(idx);
}

public void OnConfigsExecuted()
{
	char buff[1024];
	gServerCommands.GetString(buff, sizeof(buff));
	RegConsoleCmds(buff, SM_Servers, "Displays servers list.");
	
	BuildPath(Path_SM, buff, sizeof(buff), SERVER_REDIRECT_CFG);
	
	gServers.DeleteServers();
	gServers.Clear();
	if(gServersMenu)
		gServersMenu.RemoveAllItems();
	else
		gServersMenu = new Menu(Servers_Menu, MENU_ACTIONS_DEFAULT | MenuAction_DisplayItem | MenuAction_Display);
	
	if(!FileExists(buff))
	{
		gServersMenu.AddItem("no_servers", "", ITEMDRAW_DISABLED);
		return;
	}
	
	KeyValues kv = new KeyValues("Servers");
	kv.ImportFromFile(buff);
	
	if(!kv.GotoFirstSubKey())
	{
		gServersMenu.AddItem("no_servers", "", ITEMDRAW_DISABLED);
		delete kv;
		return;
	}
	
	ServerEntry se;
	Regex re = new Regex("\\b[\\d{1,3}\\.]+\\:\\d{1,5}\\b");
	
	do
	{
		kv.GetSectionName(buff, sizeof(buff));
		
		kv.GetString("ip", se.ip, sizeof(ServerEntry::ip));
		if(se.ip[0] == '\0')
		{
			LogError(SNAME..."Failed to get ip for section \"%s\" skipping.", buff);
			continue;
		}
		
		if(re.Match(se.ip) <= 0)
		{
			LogError(SNAME..."Found invalid ip address in section \"%s\" skipping.", buff);
			continue;
		}
		
		if(gRemoveThis.BoolValue && StrEqual(gThisServerIp, se.ip))
			continue;
		
		if(gServers.FindString(se.ip) != -1)
		{
			LogError(SNAME..."Found duplicate ip address in section \"%s\" skipping.", buff);
			continue;
		}
		
		kv.GetString("display_name", se.display_name, sizeof(ServerEntry::display_name));
		
		gServersMenu.AddItem(se.ip, se.display_name);
		
		se.menu = BuildServerInfoMenu();
		
		gServers.PushArray(se);
		
	} while(kv.GotoNextKey());
	
	delete re;
	delete kv;
	
	if(gSocketAvaliable)
		UpdateServersData();
	
	if(gServersMenu.ItemCount == 0)
		gServersMenu.AddItem("no_servers", "", ITEMDRAW_DISABLED);
	else if(gAdvertisementTime.FloatValue != 0.0)
	{
		if(gSocketAvaliable)
		{
			if(gAdvertisementTime.FloatValue - gSocketTimeoutTime.FloatValue - 1.0 <= 0.0)
				LogError(SNAME..."server_redirect_advertisement_time cvar should be bigger than server_redirect_socket_timeout by one second or more, advertisements are disabled!")
			else
			{
				gAdvertisementList = new ArrayList();
				gAdvertisementTimer = CreateTimer(gAdvertisementTime.FloatValue - gSocketTimeoutTime.FloatValue - 1.0, Advertisement_Timer, .flags = TIMER_FLAG_NO_MAPCHANGE);
			}
		}
		else
		{
			gAdvertisementList = new ArrayList();
			gAdvertisementTimer = CreateTimer(gAdvertisementTime.FloatValue, Advertisement_NoSocket_Timer, .flags = TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
		}
	}
	else
		delete gAdvertisementList;
}

Menu BuildServerInfoMenu()
{
	Menu menu = new Menu(ServerInfo_Menu, MENU_ACTIONS_DEFAULT | MenuAction_DisplayItem | MenuAction_DrawItem | MenuAction_Display);
	
	menu.AddItem("connect", "");
	menu.AddItem("print_info", "");
	
	menu.ExitBackButton = true;
	
	return menu;
}

void UpdateServersData()
{
	ServerEntry se;
	SocketData sd;
	ArrayList data;
	for(int i = 0; i < gServers.Length; i++)
	{
		gServers.GetArray(i, se);
		
		if(se.socket)
			continue;
		
		data = new ArrayList(sizeof(SocketData));
		
		sd.ip = se.ip;
		sd.num_of_recv = 1;
		sd.timeout = CreateTimer(gSocketTimeoutTime.FloatValue, Socket_Timeout_Timer, data);
		data.PushArray(sd);
		
		se.socket = SocketCreate(SOCKET_UDP, SocketCreate_Error);
		
		SocketSetArg(se.socket, data);
		SocketConnect(se.socket, Socket_Connected, Socket_Recieved, Socket_Disconnect, se.CutIp(), se.CutPort());
		
		gServers.SetArray(i, se);
	}
}

public Action Advertisement_NoSocket_Timer(Handle timer)
{
	if(gAdvertisementList.Length == 0)
		FillServersToAdvert();
	
	ServerEntry se;
	GetServerToAdvert(se);
	AdvertiseServer(se);
}

public Action Advertisement_Timer(Handle timer)
{
	if(gAdvertisementList.Length == 0)
		FillServersToAdvert();
	
	UpdateServersData();
	gAdvertisementTimer = CreateTimer(gSocketTimeoutTime.FloatValue + 1.0, Advertisement2_Timer, .flags = TIMER_FLAG_NO_MAPCHANGE);
}

public Action Advertisement2_Timer(Handle timer)
{
	ServerEntry se;
	if(!GetServerToAdvert(se))
	{
		FillServersToAdvert();
		if(GetServerToAdvert(se))
			 AdvertiseServer(se);
	}
	else
		AdvertiseServer(se);
	
	gAdvertisementTimer = CreateTimer(gAdvertisementTime.FloatValue - gSocketTimeoutTime.FloatValue - 1.0, Advertisement_Timer, .flags = TIMER_FLAG_NO_MAPCHANGE);
}

void FillServersToAdvert()
{
	gAdvertisementList.Clear();
	
	for(int i = 0; i < gServers.Length; i++)
		gAdvertisementList.Push(i);
}

bool GetServerToAdvert(ServerEntry se)
{
	switch(gAdvertisementOrder.IntValue)
	{
		case 0:
		{
			while(gAdvertisementList.Length != 0)
			{
				if(!FilterServerToAdvert(se))
					continue;
				
				return true;
			}
		}
		
		case 1:
		{
			int idx;
			while(gAdvertisementList.Length != 0)
			{
				idx = GetRandomInt(0, gAdvertisementList.Length - 1);
				if(!FilterServerToAdvert(se, idx))
					continue;
				
				return true;
			}
		}
	}
	
	return false;
}

bool FilterServerToAdvert(ServerEntry se, int idx = 0)
{
	gServers.GetArray(gAdvertisementList.Get(idx), se);
	if(gSocketAvaliable && (se.maxplayers == 0 
				|| (se.curr_players < gAdvertisementMinPlayers.IntValue && se.curr_players_info < gAdvertisementMinPlayers.IntValue)
				|| (!gAdvertiseThis.BoolValue && StrEqual(gThisServerIp, se.ip))))
	{
		gAdvertisementList.Erase(idx);
		return false;
	}
	
	gAdvertisementList.Erase(idx);
	return true;
}

void AdvertiseServer(ServerEntry se)
{
	char buff[32];
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i))
			continue;
		
		if(gSocketAvaliable)
		{
			Format(buff, sizeof(buff), "%T", "servers_menu_server_entry_slots_count", i, (se.curr_players == 0 ? se.curr_players_info : se.curr_players), se.maxplayers);
			PrintToChatColored(i, "%t", "server_advertisement_server_name", se.display_name);
			PrintToChatColored(i, "%t", "server_advertisement_server_stats", buff, se.ip);
		}
		else
		{
			PrintToChatColored(i, "%t", "server_advertisement_no_socket_server_name", se.display_name);
			PrintToChatColored(i, "%t", "server_advertisement_no_socket_server_stats", se.ip);
		}
	}
}

public Action Socket_Timeout_Timer(Handle timer, ArrayList data)
{
	SocketData sd;
	data.GetArray(0, sd);
	
	if(!sd.got_answer && gLogIfServerIsUnavailable.BoolValue)
		LogMessage(SNAME..."Can't get response from \"%s\", socket timed out.", sd.ip);
	
	ServerEntry se;
	int idx = gServers.GetServer(sd.ip, se);
	if(idx != -1)
	{
		if(!sd.got_answer)
			se.Clear();
		
		if(!sd.got_player_data)
			if(se.players)
				delete se.players;
		
		delete se.socket;
		gServers.SetArray(idx, se);
	}
	
	for(int client = 0; gUpdateQueue.Length != 0;)
	{
		client = GetClientOfUserId(gUpdateQueue.Get(0));
		if(client != 0 && gActiveMenu[client])
			gActiveMenu[client].DisplayAt(client, gMenuLastPos[client], MENU_TIME_FOREVER);
		gUpdateQueue.Erase(0);
	}
	
	delete data;
}

public Action SM_RefreshServers(int client, int args)
{
	if(gAdvertisementTimer)
		delete gAdvertisementTimer;
	OnConfigsExecuted();
	ReplyToCommand(client, SNAME..."Servers list was updated.");
	
	return Plugin_Handled;
}

public Action SM_Servers(int client, int args)
{
	if(!IsValidCmd())
		return Plugin_Continue;
	
	if(client == 0)
		return Plugin_Handled;
	
	if(IsSpamming(gServersCooldown[client], gCommandSpamTimeout.FloatValue))
	{
		ReplyToCommand(client, "%T", "command_spam_attempt", client);
		return Plugin_Handled;
	}
	
	if(gSocketAvaliable)
	{
		gUpdateQueue.Push(GetClientUserId(client));
		UpdateServersData();
	}
	
	gServersMenu.Display(client, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int Servers_Menu(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Display:
		{
			menu.SetTitle("%T\n ", "servers_menu_title", param1);
			gActiveMenu[param1] = menu;
			if(gUpdateQueue.FindValue(GetClientUserId(param1)) == -1)
				gUpdateQueue.Push(GetClientUserId(param1));
		}
		
		case MenuAction_DisplayItem:
		{
			if(param2 >= gMenuLastPos[param1] + 6 || param2 <= gMenuLastPos[param1] - 6)
				gMenuLastPos[param1] = param2;
			
			char buff[128];
			menu.GetItem(param2, buff, sizeof(buff));
			
			if(StrEqual(buff, "no_servers"))
			{
				Format(buff, sizeof(buff), "%T", "servers_menu_no_servers", param1);
				return RedrawMenuItem(buff);
			}
			
			ServerEntry se;
			if(gServers.GetServer(buff, se) == -1)
				return 0;
			
			if(gSocketAvaliable)
			{
				if(se.maxplayers == 0)
					Format(buff, sizeof(buff), "%T", "servers_menu_server_entry_not_available", param1);
				else
					Format(buff, sizeof(buff), "%T", "servers_menu_server_entry_slots_count", param1, (se.curr_players == 0 ? se.curr_players_info : se.curr_players), se.maxplayers);
				Format(buff, sizeof(buff), "%T", "servers_menu_server_entry", param1, buff, se.display_name);
			}
			else
				Format(buff, sizeof(buff), "%T", "servers_menu_server_entry_no_socket", param1, se.display_name);
			
			return RedrawMenuItem(buff);
		}
		
		case MenuAction_Select:
		{
			char buff[32];
			menu.GetItem(param2, buff, sizeof(buff));
			gMenuServersLastItem[param1] = menu.Selection;
			ShowServerInfoMenu(param1, buff);
		}
		
		case MenuAction_Cancel:
		{
			gActiveMenu[param1] = null;
			gMenuLastPos[param1] = 0;
			
			int idx = gUpdateQueue.FindValue(GetClientUserId(param1));
			if(idx != -1)
				gUpdateQueue.Erase(idx);
		}
	}
	
	return 0;
}

void ShowServerInfoMenu(int client, const char[] ip)
{
	ServerEntry se;
	if(gServers.GetServer(ip, se) != -1)
		se.menu.Display(client, MENU_TIME_FOREVER);
}

public int ServerInfo_Menu(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_DrawItem:
		{
			ServerEntry se;
			gServers.GetServerByMenu(menu, se);
			
			char buff[32];
			int style;
			menu.GetItem(param2, buff, sizeof(buff), style);
			
			if(StrEqual(buff, "connect"))
			{
				if(!gSocketAvaliable)
					return ITEMDRAW_DEFAULT;
				
				if(StrEqual(gThisServerIp, se.ip))
					return ITEMDRAW_DISABLED;
				
				switch(gDisableConnect.IntValue)
				{
					case 0:
						return ITEMDRAW_DEFAULT;
					
					case 1:
						if(se.password_protected)
							return ITEMDRAW_DISABLED;
					
					case 2:
						if(se.maxplayers == 0)
							return ITEMDRAW_DISABLED;
					
					case 3:
						if(se.maxplayers == 0 || se.password_protected)
							return ITEMDRAW_DISABLED;
				}
			}
			else if(!StrEqual(buff, "print_info"))
			{
				if(!se.players || StringToInt(buff) >= se.players.Length || se.maxplayers == 0 || !gShowPlayerInfo.BoolValue || !gSocketAvaliable)
					return ITEMDRAW_IGNORE;
				else
					return ITEMDRAW_DISABLED;
			}
			
			return style;
		}
		
		case MenuAction_Display:
		{
			ServerEntry se;
			gServers.GetServerByMenu(menu, se);
			
			if(se.map[0] == '\0')
				Format(se.map, sizeof(ServerEntry::map), "%T", "servinfo_menu_map_not_available", param1);
			
			if(!gSocketAvaliable)
				menu.SetTitle("%T\n ", "servinfo_menu_title_no_socket", param1, se.display_name, se.ip);
			else if(gShowPlayerInfo.BoolValue)
				menu.SetTitle("%T\n ", "servinfo_menu_title", param1, se.display_name, se.ip, se.map);
			else
			{
				char buff[32];
				if(se.maxplayers != 0)
					Format(buff, sizeof(buff), "%T", "servers_menu_server_entry_slots_count", param1, (se.curr_players == 0 ? se.curr_players_info : se.curr_players), se.maxplayers);
				else
					Format(buff, sizeof(buff), "%T", "servers_menu_server_entry_not_available", param1);
				menu.SetTitle("%T\n ", "servinfo_menu_title_no_player_info", param1, se.display_name, se.ip, se.map, buff);
			}
			
			gActiveMenu[param1] = menu;
			if(gUpdateQueue.FindValue(GetClientUserId(param1)) == -1)
				gUpdateQueue.Push(GetClientUserId(param1));
		}
		
		case MenuAction_DisplayItem:
		{
			if(param2 >= gMenuLastPos[param1] + 6 || param2 <= gMenuLastPos[param1] - 6)
				gMenuLastPos[param1] = param2;
			
			char buff[256];
			menu.GetItem(param2, buff, sizeof(buff));
			
			ServerEntry se;
			gServers.GetServerByMenu(menu, se);
			
			if(StrEqual(buff, "connect"))
			{
				buff[0] = '\0';
				
				if(StrEqual(gThisServerIp, se.ip))
					Format(buff, sizeof(buff), "%T", "servinfo_menu_connect_current", param1);
				else if(gSocketAvaliable)
				{
					switch(gDisableConnect.IntValue)
					{
						case 1:
							if(se.password_protected)
								Format(buff, sizeof(buff), "%T", "servinfo_menu_connect_password_protected", param1);
						
						case 2:
							if(se.maxplayers == 0)
								Format(buff, sizeof(buff), "%T", "servinfo_menu_connect_unavailable", param1);
						
						case 3:
						{
							if(se.maxplayers == 0)
								Format(buff, sizeof(buff), "%T", "servinfo_menu_connect_unavailable", param1);
							else if(se.password_protected)
								Format(buff, sizeof(buff), "%T", "servinfo_menu_connect_password_protected", param1);
						}
					}
				}
				
				Format(buff, sizeof(buff), "%T %s", "servinfo_menu_connect", param1, buff);
			}
			else if(StrEqual(buff, "print_info"))
			{
				if(gShowPlayerInfo.BoolValue && gSocketAvaliable)
				{
					if(se.maxplayers != 0)
						Format(buff, sizeof(buff), "%T", "servers_menu_server_entry_slots_count", param1, (se.curr_players == 0 ? se.curr_players_info : se.curr_players), se.maxplayers);
					else
						Format(buff, sizeof(buff), "%T", "servers_menu_server_entry_not_available", param1);
					Format(buff, sizeof(buff), "%T\n \n%T", "servinfo_menu_print", param1, "servinfo_menu_players", param1, buff);
					
					if(se.curr_players == 0 && se.curr_players_info == 0 && se.maxplayers != 0)
						Format(buff, sizeof(buff), "%s\n%T", buff, "servinfo_menu_players_no_players", param1);
					else if(!se.players || menu.ItemCount == 2 || se.maxplayers == 0)
						Format(buff, sizeof(buff), "%s\n%T", buff, "servinfo_menu_players_data_unavailable", param1);
				}
				else
					Format(buff, sizeof(buff), "%T", "servinfo_menu_print", param1);
			}
			else if(gSocketAvaliable && gShowPlayerInfo.BoolValue && se.players)
			{
				int idx = StringToInt(buff);
				
				if(idx >= se.players.Length)
					return 0;
				
				PlayerData pd;
				se.players.GetArray(idx, pd);
				
				FormatTimeCustom(pd.time, buff, sizeof(buff));
				Format(buff, sizeof(buff), "%T", "servinfo_menu_player_entry", param1, idx + 1, pd.name, buff);
			}
			
			return RedrawMenuItem(buff);
		}
		
		case MenuAction_Select:
		{
			char buff[256];
			menu.GetItem(param2, buff, sizeof(buff));
			
			ServerEntry se;
			gServers.GetServerByMenu(menu, se);
			
			if(StrEqual(buff, "connect"))
				if(gShowConfirmationMenu.BoolValue)
				{
					int idx = gUpdateQueue.FindValue(GetClientUserId(param1));
					if(idx != -1)
						gUpdateQueue.Erase(idx);
					
					Menu cmenu = new Menu(Confirmation_Menu);
					
					cmenu.SetTitle("%T\n ", "confirmation_menu_title", param1, se.ip);
					
					char buff2[32];
					Format(buff, sizeof(buff), "%T", "confirmation_menu_continue", param1);
					Format(buff2, sizeof(buff2), "c%s", se.ip);
					cmenu.AddItem(buff2, buff);
					
					Format(buff, sizeof(buff), "%T", "confirmation_menu_notnow", param1);
					Format(buff2, sizeof(buff2), "b%s", se.ip);
					cmenu.AddItem(buff2, buff);
					
					cmenu.Display(param1, MENU_TIME_FOREVER);
				}
				else
				{
					if(gAnnounceLeave.BoolValue)
					{
						for(int i = 1; i <= MaxClients; i++)
						{
							if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i))
								continue;
							
							PrintToChatColored(i, "%t", "server_advertisement_leave", param1, se.ip);
						}
					}
					
					RedirectClient(param1, se.ip);
				}
			else if(StrEqual(buff, "print_info"))
			{
				menu.Display(param1, MENU_TIME_FOREVER);
				PrintToConsole(param1, "%T", "server_info", param1, se.display_name, se.ip);
			}
		}
		
		case MenuAction_Cancel:
		{
			gActiveMenu[param1] = null;
			gMenuLastPos[param1] = 0;
			
			if(!IsClientConnected(param1))
				return 0;
			
			if(param2 == MenuCancel_ExitBack)
				gServersMenu.DisplayAt(param1, gMenuServersLastItem[param1], MENU_TIME_FOREVER);
			
			int idx = gUpdateQueue.FindValue(GetClientUserId(param1));
			if(idx != -1)
				gUpdateQueue.Erase(idx);
		}
	}
	
	return 0;
}

public int Confirmation_Menu(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char buff[32];
			menu.GetItem(param2, buff, sizeof(buff));
			
			if(buff[0] == 'c')
			{
				if(gAnnounceLeave.BoolValue)
				{
					for(int i = 1; i <= MaxClients; i++)
					{
						if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i))
							continue;
						
						PrintToChatColored(i, "%t", "server_advertisement_leave", param1, buff[1]);
					}
				}

				RedirectClient(param1, buff[1]);
			}
			else
				ShowServerInfoMenu(param1, buff[1]);
		}
		
		case MenuAction_End:
			delete menu;
	}
	
	return 0;
}

public int SortPlayerInfo(int index1, int index2, Handle array, Handle hndl)
{
	ArrayList al = view_as<ArrayList>(array);
	PlayerData pd;
	
	al.GetArray(index1, pd);
	float time1 = pd.time;
	al.GetArray(index2, pd);
	
	if(time1 < pd.time)
		return 1;
	else if(time1 == pd.time)
		return 0;
	else
		return -1;
}

public void Socket_Connected(Socket socket, ArrayList data)
{
	SocketSend(socket, "\xFF\xFF\xFF\xFF\x54Source Engine Query", 25);
	
	if(data && gShowPlayerInfo.BoolValue)
	{
		SocketData sd;
		data.GetArray(0, sd);
		
		ServerEntry se;
		int idx = gServers.GetServer(sd.ip, se);
		if(idx != -1)
		{
			if(se.challenge == 0)
			{
				sd.num_of_recv++;
				SocketSend(socket, "\xFF\xFF\xFF\xFF\x55\xFF\xFF\xFF\xFF", 9);
			}
			else
			{
				char buff[32];
				sd.num_of_recv++;
				Format(buff, sizeof(buff), "\xFF\xFF\xFF\xFF\x55%s", se.challenge);
				SocketSend(socket, buff, 9);
			}
			
			data.SetArray(0, sd);
		}
	}
}

public void Socket_Recieved(Socket socket, const char[] data, const int dataSize, ArrayList sock_data)
{
	SocketData sd;
	sock_data.GetArray(0, sd);
	
	if(data[0] != 0xFF || data[1] != 0xFF || data[2] != 0xFF || data[3] != 0xFF)
	{
		LogError(SNAME..."Received invalid packet for server \"%s\".", sd.ip);
		return;
	}
	
	ServerEntry se;
	int offs = 5, idx = gServers.GetServer(sd.ip, se);
	if(idx == -1)
		return;
	
	switch(data[4])
	{
		case 0x49:
		{
			sd.got_answer = true;
			
			offs++;
			offs += ByteStream_ReadString(data[offs], se.display_name, sizeof(ServerEntry::display_name));
			offs += ByteStream_ReadString(data[offs], se.map, sizeof(ServerEntry::map));
			
			offs += ByteStream_ReadUntilNull(data[offs]);
			offs += ByteStream_ReadUntilNull(data[offs]) + 2;
			
			se.curr_players_info = data[offs++];
			se.maxplayers = data[offs];
			offs += 4;
			se.password_protected = !!data[offs];
		}
		
		case 0x41:
		{
			if(++sd.challenge_retries > 3)
				ThrowError(SNAME..."Something went wrong with receiving challenge token for server %s! Preventing infinite loop....", se.ip);
			
			ByteStream_Read32(data[offs], se.challenge);
			sd.num_of_recv++;
			
			char buff[32];
			Format(buff, sizeof(buff), "\xFF\xFF\xFF\xFF\x55%c%c%c%c", se.challenge & 0xFF, se.challenge >> 8 & 0xFF, se.challenge >> 16 & 0xFF, se.challenge >>> 24);
			SocketSend(socket, buff, 9);
		}
		
		case 0x44:
		{
			sd.challenge_retries = 0;
			sd.got_player_data = true;
			
			se.curr_players = data[offs++];
			if(se.curr_players > 0)
			{
				if(se.players)
					se.players.Clear();
				else
					se.players = new ArrayList(sizeof(PlayerData));
				
				PlayerData pd;
				char buff[32];
				for(;offs < dataSize;)
				{
					offs++;
					offs += ByteStream_ReadString(data[offs], pd.name, sizeof(PlayerData::name));
					
					if(pd.name[0] == '\0')
						strcopy(pd.name, sizeof(PlayerData::name), "???");
					
					offs += 4;
					offs += ByteStream_Read32(data[offs], pd.time);
					se.players.PushArray(pd);
				}
				
				SortADTArrayCustom(se.players, SortPlayerInfo);
				for(int i = se.menu.ItemCount; i < se.players.Length + 2; i++)
				{
					IntToString(i - 2, buff, sizeof(buff));
					se.menu.AddItem(buff, "", ITEMDRAW_DISABLED);
				}
			}
		}
		
		default:
		{
			char c = data[4];
			LogError(SNAME..."Unknown response type (%02X) was received (%s).", c, sd.ip);
		}
	}
	
	sd.num_of_recv--;
	
	if(sd.num_of_recv == 0)
	{
		delete se.socket;
		delete sd.timeout;
		delete sock_data;
	}
	else
		sock_data.SetArray(0, sd);
	
	gServers.SetArray(idx, se);
	
	for(int client = 0; gUpdateQueue.Length != 0;)
	{
		client = GetClientOfUserId(gUpdateQueue.Get(0));
		if(client != 0 && gActiveMenu[client] && (data[4] == 0x49 || sd.num_of_recv == 0))
			gActiveMenu[client].DisplayAt(client, gMenuLastPos[client], MENU_TIME_FOREVER);
		gUpdateQueue.Erase(0);
	}
}

public void Socket_Disconnect(Socket socket, any arg) { }

public void SocketCreate_Error(Socket socket, const int errorType, const int errorNum, ArrayList data)
{
	//I guess this can be empty as timeout timer handles this pretty well.
}

stock bool IsSpamming(float &time_of_use, float wait_time = 5.0)
{
	if(time_of_use + wait_time > GetGameTime())
		return true;
	else
	{
		time_of_use = GetGameTime();
		return false;
	}
}

stock int ByteStream_Read32(const char[] data, any &buff)
{
	buff = view_as<any>(data[0] | data[1] << 8 | data[2] << 16 | data[3] << 24);
	return 4;
}

stock int ByteStream_ReadString(const char[] data, char[] buff, int size, bool full = true)
{
	int i;
	while(data[i] && i < size)
		buff[i] = data[i++];
	buff[i] = '\0';
	if(full)
		while(data[i++]) {}
	return i;
}

stock int ByteStream_ReadUntilNull(const char[] data)
{
	int i;
	while(data[i++]) {}
	return i;
}

stock void FormatTimeCustom(float time, char[] buff, int size)
{
	int hours = RoundToFloor(time / 3600.0);
	time -= float(hours * 3600);
	int minutes = RoundToFloor(time / 60.0);
	time -= float(minutes * 60);
	
	if(hours > 0)
		Format(buff, size, "%d:%02d:%02.0f", hours, minutes, time);
	else
		Format(buff, size, "%d:%02.0f", minutes, time);
}
