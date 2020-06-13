import sys
import os
import time
import json
import requests

current_sid = 0

ETF2L_PLAYER_API_URL = "http://api.etf2l.org/player/{}.json"
ETF2L_TEAM_MATCHES_API_URL = "https://api.etf2l.org/team/{}/matches.json"

if __name__ == "__main__":
    # we spawned this process - we gave it this argument guaranteed
    steamid = sys.argv[1]

    resp = requests.get(ETF2L_PLAYER_API_URL.format(steamid))

    resp_json = json.loads(resp.text)

    status = resp_json["status"]["code"]

    if status == 500:
        print("Player not found")
        exit(-1)

    name = resp_json["player"]["name"]
    teams = resp_json["player"]["teams"]
    sixes_team = None

    for team in teams:
        if team["type"] == "6on6":
            sixes_team = team
            break

    if sixes_team is None:
        print("No 6s team")
        exit(-1)

    # This is if we want to only check active ones
    matches_json = requests.get(ETF2L_TEAM_MATCHES_API_URL.format(sixes_team["id"])).text

    if matches_json["matches"] is None:
        print("No active sixes team")
        exit(-1)

    teamid = sixes_team["id"]
    recent_competition = -1
    division = None
    
    for competition in sixes_team["competitions"]:
        if sixes_team["competitions"][competition]["division"]["tier"] is not None:
            if int(competition) > recent_competition:
                recent_competition = int(competition)
                division = sixes_team["competitions"][competition]["division"]["tier"]

    print(",".join([str(division), name, str(teamid)]))
    exit(0)
        