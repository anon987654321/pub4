#!/usr/bin/env ruby
# frozen_string_literal: true

# MASTER tool entrypoint for Replicate.com generation workflows.
#
# The heavy implementation currently lives in DEPLOY/repligen.rb. MASTER owns
# this stable entrypoint so command dispatch, contracts, and future refactors
# do not depend on DEPLOY paths.

require "rbconfig"

master_root = File.expand_path("..", __dir__)
repo_root = File.expand_path("..", master_root)
legacy = File.join(repo_root, "DEPLOY", "repligen.rb")

unless File.file?(legacy)
  warn "repligen: legacy implementation missing: #{legacy}"
  exit 127
end

exec RbConfig.ruby, "-C", repo_root, legacy, *ARGV
