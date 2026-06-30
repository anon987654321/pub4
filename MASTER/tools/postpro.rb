#!/usr/bin/env ruby
# frozen_string_literal: true

# MASTER tool entrypoint for cinematic image post-processing.
#
# The heavy implementation lives in DEPLOY/tools/postpro/postpro.rb. MASTER owns
# this stable entrypoint so command dispatch, contracts, and future refactors
# do not depend on ad-hoc DEPLOY paths.

require "rbconfig"

master_root = File.expand_path("..", __dir__)
legacy = File.expand_path("../DEPLOY/tools/postpro/postpro.rb", master_root)
repo_root = File.expand_path("..", master_root)

unless File.file?(legacy)
  warn "postpro: legacy implementation missing: #{legacy}"
  exit 127
end

exec RbConfig.ruby, "-C", repo_root, legacy, *ARGV
