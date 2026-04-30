
def scrape_finnhousing
  @scraper = "finnhousing"

  # -------------------------------------------------

  puts "Running `#{ @scraper }`: `#{ @category }`..."

  # -------------------------------------------------

  # Override `@variance` from `shared_settings.rb`

  @variance = "90000"

  # -------------------------------------------------

  @pages = "2"

  # -------------------------------------------------

  @config_file = "#{ @home }/scrapers/#{ @scraper }/spyder_config.js"
  @log_file = "#{ @home }/log/spyder_#{ @scraper }.log"

  # -------------------------------------------------

  system ". #{ @apikey } && #{ @spyder } #{ @scraper } --config #{ @config_file } --brgen_forum '#{ @brgen_forum }' --category '#{ @category }' --variance #{ @variance } --pages #{ @pages } --effects #{ @effects_file } > #{ @log_file }"
end

# -------------------------------------------------

def finnhousing_nye_boliger
  @brgen_forum = "Nye boliger"
  @category = "realestate/newbuildings/browse1"

  scrape_finnhousing
end

def finnhousing_bolig_til_salgs
  @brgen_forum = "Bolig til salgs"
  @category = "realestate/homes/browse1"

  scrape_finnhousing
end

def finnhousing_bolig_til_leie
  @brgen_forum = "Bolig til salgs"
  @category = "realestate/lettings/browse1"

  scrape_finnhousing
end

def finnhousing_hybler_bofellesskap
  @brgen_forum = "Hybel, kollektiv"
  @category = "realestate/lettings/bedsit/browse1"

  scrape_finnhousing
end

