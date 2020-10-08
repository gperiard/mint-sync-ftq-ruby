#!/usr/bin/env ruby

require 'yaml'
require 'mechanize'
require "selenium-webdriver"
require 'interactor'
require 'json'
require 'httparty'

def fetch_ftq_amount(email, password)
    mechanize = Mechanize.new{ |agent|
        agent.follow_meta_refresh = true
    }
    login = mechanize.get("https://www.fondsftq.com/en/particuliers/my-online-account/login")
    form = login.form(:action => "/particuliers/my-online-account/login") 
    form["Email"] = email
    form["Password"] = password
    
    home = form.submit

    return home.at("#FondsFTQ > div > div > div.P--Portefeuille-apercu > div.p__rendement > div.p__rendement-valeur.border-left.valeur-total > p.p__montant.no-margin-bottom").text.strip.delete('^0-9\.')
end

def set_mint_property_amount(email, password, property, value)
    options = Selenium::WebDriver::Chrome::Options.new
    # options.add_argument('--headless')
    # options.add_argument('--no-sandbox')
    # options.add_argument('--disable-dev-shm-usage')
    # options.add_argument('--disable-gpu')
    driver = Selenium::WebDriver.for :chrome, options: options
    wait = Selenium::WebDriver::Wait.new(driver: driver, timeout: 2) # seconds


    driver.get 'https://www.mint.com'

    mechanize = Mechanize.new{ |agent|
        agent.follow_meta_refresh = true
    }

    # driver.manage.all_cookies().each do |c|
    #     mechanize.cookie_jar.add(".intuit.com", c)
    # end

    element = driver.find_element(:link_text => "Sign in")
    element.click()
    sleep(2)
    # wait
    email_input = driver.find_element(:id => "ius-userid")
    email_input.clear()
    email_input.send_keys(email)
    driver.find_element(:id => "ius-password").send_keys(password)
    driver.find_element(:id => "ius-sign-in-submit-btn").submit()

    sleep(5)

    data = driver.find_element(:name => "javascript-user").attribute("value")
    info = JSON.parse(data)
    token = info["token"]
    userId = info["userId"]

    input = '[{"args":{"types":["OTHER_PROPERTY", "UNCLASSIFIED"]},"id": "27036","service": "MintAccountService", "task": "getAccountsSorted"}]'

    cookies = ""
    driver.manage.all_cookies().each do |c|
        cookies += "%s=%s; " % [c[:name], c[:value]] 
    end

    apiKey =  driver.execute_script('return window.MintConfig.browserAuthAPIKey')    

    headers = {
        'accept': 'application/json',
        'cookie': cookies,
    }

    url = "https://mint.intuit.com/bundledServiceController.xevent?legacy=false&token=%s" % token
    response = HTTParty::post(url, :headers => headers, :body => {'input': input})
    accounts = JSON.parse(response.body)

    @ftq = nil

    accounts["response"]["27036"]["response"].each do | account |
        puts account["accountName"]
        if account["accountName"] == property
            @ftq = account
        end
    end

    property_account_url = "https://mint.intuit.com/mas/v1/providers/PFM:%s_%s/accounts/PFM:OtherPropertyAccount:%s_%s" % [
        userId,
        @ftq["fiLoginId"],
        userId,
        @ftq["accountId"],
    ]

    headers = {
        'cookie': cookies,
        'content-type': 'application/json',
        'authorization': 'Intuit_APIKEY intuit_apikey=%s' % apiKey,
    }

    puts property_account_url
    response = HTTParty::patch(property_account_url, :headers => headers, :body => {"name": property, "value": value, "type": "OtherPropertyAccount"}.to_json)    
    puts response.body

end
        
def main()
    config = YAML.load_file(ARGV[0])
    amount = fetch_ftq_amount(config["ftq"]["email"], config["ftq"]["password"])
    puts amount
    set_mint_property_amount(config["mint"]["email"], config["mint"]["password"], config["mint"]["property_label"], amount)
end

main