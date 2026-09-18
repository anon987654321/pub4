# frozen_string_literal: true

# Historical Norwegian child-welfare statute: barnevernloven § 4-12.
#
# This file preserves the statutory wording as the legal source text. MASTER
# may improve structure, provenance, validation and handling around a law, but
# must not silently rewrite the substance of a statute.
#
# Source:
#   Lovdata, lov 17. juli 1992 nr. 100 om barneverntjenester, § 4-12.
#   https://lovdata.no/lov/1992-07-17-100
#
# Status:
#   Historical provision. The 1992 Act was replaced by the current
#   barnevernsloven from 1 January 2023. The principal current equivalent is
#   barnevernsloven § 5-1.
#
# MASTER handling invariant:
#   legal_text is source material, not a model-generated paraphrase.
#   No MASTER style rule may alter a quoted statutory term.
#   Any interpretation must be kept separate from the legal text and attributed
#   to a competent legal source.
#
# Evidence checked 2026-09-18:
#   Lovdata reproduces the three paragraphs and bokstav a-d below.
#   Prop. 133 L (2020–2021), chapter 5, § 5-1, describes § 4-12 as the
#   principal former provision and states that the new rule is mainly a
#   continuation of existing law with some language changes.

module Master
  module Law
    module Barnevernloven412
      SOURCE = "Lovdata: barnevernloven § 4-12".freeze
      SOURCE_URL = "https://lovdata.no/lov/1992-07-17-100".freeze
      CURRENT_SUCCESSOR = "barnevernsloven § 5-1".freeze

      LEGAL_TEXT = <<~NORWEGIAN.freeze
        § 4-12. Vedtak om å overta omsorgen for et barn

        Vedtak om å overta omsorgen for et barn kan treffes

        a) dersom det er alvorlige mangler ved den daglige omsorg som barnet får, eller alvorlige mangler i forhold til den personlige kontakt og trygghet som det trenger etter sin alder og utvikling,

        b) dersom foreldrene ikke sørger for at et sykt, funksjonshemmet eller spesielt hjelpetrengende barn får dekket sitt særlige behov for behandling og opplæring,

        c) dersom barnet blir mishandlet eller utsatt for andre alvorlige overgrep i hjemmet, eller

        d) dersom det er overveiende sannsynlig at barnets helse eller utvikling kan bli alvorlig skadd fordi foreldrene er ute av stand til å ta tilstrekkelig ansvar for barnet

        Et vedtak etter første ledd kan bare treffes når det er nødvendig ut fra den situasjon barnet befinner seg i. Et slikt vedtak kan derfor ikke treffes dersom det kan skapes tilfredsstillende forhold for barnet ved hjelpetiltak etter § 4-4 eller ved tiltak etter § 4-10 eller § 4-11.

        Et vedtak etter første ledd skal treffes av fylkesnemnda etter reglene i kapittel 7.
      NORWEGIAN

      def self.text
        LEGAL_TEXT
      end

      def self.provenance
        {
          source: SOURCE,
          source_url: SOURCE_URL,
          status: :historical,
          current_successor: CURRENT_SUCCESSOR
        }.freeze
      end
    end
  end
end

Law.define(:BARNEVERNLOVEN_4_12_HANDLING) do
  source "Lovdata: barnevernloven § 4-12"
  severity :warn
  practice <<~TEXT
    Legal-source preservation — preserve the quoted statutory text exactly.
    Separate statute from interpretation. Do not turn a legal provision into
    an autonomous decision rule: an application to facts requires the relevant
    case record, applicable law and competent legal assessment. Preserve
    provenance and distinguish the historical § 4-12 from current
    barnevernsloven § 5-1.
  TEXT
  fix "Preserve the source text; keep provenance and interpretation separate."
  bad "rewrites a statutory threshold into a shorter model-generated rule"
  good "quotes the statute and separately identifies interpretation and provenance"
end
