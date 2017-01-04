#include <sourcemod>
#include <sdkhooks>
#include <colorvariables.inc>

Menu MainMenu = null;
new Handle:db = INVALID_HANDLE;
new Handle:cvar_Showmessage = INVALID_HANDLE;
new Handle:cvar_MessageDelay = INVALID_HANDLE;
new Handle:cvar_CheckBanlist = INVALID_HANDLE;
new Handle:cvar_SendClientData = INVALID_HANDLE;

public Plugin:myinfo =
{
	name = "CS:CO Watcher Anticheat",
	author = "Sovietball",
	version = "1.01",
	description = "Allows CS:CO players to report suspicious gamers for the admins to check.",
	url = "http://cowatcher.org"
};
 
public void OnPluginStart()
{
	AutoExecConfig(true, "csgo_reporter");
	RegConsoleCmd("report", PrintMenu);
	RegConsoleCmd("sm_report", PrintMenu);
	cvar_Showmessage = CreateConVar("sm_join_showprotectmessage", "1", "Enable welcomemessage");	
	cvar_MessageDelay = CreateConVar("sm_showmessage_delay", "5.0", "Seconds after join the message is shown in chat");
	cvar_CheckBanlist = CreateConVar("sm_check_banlist", "1", "Checks if joining client is a hacker, and kick him if that is the case");
	cvar_SendClientData = CreateConVar("sm_submit_overwatch", "1", "Sends the steamids from the players on your server to the database. Allows Overwatchers to join.");		
	
	new Handle:kv = CreateKeyValues("sql");
	KvSetString(kv, "driver", "mysql");
	KvSetString(kv, "host", "");
	KvSetString(kv, "port", "");
	KvSetString(kv, "database", "");
	KvSetString(kv, "user", "");
	KvSetString(kv, "pass", "");	
	
	new String:error[256];
	db = SQL_ConnectCustom(kv, error, sizeof(error), true);
	CloseHandle(kv);

	LoadTranslations("cowatcher.phrases.txt");
	
	HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy); 
}

public OnClientPutInServer(client)
{
	new String:new_client_steamid[64];
	new String:query[256];
	
	GetClientAuthId(client, AuthId_SteamID64, new_client_steamid, sizeof(new_client_steamid));
	Format(query, sizeof(query), "select steamid from banlist where steamid='%s'", new_client_steamid);
	
	if(GetConVarInt(cvar_CheckBanlist) == 1)
	{
		new Handle:rquery = SQL_Query(db, query);
		if (rquery != null)
		{
			new found = SQL_GetRowCount(rquery);
			if(found)
			{
				new String:name[64];
				new String:name_format[64];
				GetClientName(client,name,sizeof(name));
				Format(name_format,sizeof(name_format),"%s",name);
				CPrintToChatAll("%T","protecktmessage", LANG_SERVER, name);
				KickClient(client, "%T", "blockmessage", client);
			}			
		}
	}
	
	if(GetConVarInt(cvar_Showmessage) == 1)
	{
		CreateTimer (GetConVarFloat(cvar_MessageDelay), MessageHandler, client);
	}
	
}

public Action:MessageHandler(Handle: timer, any:client)
{
	if (IsClientConnected(client) && IsClientInGame(client))
	{
		CPrintToChat(client, "%T", "welcome", client);
	}
}
 
public void OnMapEnd()
{
	if (MainMenu != INVALID_HANDLE)
	{
		delete(db);
		delete(MainMenu);
		MainMenu = null;
	}
}
 
Menu BuildMenu(client)
{
	Menu menu = new Menu(HandlerReport);
	
	new String:name[64];
	new String:name_format[64];
	new String:uid[12];
	new String:buffer[32];
	new min = 0;
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i) && i!=client && GetClientName(i,name,sizeof(name)))
		{	
			min = 1;
			Format(uid,sizeof(uid),"%i",i);
			Format(name_format,sizeof(name_format),"%s",name);
			menu.AddItem(uid, name_format);
		}
	}
	
	Format(buffer, sizeof(buffer), "%T", "reportmenu_title", client);

	menu.SetTitle(buffer);
 
	if(min == 0)
	{
		CPrintToChat(client, "%T", "nobody_to_report");
	}
 
	return menu;
 
}
public int HandlerReport(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		new String:selected[2];
		menu.GetItem(param2, selected, sizeof(selected));
		BustPlayer(StringToInt(selected),param1);
	}
}

public BustPlayer(uid,cid){
	new String:hacker_steamid[64];
	new String:client_steamid[64];
	new String:query[256];
	new String:name[64];
	
	if(uid != cid)
	{
		GetClientAuthId(uid, AuthId_SteamID64, hacker_steamid, sizeof(hacker_steamid));
		GetClientAuthId(cid, AuthId_SteamID64, client_steamid, sizeof(client_steamid));
		Format(query, sizeof(query), "insert into reportlist(reporter,hacker) values('%s','%s')", client_steamid, hacker_steamid);
		SQL_FastQuery(db, query);

		GetClientName(uid,name,sizeof(name));		
		CPrintToChat(cid, "%T", "report_confirmed", cid, name, hacker_steamid);
	}
}

public MysqlResult(Handle:owner, Handle:h, const String:error[], any:data)
{
	return;
}

public Action PrintMenu(int client, int args)
{
	MainMenu = BuildMenu(client);
 
	MainMenu.Display(client, MENU_TIME_FOREVER);
 
	return Plugin_Handled;
}

public OnRoundStart(Handle:event, const String:name[], bool:broadcast)
{
	if(GetConVarInt(cvar_SendClientData) == 1)
	{
		new String:ClearIp[100];
		decl String:Status[600];
		ServerCommandEx(Status, 600, "status");

		decl String:Lines[4][100];
		ExplodeString(Status, "\n", Lines, 3, 100);

		ClearIp = Lines[2]; //status line containing ip

		ExplodeString(ClearIp, ":", Lines, 5, 32);
		ClearIp = Lines[1];
		TrimString(ClearIp);

		new PORT = GetConVarInt(FindConVar("hostport"));
		new String:client_steamid[64];
		new String:query[256];
		
		for(new i=1;i<=MaxClients;i++)
		{
			if(IsClientInGame(i) && !IsFakeClient(i) && GetClientAuthId(i, AuthId_SteamID64, client_steamid, sizeof(client_steamid)))
			{		
				Format(query, sizeof(query), "insert into steamid_locations(steamid,ip,port) values('%s','%s','%i')", client_steamid, ClearIp, PORT);
				SQL_FastQuery(db, query);
			}
		}	
	}
}