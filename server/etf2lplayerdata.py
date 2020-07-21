import time
import json
import requests

current_sid = 0

ETF2L_PLAYER_API_URL = "http://api.etf2l.org/player/{}.json"
ETF2L_TEAM_MATCHES_API_URL = "https://api.etf2l.org/team/{}/matches.json"

GAMEMODE_MAP = {'1' : 'Highlander', '2' : '6on6'}

def get_etf2l_data(steamid, gamemode):

    resp = requests.get(ETF2L_PLAYER_API_URL.format(steamid))

    resp_json = json.loads(resp.text)

    status = resp_json["status"]["code"]

    if status == 500:
        return "Player not found"

    name = resp_json["player"]["name"]
    teams = resp_json["player"]["teams"]
    bans = resp_json["player"]["bans"]

    if bans:
        current_time = time.time()
        for ban in bans:
            if ban["end"] > current_time:
                return ",".join(["banned", name, "banned"])

    comp_team = None

    if teams is None:
        return "No teams"

    for team in teams:
        if team["type"] == GAMEMODE_MAP[gamemode]:
            comp_team = team
            break

    if comp_team is None:
        return "No team of gamemode type"

    # This is if we want to only check active ones
    #matches_json = json.loads(requests.get(ETF2L_TEAM_MATCHES_API_URL.format(comp_team["id"])).text)

    #if matches_json["matches"] is None or comp_team["competitions"] is None:
    #    print("No active team")
    #    exit(-1)

    teamid = comp_team["id"]
    recent_competition = -1
    division = None

    # TODO more testing, I'm sure this is KeyError galore 
    for competition in comp_team["competitions"]:
        if comp_team["competitions"][competition]["division"]["tier"] is not None:
            if int(competition) > recent_competition:
                recent_competition = int(competition)
                division = comp_team["competitions"][competition]["division"]["tier"]

    return ",".join([str(division), name, str(teamid)])