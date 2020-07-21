#pragma semicolon 1

#include <sourcemod>
#include <curl>
#define AUTOLOAD_EXTENSIONS
#define REQUIRE_EXTENSIONS

#define min(%1,%2) (((%1) < (%2)) ? (%1) : (%2))

#include "plw_plugin_version"

// barbancle
#define HOME_TEAM_ID 6602

#define FAKE_PASSWORD_VAR "cl_team"
#define DEFAULT_FAKE_PW "ringer"
#define DEFAULT_PASSWORD "pugmodepw"

#define DEFAULT_CHECKER_URL "pootis.org/leagueresolver"

#define STEAMID_LENGTH 32
#define MAX_PASSWORD_LENGTH 255
#define DEFAULT_BUFFER_SIZE 512

#define MAX_DIV_CHAR '7'
#define MAX_DIV_INT 7
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
ConVar g_allowKickedOutput;
ConVar g_pugMode;
ConVar g_leagueResolverURL;

char g_cURLResponseBuffer[1024];
char g_sourcemodPath[400];
char IntToETF2LDivision[5][] = {"Prem", "Division 1", "Division 2", "Division 3", "Division 4"};
char IntToRGLDivision[7][] = {"Invite", "Division 1", "Division 2", "Main", "Intermediate", "Amateur", "Newcomer"};
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

	HookEvent("server_spawn", GetGameDirHook);
	HookEvent("player_connect", ConnectSilencer, EventHookMode_Pre);
	HookEvent("player_disconnect", KickSilencer, EventHookMode_Pre);
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
	PrintToServer("Competitive Player Whitelist loaded");
}

public Action ConnectSilencer(Event event, const char[] name, bool dontBroadcast) {
	SetEventBroadcast(event, true);
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
			
			PrintToServer("reason: %s", disconnectReason);
		}
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

public void ConVarChangeKick(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (strlen(newvalue) != 1 || (newvalue[0] != '0' && newvalue[0] != '1')) {
		PrintToChatAll("[SM]: Invalid plugin mode, setting to default (off)");
		SetConVarString(cvar, "0");
		return;
	}
	int int_newvalue = StringToInt(newvalue);
	int int_oldvalue = StringToInt(oldvalue);
	if (int_newvalue == int_oldvalue) {
		return;
	}
	if (GetConVarBool(g_allowChatMessages))
		PrintToChatAll("[SM]: Kick output mode %s", int_newvalue == 1 ? "enabled" : "disabled");

}

public void ConVarChangePug(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
	if (strlen(newvalue) != 1 || (newvalue[0] != '0' && newvalue[0] != '1')) {
		PrintToChatAll("[SM]: Invalid plugin mode, setting to default (off)");
		SetConVarString(cvar, "0");
		return;
	}
	int int_newvalue = StringToInt(newvalue);
	int int_oldvalue = StringToInt(oldvalue);
	if (int_newvalue == int_oldvalue) {
		return;
	}
	if (int_newvalue == 1) {
		SetConVarString(g_useWhitelist, "0");
		// set to whatever you want server pw to be, this is just a placeholder
		SetConVarString(FindConVar("sv_password"), DEFAULT_PASSWORD);
	}
	if (int_newvalue == 0) {
		SetConVarString(g_useWhitelist, "1");
		SetConVarString(FindConVar("sv_password"), "");
	}
	if (GetConVarBool(g_allowChatMessages))
		PrintToChatAll("[SM]: Pug mode %s", int_newvalue == 1 ? "enabled" : "disabled");
}

public void ConVarChangeEnabled(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
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

public void ConVarChangeBanCheck(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
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

public void ConVarChangeGamemode(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
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

public void ConVarChangeLeagues(ConVar cvar, const char[] oldvalue, const char[] newvalue) {
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
		char split_buffer[MAX_DIV_INT][64];
		int n_divs = ExplodeString(newvalue, ",", split_buffer, MAX_DIV_INT, 64, false);
		for (int i = 0; i < n_divs; i++) {
			if (strlen(split_buffer[i]) != 1) 
				continue;
			if (GetConVarBool(g_allowChatMessages))
				PrintToChatAll("[SM]: %s", cvar == g_rglDivsAllowed ? 
										IntToRGLDivision[(split_buffer[i][0] - '0') - 1] :
										IntToETF2LDivision[(split_buffer[i][0] - '0') - 1]);
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

public void LeagueSuccessHelper(int client, int league) {
	char divisionNameTeamID[3][64]; // (div, rgl_name, team id)
	ExplodeString(g_cURLResponseBuffer, ",", divisionNameTeamID, 3, 64);

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
		if (GetConVarBool(g_allowKickedOutput) && GetConVarBool(g_allowChatMessages))
        		PrintToChatAll("%s player %s tried to join", league == LEAGUE_RGL ? "RGL" : "ETF2L", divisionNameTeamID[1]);
		KickClient(client, "You are not an %s player in the currently whitelisted divisions", league == LEAGUE_RGL ? "RGL" : "ETF2L");
		return;
	}

	if (MODE_TEAMONLY & GetConVarInt(g_serverMode)) {
		if (StringToInt(divisionNameTeamID[2]) == GetConVarInt(g_teamID)) {
   			PrintJoinString(divisionNameTeamID[1], divisionNameTeamID[0], league);
		} else {
			if (GetConVarBool(g_allowKickedOutput) && GetConVarBool(g_allowChatMessages))
				PrintToChatAll("%s player %s tried to join", league == LEAGUE_RGL ? "RGL" : "ETF2L", divisionNameTeamID[1]);
			KickClient(client, "You aren't currently in the team whitelist");
		}
	} else if (MODE_ALL & GetConVarInt(g_serverMode)) {
		PrintJoinString(divisionNameTeamID[1], divisionNameTeamID[0], league);
	} else if (MODE_SCRIM & GetConVarInt(g_serverMode) && (StringToInt(divisionNameTeamID[2]) == GetConVarInt(g_scrimID) || 
														   StringToInt(divisionNameTeamID[2]) == GetConVarInt(g_teamID))) {
		PrintJoinString(divisionNameTeamID[1], divisionNameTeamID[0], league);
	} else if (MODE_MATCH & GetConVarInt(g_serverMode) && (StringToInt(divisionNameTeamID[2]) == GetConVarInt(g_matchID) || 
														   StringToInt(divisionNameTeamID[2]) == GetConVarInt(g_teamID))) {
		PrintJoinString(divisionNameTeamID[1], divisionNameTeamID[0], league);
	} else {
		// deny all here
		if (GetConVarBool(g_allowKickedOutput) && GetConVarBool(g_allowChatMessages))
			PrintToChatAll("%s player %s tried to join", league == LEAGUE_RGL ? "RGL" : "ETF2L", divisionNameTeamID[1]);	
		KickClient(client, "You don't fit the current server's whitelist rules");
	}
}

public bool get_response_success() {
	int comma_index = FindCharInString(g_cURLResponseBuffer, ',', false);
	if (comma_index == -1) {
		return false;
	}
	comma_index = FindCharInString(g_cURLResponseBuffer + comma_index)
	return comma_index != -1;
}

public void ETF2LGetPlayerDataCallback(Handle hCurl, CURLcode code, any data) {
	int client = data;
	if (code != CURLE_OK) {
		char curlError[256];
		curl_easy_strerror(code, curlError, sizeof(curlError));
	} else {
		bool success = get_response_success();
		if (success) {
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

public void setup_curl_request(const String:steamID[], int client, int league) {
	Handle hCurl = curl_easy_init();
	if (hCurl == INVALID_HANDLE) {
		PrintToServer("Invalid CURL handle on setup");
		return;
	}

	curl_easy_setopt_function(hCurl, CURLOPT_WRITEFUNCTION, ReceiveData);

	char local_leagueResolverURL[1024];
	GetConVarString(g_leagueResolverURL, local_leagueResolverURL, sizeof(local_leagueResolverURL));

	char temp_buffer[512];
	Format(temp_buffer, sizeof(temp_buffer), "?steamid=%s&gamemode=%d&league=%s", steamID, GetConVarInt(g_gamemode), league == LEAGUE_RGL ? "RGL" : "ETF2L");
	StrCat(local_leagueResolverURL, temp_buffer, sizeof(temp_buffer));

	curl_easy_setopt_string(hCurl, CURLOPT_URL, local_leagueResolverURL);

	strcopy(g_cURLResponseBuffer, sizeof(g_cURLResponseBuffer), "");

	curl_easy_perform_thread(hCurl, league == LEAGUE_RGL ? RGLGetPlayerDataCallback : ETF2LGetPlayerDataCallback, client);
}

public ReceiveData(Handle handle, const String:buffer[], const bytes, const nmemb) {
	StrCat(g_cURLResponseBuffer, sizeof(g_cURLResponseBuffer), buffer);
	return bytes * nmemb;
}

public void GetETF2LUserByID(const String:steamID[], int client) {
	setup_curl_request(steamID, client, LEAGUE_ETF2L);
}

public void RGLGetPlayerDataCallback(Handle hCurl, CURLcode code, any data) {
	int client = data;
	if (code != CURLE_OK) {
		char curlError[256];
		curl_easy_strerror(code, curlError, sizeof(curlError));
	} else {
		bool success = get_response_success();
		if (success) {
			LeagueSuccessHelper(client, LEAGUE_RGL);
		} else {
			if (GetConVarInt(g_leaguesAllowed) & LEAGUE_ETF2L) {
				char steamID[STEAMID_LENGTH];
				GetClientAuthId(client, AuthId_SteamID64, steamID, STEAMID_LENGTH);
				GetETF2LUserByID(steamID, client);
			} else {
				KickClient(client, "You are not an RGL player");
			}
		}
	}
	CloseHandle(hCurl);
}

public void GetRGLUserByID(const String:steamID[], int client) {
	setup_curl_request(steamID, client, LEAGUE_RGL);
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

