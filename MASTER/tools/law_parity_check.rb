# frozen_string_literal: true

# lint:law_parity — the constitutional enforcement audit must have a real caller.
require_relative "../lib/master"
require_relative "../lib/fix/law_parity"

parity = Master::Fix::LawParity.new
report = parity.report
puts report
abort "law_parity: constitutional enforcement gap remains" unless report.start_with?("law_parity: ok")
