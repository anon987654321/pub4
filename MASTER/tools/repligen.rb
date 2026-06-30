#!/usr/bin/env ruby
# frozen_string_literal: true

# MASTER tool entrypoint for Replicate.com generation workflows.
#
# The heavy implementation currently lives in DEPLOY/tools/repligen.rb. MASTER owns
# this stable entrypoint so command dispatch, contracts, and future refactors
# do not depend on DEPLOY paths.

require "rbconfig"

master_root = File.expand_path("..", __dir__)
legacy = File.expand_path("../DEPLOY/tools/repligen.rb", master_root)
repo_root = File.expand_path("..", master_root)

unless File.file?(legacy)
  warn "repligen: legacy implementation missing: #{legacy}"
  exit 127
end

exec RbConfig.ruby, "-C", repo_root, legacy, *ARGV
