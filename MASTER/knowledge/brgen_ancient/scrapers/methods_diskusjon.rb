
def scrape_diskusjon
  @scraper = "diskusjon"

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

def diskusjon_skole_leksehjelp
  @brgen_forum = "Skole, leksehjelp"
  @source_forum = "241"

  scrape_diskusjon
end

def diskusjon_humor
  @brgen_forum = "LOL"
  @source_forum = "73"

  scrape_diskusjon
end

def diskusjon_helse
  @brgen_forum = "Helse, kosthold"
  @source_forum = "335"

  scrape_diskusjon
end

def diskusjon_samliv_relasjoner
  @brgen_forum = "Kjærlighet, samliv"
  @source_forum = "334"

  scrape_diskusjon
end

def diskusjon_teknologi_vitenskap
  @brgen_forum = "Kjærlighet, samliv"
  @source_forum = "182"

  scrape_diskusjon
end

def diskusjon_seksualitet
  @brgen_forum = "Seksualitet"
  @source_forum = "433"

  scrape_diskusjon
end

def diskusjon_fotografering
  @brgen_forum = "Foto"
  @source_forum = "65"

  scrape_diskusjon
end

def diskusjon_bilderedigering_programvare
  @brgen_forum = "Foto"
  @source_forum = "66"

  scrape_diskusjon
end

def diskusjon_forsvaret
  @brgen_forum = "Forsvaret"
  @source_forum = "466"

  scrape_diskusjon
end

def diskusjon_film
  @brgen_forum = "TV, film"
  @source_forum = "199"

  scrape_diskusjon
end

def diskusjon_tv
  @brgen_forum = "TV, film"
  @source_forum = "340"

  scrape_diskusjon
end

def diskusjon_musikk
  @brgen_forum = "Musikk"
  @source_forum = "200"

  scrape_diskusjon
end

def diskusjon_litteratur
  @brgen_forum = "Popkultur, litteratur"
  @source_forum = "210"

  scrape_diskusjon
end

def diskusjon_spraak
  @brgen_forum = "Språk"
  @source_forum = "364"

  scrape_diskusjon
end

def diskusjon_bil
  @brgen_forum = "Bil, trafikk"
  @source_forum = "150"

  scrape_diskusjon
end

def diskusjon_trafikk
  @brgen_forum = "Bil, trafikk"
  @source_forum = "161"

  scrape_diskusjon
end

def diskusjon_familie_barn
  @brgen_forum = "Barn, familie"
  @source_forum = "431"

  scrape_diskusjon
end

def diskusjon_politikk_samfunn
  @brgen_forum = "Politikk"
  @source_forum = "57"

  scrape_diskusjon
end

def diskusjon_religion_filosofi_livssyn
  @brgen_forum = "Religion, spiritualitet"
  @source_forum = "366"

  scrape_diskusjon
end

def diskusjon_oekonomi
  @brgen_forum = "Forbruker, økonomi"
  @source_forum = "518"

  scrape_diskusjon
end

def diskusjon_fotball
  @brgen_forum = "Sport, trening"
  @source_forum = "327"

  scrape_diskusjon
end

def diskusjon_vintersport
  @brgen_forum = "Sport, trening"
  @source_forum = "510"

  scrape_diskusjon
end

def diskusjon_annen_sport_idrett
  @brgen_forum = "Sport, trening"
  @source_forum = "214"

  scrape_diskusjon
end

def diskusjon_trening_kosthold
  @brgen_forum = "Helse, kosthold"
  @source_forum = "328"

  scrape_diskusjon
end

