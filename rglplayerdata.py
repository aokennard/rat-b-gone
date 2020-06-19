# the sole purpose is to get (div, name, current team) from RGL
import sys
import os
import time
import shutil
import requests
from bs4 import BeautifulSoup

# 1 = hl, 2 = 6v
RGL_SEARCH_LEAGUE_TABLE = {"2" : "40", "7v7" : "1", "6v6NR" : "37", "1" : "24"}
RGL_LEAGUE_STRING_ID_MAP = {"Prolander" : "7v7", "NR Sixes" : "6v6NR", "Highlander" : "1", "Trad. Sixes" : "2"}
RGL_SEARCH_URL = "https://rgl.gg/Public/PlayerProfile.aspx?p={}&r={}"

current_sid = 0

def get_name_from_div(div):
    try:
        timeline = div.find("h1")
        # may say if banned here?
        name_span = timeline.find(id="ContentPlaceHolder1_Main_lblPlayerName")
        # hacky but functional, TODO better way
        ban = False
        if name_span.find("s") and name_span.find("s").has_attr('style') and name_span.find("s")['style'] == "color: red":
            ban = True
        return name_span.text, ban
    except Exception:
        return None, None

def get_gamemode_from_string(gamemode_str):
    
    gamemode, rgl, region = gamemode_str.split('-')
    gamemode = gamemode.rstrip()
    region = region.lstrip()

    # ignore one day cups or weird stuff - also TODO cleanup later

    if gamemode == "Prolander":
        if region == "North America":
            return RGL_LEAGUE_STRING_ID_MAP[gamemode]
        return None
    if gamemode == "Highlander":
        if region == "HL North America":
            return RGL_LEAGUE_STRING_ID_MAP[gamemode]
        return None
    if gamemode == "Trad. Sixes":
        if region == "NA Traditional Sixes":
            return RGL_LEAGUE_STRING_ID_MAP[gamemode]
        return None
    if gamemode == "NR Sixes":
        if region == "No Restriction Sixes":
            return RGL_LEAGUE_STRING_ID_MAP[gamemode]
        return None
    return None

def get_div_teamid_from_table(table):
    division = None
    team_id = None
    try:
        rows = table.find_all("tr")[1:] # first is a header
        # if it's green then it's active
        if rows[0].has_attr('style') and rows[0]['style'] == 'background-color: #B9DFCD':
            most_recent_cols = rows[0].find_all('td')
            # I think for now all I care about is the first one, but some stuff may be placeholders for later
            division = most_recent_cols[1].text.strip()
            # yikes
            team_id = most_recent_cols[2].find('a')['href'].split('?t=')[1]
    except Exception:
        pass

    return division, team_id

if __name__ == "__main__":
    # we spawned this process - we gave it these arguments guaranteed
    steamid = sys.argv[1]
    gamemode = sys.argv[2]
    current_sid = steamid

    request = requests.get(RGL_SEARCH_URL.format(steamid, RGL_SEARCH_LEAGUE_TABLE[gamemode]))
    soup = BeautifulSoup(request.content, features="lxml")

    div_head = soup.find("div", {"class":"col-sm-9"})

    div_name = div_head.find("div", {"class":"page-header text-center"})

    # verify they exist

    placeholder = div_head.find(id="ContentPlaceHolder1_Main_hMessage")
    if placeholder.text.lstrip() == "Player does not exist in RGL":
        print("Player not found")
        exit(-1)

    name, ban_status = get_name_from_div(div_name)
    if name == None:
        print("Name not found")
        exit(-1)
    if ban_status:
        print(",".join(["banned", name, "banned"]))
        exit(0)

    # h3, hr, table is the format repeated
    h3s = div_head.find_all("h3")
    league_types = h3s # first is just a message, last is ban history, other misc too maybe
    league_tables = div_head.find_all("table")
    division = None
    team_id = None

    # at end of league_types / h3's, there is a banhistory
    league_table_index = 0
    for i, league_type_tag in enumerate(league_types):
        league_type_span = league_type_tag.find("span") #.find("strong").text

        if league_type_span['id'] and league_type_span['id'].startswith("ContentPlaceHolder1_Main_rptLeagues_lblLeagueName"):
            league_type_string = league_type_span.text
            # process string to determine if correct gamemode
            if gamemode == get_gamemode_from_string(league_type_string):
                league_table = league_tables[league_table_index]
                division, team_id = get_div_teamid_from_table(league_table)
                break
            # assume league tables are contiguous
            league_table_index += 1
    else:
        print("Couldn't find correct gamemode")
        exit(-1)

    if division is None:
        division = ""
    if team_id is None:
        team_id = ""
    
    print(",".join([division, name, team_id]))
    exit(0)


   







