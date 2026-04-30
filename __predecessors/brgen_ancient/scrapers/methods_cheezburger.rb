
def scrape_cheezburger
  @scraper = "cheezburger"

  # -------------------------------------------------

  puts "Running `#{ @scraper }`: `#{ @category }`..."

  # -------------------------------------------------

  @pages = "#{ rand(2..8) }"

  # -------------------------------------------------

  @min_likes = "15"

  # Percentage in decimals relative to `@min_likes`

  @max_dislikes = "0.5"

  # -------------------------------------------------

  @brgen_forum = "LOL"

  # -------------------------------------------------

  @config_file = "#{ @home }/scrapers/#{ @scraper }/spyder_config.js"
  @log_file = "#{ @home }/log/spyder_#{ @scraper }.log"

  # -------------------------------------------------

  system ". #{ @apikey } && #{ @spyder } #{ @scraper } --config #{ @config_file } --brgen_forum '#{ @brgen_forum }' --category '#{ @category }' --pages #{ @pages } --variance #{ @variance } --min_likes #{ @min_likes } --max_dislikes #{ @max_dislikes } --effects #{ @effects_file } > #{ @log_file }"
end

# -------------------------------------------------

# FeedBlitz categories: http://goo.gl/lUrGof

def cheezburger_failblog_after12
  @category = "After12-PartyFailsAndAfterHoursHijinks"

  scrape_cheezburger
end

def cheezburger_failblog_autocowrecks
  @category = "AutoCowrecks"

  scrape_cheezburger
end

def cheezburger_failblog_datingfails
  @category = "DatingFails"

  scrape_cheezburger
end

def cheezburger_failblog_failnation
  @category = "FailNation"

  scrape_cheezburger
end

def cheezburger_failblog_failbooking
  @category = "Failbooking"

  scrape_cheezburger
end

def cheezburger_failblog_musicfails
  @category = "MusicFails"

  scrape_cheezburger
end

def cheezburger_failblog_parentingfails
  @category = "ParentingFails"

  scrape_cheezburger
end

def cheezburger_failblog_poorlydressed
  @category = "poorlydressed"

  scrape_cheezburger
end

def cheezburger_failblog_schooloffail
  @category = "schooloffail"

  scrape_cheezburger
end

def cheezburger_failblog_hackedirl
  @category = "HackedIrl"

  scrape_cheezburger
end

def cheezburger_failblog_cringe
  @category = "cringe"

  scrape_cheezburger
end

# -------------------------------------------------

def cheezburger_memebase_artoftrolling
  @category = "AOT"

  scrape_cheezburger
end

def cheezburger_memebase_senorgif
  @category = "SenorGif"

  scrape_cheezburger
end

# -------------------------------------------------

def cheezburger_icanhas_squee
  @category = "DailySquee"

  scrape_cheezburger
end

