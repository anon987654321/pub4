#!/usr/bin/env ruby
# frozen_string_literal: true

require "shellwords"

if $PROGRAM_NAME == __FILE__
  if ARGV.empty?
    puts "warn: repligen CLI stub — cloud image/video via Replicate API"
    puts "fix: set REPLICATE_API_TOKEN; use Master::Reach::ReplicateClient from Ruby"
    puts "fix: local identity LoRA via /lora-train (data/lora_pipeline.yml)"
    exit 0
  end

  puts "warn: repligen CLI not implemented for: #{ARGV.shelljoin}"
  puts "fix: use /repligen through MASTER CLI or ReplicateClient in Ruby"
  exit 1
end