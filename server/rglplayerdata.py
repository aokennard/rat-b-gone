import os
import requests
try:
    from bs4 import BeautifulSoup
except ImportError:
    print("BeautifulSoup not found! Did you pip install it / the requirements?")
    print("Exiting with status 0 so all people are allowed instead of none")
    exit(0)

# 1 = hl, 2 = 6v, 4 = yomps tourney
RGL_SEARCH_LEAGUE_TABLE = {"2" : "40", "7v7" : "1", "6v6NR" : "37", "1" : "24", "4" : "54"}
RGL_LEAGUE_STRING_ID_MAP = {"Prolander" : "7v7", "NR Sixes" : "6v6NR", "Highlander" : "1", "Trad. Sixes" : "2", "Yomps Tourney" : "4"}
RGL_DIVS_LIST = ["banned", "Invite", "Div-1", "Div-2", "Main", "Intermediate", "Amateur", "Newcomer", "Admin Placement"]
RGL_SEARCH_URL = "https://rgl.gg/Public/PlayerProfile.aspx?p={}&r={}"

'''
    Input: the div that contains all relevant player data content: name, team tables by gamemode, trophies
    Output: a pair of (user's name on the page, whether use is currently banned)
'''

def get_name_banstatus_from_div(div):
    try:
        timeline = div.find("h1")
        name_span = timeline.find(id="ContentPlaceHolder1_Main_lblPlayerName")
        # slightly improved ban verification
        ban = False
        div_banned = div.find(id="ContentPlaceHolder1_Main_divBanned")
        if div_banned and div_banned.find("h3") and div_banned.find("h3").text == "Player is banned from RGL":
            ban = True
        return name_span.text, ban
    # could just check if each return is None but that looks a bit worse
    except Exception:
        return None, None

'''
    Input: a string that contains relevant gamemode / league data
    The format I've observed is <gamemode type> - RGL - <region / gamemode specifics>
    This function is pretty catered to NA only HL/6s/Prolander, need to expand if I want to support more modes
    Output: the relevant identifier key in 'RGL_SEARCH_LEAGUE_TABLE' which uniquely identifies a gamemode
''' 

def get_gamemode_from_string(gamemode_str):
    
    gamemode, rgl, region = gamemode_str.split('-')
    gamemode = gamemode.rstrip()
    region = region.lstrip()

    # ignore one day cups or weird stuff - also TODO cleanup later, make easier for adding in cups or tourneys, etc

    if gamemode == "Prolander":
        if region == "North America":
            return RGL_LEAGUE_STRING_ID_MAP[gamemode]
    if gamemode == "Highlander":
        if region == "NA Highlander":
            return RGL_LEAGUE_STRING_ID_MAP[gamemode]
    if gamemode == "Trad. Sixes":
        if region == "NA Traditional Sixes":
            return RGL_LEAGUE_STRING_ID_MAP[gamemode]
        if region == "yomps' Family Fundraiser":
            return RGL_LEAGUE_STRING_ID_MAP["Yomps Tourney"]
    if gamemode == "NR Sixes":
        if region == "No Restriction Sixes":
            return RGL_LEAGUE_STRING_ID_MAP[gamemode]
    return None

'''
    Input: a table Tag structure, which contains information on one players history in that gamemode.
    Output: a pair of (the division of the most recent active team the player's on for table's gamemode, the id of said team)
'''

def get_div_teamid_from_table(table, use_most_recent_team):
    division = None
    team_id = None
    try:
        # first is a header
        rows = table.find_all("tr")[1:] 
        #print(rows)
        # if it's green then it's active
        if use_most_recent_team or (rows[0].has_attr('style') and rows[0]['style'] == 'background-color: #B9DFCD'):
            most_recent_cols = rows[0].find_all('td')
            # I think for now all I care about is the first one, but some stuff may be placeholders for later
            division = most_recent_cols[1].text.strip()
            # yikes but we're in a try-except
            team_id = most_recent_cols[2].find('a')['href'].split('?t=')[1]
    except Exception:
        pass

    return division, team_id

'''
    Input:
        parameters_dict: a MultiDict from Flask containing ConVar data from a server
    Output:
        a 3-tuple of (division of joining player, RGL alias, team id for gamemode we're looking for)
        alternatively: ("", RGL alias, "") when no team found
                       ("banned", RGL alias, "banned") on an RGL banned steamid
                       error messages when player not in RGL, alias not found, no teams for the gamemode we're looking for
'''


def get_rgl_data(parameters_dict, use_recent_team=False):

    steamid = parameters_dict.get('steamid')
    gamemode = parameters_dict.get('gamemode')
    # get and parse the player's page
    try:
        request = requests.get(RGL_SEARCH_URL.format(steamid, RGL_SEARCH_LEAGUE_TABLE[gamemode]))
    except Exception:
        return "requests exception"
    if not request or request.status_code != 200:
        return "request failure"

    soup = BeautifulSoup(request.content, features="lxml")
    if not soup:
        return "soup fail"

    div_head = soup.find("div", {"class":"col-sm-9"})
    if not div_head:
        return "Page malformed or edge case found for pages"

    div_name = div_head.find("div", {"class":"page-header text-center"})
    if not div_name:
        return "Page malformed or edge case found for pages"

    # verify they exist

    placeholder = div_head.find(id="ContentPlaceHolder1_Main_hMessage")
    if not placeholder or placeholder.text.lstrip() == "Player does not exist in RGL":
        return "Player not found"

    name, ban_status = get_name_banstatus_from_div(div_name)
    if name == None:
        return "Name not found"
    if ban_status:
        if parameters_dict.get('allowbans'):
            return ",".join(["banned", name, "banned"])
        return "banned player"

    # h3, hr, table is the format repeated
    league_types = div_head.find_all("h3")
    league_tables = div_head.find_all("table")

    if league_tables is None or league_types is None:
        return "Unknown user profile format"

    division = None
    player_team_id = None

    # assume league tables are contiguous, so increment for each table we see to index into list of tables 
    # I did this instead of zip incase of mismatched number of h3/tables, which can vary if someone is banned or has other stuff thats non-standard going on
    league_table_index = 0

    # There is probably a more elegant way to iterate over multiple grouped (h3, hr, table) tags, but this works for now
    for league_type_tag in league_types:
        league_type_span = league_type_tag.find("span")
        if not league_type_span:
            # Ignore tag if its the probation tag
            if league_type_tag.text != "Player is under probation":
                league_table_index += 1
            continue
        # located a table of some gamemode
        if league_type_span['id'] and league_type_span['id'].startswith("ContentPlaceHolder1_Main_rptLeagues_lblLeagueName"):
            league_type_string = league_type_span.text
            if not league_type_string:
                league_table_index += 1
                continue
            gamemode_str = get_gamemode_from_string(league_type_string)
            # process string to determine if correct gamemode
            if gamemode == gamemode_str:
                league_table = league_tables[league_table_index]
                division, player_team_id = get_div_teamid_from_table(league_table, use_recent_team)
                break
            
            league_table_index += 1
    else:
        return "Couldn't find correct gamemode"

    # We found you, but no active team I guess
    if division is None or player_team_id is None:
        division = ""
        player_team_id = ""

    player_data = ",".join([division, name, player_team_id])

    if division not in list(map(lambda x: RGL_DIVS_LIST[int(x)], parameters_dict.get('rgldivs').split(","))):
        return "invalid div"

    print(player_data)
    mode = int(parameters_dict.get('mode'))

    if parameters_dict.get('teamid') == player_team_id:
        return player_data
    
    if mode & 1 and parameters_dict.get('scrimid') == player_team_id:
        return player_data

    if mode & 2 and parameters_dict.get('matchid') == player_team_id:
        return player_data

    if mode & 4:
        return player_data

    return "invalid player"
