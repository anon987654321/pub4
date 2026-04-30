
def scrape_finnjobs
  @scraper = "finnjobs"

  # -------------------------------------------------

  puts "Running `#{ @scraper }`: `#{ @occupation }`..."

  # -------------------------------------------------

  # Override `@variance` from `shared_settings.rb`

  @variance = "90000"

  # -------------------------------------------------

  @pages = "2"

  # -------------------------------------------------

  @config_file = "#{ @home }/scrapers/#{ @scraper }/spyder_config.js"
  @log_file = "#{ @home }/log/spyder_#{ @scraper }.log"

  # -------------------------------------------------

  system ". #{ @apikey } && #{ @spyder } #{ @scraper } --config #{ @config_file } --brgen_forum '#{ @brgen_forum }' --occupation '#{ @occupation }' --variance #{ @variance } --pages #{ @pages } --effects #{ @effects_file } > #{ @log_file }"
end

# -------------------------------------------------

def finnjobs_barnehage
  @brgen_forum = "Barnehage"
  @occupation = "Barnehage"

  scrape_finnjobs
end

def finnjobs_butikkansatt
  @brgen_forum = "Butikkansatt"
  @occupation = "Butikkansatt"

  scrape_finnjobs
end

def finnjobs_forskning_stipendiat
  @brgen_forum = "Forskning, stipendiat"
  @occupation = "Forskning/Stipendiat"

  scrape_finnjobs
end

def finnjobs_kontor_administrasjon
  @brgen_forum = "Kontor, administrasjon"
  @occupation = "Kontor og administrasjon"

  scrape_finnjobs
end

def finnjobs_it_utvikling
  @brgen_forum = "IT-utvikling"
  @occupation = "IT utvikling"

  scrape_finnjobs
end

def finnjobs_ingenioer
  @brgen_forum = "Ingeniør"
  @occupation = "Ingeniør"

  scrape_finnjobs
end

def finnjobs_håndverker
  @brgen_forum = "Håndverker"
  @occupation = "Håndverker"

  scrape_finnjobs
end

def finnjobs_helsepersonell
  @brgen_forum = "Helsepersonell"
  @occupation = "Helsepersonell"

  scrape_finnjobs
end

def finnjobs_konsulent
  @brgen_forum = "Konsulent"
  @occupation = "Konsulent"

  scrape_finnjobs
end

def finnjobs_kundeservice
  @brgen_forum = "Kundeservice"
  @occupation = "Kundeservice"

  scrape_finnjobs
end

def finnjobs_prosjektledelse
  @brgen_forum = "Prosjektledelse"
  @occupation = "Prosjektledelse"

  scrape_finnjobs
end

def finnjobs_salg
  @brgen_forum = "Salg"
  @occupation = "Salg"

  scrape_finnjobs
end

def finnjobs_konsulent
  @brgen_forum = "Konsulent, veileder"
  @occupation = "Rådgivning"

  scrape_finnjobs
end

def finnjobs_renhold
  @brgen_forum = "Renhold"
  @occupation = "Renhold"

  scrape_finnjobs
end

def finnjobs_logistikk_lager
  @brgen_forum = "Logistikk, lager"
  @occupation = "Logistikk og lager"

  scrape_finnjobs
end

def finnjobs_lege
  @brgen_forum = "Lege"
  @occupation = "Lege"

  scrape_finnjobs
end

def finnjobs_ledelse
  @brgen_forum = "Ledelse"
  @occupation = "Ledelse"

  scrape_finnjobs
end

def finnjobs_oekonomi_regnskap
  @brgen_forum = "Økonomi, regnskap"
  @occupation = "Økonomi og regnskap"

  scrape_finnjobs
end

def finnjobs_undervisning_pedagogikk
  @brgen_forum = "Undervisning, pedagogikk"
  @occupation = "Undervisning og pedagogikk"

  scrape_finnjobs
end

def finnjobs_sykepleier
  @brgen_forum = "Sykepleier"
  @occupation = "Sykepleier"

  scrape_finnjobs
end

