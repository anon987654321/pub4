# frozen_string_literal: true

module Bplan
  module Constants
    DATE = "14. juli 2026"
    DATE_ISO = "2026-07-14"
    LANG = "nb"
    FOOTER = "Johann Tepstad &amp; GK Tepstad"
    HTU_CSS = "htu/htu.css"
    LOGO = "htu/bergen.svg"
    BASE_URL = ENV.fetch("BPLAN_BASE_URL", "https://bplan.pub.healthcare").freeze

    GLOBAL_DISCLAIMER = <<~TXT.strip.freeze
      Tall og frister i BPLAN er realistiske estimater for solo-utvikler i Bergen (2026).
      Verifiser alltid på giverens nettside før sending. Ingen garanti for tildeling.
      Boligspor og innovasjonsspor holdes adskilt — ikke dobbelsøk for samme utgift.
    TXT

    # Innovasjon Norge: book rådgiver — ikke masse-e-post selv om brev finnes i manifest.
    INNOVASJON_NO_SENDABLE = false

    MASTER_RAILS_DOC_LINE = <<~TXT.strip.freeze
      MASTER utvikler og forbedrer kode; RAILS/ deployer Rails 8-apper (brgen.no, amber.brgen.no, bsdports.org).
      BPLAN dokumenterer og søker støtte — egen app, ikke en del av RAILS/.
    TXT

    RAILS_APP_PATHS = {
      "brgen" => "RAILS/brgen",
      "amber" => "RAILS/amber",
      "bsdports" => "RAILS/bsdports",
    }.freeze

    APPLICANT = {
      name: "Johann Tepstad",
      org: "PubHealthcare",
      address: "Kanalveien 10, 5068 Bergen",
      web: "www.pub.healthcare",
      email: "bergen@pub.attorney",
      footer: FOOTER,
    }.freeze

    PLAN_META = {
      "master" => "PubHealthcare · Kanalveien 10, 5068 Bergen<br>Innovasjon Norge · SkatteFUNN · direkte kjerne",
      "pub_healthcare" => "pub.healthcare · Bergen<br>Innovasjon Norge · Helse Vest · TRL 4–5",
      "brgen" => "brgen.no · Bergen først<br>RAILS-app · indirekte MASTER-leveranse",
      "amber" => "Amber · mote og sirkulær økonomi<br>RAILS · MASTER-drevet outfit-AI",
      "bsdports" => "OpenBSD · digital suverenitet<br>RAILS · MASTER sikkerhetslag",
      "syre" => "SYRE Footwear · Bergen<br>3D-print · bærekraft · lokal produksjon",
      "norwegian_hedge" => "Norwegian Hedge AS · Bergen<br>Programvare for risikostyring — ikke uregulert fond",
      "ditt_parti" => "Ditt Parti · Bergen og Vestland<br>Civic tech · MASTER oversetter jargon",
      "ilumi_gravferd" => "Ilumi · Bergen og Vestland<br>Sosial innovasjon · fastpris · digital minnebok",
      "pub_attorney" => "pub.attorney · ai.brgen.no<br>HTU-klar dokumentasjon · åpen juridisk veiledning",
      "sovereign_vps" => "OpenBSD · relayd · Falcon<br>MASTER + RAILS deploy på egen maskin",
      "radio_bergen" => "MASTER/lib/voice · TTS · fellesskapsradio<br>Bergen · åpen distribusjon",
      "repligen_studio" => "Repligen + Postpro · Bergen<br>MASTER-drevet bilde/video for lokale aktører",
      "bolig_bergen" => "Personlig · ærlig spor<br>Bergen kommune Boligkontoret · separat fra prosjektfinansiering",
      "personal" => "Personlig · Bergen<br>Gunvor Minde · vanskeligstilte · brofinansiering — ikke teknologiprosjekt",
    }.freeze

    PLAN_ORDER = %w[
      master pub_healthcare brgen amber bsdports syre norwegian_hedge ditt_parti
      ilumi_gravferd pub_attorney sovereign_vps radio_bergen repligen_studio bolig_bergen personal
    ].freeze

    NON_SENDABLE_APP_FILES = %w[
      01_innovasjon_norge_master.html
      65_legathandboken_generell.html
    ].freeze

    NON_SENDABLE_NOTES = {
      "01_innovasjon_norge_master.html" =>
        "Innovasjon Norge — book møte med rådgiver Bergen, ikke masse-e-post. Bekreft kanal på contact_url.",
      "65_legathandboken_generell.html" =>
        "Intern mal for Legathåndboken — tilpass per giver manuelt. Ikke masseutsendelse.",
    }.freeze
  end

  PLAN_ORDER = Constants::PLAN_ORDER
  PLAN_META = Constants::PLAN_META
  LANG = Constants::LANG
  GLOBAL_DISCLAIMER = Constants::GLOBAL_DISCLAIMER
  MASTER_RAILS_DOC_LINE = Constants::MASTER_RAILS_DOC_LINE
  RAILS_APP_PATHS = Constants::RAILS_APP_PATHS
  INNOVASJON_NO_SENDABLE = Constants::INNOVASJON_NO_SENDABLE
end