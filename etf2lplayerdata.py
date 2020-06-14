import sys
import os
import time
import json
import requests

current_sid = 0

ETF2L_PLAYER_API_URL = "http://api.etf2l.org/player/{}.json"
ETF2L_TEAM_MATCHES_API_URL = "https://api.etf2l.org/team/{}/matches.json"

GAMEMODE_MAP = {'1' : 'Highlander', '2' : '6on6'}

if __name__ == "__main__":
    # we spawned this process - we gave it these arguments guaranteed
    steamid = sys.argv[1]
    gamemode = sys.argv[2]

    resp = requests.get(ETF2L_PLAYER_API_URL.format(steamid))

    resp_json = json.loads(resp.text)

    status = resp_json["status"]["code"]

    if status == 500:
        print("Player not found")
        exit(-1)

    name = resp_json["player"]["name"]
    teams = resp_json["player"]["teams"]
    comp_team = None

    for team in teams:
        if team["type"] == GAMEMODE_MAP[gamemode]:
            comp_team = team
            break

    if comp_team is None:
        print("No team of gamemode type")
        exit(-1)

    # This is if we want to only check active ones
    #matches_json = json.loads(requests.get(ETF2L_TEAM_MATCHES_API_URL.format(comp_team["id"])).text)

    #if matches_json["matches"] is None or comp_team["competitions"] is None:
    #    print("No active team")
    #    exit(-1)

    teamid = comp_team["id"]
    recent_competition = -1
    division = None

    for competition in comp_team["competitions"]:
        if comp_team["competitions"][competition]["division"]["tier"] is not None:
            if int(competition) > recent_competition:
                recent_competition = int(competition)
                division = comp_team["competitions"][competition]["division"]["tier"]

    print(",".join([str(division), name, str(teamid)]))
    exit(0)
        