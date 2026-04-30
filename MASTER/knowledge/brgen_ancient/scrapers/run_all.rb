
# Scrapes infinitely and randomly

# Launches on reboot from `config/schedule.rb`

require_relative "run_all_shared_settings.rb"

require_relative "methods_cheezburger.rb"
require_relative "methods_visitbergen.rb"
require_relative "methods_kvinneguiden.rb"
require_relative "methods_diskusjon.rb"
require_relative "methods_freak.rb"
require_relative "methods_finnhousing.rb"
require_relative "methods_finnjobs.rb"
require_relative "methods_finntorget.rb"

scrapers = {

  # Probabilities ranging from 0.0 to 1.0

  0.5 => [
    method(:cheezburger_failblog_after12),
    method(:cheezburger_failblog_autocowrecks),
    method(:cheezburger_failblog_datingfails),
    method(:cheezburger_failblog_failnation),
    method(:cheezburger_failblog_failbooking),
    method(:cheezburger_failblog_musicfails),
    method(:cheezburger_failblog_parentingfails),
    method(:cheezburger_failblog_poorlydressed),
    method(:cheezburger_failblog_schooloffail),
    method(:cheezburger_failblog_hackedirl),
    method(:cheezburger_failblog_cringe),
    method(:cheezburger_memebase_artoftrolling),
    method(:cheezburger_memebase_senorgif)
  ],

  # -------------------------------------------------

  0.3 => [
    method(:visitbergen_hva_skjer_konserter),
    method(:visitbergen_hva_skjer_festivaler),
    method(:visitbergen_hva_skjer_revy_teater),
    method(:visitbergen_hva_skjer_barn_familie),
    method(:visitbergen_hva_skjer_store_byarrangement),
    method(:visitbergen_hva_skjer_utstillinger),
    method(:visitbergen_hva_skjer_senior),

    # -------------------------------------------------

    method(:kvinneguiden_samliv_kjaerlighetsrelasjoner),
    method(:kvinneguiden_seksualitet),
    method(:kvinneguiden_singelliv_dating),
    method(:kvinneguiden_mat_drikke),
    method(:kvinneguiden_reiseliv),
    method(:kvinneguiden_kosthold_trening_sport),
    method(:kvinneguiden_kropp_helse),
    method(:kvinneguiden_klaer_sko_mote),
    method(:kvinneguiden_velvaere_hud_haar_kosmetikk),
    method(:kvinneguiden_politikk),

    # -------------------------------------------------

    method(:diskusjon_skole_leksehjelp),
    method(:diskusjon_humor),
    method(:diskusjon_helse),
    method(:diskusjon_samliv_relasjoner),
    method(:diskusjon_teknologi_vitenskap),
    method(:diskusjon_seksualitet)
  ],

  # -------------------------------------------------

  0.2 => [
    method(:cheezburger_icanhas_squee),

    # -------------------------------------------------

    method(:finnhousing_nye_boliger),
    method(:finnhousing_bolig_til_salgs),
    method(:finnhousing_bolig_til_leie),
    method(:finnhousing_hybler_bofellesskap),

    # -------------------------------------------------

    method(:finnjobs_barnehage),
    method(:finnjobs_butikkansatt),
    method(:finnjobs_forskning_stipendiat),
    method(:finnjobs_kontor_administrasjon),
    method(:finnjobs_it_utvikling),
    method(:finnjobs_ingenioer),
    method(:finnjobs_håndverker),
    method(:finnjobs_helsepersonell),
    method(:finnjobs_konsulent),
    method(:finnjobs_kundeservice),
    method(:finnjobs_prosjektledelse),
    method(:finnjobs_salg),
    method(:finnjobs_konsulent),
    method(:finnjobs_renhold),
    method(:finnjobs_logistikk_lager),
    method(:finnjobs_lege),
    method(:finnjobs_ledelse),
    method(:finnjobs_oekonomi_regnskap),
    method(:finnjobs_undervisning_pedagogikk),
    method(:finnjobs_sykepleier),

    # -------------------------------------------------

    method(:visitbergen_aktiviteter_guidede_turer),
    method(:visitbergen_aktiviteter_sport_friluft)
  ],

  # -------------------------------------------------

  0.1 => [
    method(:visitbergen_servering_nattklubber),
    method(:visitbergen_servering_barer_puber),
    method(:visitbergen_servering_restauranter),
    method(:visitbergen_servering_cafe_konditori),

    # -------------------------------------------------

    method(:freak_rusmidler),
    method(:freak_samfunn_etikk_politikk),
    method(:freak_reise),
    method(:freak_undergrunn),
    method(:freak_diskusjon),
    method(:freak_vitenskap_forskning),
    method(:freak_film_tv),
    method(:freak_boeker),
    method(:freak_musikk),
    method(:freak_grafitti_street_art),

    # -------------------------------------------------

    method(:kvinneguiden_barn_familie),
    method(:kvinneguiden_bryllup),
    method(:kvinneguiden_graviditet_spedbarn),
    method(:kvinneguiden_hus_hage_hobby),
    method(:kvinneguiden_kjaeledyr),
    method(:kvinneguiden_kultur_litteratur_musikk),
    method(:kvinneguiden_tv_film),
    method(:kvinneguiden_bil_trafikk),
    method(:kvinneguiden_generelt),
    method(:kvinneguiden_vitenskap_historie_natur_miljoe),
    method(:kvinneguiden_religion_alternativ_filosofisk),
    method(:kvinneguiden_skraablikk_generaliseringer),
    method(:kvinneguiden_spraak),

    # -------------------------------------------------

    method(:diskusjon_fotografering),
    method(:diskusjon_bilderedigering_programvare),
    method(:diskusjon_forsvaret),
    method(:diskusjon_film),
    method(:diskusjon_tv),
    method(:diskusjon_musikk),
    method(:diskusjon_litteratur),
    method(:diskusjon_spraak),
    method(:diskusjon_bil),
    method(:diskusjon_trafikk),
    method(:diskusjon_familie_barn),
    method(:diskusjon_politikk_samfunn),
    method(:diskusjon_religion_filosofi_livssyn),
    method(:diskusjon_oekonomi),
    method(:diskusjon_fotball),
    method(:diskusjon_vintersport),
    method(:diskusjon_annen_sport_idrett),
    method(:diskusjon_trening_kosthold),

    # -------------------------------------------------

    method(:finntorget_utstyr_bil_baat_mc),
    method(:finntorget_dyr_utstyr),
    method(:finntorget_klaer_kosmetikk_accessoirer),
    method(:finntorget_moebler_interioer),
    method(:finntorget_foreldre_barn),
    method(:finntorget_hobby_fritid),
    method(:finntorget_hus_hage),
    method(:finntorget_elektronikk_hvitevarer),
    method(:finntorget_sport_friluftsliv),
    method(:finntorget_naeringsvirksomhet)
  ]
}

# -------------------------------------------------

# Independent probabilities, ie. not requiring the sum total of 1.0

probability_bottom = 0.0

scrapers_probabalized = scrapers.each_with_object({}) do |(probability, group), range|
  probability_top = probability_bottom + probability
  range[(probability_bottom...probability_top)] = group
  probability_bottom = probability_top
end

# -------------------------------------------------

previous_scraper = nil

while true
  random = Kernel.rand

  scrapers_probabalized.each do |range, scraper|
    if range.include?(random)
      current_scraper = scraper.sample

      # Make sure scrapers aren't repeated consecutively

      unless previous_scraper == current_scraper
        current_scraper.call

        # Wait 20-60 minutes before moving onto next

        time = rand(1200..3600)

        puts "Sleeping #{ time } seconds..."
        sleep time

        # Update check

        previous_scraper = current_scraper
      end
    end
  end
end

