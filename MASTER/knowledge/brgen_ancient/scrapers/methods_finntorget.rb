
def scrape_finntorget
  @scraper = "finntorget"

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

def finntorget_utstyr_bil_baat_mc
  @brgen_forum = "Bil, båt, MC"
  @category = "90"

  scrape_finntorget
end

def finntorget_dyr_utstyr
  @brgen_forum = "Dyr, utstyr"
  @category = "77"

  scrape_finntorget
end

def finntorget_klaer_kosmetikk_accessoirer
  @brgen_forum = "Klær, sko, tilbehør"
  @category = "71"

  scrape_finntorget
end

def finntorget_moebler_interioer
  @brgen_forum = "Møbler, interiør"
  @category = "78"

  scrape_finntorget
end

def finntorget_foreldre_barn
  @brgen_forum = "Foreldre, barn"
  @category = "68"

  scrape_finntorget
end

def finntorget_hobby_fritid
  @brgen_forum = "Hobby, fritid"
  @category = "86"

  scrape_finntorget
end

def finntorget_hus_hage
  @brgen_forum = "Hus, hage"
  @category = "67"

  scrape_finntorget
end

def finntorget_elektronikk_hvitevarer
  @brgen_forum = "Elektronikk, hvitevarer"
  @category = "93"

  scrape_finntorget
end

def finntorget_sport_friluftsliv
  @brgen_forum = "Sport, treningsutstyr"
  @category = "69"

  scrape_finntorget
end

def finntorget_naeringsvirksomhet
  @brgen_forum = "Næringsvirksomhet"
  @category = "91"

  scrape_finntorget
end

