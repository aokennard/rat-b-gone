#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <cURL>
#define AUTOLOAD_EXTENSIONS
#define REQUIRE_EXTENSIONS

#define min(%1,%2) (((%1) < (%2)) ? (%1) : (%2))

#include "plw_plugin_version"

int USING_LEAGUE_CACHING = 1;

// witness gaming
#define HOME_TEAM_ID 7203

#define SERVER_PRINT_PREFIX "[Player Whitelist]"

#define FAKE_PASSWORD_VAR "cl_team"
#define DEFAULT_FAKE_PW "ringer"
#define DEFAULT_PASSWORD "pugmodepw"

#define DEFAULT_CHECKER_URL "pootis.org:5000/leagueresolver"
#define RESOLVER_URL_PARAMETER_STR 

#define MAX_NUM_CLIENTS 24
#define STEAMID_LENGTH 32
#define MAX_PASSWORD_LENGTH 255

#define MAX_DIV_CHAR '8'
#define MAX_RGL_DIV_INT 8
#define RGL_DIV_ALL "1,2,3,4,5,6,7,8"

// idk how etf2l works now, lowest tier I saw was 4
#define MAX_ETF2L_DIV_CHAR '5'
#define MAX_ETF2L_DIV_INT 5
#define ETF2L_DIV_ALL "1,2,3,4,5"

#define MODE_TEAMONLY 0x0
#define MODE_SCRIM 0x1
#define MODE_MATCH 0x2
#define MODE_ALL 0x4

#define LEAGUE_RGL 0x1
#define LEAGUE_ETF2L 0x2
#define LEAGUE_ALL (LEAGUE_RGL | LEAGUE_ETF2L)

#define GAMEMODE_HL 0x1
#define GAMEMODE_6S 0x2
#define GAMEMODE_YMPS 0x4

ConVar g_useWhitelist;

// server-side logic
ConVar g_gamemode;
ConVar g_leaguesAllowed;
// optional based on leagues allowed
ConVar g_rglDivsAllowed;
ConVar g_etf2lDivsAllowed;
// allow
ConVar g_serverMode;
// optional based on server mode
ConVar g_teamID;
ConVar g_scrimID;
ConVar g_matchID;
// only include if true
ConVar g_allowBannedPlayers;

// plugin-side
ConVar g_allowChatMessages;
ConVar g_allowKickedOutput;
ConVar g_allowJoinOutput;
ConVar g_pugMode;
ConVar g_leagueResolverURL;
ConVar g_dbReconnectInterval;
ConVar g_useLeagueName; // WIP
ConVar g_ringerPassword;

char g_leagueResponseBuffer[24][1024];
char g_sourcemodPath[400];

Handle g_DBReconnectTimer;
Database sql_db;

StringMap playerNames;
//StringMap playerTeams;

char IntToETF2LDivision[MAX_ETF2L_DIV_INT + 1][] = {"banned", "Prem", "Division 1", "Division 2", "Division 3", "Division 4"};
char IntToRGLDivision[MAX_RGL_DIV_INT + 1][] = {"banned", "Invite", "Div-1", "Div-2", "Main", "Intermediate", "Amateur", "Newcomer", "Admin Placement"};
char KickMessages[7][] = {"You are not an RGL player in the currently whitelisted divisions",
						 "You are not an ETF2L player in the currently whitelisted divisions",
						 "You aren't currently in the team whitelist",
						 "You don't fit the current server's whitelist rules",
						 "You are not an RGL or ETF2L player",
						 "You are not an ETF2L player",
						 "Kicked from server"};

public Plugin:myinfo = {
	name        = "TF2 Competitive Player Whitelist",
	author      = "yosh",
	description = "Filters out non-whitelisted users based on competitive play (RGL / ETF2L)",
	version     = PLUGIN_VERSION,
	url         = "pootis.org"
};

public OnPluginStart()
{
	// because stringify macro doesnt exist here? hmmm
	char macro_int_buf[32];

	CreateConVar("plw_version", PLUGIN_VERSION, "Auto-kick whitelist");
	g_useWhitelist = CreateConVar("plw_enable", "1", "Toggles the use of the competitive filter");

	g_allowChatMessages = CreateConVar("plw_chat_output", "1", "Toggles the plugin printing to chat on join/kick");

	g_useLeagueName = CreateConVar("plw_use_league_alias", "0", "Uses official league alias for joining players");
	g_allowJoinOutput = CreateConVar("plw_join_output", "1", "Toggles in-chat join messages (spam prevention)");
	g_allowKickedOutput = CreateConVar("plw_kick_output", "0", "Toggles in-chat kick messages (prevents spamming, usually)");

	// pug mode requires a password, because people might not play in RGL. 
	g_pugMode = CreateConVar("plw_pugmode", "0", "Toggles whether or not the server is in pug-mode (plw_enable 0; sv_password <default_password>)");

	g_allowBannedPlayers = CreateConVar("plw_allow_banned", "0", "Allow banned players to play in the server");

	IntToString(GAMEMODE_6S, macro_int_buf, sizeof(macro_int_buf));
	g_gamemode = CreateConVar("plw_gamemode", macro_int_buf, "The type of gamemode to search for when doing player auth; 1 = HL, 2 = 6s");

	IntToString(LEAGUE_ALL, macro_int_buf, sizeof(macro_int_buf));
	g_leaguesAllowed = CreateConVar("plw_leagues", macro_int_buf, "The leagues to check potential joiners may be in (or operator); 1 = RGL, 2 = ETF2L");

	g_rglDivsAllowed = CreateConVar("plw_divs_rgl", RGL_DIV_ALL, "Allowed division players (comma separated): 1 = invite, 2 = div1, 3 = div2, 4 = main, 5 = intermediate, 6 = amateur, 7 = newcomer");
	
	g_etf2lDivsAllowed = CreateConVar("plw_divs_etf2l", ETF2L_DIV_ALL, "Allowed division players (comma separated): 1 = prem, 2 = div1, 3 = div2, 4 = div3, 5 = div4");

	IntToString(MODE_ALL, macro_int_buf, sizeof(macro_int_buf));
	g_serverMode = CreateConVar("plw_mode", macro_int_buf, "Determines who can join - 0 = only team, 1 = team + scrim, 2 = team + match, 3 = team + scrim + match, 4 = all");

	IntToString(HOME_TEAM_ID, macro_int_buf, sizeof(macro_int_buf));
	g_teamID = CreateConVar("plw_teamid", macro_int_buf, "ID of home team - always allowed");

	g_scrimID = CreateConVar("plw_scrimid", "0", "ID of scrim team - sometimes allowed"); 
	// I could technically scrape these off of a website but that sounds awful
	g_matchID = CreateConVar("plw_matchid", "0", "ID of match team - sometimes allowed");

	g_ringerPassword = CreateConVar("plw_fakepw", DEFAULT_FAKE_PW, "The password that ringers / specs can use to join - max length of 255");

	g_leagueResolverURL = CreateConVar("plw_leaguechecker_url", DEFAULT_CHECKER_URL, "The URL of a server which can resolve requests of 'steamid' to whether the player is valid");

	g_dbReconnectInterval = CreateConVar("plw_db_reconnect_time", "1", "The time it takes to attempt a reconnect to the SQL cache");

	if (USING_LEAGUE_CACHING) {
		SetupSQLCache();
	}

	playerNames = new StringMap();
	//playerTeams = new StringMap();

	HookEvent("server_spawn", GetGameDirHook);
	HookEvent("player_connect", ConnectSilencer, EventHookMode_Pre);
	HookEvent("player_disconnect", KickSilencer, EventHookMode_Pre);
	//HookEvent("player_changename", Event_NameChange, EventHookMode_Post);
	//HookUserMessage(GetUserMessageId("SayText2"), UserMessage_SayText2, true);
	//RegServerCmd("plw_forceupdate_alias", Command_AliasUpdate);

	HookConVarChange(g_useWhitelist, ConVarChangeEnabled);
	HookConVarChange(g_allowBannedPlayers, ConVarChangeBanCheck);
	HookConVarChange(g_gamemode, ConVarChangeGamemode);
	HookConVarChange(g_leaguesAllowed, ConVarChangeLeagues);
	HookConVarChange(g_rglDivsAllowed, ConVarChangeDivs);
	HookConVarChange(g_etf2lDivsAllowed, ConVarChangeDivs);
	HookConVarChange(g_serverMode, ConVarChangeMode);
	HookConVarChange(g_teamID, ConVarChangeID);
	HookConVarChange(g_scrimID, ConVarChangeID);
	HookConVarChange(g_matchID, ConVarChangeID);
	HookConVarChange(g_ringerPassword, ConVarChangeFakePW);
	HookConVarChange(g_pugMode, ConVarChangePug);
	HookConVarChange(g_allowKickedOutput, ConVarChangeKick);	
	HookConVarChange(g_useLeagueName, ConVarChangeLeagueAlias);
	HookConVarChange(g_allowJoinOutput, ConVarChangeJoin);
	PrintToServer("%s Competitive Player Whitelist loaded", SERVER_PRINT_PREFIX);
	PrintToChatAll("[SM] Player whitelist version %s loaded.", PLUGIN_VERSION);
}

public Action Timer_DBReconnect(Handle timer) {
	g_DBReconnectTimer = INVALID_HANDLE;

	char query[256];
	Format(query, sizeof(query), "SELECT steamid FROM league_player_cache WHERE league=1 LIMIT 1");
	SQL_TQuery(sql_db, SQLErrorCheckCallback, query);
}

// mgemod
public SQLErrorCheckCallback(Handle owner, Handle hndl, const String:error[], any data) {
	if (!StrEqual("", error)) {
		PrintToServer("%s Query failed: %s", SERVER_PRINT_PREFIX, error);
		PrintToServer("%s Retrying DB connection in %i minutes", SERVER_PRINT_PREFIX, g_dbReconnectInterval);
		
		if (g_DBReconnectTimer == INVALID_HANDLE) {
			g_DBReconnectTimer = CreateTimer(float(60 * g_dbReconnectInterval), Timer_DBReconnect, 0, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	// Could add a test / different call back for error handling, query all people in server to check if they exist in cache?
}

public void SetupSQLCache() {
	char error[256];

	sql_db = SQL_Connect("storage-local", true, error, sizeof(error));
	if (sql_db == INVALID_HANDLE) {
		SetFailState("Couldn't connect to database: %s", error);
	} else {
		PrintToServer("%s Success, using SQLite storage-local", SERVER_PRINT_PREFIX);
	}

	SQL_TQuery(sql_db, SQLErrorCheckCallback, "CREATE TABLE IF NOT EXISTS league_player_cache (steamid TEXT PRIMARY KEY, division TEXT, name TEXT, teamid INTEGER, league INTEGER)");
}

public void OnMapStart() {
	//playerNames.Clear();
	//playerTeams.Clear();
} 

public void OnMapEnd() {
	g_DBReconnectTimer = INVALID_HANDLE;
}

public Action ConnectSilencer(Event event, const char[] name, bool dontBroadcast) {
	if (GetConVarBool(g_allowJoinOutput)) {
		if (!dontBroadcast)
			SetEventBroadcast(event, true);
	}
	
	return Plugin_Continue;
}

public Action KickSilencer(Event event, const char[] name, bool dontBroadcast) {
	if (!GetConVarBool(g_allowKickedOutput)) {
		if (!dontBroadcast) {
			char disconnectReason[64];
			GetEventString(event, "reason", disconnectReason, sizeof(disconnectReason));
		
			for (int i = 0; i < 7; i++) {
				if (strcmp(KickMessages[i], disconnectReason, true) == 0) {
					SetEventBroadcast(event, true);
					break;
				}
			}
			
			PrintToServer("%s reason: %s", SERVER_PRINT_PREFIX, disconnectReason);
		}
	}

	/*int client = GetClientOfUserId(GetEventInt(event, "userid"));
	char client_string[64];
	IntToString(client, client_string, sizeof(client_string));
	playerTeams.Remove(client_string);
	playerNames.Remove(client_string);*/

	return Plugin_Continue;
}

public Action Command_AliasUpdate(int args) {
	for (int i = 1; i < MaxClients; i++) {
		if (IsClientConnected(i)) {
			char playerName[32];
			char client_string[64];
			IntToString(i, client_string, sizeof(client_string));
			playerNames.GetString(client_string, playerName, sizeof(playerName));
			SetClientName(i, playerName);
		}
	}
} 

// taken from https://github.com/erynnb/pugchamp - WIP
public void Event_NameChange(Event event, const char[] name, bool dontBroadcast) {
	if (!GetConVarBool(g_useLeagueName)) {
		return;
	}
	int client = GetClientOfUserId(event.GetInt("userid"));
	char client_string[32];
	IntToString(client, client_string, sizeof(client_string));
	if (!IsClientReplay(client) && !IsClientSourceTV(client)) {
		char newName[32];
		event.GetString("newname", newName, sizeof(newName));

		char playerName[32];
		if (playerNames.GetString(client_string, playerName, sizeof(playerName))) {
			if (!StrEqual(newName, playerName)) {
				SetClientName(client, playerName);
			}
		}
	}
}
 
// taken from https://github.com/erynnb/pugchamp - WIP
public Action UserMessage_SayText2(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init) {
    if (!GetConVarBool(g_useLeagueName)) {
        return Plugin_Continue;
    }

    char buffer[512];

    if (!reliable) {
        return Plugin_Continue;
    }

    msg.ReadByte();
    msg.ReadByte();
    msg.ReadString(buffer, sizeof(buffer), false);

    if (StrContains(buffer, "#TF_Name_Change") != -1) {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public Action GetGameDirHook(Event event, const char[] name, bool dontBroadcast) {
	char game[256];
	event.GetString("game", game, sizeof(game));

	char sm_path[128];
	BuildPath(Path_SM, sm_path, sizeof(sm_path), "");

	Format(g_sourcemodPath, sizeof(g_sourcemodPath), "%s\\%s", game, sm_path);

	UnhookEvent("server_spawn", GetGameDirHook);
}

// need to think of a better name for this
public bool ValidBoolConVarUpdate(ConVar cvar, const char[] oldvalue, const char[] newvalue, const char[] defaultvalue) {
	if (strlen(newvalue) != 1 || (newvalue[0] != '0' && newvalue[0] != '1')) {
		PrintToChatAll("[SM]: Invalid plugin mode, setting to default (%s)", defaultvalue[0] == '0' ? "off" : "on");
		SetConVarString(cvar, defaultvalue);
		return false;
	}
	int int_newvalue = StringToInt(newvalue);
	int int_oldvalue = StringToInt(oldvalue);
	return int_newvalue != int_oldvalue;
}

public void ConVarChangeLeagueAlias(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (ValidBoolConVarUpdate(cvar, oldvalue, newvalue, "0") && GetConVarBool(g_allowChatMessages)) {
		PrintToChatAll("[SM]: Use league names mode %s", StringToInt(newvalue) == 1 ? "enabled" : "disabled");
	}
}				

public void ConVarChangeJoin(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (ValidBoolConVarUpdate(cvar, oldvalue, newvalue, "1") && GetConVarBool(g_allowChatMessages)) {
		PrintToChatAll("[SM]: Join output mode %s", StringToInt(newvalue) == 1 ? "enabled" : "disabled");
	}
}

public void ConVarChangeExec(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (ValidBoolConVarUpdate(cvar, oldvalue, newvalue, "0") && GetConVarBool(g_allowChatMessages)) {
		PrintToChatAll("[SM]: Team Exec mode %s (WARNING: possibly unsafe)", StringToInt(newvalue) == 1 ? "enabled" : "disabled");
	}
}

public void ConVarChangeKick(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (ValidBoolConVarUpdate(cvar, oldvalue, newvalue, "0") && GetConVarBool(g_allowChatMessages)) {
		PrintToChatAll("[SM]: Kick output mode %s", StringToInt(newvalue) == 1 ? "enabled" : "disabled");
	}
}

public void ConVarChangePug(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (ValidBoolConVarUpdate(cvar, oldvalue, newvalue, "0")) {
		if (StringToInt(newvalue) == 1) {
			SetConVarString(g_useWhitelist, "0");
			// set to whatever you want server pw to be, this is just a placeholder
			SetConVarString(FindConVar("sv_password"), DEFAULT_PASSWORD);
		}

		if (StringToInt(newvalue) == 0) {
			SetConVarString(g_useWhitelist, "1");
			SetConVarString(FindConVar("sv_password"), "");
		}

		if (GetConVarBool(g_allowChatMessages))
			PrintToChatAll("[SM]: Pug mode %s", StringToInt(newvalue) == 1 ? "enabled" : "disabled");
		}
}

public void ConVarChangeEnabled(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (ValidBoolConVarUpdate(cvar, oldvalue, newvalue, "1") && GetConVarBool(g_allowChatMessages)) {
		PrintToChatAll("[SM]: Player whitelist %s", StringToInt(newvalue) == 1 ? "enabled" : "disabled");
	}
}

public void ConVarChangeBanCheck(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (ValidBoolConVarUpdate(cvar, oldvalue, newvalue, "0") && GetConVarBool(g_allowChatMessages)) {
		PrintToChatAll("[SM]: Banned players%sallowed in server", StringToInt(newvalue) == 1 ? " " : " not ");
	}
}

public void ConVarChangeGamemode(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	// make better value checking for HL/6s
	if (strlen(newvalue) != 1 || (newvalue[0] != '1' && newvalue[0] != '2' && newvalue[0] != '4')) {
		PrintToChatAll("[SM]: Invalid plugin mode (%d), setting to default (6s)", newvalue[0]);
		SetConVarString(cvar, "2");
		return;
	}
	int int_newvalue = StringToInt(newvalue);
	int int_oldvalue = StringToInt(oldvalue);
	if (int_newvalue == int_oldvalue) {
		return;
	}
	if (GetConVarBool(g_allowChatMessages))
		PrintToChatAll("[SM]: %s based whitelist", int_newvalue == GAMEMODE_HL ? "HL" : int_newvalue == GAMEMODE_6S ? "6s" : "Yomps tourney");
}

public void ConVarChangeLeagues(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	int int_newvalue = StringToInt(newvalue);
	int int_oldvalue = StringToInt(oldvalue);
	if (int_newvalue <= 0 || int_newvalue > 3) {
		PrintToChatAll("[SM]: Invalid plugin mode, setting to default (RGL+ETF2L)");
		SetConVarString(cvar, "3");
		return;
	}
	if (int_newvalue == int_oldvalue) {
		return;
	}
	if (GetConVarBool(g_allowChatMessages))
		PrintToChatAll("[SM]: Checking %s league mode", 
								int_newvalue == LEAGUE_RGL ? "RGL" : 
								int_newvalue == LEAGUE_ETF2L ? "ETF2L" : "RGL or ETF2L");

}

public void ConVarChangeDivs(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (strcmp(oldvalue, newvalue, true) != 0) {
		// error checking
		for (int i = 0; i < strlen(newvalue); i++) {
			if (newvalue[i] == ',') 
				continue;
			if (newvalue[i] > MAX_DIV_CHAR || newvalue[i] <= '0') {
				if (GetConVarBool(g_allowChatMessages))
					PrintToChatAll("[SM]: Unknown div sequence, resetting to default all divs");
				SetConVarString(cvar, cvar == g_rglDivsAllowed ? RGL_DIV_ALL : ETF2L_DIV_ALL);
				return;
			}
			
		}
		if (GetConVarBool(g_allowChatMessages))
			PrintToChatAll("[SM]: Whitelisted RGL divs:");
		char split_buffer[MAX_RGL_DIV_INT][64];
		int n_divs = ExplodeString(newvalue, ",", split_buffer, MAX_RGL_DIV_INT, 64, false);
		for (int i = 0; i < n_divs; i++) {
			if (strlen(split_buffer[i]) != 1) 
				continue;
			if (GetConVarBool(g_allowChatMessages))
				PrintToChatAll("[SM]: %s", cvar == g_rglDivsAllowed ? 
										IntToRGLDivision[(split_buffer[i][0] - '0')]:
										IntToETF2LDivision[(split_buffer[i][0] - '0')]);
		}
	}
}

public void ConVarChangeMode(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (strlen(newvalue) != 1 || newvalue[0] > '4' || newvalue[0] < '0') {
		PrintToChatAll("[SM]: Invalid mode, setting to default (all)");
		SetConVarString(cvar, "4");
		return;
	}
	int int_newvalue = StringToInt(newvalue);
	int int_oldvalue = StringToInt(oldvalue);
	if (int_newvalue == int_oldvalue) {
		return;
	}
	if (!GetConVarBool(g_allowChatMessages))
		return;
	switch(int_newvalue) {
		case MODE_TEAMONLY:
			PrintToChatAll("[SM]: Only home team allowed");
		case MODE_SCRIM:
			PrintToChatAll("[SM]: Only home team + scrim team allowed");
		case MODE_MATCH:
			PrintToChatAll("[SM]: Only home team + match team allowed");
		case MODE_MATCH | MODE_SCRIM:
			PrintToChatAll("[SM]: Only home team, match team, and scrim team allowed");
		case MODE_ALL:
			PrintToChatAll("[SM]: Default all player allowed mode");
	}
}

public void ConVarChangeID(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	int int_newvalue = StringToInt(newvalue);
	int int_oldvalue = StringToInt(oldvalue);
	if (int_newvalue <= 0) {
		PrintToChatAll("[SM]: Invalid new ID, reinput a valid one. Resetting to 1");
		SetConVarString(cvar, "1");
		return;
	}
	if (int_newvalue == int_oldvalue) {
		return;
	}
	if (GetConVarBool(g_allowChatMessages))
		PrintToChatAll("[SM]: %s ID changed to %d. Do note this isn't verified to be a valid team, doublecheck ID!", 
							cvar == g_teamID ? "Home team" : 
							cvar == g_scrimID ? "Scrim team" :
							cvar == g_matchID ? "Match team" : "Unknown cvar", int_newvalue);
}

public void ConVarChangeFakePW(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (strcmp(oldvalue, newvalue, true) != 0 && GetConVarBool(g_allowChatMessages)) {
		PrintToChatAll("[SM]: Changed ringer/spec password");
	}
}

public void PrintETF2LJoinString(const char[] name, const char[] division) {
	PrintToChatAll("Player %s (ETF2L div: %s) joined the server", name, division);
}

public void PrintRGLJoinString(const char[] name, const char[] division) {
	PrintToChatAll("Player %s (RGL div: %s) joined the server", name, division);
}

public void PrintJoinString(const char[] name, const char[] division, int league) {
	if (!GetConVarBool(g_allowChatMessages))
		return;
	if (league == LEAGUE_RGL) {
		PrintRGLJoinString(name, division);
	} else {
		PrintETF2LJoinString(name, division);
	}
}

public void GetFormattedServerParameters(char steamID[STEAMID_LENGTH], char buffer[1024]) {
	StrCat(buffer, sizeof(buffer), "?steamid=");
	StrCat(buffer, sizeof(buffer), steamID);

	StrCat(buffer, sizeof(buffer), "&gamemode=");
	StrCat(buffer, sizeof(buffer), GetConVarString(g_gamemode));

	StrCat(buffer, sizeof(buffer), "&leagues=");
	StrCat(buffer, sizeof(buffer), GetConVarString(g_leaguesAllowed));

	StrCat(buffer, sizeof(buffer), "&mode=");
	StrCat(buffer, sizeof(buffer), GetConVarString(g_serverMode));

	StrCat(buffer, sizeof(buffer), "&teamid=");
	StrCat(buffer, sizeof(buffer), GetConVarString(g_teamID));

	if (GetConVarString(g_serverMode) & MODE_SCRIM) {
		StrCat(buffer, sizeof(buffer), "&scrimid=");
		StrCat(buffer, sizeof(buffer), GetConVarString(g_scrimID));
	}

	if (GetConVarString(g_serverMode) & MODE_MATCH) {
		StrCat(buffer, sizeof(buffer), "&matchid=");
		StrCat(buffer, sizeof(buffer), GetConVarString(g_matchID));
	}

	if (GetConVarInt(g_leaguesAllowed) & LEAGUE_RGL) {
		StrCat(buffer, sizeof(buffer), "&rgldivs=");
		StrCat(buffer, sizeof(buffer), GetConVarString(g_rglDivsAllowed));
	}
	if (GetConVarInt(g_leaguesAllowed) & LEAGUE_ETF2L) {
		StrCat(buffer, sizeof(buffer), "&etf2ldivs=");
		StrCat(buffer, sizeof(buffer), GetConVarString(g_etf2lDivsAllowed));
	}

	if (GetConVarBool(g_allowBannedPlayers)) {
		StrCat(buffer, sizeof(buffer), "&allowbans=1");
	}
}

public void LeagueSuccessHelper(int client, int league) {
	// In this branch, if we get to this point, they're in the appropriate divs / teams / etc

	char divisionNameTeamID[3][64]; // (div, rgl_name, team id)
	ExplodeString(g_leagueResponseBuffer[client], ",", divisionNameTeamID, 3, 64);
	char steamID[STEAMID_LENGTH];
	GetClientAuthId(client, AuthId_SteamID64, steamID, STEAMID_LENGTH);

	PrintToServer("%s div: %s name: %s teamid: %s", SERVER_PRINT_PREFIX, divisionNameTeamID[0], divisionNameTeamID[1], divisionNameTeamID[2]);
	PrintJoinString(divisionNameTeamID[1], divisionNameTeamID[0], league);

	SetSteamIDInCache(steamID, league, divisionNameTeamID);

	for (int i = 0; i < sizeof(g_leagueResponseBuffer[]); i++) {
		g_leagueResponseBuffer[client][i] = 0;
	}

	/* WIP 
	char client_string[64];
	IntToString(client, client_string, sizeof(client_string));
	playerTeams.SetString(client_string, divisionNameTeamID[2], true);
	playerNames.SetString(client_string, divisionNameTeamID[1], true);
	PrintToServer("New name entry: (%s, %s)", client_string, divisionNameTeamID[1]);
	if (GetConVarBool(g_useLeagueName))
		SetClientName(client, divisionNameTeamID[1]);
	*/
}

// we define 'success' as commas in the response as <div>,<name>,<teamid> is seen as success
public bool GetResponseSuccess(int client) {
	int comma_index = FindCharInString(g_leagueResponseBuffer[client], ',', false);
	PrintToServer("%s client resp buffer: %s", SERVER_PRINT_PREFIX, g_leagueResponseBuffer[client]);
	return comma_index != -1;
}

public void ETF2LGetPlayerDataCallback(Handle hCurl, CURLcode code, any data) {
	int client = data;
	char steamID[STEAMID_LENGTH];
	GetClientAuthId(client, AuthId_SteamID64, steamID, STEAMID_LENGTH);

	if (code != CURLE_OK) {
		char curlError[256];
		curl_easy_strerror(code, curlError, sizeof(curlError));
	} else {
		bool success = GetResponseSuccess(client);
		if (success || GetSteamIDInCache(client, steamID, LEAGUE_ETF2L)) {
			LeagueSuccessHelper(client, LEAGUE_ETF2L);
		} else {
			if (GetConVarInt(g_leaguesAllowed) & LEAGUE_RGL) {
				KickClient(client, "You are not an RGL or ETF2L player");
			} else {
				KickClient(client, "You are not an ETF2L player");
			}
		}
	}
	CloseHandle(hCurl);
}

public void SetupCurlRequest(const String:steamID[], int client, int league) {
	Handle hCurl = curl_easy_init();
	if (hCurl == INVALID_HANDLE) {
		PrintToServer("%s Invalid CURL handle on setup", SERVER_PRINT_PREFIX);
		return;
	}

	curl_easy_setopt_function(hCurl, CURLOPT_WRITEFUNCTION, ReceiveData, client);

	char local_leagueResolverURL[2048];
	GetConVarString(g_leagueResolverURL, local_leagueResolverURL, sizeof(local_leagueResolverURL));
	char temp_buffer[1024];
	GetFormattedServerParameters(steamID, temp_buffer);
	StrCat(local_leagueResolverURL, sizeof(local_leagueResolverURL), temp_buffer);

	curl_easy_setopt_string(hCurl, CURLOPT_URL, local_leagueResolverURL);

	for (int i = 0; i < sizeof(g_leagueResponseBuffer[]); i++) {
		g_leagueResponseBuffer[client][i] = 0;
	}	

	curl_easy_perform_thread(hCurl, league == LEAGUE_RGL ? RGLGetPlayerDataCallback : ETF2LGetPlayerDataCallback, client);
}

public ReceiveData(Handle handle, const String:buffer[], const bytes, const nmemb, any data) {
	int client = data;
	StrCat(g_leagueResponseBuffer[client], sizeof(g_leagueResponseBuffer[]), buffer);
	return bytes * nmemb;
}

public void GetETF2LUserByID(const String:steamID[], int client) {
	SetupCurlRequest(steamID, client, LEAGUE_ETF2L);
}

// side effect of clearing g_leagueResponseBuffer
public bool GetSteamIDInCache(int client, const String:steamID[], int league_type) {
	char query[256];

	Format(query, sizeof(query), "SELECT division,name,teamid FROM league_player_cache WHERE steamid='%s' AND league=%i", steamID, league_type);

	// If this causes server lag, may need async callback w/ T_Query
	DBResultSet playerDBRS = SQL_Query(sql_db, query, sizeof(query));

	PrintToServer("Queried, steamID: %s", steamID);

	if (playerDBRS == null || !playerDBRS.HasResults || playerDBRS.RowCount == 0) {
		return false;
	}

	for (int i = 0; i < sizeof(g_leagueResponseBuffer[]); i++) {
		g_leagueResponseBuffer[client][i] = 0;
	}
	//strcopy(g_leagueResponseBuffer[client], sizeof(g_leagueResponseBuffer[]), "");

	char buffer[64];
	for (int i = 0; i < 3; i++) {
		playerDBRS.FetchString(i, buffer, sizeof(buffer));
		StrCat(g_leagueResponseBuffer[client], sizeof(g_leagueResponseBuffer[]), buffer);
		StrCat(g_leagueResponseBuffer[client], sizeof(g_leagueResponseBuffer[]), ",");
	}
	return true;
}

public void SetSteamIDInCache(const String:steamID[], int league_type, char divisionNameTeamID[3][64]) {
	char query[256];

	// not optimal but hey
	Format(query, sizeof(query), "REPLACE INTO league_player_cache VALUES ('%s', '%s', '%s', %i, %i)", 
																			steamID, 
																			divisionNameTeamID[0], 
																			divisionNameTeamID[1], 
																			StringToInt(divisionNameTeamID[2]),
																			league_type);
	SQL_TQuery(sql_db, SQLErrorCheckCallback, query);
}

public void RGLGetPlayerDataCallback(Handle hCurl, CURLcode code, any data) {
	int client = data;
	char steamID[STEAMID_LENGTH];
	GetClientAuthId(client, AuthId_SteamID64, steamID, STEAMID_LENGTH);

	if (code != CURLE_OK) {
		char curlError[256];
		curl_easy_strerror(code, curlError, sizeof(curlError));
	} else {
		bool success = GetResponseSuccess(client);
		if (success || GetSteamIDInCache(client, steamID, LEAGUE_RGL)) { 
			LeagueSuccessHelper(client, LEAGUE_RGL);
		} else {
			if (GetConVarInt(g_leaguesAllowed) & LEAGUE_ETF2L) {
				GetETF2LUserByID(steamID, client);
			} else {
				KickClient(client, "You are not an RGL player");
			}
		}
	}
	CloseHandle(hCurl);
}

public void GetRGLUserByID(const String:steamID[], int client) {
	SetupCurlRequest(steamID, client, LEAGUE_RGL);
}

public void OnClientAuthorized(int client, const char[] auth)
{
	if (IsClientReplay(client) || IsClientSourceTV(client)) {
		PrintToServer("%s STV/Replay joined", SERVER_PRINT_PREFIX);
		return;
	}

	char steamID[STEAMID_LENGTH];
	if (!GetClientAuthId(client, AuthId_SteamID64, steamID, STEAMID_LENGTH)) {
		KickClient(client, "Invalid steamID authorization, possibly retry");
	}
	PrintToServer("%s steamID %s connected", SERVER_PRINT_PREFIX, steamID);

	// Client's password
	char password[MAX_PASSWORD_LENGTH + 1];
	if(!GetClientInfo(client, FAKE_PASSWORD_VAR, password, MAX_PASSWORD_LENGTH)) {
		PrintToServer("%s Failed to get client password", SERVER_PRINT_PREFIX);
		strcopy(password, 0, "");
	}
	PrintToServer("%s Inputted 'pass': %s", SERVER_PRINT_PREFIX, password);

	// Server controlled password
	char fakePasswordBuf[MAX_PASSWORD_LENGTH + 1];
	GetConVarString(g_ringerPassword, fakePasswordBuf, MAX_PASSWORD_LENGTH);

	if (strlen(password) > 0) {
		if (strcmp(password, fakePasswordBuf, true) == 0) {
			PrintToServer("%s Joined via password", SERVER_PRINT_PREFIX);
			return;
		}
	}

	// if we aren't using whitelist
	if (!GetConVarBool(g_useWhitelist)) {
		PrintToServer("%s Not using whitelist", SERVER_PRINT_PREFIX);
		return;
	}
	// if RGL / all, check RGL first (then check etf2l)
	if (GetConVarInt(g_leaguesAllowed) & LEAGUE_RGL) {
		GetRGLUserByID(steamID, client); 
	} else if (GetConVarInt(g_leaguesAllowed) & LEAGUE_ETF2L) {
		GetETF2LUserByID(steamID, client);
	}
}

