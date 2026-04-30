
def scrape_visitbergen
  @scraper = "visitbergen"

  # -------------------------------------------------

  puts "Running `#{ @scraper }`: `#{ @category }/#{ @subcategory }`..."

  # -------------------------------------------------

  @days = "#{ rand(15..50) }"

  # -------------------------------------------------

  @config_file = "#{ @home }/scrapers/#{ @scraper }/spyder_config.js"
  @log_file = "#{ @home }/log/spyder_#{ @scraper }.log"

  # -------------------------------------------------

  system ". #{ @apikey } && #{ @spyder } #{ @scraper } --config #{ @config_file } --brgen_forum '#{ @brgen_forum }' --category '#{ @category }' --subcategory '#{ @subcategory }' --days #{ @days } --variance #{ @variance } --effects #{ @effects_file } > #{ @log_file }"
end

# -------------------------------------------------

def visitbergen_hva_skjer_konserter
  @brgen_forum = "Konserter, fester"
  @category = "hva-skjer"
  @subcategory = "1-1219"

  scrape_visitbergen
end

def visitbergen_hva_skjer_festivaler
  @brgen_forum = "Konserter, fester"
  @category = "hva-skjer"
  @subcategory = "1-1220"

  scrape_visitbergen
end

def visitbergen_hva_skjer_revy_teater
  @brgen_forum = "Dans, drama"
  @category = "hva-skjer"
  @subcategory = "1-1221"

  scrape_visitbergen
end

def visitbergen_hva_skjer_barn_familie
  @brgen_forum = "Barn, familie"
  @category = "hva-skjer"
  @subcategory = "1-1222"

  scrape_visitbergen
end

def visitbergen_hva_skjer_idrett
  @brgen_forum = "Sport, idrett"
  @category = "hva-skjer"
  @subcategory = "1-1223"

  scrape_visitbergen
end

def visitbergen_utstillinger
  @brgen_forum = "Utstillinger"
  @category = "hva-skjer"
  @subcategory = "1-1224"

  scrape_visitbergen
end

def visitbergen_hva_skjer_senior
  @brgen_forum = "Senior"
  @category = "hva-skjer"
  @subcategory = "1-1223"

  scrape_visitbergen
end

# -------------------------------------------------

def visitbergen_servering_nattklubber
  @brgen_forum = "Utesteder"
  @category = "servering"
  @subcategory = "Nattklubber"

  scrape_visitbergen
end

def visitbergen_servering_barer_puber
  @brgen_forum = "Utesteder"
  @category = "servering"
  @subcategory = "Barer--Puber"

  scrape_visitbergen
end

def visitbergen_servering_restauranter
  @brgen_forum = "Restauranter, kaféer"
  @category = "servering"
  @subcategory = "Restauranter"

  scrape_visitbergen
end

def visitbergen_servering_cafe_konditori
  @brgen_forum = "Restauranter, kaféer"
  @category = "servering"
  @subcategory = "Cafe-og-konditori"

  scrape_visitbergen
end

# -------------------------------------------------

def visitbergen_aktiviteter_guidede_turer
  @brgen_forum = "Aktiviteter"
  @category = "AKTIVITETER"
  @subcategory = "Guidede-turer1"

  scrape_visitbergen
end

def visitbergen_aktiviteter_sport_friluft
  @brgen_forum = "Sport, idrett"
  @category = "AKTIVITETER"
  @subcategory = "Sports-og-friluftsaktiviteter"

  scrape_visitbergen
end

