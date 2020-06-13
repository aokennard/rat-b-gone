# the sole purpose is to get (div, name, current team) from RGL
import sys
import os
import time
import shutil

from selenium import webdriver
from selenium.webdriver.common.by import By

RGL_SEARCH_LEAGUE_TABLE = {"6v6" : "40", "7v7" : "1", "6v6NR" : "37", "9v9" : "24"}
RGL_SEARCH_URL = "https://rgl.gg/public/playersearch.aspx?r="
INPUT_ID_STRING = "txtSearchPlayer"
INPUT_BUTTON_ID_STRING = "btnSearchPlayer"
NOT_FOUND_ELEM_ID = "ContentPlaceHolder1_lblMessage"

WAIT_FOR_TIMEOUT = 3

current_sid = 0

def wait_for_condition(condition_function):
    start = time.time()
    end = start + WAIT_FOR_TIMEOUT
    while time.time() < end:
        if condition_function():
            return True
        else:
            time.sleep(0.1)
    raise TimeoutError('Timedout waiting for function: {}'.format(condition_function.__name__))

# wrapper class for waiting until a new page is loaded
class PageLoadWrapper(object):
    def __init__(self, browser):
        self.browser = browser

    def __enter__(self):
        self.old_page = self.browser.find_element_by_tag_name('html')

    def page_has_loaded(self):
        new_page = self.browser.find_element_by_tag_name('html')
        # either there is red text saying theres no player found, or there is new content
        # TODO make this less awful
        player_not_found_elem = driver.find_element_by_id(NOT_FOUND_ELEM_ID).get_attribute('style')
        player_found_elem = driver.find_element_by_xpath('//tbody[.//tr[.//th[text()="Name"]]]')
        return player_not_found_elem or player_found_elem

    def __exit__(self, *_):
        wait_for_condition(self.page_has_loaded)

if __name__ == "__main__":
    # we spawned this process - we gave it this argument guaranteed
    steamid = sys.argv[1]
    current_sid = steamid

    # TODO support for other webdrivers
    # this is built to run on a VPS without X forwarding - also it runs faster headless
    cr_options = webdriver.ChromeOptions()
    cr_options.add_argument('--headless')
    cr_options.add_argument('--no-sandbox')
    
    chromedriver_path = shutil.which('chromedriver')
    driver = webdriver.Chrome(executable_path=chromedriver_path, chrome_options=cr_options, service_args=['--verbose', '--log-path=/tmp/chromedriver.log'])
    driver.get(RGL_SEARCH_URL + RGL_SEARCH_LEAGUE_TABLE["6v6"])

    # locate the place to put ID

    driver.execute_script("document.getElementById('{}').setAttribute('value', '{}')".format(INPUT_ID_STRING, steamid))

    # click button to refresh page

    button = driver.find_element_by_id(INPUT_BUTTON_ID_STRING)
    with PageLoadWrapper(driver):
        button.click()

    # if they arent in RGL - there's a better way of doing this but i'm lazy
   
    try: 
        table_tag = driver.find_element_by_xpath('//tbody[.//tr[.//th[text()="Name"]]]')
    except Exception:
        table_tag = None

    if not table_tag:
        print("No player with id found")
        exit(-1)
    else:
        # parsing to find relevant info - name, team, division
        tbody_data = driver.find_element_by_xpath('//tbody[.//tr[.//th[text()="Name"]]]')
        cols = tbody_data.find_elements(By.TAG_NAME, "tr")[1].find_elements(By.TAG_NAME, "td")
        # ugly but whatever, it's functional - can fix later
        name = cols[2].find_elements(By.TAG_NAME, "a")[1].text
        team = cols[3].find_elements(By.TAG_NAME, "a")[0].get_attribute('href').split("=")[1]
        div = cols[4].find_elements(By.TAG_NAME, "a")[0].text
        print(",".join([div, name, team]))
        exit(0)






