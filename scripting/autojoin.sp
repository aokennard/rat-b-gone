#pragma semicolon 1

#include <sourcemod>
#include <system2>
#define AUTOLOAD_EXTENSIONS
#define REQUIRE_EXTENSIONS

#define min(%1,%2) (((%1) < (%2)) ? (%1) : (%2))

#define PLUGIN_VERSION "1.5.0"

// barbancle
#define HOME_TEAM_ID 6602

#define FAKE_PASSWORD_VAR "cl_team"
#define DEFAULT_FAKE_PW "ringer"

#define STEAMID_LENGTH 32

#define RGL_DIV_INVITE 0x1
#define RGL_DIV_1 0x2
#define RGL_DIV_2 0x4
#define RGL_DIV_MAIN 0x8
#define RGL_DIV_INT 0x10
#define RGL_DIV_AMA 0x20
#define RGL_DIV_NEW 0x40
#define RGL_DIV_ALL (RGL_DIV_INVITE | RGL_DIV_1 | RGL_DIV_2  | RGL_DIV_MAIN | RGL_DIV_INT | RGL_DIV_AMA | RGL_DIV_NEW)

// idk how etf2l works now, lowest tier I saw was 4
#define ETF2L_DIV_PREM 0x1
#define ETF2L_DIV_1 0x2
#define ETF2L_DIV_2 0x4
#define ETF2L_DIV_3 0x8
#define ETF2L_DIV_4 0x10
#define ETF2L_DIV_ALL (ETF2L_DIV_PREM | ETF2L_DIV_1 | ETF2L_DIV_2 | ETF2L_DIV_3 | ETF2L_DIV_4)

#define MODE_TEAMONLY 0x0
#define MODE_SCRIM 0x1
#define MODE_MATCH 0x2
#define MODE_ALL 0x4

#define LEAGUE_RGL 0x1
#define LEAGUE_ETF2L 0x2
#define LEAGUE_ALL (LEAGUE_RGL | LEAGUE_ETF2L)

ConVar g_useWhitelist;
ConVar g_rglDivsAllowed;
ConVar g_etf2lDivsAllowed;
ConVar g_serverMode;
ConVar g_teamID;
ConVar g_scrimID;
ConVar g_matchID;
ConVar g_ringerPassword;
ConVar g_leaguesAllowed;

public Plugin:myinfo = {
	name        = "Rat-B-Gone: TF2 Competitive Player Whitelist",
	author      = "yosh",
	description = "Filters out non-whitelisted users based on competitive play",
	version     = PLUGIN_VERSION,
	url         = "pootis.org"
};


public OnPluginStart()
{
	//ringer_spec_index = 0;
	char macro_int_buf[64]; // because stringify doesnt exist apparently

	CreateConVar("plw_version", PLUGIN_VERSION, "Auto-kick whitelist");
	g_useWhitelist = CreateConVar("plw_enable", "1", "Toggles the use of the competitive filter");

	IntToString(LEAGUE_ALL, macro_int_buf, 64);
	g_leaguesAllowed = CreateConVar("plw_leagues", macro_int_buf, "The leagues to check potential joiners may be in (or operator); 1 = RGL, 2 = ETF2L");

	IntToString(RGL_DIV_ALL, macro_int_buf, 64);
	g_rglDivsAllowed = CreateConVar("plw_divs_rgl", macro_int_buf, "Allowed division players (or operator): 1 = invite, 2 = div1, 4 = div2, 8 = main, 16 = intermediate, 32 = amateur, 64 = newcomer");
	
	IntToString(ETF2L_DIV_ALL, macro_int_buf, 64);
	g_etf2lDivsAllowed = CreateConVar("plw_divs_etf2l", macro_int_buf, "Allowed division players (or operator): 1 = prem, 2 = div1, 4 = div2, 8 = div3, 16 = div4");

	IntToString(MODE_ALL, macro_int_buf, 64);
	g_serverMode = CreateConVar("plw_mode", macro_int_buf, "Determines who can join - 0 = only team, 1 = team + scrim, 2 = team + match, 3 = team + scrim + match, 4 = all");

	IntToString(HOME_TEAM_ID, macro_int_buf, 64);
	g_teamID = CreateConVar("plw_teamid", macro_int_buf, "ID of home team - always allowed");

	g_scrimID = CreateConVar("plw_scrimid", "0", "ID of scrim team - sometimes allowed"); 
	// I could technically scrape these off of a website but that sounds awful
	g_matchID = CreateConVar("plw_matchid", "0", "ID of match team - sometimes allowed");

	g_ringerPassword = CreateConVar("plw_fakepw", DEFAULT_FAKE_PW, "The password that ringers / specs can use to join");
	
	PrintToServer("Competitive Player Whitelist loaded");
}

public OnPluginEnd() {
	//CloseHandle(rgl_sid_map);
}

public void PrintETF2LJoinString(const char[] name, const char[] division) {
	PrintToChatAll("Player %s (ETF2L div: %s) joined the server", name, division);
}

public void PrintRGLJoinString(const char[] name, const char[] division) {
	PrintToChatAll("Player %s (RGL div: %s) joined the server", name, division);
}

public int ETF2LDivisionToInt(char tier[64]) {
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
		return 0x1;
	if (strncmp(div, "Div-1", 5, false) == 0)
		return 0x2;
	if (strncmp(div, "Div-2", 5, false) == 0)
		return 0x4;
	if (strncmp(div, "Main", 4, false) == 0)
		return 0x8;
	if (strncmp(div, "Intermediate", 12, false) == 0)
		return 0x10;
	if (strncmp(div, "Amateur", 7, false) == 0)
		return 0x20;
	if (strncmp(div, "Newcomer", 8, false) == 0)
		return 0x40;
	return 0x0;
}

public void LeagueSuccessHelper(System2ExecuteOutput output, int client, int league) {
	char pyOutData[256];
	char divisionNameTeamID[3][64]; // (div, rgl_name, team id)
	output.GetOutput(pyOutData, 256);
	ExplodeString(pyOutData, ",", divisionNameTeamID, 3, 64);

	PrintToServer("div: %s name: %s teamid: %s", divisionNameTeamID[0], divisionNameTeamID[1], divisionNameTeamID[2]);
	int div = (league == LEAGUE_RGL ? RGLDivisionToInt(divisionNameTeamID[0]) : ETF2LDivisionToInt(divisionNameTeamID[0]));
	if (div == -1) {
		// investigate
		PrintToServer("Unexpected ETF2L tier, check up on it");
	}

	if ((div & GetConVarInt(league == LEAGUE_RGL ? g_rglDivsAllowed : g_etf2lDivsAllowed)) == 0) {
		KickClient(client, "You are not an %s player in the currently whitelisted divisions", league == LEAGUE_RGL ? "RGL" : "ETF2L");
		return;
	}

	if (MODE_TEAMONLY & GetConVarInt(g_serverMode)) {
		if (StringToInt(divisionNameTeamID[2]) == GetConVarInt(g_teamID)) {
   				(league == LEAGUE_RGL ? PrintRGLJoinString(divisionNameTeamID[1], divisionNameTeamID[0]) : PrintETF2LJoinString(divisionNameTeamID[1], divisionNameTeamID[0]));
				return;
		}
		KickClient(client, "You aren't currently in the team whitelist");
		return;
	}

	if (MODE_ALL & GetConVarInt(g_serverMode)) {
		(league == LEAGUE_RGL ? PrintRGLJoinString(divisionNameTeamID[1], divisionNameTeamID[0]) : PrintETF2LJoinString(divisionNameTeamID[1], divisionNameTeamID[0]));
		return;
	}

	if (MODE_SCRIM & GetConVarInt(g_serverMode) && StringToInt(divisionNameTeamID[2]) == GetConVarInt(g_scrimID)) {
		(league == LEAGUE_RGL ? PrintRGLJoinString(divisionNameTeamID[1], divisionNameTeamID[0]) : PrintETF2LJoinString(divisionNameTeamID[1], divisionNameTeamID[0]));
		return;
	}

	if (MODE_MATCH & GetConVarInt(g_serverMode) && StringToInt(divisionNameTeamID[2]) == GetConVarInt(g_matchID)) {
		(league == LEAGUE_RGL ? PrintRGLJoinString(divisionNameTeamID[1], divisionNameTeamID[0]) : PrintETF2LJoinString(divisionNameTeamID[1], divisionNameTeamID[0]));
		return;
	}

	// deny all here
	KickClient(client, "You don't fit the current server's whitelist rules");
}

public void ETF2LGetPlayerDataCallback(bool success, const char[] command, System2ExecuteOutput output, any data) {
	int client = data;
	if (!success || output.ExitStatus != 0) {
		char pyOutData[256];
		output.GetOutput(pyOutData, 256);
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

public void GetETF2LUserByID(const String:steamID[], int client) {
	char cmd[256];
	Format(cmd, 256, "python3 /home/tf2server/hlserver/hlserver/tf/addons/sourcemod/plugins/etf2lplayerdata.py %s", steamID);
	
	System2_ExecuteThreaded(ETF2LGetPlayerDataCallback, cmd, client);
}

public void RGLGetPlayerDataCallback(bool success, const char[] command, System2ExecuteOutput output, any data) {
	int client = data;
	
	if (!success || output.ExitStatus != 0) {
		// failed to get, they aren't in RGL
		char pyOutData[256];
		output.GetOutput(pyOutData, 256);
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
	char cmd[256];
	Format(cmd, 256, "python3  /home/tf2server/hlserver/hlserver/tf/addons/sourcemod/plugins/rglplayerdata.py %s", steamID);
	PrintToServer("cmd: %s", cmd);

	System2_ExecuteThreaded(RGLGetPlayerDataCallback, cmd, client);
}

public void OnClientAuthorized(int client, const char[] auth)
{
	// TODO more STV testing
	if (IsClientSourceTV(client)) {
		return;
	}

	char steamID[STEAMID_LENGTH];
	GetClientAuthId(client, AuthId_SteamID64, steamID, STEAMID_LENGTH);

	// Client's password
	char password[256];
	GetClientInfo(client, FAKE_PASSWORD_VAR, password, 256);
	PrintToServer("Inputted 'pass': %s", password);

	// Server controlled password
	char fakePasswordBuf[256];
	GetConVarString(g_ringerPassword, fakePasswordBuf, 256);

	if (strlen(password) > 0) {
		int passwordLen = strlen(password);
		int fakePasswordLen = strlen(fakePasswordBuf);
		int minPasswordLen = min(passwordLen, fakePasswordLen); // don't have gcc's typeof helper macro here, so we do this
		if (strncmp(password, fakePasswordBuf, minPasswordLen, false) == 0) {
			PrintToServer("Joined via password");
			return;
		}
	}

	// if we aren't using whitelist
	if (GetConVarInt(g_useWhitelist) == 0) {
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

