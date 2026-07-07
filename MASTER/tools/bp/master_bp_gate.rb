# frozen_string_literal: true

require "pathname"

ROOT = Pathname(__dir__)
PLAN_FILES = %w[
  syre.html
  speis.html
  norwegianhedge.html
  pubhealthcare.html
  ragnhild.html
  govt_bergen.html
  nato.html
  ai3.html
].freeze

REQUIRED_SECTION_IDS = %w[
  sammendrag
  problem-og-mulighet
  marked-og-kunder
  losning-og-produkt
  teknologi-og-innovasjon
  forretningsmodell
  gjennomforing-og-drift
  utviklingsveikart
  finansieringsbehov
  team-og-kompetanse
  risiko-og-tiltak
  baerekraft-og-samfunnsansvar
  maltall-og-validering
].freeze

class BusinessPlanGate
  def initialize(root: ROOT)
    @root = root
  end

  def run
    findings = PLAN_FILES.flat_map { |file| inspect_plan(file) }
    inspect_index(findings)
    if findings.empty?
      puts "bp_gate: ok files=#{PLAN_FILES.length}"
      return true
    end

    findings.each { |finding| warn(finding) }
    false
  end

  private

  attr_reader :root

  def inspect_plan(file)
    path = root.join(file)
    return ["#{file}: missing"] unless path.file?

    html = path.read
    findings = []
    findings << "#{file}: missing inline <style>" unless html.include?("<style>")
    findings << "#{file}: missing inline <script>" unless html.include?("<script>")
    findings << "#{file}: external stylesheet link" if html.match?(/<link\b[^>]*rel=[\"']stylesheet/i)
    findings << "#{file}: external script src" if html.match?(/<script\b[^>]*\bsrc=/i)
    findings << "#{file}: language must be Norwegian" unless html.include?("lang=\"no\"") || html.include?("lang='no'")
    findings.concat(missing_sections(file, html))
    findings
  end

  def missing_sections(file, html)
    REQUIRED_SECTION_IDS.filter_map do |section_id|
      next if html.include?(%(<section id="#{section_id}")) || html.include?(%(<section id='#{section_id}'))

      "#{file}: missing section ##{section_id}"
    end
  end

  def inspect_index(findings)
    path = root.join("index.html")
    if !path.file?
      findings << "index.html: missing"
      return
    end

    html = path.read
    PLAN_FILES.each do |file|
      findings << "index.html: missing link to #{file}" unless html.include?(file)
    end
  end
end

exit(BusinessPlanGate.new.run ? 0 : 1)
