#!/usr/bin/env ruby
# frozen_string_literal: true

# MASTER tool entrypoint for cinematic image post-processing.
#
# The heavy implementation lives in DEPLOY/postpro/postpro.rb. MASTER owns
# this stable entrypoint so command dispatch, contracts, and future refactors
# do not depend on DEPLOY paths.

require "rbconfig"

master_root = File.expand_path("..", __dir__)
repo_root = File.expand_path("..", master_root)
legacy = File.join(repo_root, "DEPLOY", "postpro", "postpro.rb")

unless File.file?(legacy)
  warn "postpro: legacy implementation missing: #{legacy}"
  exit 127
end

Dir.chdir(repo_root) do
  exec RbConfig.ruby, legacy, *ARGV
end
