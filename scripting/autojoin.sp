#pragma semicolon 1

#include <sourcemod>
#include <system2>
#define AUTOLOAD_EXTENSIONS
#define REQUIRE_EXTENSIONS

#define min(%1,%2) (((%1) < (%2)) ? (%1) : (%2))

#include "plw_plugin_version"

// barbancle
#define HOME_TEAM_ID 6602

#define FAKE_PASSWORD_VAR "cl_team"
#define DEFAULT_FAKE_PW "ringer"

#define STEAMID_LENGTH 32
#define MAX_PASSWORD_LENGTH 255
#define DEFAULT_BUFFER_SIZE 512

#define MAX_DIV_CHAR '7'
#define RGL_DIV_INVITE 0x1
#define RGL_DIV_1 0x2
#define RGL_DIV_2 0x3
#define RGL_DIV_MAIN 0x4
#define RGL_DIV_INT 0x5
#define RGL_DIV_AMA 0x6
#define RGL_DIV_NEW 0x7
#define RGL_DIV_ALL "1,2,3,4,5,6,7"

// idk how etf2l works now, lowest tier I saw was 4
#define ETF2L_DIV_PREM 0x1
#define ETF2L_DIV_1 0x2
#define ETF2L_DIV_2 0x3
#define ETF2L_DIV_3 0x4
#define ETF2L_DIV_4 0x5
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

ConVar g_useWhitelist;
ConVar g_rglDivsAllowed;
ConVar g_etf2lDivsAllowed;
ConVar g_serverMode;
ConVar g_teamID;
ConVar g_scrimID;
ConVar g_matchID;
ConVar g_ringerPassword;
ConVar g_leaguesAllowed;
ConVar g_gamemode;
ConVar g_allowBannedPlayers;
ConVar g_allowChatMessages;

char IntToETF2LDivision[5][] = {"Prem", "Division 1", "Division 2", "Division 3", "Division 4"};
char IntToRGLDivision[7][] = {"Invite", "Division 1", "Division 2", "Main", "Intermediate", "Amateur", "Newcomer"};

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

	HookEvent("player_disconnect", plLeave, EventHookMode_Pre);
    	HookConVarChange(g_useWhitelist, CVarChangeEnabled);
	HookConVarChange(g_allowBannedPlayers, CVarChangeBanCheck);
	HookConVarChange(g_gamemode, CVarChangeGamemode);
	HookConVarChange(g_leaguesAllowed, CVarChangeLeagues);
	HookConVarChange(g_rglDivsAllowed, CVarChangeDivs);
	HookConVarChange(g_etf2lDivsAllowed, CVarChangeDivs);
	HookConVarChange(g_serverMode, CVarChangeMode);
	HookConVarChange(g_teamID, CVarChangeID);
	HookConVarChange(g_scrimID, CVarChangeID);
	HookConVarChange(g_matchID, CVarChangeID);
	HookConVarChange(g_ringerPassword, CVarChangeFakePW);
	
	PrintToServer("Competitive Player Whitelist loaded");
}

// Need to test ability to silence 'kicked' messages
public Action plLeave(Event event, const char[] name, bool dontBroadcast) {
	PrintToServer("plLeave event: %s", name);
	SetEventBroadcast(event, true);
	return Plugin_Continue;
}

public void CVarChangeEnabled(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (strlen(newvalue) != 1 || (newvalue[0] != '0' && newvalue[0] != '1')) {
		PrintToChatAll("[SM]: Invalid plugin mode, setting to default (on)");
		SetConVarString(cvar, "1");
		return;
	}

	int int_newvalue = StringToInt(newvalue);
	int int_oldvalue = StringToInt(oldvalue);
	if (int_newvalue == int_oldvalue) {
		return;
	}
	if (GetConVarBool(g_allowChatMessages))
		PrintToChatAll("[SM]: Player whitelist %s", int_newvalue == 1 ? "enabled" : "disabled");
}

public void CVarChangeBanCheck(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (strlen(newvalue) != 1 || (newvalue[0] != '0' && newvalue[0] > '1')) {
		PrintToChatAll("[SM]: Invalid plugin mode, setting to default (on)");
		SetConVarString(cvar, "0");
		return;
	}

	int int_newvalue = StringToInt(newvalue);
	int int_oldvalue = StringToInt(oldvalue);
	if (int_newvalue == int_oldvalue) {
		return;
	}
	if (GetConVarBool(g_allowChatMessages))
		PrintToChatAll("[SM]: Banned players%sallowed in server", int_newvalue == 1 ? " " : " not ");
}

public void CVarChangeGamemode(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	// make better value checking for HL/6s
	if (strlen(newvalue) != 1 || (newvalue[0] != '1' && newvalue[0] != '2')) {
		PrintToChatAll("[SM]: Invalid plugin mode, setting to default (6s)");
		SetConVarString(cvar, "2");
		return;
	}
	int int_newvalue = StringToInt(newvalue);
	int int_oldvalue = StringToInt(oldvalue);
	if (int_newvalue == int_oldvalue) {
		return;
	}
	if (GetConVarBool(g_allowChatMessages))
		PrintToChatAll("[SM]: %s based whitelist", int_newvalue == GAMEMODE_HL ? "HL" : int_newvalue == GAMEMODE_6S ? "6s" : "Unknown");
}

public void CVarChangeLeagues(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	int int_newvalue = StringToInt(newvalue);
	int int_oldvalue = StringToInt(oldvalue);
	if (int_newvalue == 0 || int_newvalue < 0 || int_newvalue > 3) {
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
								int_newvalue == LEAGUE_ETF2L ? "ETF2L" : 
								int_newvalue == LEAGUE_ALL ? "RGL or ETF2L" : "unknown");

}

// TODO fix to use explodestring
public void CVarChangeDivs(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (strcmp(oldvalue, newvalue, true) != 0) {
		if (GetConVarBool(g_allowChatMessages))
			PrintToChatAll("[SM]: Whitelisted RGL divs:");
		for (int i = 0; i < strlen(newvalue); i++) {
			if (newvalue[i] == ',') 
				continue;
			if (newvalue[i] > MAX_DIV_CHAR || newvalue[i] <= '0') {
				PrintToChatAll("[SM]: Unknown div sequence, resetting to default all divs");
				SetConVarString(cvar, cvar == g_rglDivsAllowed ? RGL_DIV_ALL : ETF2L_DIV_ALL);
				return;
			}
			if (GetConVarBool(g_allowChatMessages))
				PrintToChatAll("[SM]: %s", cvar == g_rglDivsAllowed ? 
										IntToRGLDivision[(newvalue[i] - '0') - 1] :
										IntToETF2LDivision[(newvalue[i] - '0') - 1]);
		}
	}
}

public void CVarChangeMode(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
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

public void CVarChangeID(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
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

public void CVarChangeFakePW(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (strcmp(oldvalue, newvalue, true) != 0) {
		if (GetConVarBool(g_allowChatMessages))
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

public int ETF2LDivisionToInt(char tier[64]) {
	if (strncmp(tier, "banned", 6, false) == 0) {
		return 0x0;
	}
	switch (tier[0]) {
		case '0':
			return ETF2L_DIV_PREM;
		case '1':
			return ETF2L_DIV_1;
		case '2':
			return ETF2L_DIV_2;
		case '3':
			return ETF2L_DIV_3;
		case '4':
			return ETF2L_DIV_4;
	}
	return -1;
}

public int RGLDivisionToInt(char div[64]) {
	if (strncmp(div, "Invite", 6, false) == 0)
		return RGL_DIV_INVITE;
	if (strncmp(div, "Div-1", 5, false) == 0)
		return RGL_DIV_1;
	if (strncmp(div, "Div-2", 5, false) == 0)
		return RGL_DIV_2;
	if (strncmp(div, "Main", 4, false) == 0)
		return RGL_DIV_MAIN;
	if (strncmp(div, "Intermediate", 12, false) == 0)
		return RGL_DIV_INT;
	if (strncmp(div, "Amateur", 7, false) == 0)
		return RGL_DIV_AMA;
	if (strncmp(div, "Newcomer", 8, false) == 0)
		return RGL_DIV_NEW;
	if (strncmp(div, "banned", 6, false) == 0)
		return 0x0;
	return -1;
}

public void LeagueSuccessHelper(System2ExecuteOutput output, int client, int league) {
	char pyOutData[DEFAULT_BUFFER_SIZE];
	char divisionNameTeamID[3][64]; // (div, rgl_name, team id)
	output.GetOutput(pyOutData, sizeof(pyOutData));
	ExplodeString(pyOutData, ",", divisionNameTeamID, 3, 64);

	PrintToServer("div: %s name: %s teamid: %s", divisionNameTeamID[0], divisionNameTeamID[1], divisionNameTeamID[2]);
	int div = (league == LEAGUE_RGL ? RGLDivisionToInt(divisionNameTeamID[0]) : ETF2LDivisionToInt(divisionNameTeamID[0]));
	if (div == -1) {
		// investigate
		PrintToServer("Unexpected tier, check up on it - likely not on a team");
		strcopy(divisionNameTeamID[0], 6, "No div");
		strcopy(divisionNameTeamID[2], 2, "-1");
	}
	
	if (div == 0 && GetConVarBool(g_allowBannedPlayers)) {
		if (GetConVarBool(g_allowChatMessages))
			PrintToChatAll("Player %s (%s league banned) is joining", league == LEAGUE_RGL ? "RGL" : "ETF2L", divisionNameTeamID[1]);
		return;
	}

	char divs[64];
	char div_string[64];
	GetConVarString(league == LEAGUE_RGL ? g_rglDivsAllowed : g_etf2lDivsAllowed, divs, 64);
	IntToString(div, div_string, 64);
	if (StrContains(divs, div_string, false) == -1) {	
		if (GetConVarBool(g_allowChatMessages))
        		PrintToChatAll("RGL player %s tried to join", divisionNameTeamID[1]);
		KickClient(client, "You are not an %s player in the currently whitelisted divisions", league == LEAGUE_RGL ? "RGL" : "ETF2L");
		return;
	}

	if (MODE_TEAMONLY & GetConVarInt(g_serverMode)) {
		if (StringToInt(divisionNameTeamID[2]) == GetConVarInt(g_teamID)) {
   			PrintJoinString(divisionNameTeamID[1], divisionNameTeamID[0], league);
		} else {
			
			if (GetConVarBool(g_allowChatMessages))
				PrintToChatAll("RGL player %s tried to join", divisionNameTeamID[1]);
			KickClient(client, "You aren't currently in the team whitelist");
		}
	} else if (MODE_ALL & GetConVarInt(g_serverMode)) {
		PrintJoinString(divisionNameTeamID[1], divisionNameTeamID[0], league);
	} else if (MODE_SCRIM & GetConVarInt(g_serverMode) && StringToInt(divisionNameTeamID[2]) == GetConVarInt(g_scrimID)) {
		PrintJoinString(divisionNameTeamID[1], divisionNameTeamID[0], league);
	} else if (MODE_MATCH & GetConVarInt(g_serverMode) && StringToInt(divisionNameTeamID[2]) == GetConVarInt(g_matchID)) {
		PrintJoinString(divisionNameTeamID[1], divisionNameTeamID[0], league);
	} else {
		// deny all here
		if (GetConVarBool(g_allowChatMessages))
			PrintToChatAll("RGL player %s tried to join", divisionNameTeamID[1]);
		KickClient(client, "You don't fit the current server's whitelist rules");
	}
}

public void ETF2LGetPlayerDataCallback(bool success, const char[] command, System2ExecuteOutput output, any data) {
	int client = data;
	if (!success || output.ExitStatus != 0) {
		char pyOutData[DEFAULT_BUFFER_SIZE];
		output.GetOutput(pyOutData, sizeof(pyOutData));
		PrintToServer("output: %s", pyOutData);
		if (GetConVarInt(g_leaguesAllowed) & LEAGUE_RGL) {
			KickClient(client, "You are not an RGL or ETF2L player");
		} else {
			KickClient(client, "You are not an ETF2L player");
		}
	} else {
		LeagueSuccessHelper(output, client, LEAGUE_ETF2L);
	}
}

public void GetSMPath(char[] path, int maxLength) {
	System2_Execute(path, maxLength, "echo -n $SOURCEMOD_ROOT");
	PrintToServer("%s path", path);
}

public void GetETF2LUserByID(const String:steamID[], int client) {
	char etf2lGetDataCommand[DEFAULT_BUFFER_SIZE];
	char smPath[DEFAULT_BUFFER_SIZE];
	GetSMPath(smPath, sizeof(smPath));
	Format(etf2lGetDataCommand, sizeof(etf2lGetDataCommand), "python3 %s/etf2lplayerdata.py %s %d", smPath, steamID, GetConVarInt(g_gamemode));
	PrintToServer("ETF2L cmd: %s", etf2lGetDataCommand);
	
	System2_ExecuteThreaded(ETF2LGetPlayerDataCallback, etf2lGetDataCommand, client);
}

public void RGLGetPlayerDataCallback(bool success, const char[] command, System2ExecuteOutput output, any data) {
	int client = data;
	
	if (!success || output.ExitStatus != 0) {
		// failed to get, they aren't in RGL
		char pyOutData[DEFAULT_BUFFER_SIZE];
		output.GetOutput(pyOutData, sizeof(pyOutData));
		PrintToServer("output: %s", pyOutData);
		// etf2l is always checked last unless it's only one
		if (GetConVarInt(g_leaguesAllowed) & LEAGUE_ETF2L) {
			char steamID[STEAMID_LENGTH];
			GetClientAuthId(client, AuthId_SteamID64, steamID, STEAMID_LENGTH);
			GetETF2LUserByID(steamID, client);
		}	
	} else {
		LeagueSuccessHelper(output, client, LEAGUE_RGL);
	}

}

public void GetRGLUserByID(const String:steamID[], int client) {
	char rglGetDataCommand[DEFAULT_BUFFER_SIZE];
	char smPath[DEFAULT_BUFFER_SIZE];
	GetSMPath(smPath, sizeof(smPath));
	Format(rglGetDataCommand, sizeof(rglGetDataCommand), "python3 %s/rglplayerdata.py %s %d", smPath, steamID, GetConVarInt(g_gamemode));
	PrintToServer("RGL cmd: %s", rglGetDataCommand);

	System2_ExecuteThreaded(RGLGetPlayerDataCallback, rglGetDataCommand, client);
}

public void OnClientAuthorized(int client, const char[] auth)
{
	// TODO more STV testing
	if (IsClientSourceTV(client)) {
		PrintToServer("STV joined");
		return;
	}

	char steamID[STEAMID_LENGTH];
	GetClientAuthId(client, AuthId_SteamID64, steamID, STEAMID_LENGTH);
	PrintToServer("------steamid %s connected", steamID);

	// Client's password
	char password[MAX_PASSWORD_LENGTH + 1];
	GetClientInfo(client, FAKE_PASSWORD_VAR, password, MAX_PASSWORD_LENGTH);
	PrintToServer("------Inputted 'pass': %s", password);

	// Server controlled password
	char fakePasswordBuf[MAX_PASSWORD_LENGTH + 1];
	GetConVarString(g_ringerPassword, fakePasswordBuf, MAX_PASSWORD_LENGTH);

	if (strlen(password) > 0) {
		if (strcmp(password, fakePasswordBuf, true) == 0) {
			PrintToServer("Joined via password");
			return;
		}
	}

	// if we aren't using whitelist
	if (!GetConVarBool(g_useWhitelist)) {
		PrintToServer("Not using whitelist");
		return;
	}
	// if RGL / all, check RGL first (then check etf2l)
	if (GetConVarInt(g_leaguesAllowed) & LEAGUE_RGL) {
		GetRGLUserByID(steamID, client); 
	} else if (GetConVarInt(g_leaguesAllowed) & LEAGUE_ETF2L) {
		GetETF2LUserByID(steamID, client);
	}
}

