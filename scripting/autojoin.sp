#pragma semicolon 1

#include <sourcemod>
#include <system2>
#define AUTOLOAD_EXTENSIONS
#define REQUIRE_EXTENSIONS

#define xstr(s) str(s)
#define str(s) #s

#define PLUGIN_VERSION "1.0.1"

// barbancle
#define HOME_TEAM_ID 6602

#define RGL_SEARCH_URL "https://rgl.gg/public/playersearch.aspx?r=40"
#define RGL_TEAM_URL "https://rgl.gg/Public/Teamb.aspx?t=%d&r=40"
#define FAKE_PASSWORD_VAR "cl_language"
#define DEFAULT_FAKE_PW "rat"

#define STEAMID_LENGTH 32

#define RGL_DIV_INVITE 0x1
#define RGL_DIV_1 0x2
#define RGL_DIV_2 0x4
#define RGL_DIV_MAIN 0x8
#define RGL_DIV_INT 0x10
#define RGL_DIV_AMA 0x20
#define RGL_DIV_NEW 0x40

#define RGL_TEAMONLY 0x0
#define RGL_SCRIM 0x1
#define RGL_MATCH 0x2

#define RGL_MODE_ALL 0x4
#define RGL_DIV_ALL (RGL_DIV_INVITE|RGL_DIV_1|RGL_DIV_2|RGL_DIV_MAIN|RGL_DIV_INT|RGL_DIV_AMA|RGL_DIV_NEW)

ConVar g_useWhitelist;
ConVar g_rglDivsAllowed;
ConVar g_rglMode;
ConVar g_teamID;
ConVar g_scrimID;
ConVar g_matchID;
ConVar g_ringerPassword;
//ConVar g_otherPlayerCount;

// Old ringer variables
//char ringer_spec_ids[16][STEAMID_LENGTH];
//int ringer_spec_index;

public Plugin:myinfo = {
	name        = "Rat-B-Gone: TF2 RGL Player Whitelist",
	author      = "yosh",
	description = "Filters out non-whitelisted users based on competitive play",
	version     = PLUGIN_VERSION,
	url         = "pootis.org"
};


public OnPluginStart()
{
	//ringer_spec_index = 0;
	g_rglDivsAllowed = CreateConVar("plw_divs", xstr(RGL_DIV_ALL), "Allowed division players (or operator): 1 = invite, 2 = div1, 4 = div 2, 8 = main, 16 = intermediate, 32 = amateur, 64 = newcomer");
	
	g_rglMode = CreateConVar("plw_mode", xstr(RGL_MODE_ALL), "Determines who can join - 0 = only team, 1 = team + scrim, 2 = team + match, 3 = team + scrim + match, 4 = all");

	CreateConVar("plw_version", PLUGIN_VERSION, "Auto-kick whitelist");
    g_useWhitelist = CreateConVar("plw_enable", "1", "Toggles the use of the competitive filter");

	g_teamID = CreateConVar("plw_teamid", xstr(HOME_TEAM_ID), "ID of home team - always allowed");

	g_scrimID = CreateConVar("plw_scrimid", "0", "ID of scrim team - sometimes allowed"); 
	// I could technically scrape these off of RGL website but that sounds awful
	g_matchID = CreateConVar("plw_matchid", "0", "ID of match team - sometimes allowed");

	//g_otherPlayerCount = CreateConVar("plw_others_count", "3", "Number of 'rule breaker' players allowed - 2 ringer, 1 spec. Set to 0 if no ringers/specs needed");

	g_ringerPassword = CreateConVar("plw_fakepw", DEFAULT_FAKE_PW, "The password that ringers / specs can use to join")
	
	PrintToServer("RGL Player Whitelist loaded");
}

public OnPluginEnd() {
	//CloseHandle(rgl_sid_map);
}

public int DivisionToInt(char div[64]) {
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


public void RGLGetPlayerDataCallback(bool success, const char[] command, System2ExecuteOutput output, any data) {
	int client = data;
	if (!success || output.ExitStatus != 0) {
		// failed to get, they aren't in RGL
		char outdata[256];
		output.GetOutput(outdata, 256);
		PrintToServer("output: %s", outdata);
		KickClient(client, "You are not an RGL player");
	} else {
		
		char steamID[STEAMID_LENGTH];
    	GetClientAuthId(client, AuthId_SteamID64, steamID, STEAMID_LENGTH);

		char outdata[256];
		char div_name_teamid[3][64]; // (div, rgl_name, team id)
		output.GetOutput(outdata, 256);
		ExplodeString(outdata, ",", div_name_teamid, 3, 64);

		PrintToServer("Player %s (RGL div: %s) the server", div_name_teamid[1], div_name_teamid[0]);
    	int div = DivisionToInt(div_name_teamid[0]);
    	PrintToServer("div: %s name: %s teamid: %s", div_name_teamid[0], div_name_teamid[1], div_name_teamid[2]);

		// First layer is checking if they are in the allowed divisions to join
    	if ((div & GetConVarInt(g_rglDivsAllowed)) == 0) {
			KickClient(client, "You are not an RGL player in the currently whitelisted divisions");
			return;
    	}

		// Then check if they follow the correct 'server mode' for joining - scrim, match, general, etc
    	if (RGL_TEAMONLY & GetConVarInt(g_rglMode)) {
			if (StringToInt(div_name_teamid[2]) == GetConVarInt(g_teamID)) {
   	    		PrintToChatAll("Player %s (RGL div: %s) joined the server", div_name_teamid[1], div_name_teamid[0]);
	    		return;
			}
			KickClient(client, "You aren't currently in the team whitelist");
			return;
    	}

    	if (RGL_MODE_ALL & GetConVarInt(g_rglMode)) {
			PrintToChatAll("Player %s (RGL div: %s) joined the server", div_name_teamid[1], div_name_teamid[0]);
			return;
    	}

    	if (RGL_SCRIM & GetConVarInt(g_rglMode) && StringToInt(div_name_teamid[2]) == GetConVarInt(g_scrimID)) {
			PrintToChatAll("Player %s (RGL div: %s) joined the server", div_name_teamid[1], div_name_teamid[0]);
			return;
    	}

    	if (RGL_MATCH & GetConVarInt(g_rglMode) && StringToInt(div_name_teamid[2]) == GetConVarInt(g_matchID)) {
			PrintToChatAll("Player %s (RGL div: %s) joined the server", div_name_teamid[1], div_name_teamid[0]);
			return;
    	}

		// old heuristic for Ringers / Specs
		/*
    	if (ringer_spec_index < GetConVarInt(g_otherPlayerCount)) {
			strcopy(ringer_spec_ids[ringer_spec_index], STEAMID_LENGTH, steamID);
			ringer_spec_index++;
			PrintToChatAll("Player %s (RGL div: %s) joined the server", div_name_tid[1], div_name_tid[0]);		
			return;
    	}
		*/

    	// deny all here
    	KickClient(client, "You don't fit the current server's whitelist rules");
	
	}

}

public void GetRGLUserByID(const String:steamID[], int client) {
	char cmd[256];
	Format(cmd, 256, "python3 /home/tf2server/hlserver/hlserver/tf/addons/sourcemod/plugins/rglplayerdata.py %s", steamID);
	PrintToServer("cmd: %s", cmd);

	System2_ExecuteThreaded(RGLGetPlayerDataCallback, cmd, client);
}

public void OnClientAuthorized(int client, const char[] auth)
{
    char steamID[STEAMID_LENGTH];
    GetClientAuthId(client, AuthId_SteamID64, steamID, STEAMID_LENGTH);

    char password[256];
    GetClientInfo(client, FAKE_PASSWORD_VAR, password, 256);
    PrintToServer("Inputted 'pass': %s", password);

	char fakepw_buf[256];
	GetConVarString(g_ringerPassword, fakepw_buf, 256);

    if (strlen(password) > 0) {
		if (strncmp(password, fakepw_buf, min(strlen(fakepw_buf), password), false) == 0) {
			PrintToServer("Joined via password");
			return;
		}
    }

    // if we aren't using whitelist
    if (GetConVarInt(g_useWhitelist) == 0) {
        PrintToServer("Not using whitelist");
		return;
    }

    GetRGLUserByID(steamID, client); 
}

// TODO http://sourcemod.net/new-api/clients/IsClientSourceTV
// Need to test if STV works with this

public OnClientDisconnect(int client) {
	
	/* Old ringer / spec verification on leaving
	if (GetConVarInt(g_useWhitelist) == 0) {
        return;
    }

    char clientSteamID[STEAMID_LENGTH];
	GetClientAuthId(client, AuthId_SteamID64, clientSteamID, STEAMID_LENGTH);

	for (int i = 0; i < 16; i++) {
		if (strncmp(ringer_spec_ids[i], clientSteamID, STEAMID_LENGTH, false) == 0) {
			// move everyone else backwards 1, lazy and slow but w/e
			for (int j = i; j < ringer_spec_index - 1; j++) {
				strcopy(ringer_spec_ids[j], STEAMID_LENGTH, ringer_spec_ids[j + 1]);
			}
			ringer_spec_index--;
			break;
		}
	}
	*/
}
