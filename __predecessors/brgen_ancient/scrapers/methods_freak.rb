
def scrape_freak
  @scraper = "freak"

  # -------------------------------------------------

  puts "Running `#{ @scraper }`: `#{ @source_forum }`..."

  # -------------------------------------------------

  @pages = "1"
  @min_views = "1000"
  @min_replies = "0"

  # -------------------------------------------------

  @config_file = "#{ @home }/scrapers/#{ @scraper }/spyder_config.js"
  @log_file = "#{ @home }/log/spyder_#{ @scraper }.log"

  # -------------------------------------------------

  system ". #{ @apikey } && #{ @spyder } #{ @scraper } --config #{ @config_file } --brgen_forum '#{ @brgen_forum }' --source_forum #{ @source_forum } --variance #{ @variance } --pages #{ @pages } --min_views #{ @min_views } --min_replies #{ @min_replies } --effects #{ @effects_file } > #{ @log_file }"
end

# -------------------------------------------------

def freak_rusmidler
  @brgen_forum = "Rus"
  @source_forum = "70"

  scrape_freak
end

def freak_samfunn_etikk_politikk
  @brgen_forum = "Politikk"
  @source_forum = "82"

  scrape_freak
end

def freak_reise
  @brgen_forum = "Reise"
  @source_forum = "197"

  scrape_freak
end

def freak_undergrunn
  @brgen_forum = "Undergrunn"
  @source_forum = "99"

  scrape_freak
end

def freak_diskusjon
  @brgen_forum = "Generelt"
  @source_forum = "45"

  scrape_freak
end

def freak_vitenskap_forskning
  @brgen_forum = "Forskning, vitenskap"
  @source_forum = "173"

  scrape_freak
end

def freak_film_tv
  @brgen_forum = "TV, film"
  @source_forum = "110"

  scrape_freak
end

def freak_boeker
  @brgen_forum = "Popkultur, litteratur"
  @source_forum = "195"

  scrape_freak
end

def freak_musikk
  @brgen_forum = "Musikk"
  @source_forum = "60"

  scrape_freak
end

def freak_grafitti_street_art
  @brgen_forum = "Grafitti, gatekunst"
  @source_forum = "187"

  scrape_freak
end

