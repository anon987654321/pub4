
def scrape_kvinneguiden
  @scraper = "kvinneguiden"

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

def kvinneguiden_samliv_kjaerlighetsrelasjoner
  @brgen_forum = "Kjærlighet, samliv"
  @source_forum = "16"

  scrape_kvinneguiden
end

def kvinneguiden_seksualitet
  @brgen_forum = "Seksualitet"
  @source_forum = "17"

  scrape_kvinneguiden
end

def kvinneguiden_singelliv_dating
  @brgen_forum = "Singel"
  @source_forum = "61"

  scrape_kvinneguiden
end

def kvinneguiden_mat_drikke
  @brgen_forum = "Mat, drikke"
  @source_forum = "12"

  scrape_kvinneguiden
end

def kvinneguiden_reiseliv
  @brgen_forum = "Reise"
  @source_forum = "14"

  scrape_kvinneguiden
end

def kvinneguiden_kosthold_trening_sport
  @brgen_forum = "Trening, kosthold"
  @source_forum = "101"

  scrape_kvinneguiden
end

def kvinneguiden_kropp_helse
  @brgen_forum = "Helse, kosthold"
  @source_forum = "10"

  scrape_kvinneguiden
end

def kvinneguiden_klaer_sko_mote
  @brgen_forum = "Mote, kosmetikk"
  @source_forum = "138"

  scrape_kvinneguiden
end

def kvinneguiden_velvaere_hud_haar_kosmetikk
  @brgen_forum = "Mote, kosmetikk"
  @source_forum = "31"

  scrape_kvinneguiden
end

def kvinneguiden_politikk
  @brgen_forum = "Politikk"
  @source_forum = "1"

  scrape_kvinneguiden
end

def kvinneguiden_barn_familie
  @brgen_forum = "Barn, familie"
  @source_forum = "2"

  scrape_kvinneguiden
end

def kvinneguiden_bryllup
  @brgen_forum = "Bryllup"
  @source_forum = "3"

  scrape_kvinneguiden
end

def kvinneguiden_graviditet_spedbarn
  @brgen_forum = "Gradivitet, spedbarn"
  @source_forum = "6"

  scrape_kvinneguiden
end

def kvinneguiden_hus_hage_hobby
  @brgen_forum = "Hus, hage"
  @source_forum = "8"

  scrape_kvinneguiden
end

def kvinneguiden_kjaeledyr
  @brgen_forum = "Kjæledyr"
  @source_forum = "51"

  scrape_kvinneguiden
end

def kvinneguiden_kultur_litteratur_musikk
  @brgen_forum = "Popkultur, litteratur"
  @source_forum = "11"

  scrape_kvinneguiden
end

def kvinneguiden_tv_film
  @brgen_forum = "TV, film"
  @source_forum = "119"

  scrape_kvinneguiden
end

def kvinneguiden_bil_trafikk
  @brgen_forum = "Bil, trafikk"
  @source_forum = "121"

  scrape_kvinneguiden
end

def kvinneguiden_generelt
  @brgen_forum = "Generelt"
  @source_forum = "5"

  scrape_kvinneguiden
end

def kvinneguiden_vitenskap_historie_natur_miljoe
  @brgen_forum = "Forskning, vitenskap"
  @source_forum = "139"

  scrape_kvinneguiden
end

def kvinneguiden_religion_alternativ_filosofisk
  @brgen_forum = "Religion, spiritualitet"
  @source_forum = "42"

  scrape_kvinneguiden
end

def kvinneguiden_skraablikk_generaliseringer
  @brgen_forum = "Generelt"
  @source_forum = "43"

  scrape_kvinneguiden
end

def kvinneguiden_spraak
  @brgen_forum = "Språk"
  @source_forum = "114"

  scrape_kvinneguiden
end

