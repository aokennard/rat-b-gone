# the sole purpose is to get (name, current team, div) from RGL
import sys
import os
import time
from selenium import webdriver
from selenium.webdriver.common.by import By

RGL_SEARCH_URL = "https://rgl.gg/public/playersearch.aspx?r=40"
INPUT_NAME_STRING = "ctl00$ContentPlaceHolder1$txtSearchPlayer"
INPUT_ID_STRING = "txtSearchPlayer"
INPUT_BUTTON_ID_STRING = "btnSearchPlayer"
NOT_FOUND_ELEM = "ContentPlaceHolder1_lblMessage"

current_sid = 0

def wait_for(condition_function):
  start_time = time.time()
  while time.time() < start_time + 3:
    if condition_function():
      return True
    else:
      time.sleep(0.1)
  raise Exception('Timeout waiting for {}'.format(condition_function.__name__))

class wait_for_page_load(object):
  def __init__(self, browser):
    self.browser = browser
  def __enter__(self):
    self.old_page = self.browser.find_element_by_tag_name('html')
  def page_has_loaded(self):
    new_page = self.browser.find_element_by_tag_name('html')
    return driver.find_element_by_id(NOT_FOUND_ELEM).get_attribute('style') or driver.find_element_by_xpath('//tbody[.//tr[.//th[text()="Name"]]]')
  def __exit__(self, *_):
    wait_for(self.page_has_loaded)

if __name__ == "__main__":
    # assume we have an argument
    steamid = sys.argv[1]
    current_sid = steamid
    cr_options = webdriver.ChromeOptions()
    cr_options.add_argument('--headless')
    cr_options.add_argument('--no-sandbox')
    driver = webdriver.Chrome(executable_path=r'/home/tf2server/hlserver/hlserver/tf/addons/sourcemod/chromedriver', chrome_options=cr_options, service_args=['--verbose', '--log-path=/tmp/chromedriver.log'])
    driver.get(RGL_SEARCH_URL)

    # locate the place to put ID

    driver.execute_script("document.getElementById('{}').setAttribute('value', '{}')".format(INPUT_ID_STRING, steamid))
    
    #input_form = driver.find_element_by_id(INPUT_ID_STRING).set_attribute('value', steamid)
    #input_form.value = steamid

    # click button to refresh page

    button = driver.find_element_by_id(INPUT_BUTTON_ID_STRING)
    with wait_for_page_load(driver):
        button.click()

    # if they arent in RGL
   
    try: 
        table_tag = driver.find_element_by_xpath('//tbody[.//tr[.//th[text()="Name"]]]') #.find_element_by_tag_name("strong")
    except Exception:
        table_tag = None

    if not table_tag:
        print("No player with id found")
        exit(-1)
    else:
        tbody_data = driver.find_element_by_xpath('//tbody[.//tr[.//th[text()="Name"]]]')
        cols = tbody_data.find_elements(By.TAG_NAME, "tr")[1].find_elements(By.TAG_NAME, "td")
        name, team, div = (cols[2].find_elements(By.TAG_NAME, "a")[1].text, cols[3].find_elements(By.TAG_NAME, "a")[0].get_attribute('href').split("=")[1], cols[4].find_elements(By.TAG_NAME, "a")[0].text)
        print(",".join([div, name, team]))
        exit(0)







