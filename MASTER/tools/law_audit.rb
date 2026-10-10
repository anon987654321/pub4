#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/operator/law_audit"

ok = Operator::LawAudit.run(json: ARGV.include?("--json"))
exit(ok ? 0 : 1)
