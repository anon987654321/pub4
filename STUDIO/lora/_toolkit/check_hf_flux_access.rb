#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Nothing to check when FLUX is not the base.
#
# This gate exists because FLUX.1-dev is licence-gated: a token that has not
# accepted the terms downloads a 403 and the failure appears hundreds of lines
# later inside diffusers. Real problem, and entirely FLUX's.
#
# SDXL is not gated. It needs no token at all. But every lane in run_generate.sh
# calls this gate unconditionally, so an SDXL render on a machine with no HF
# credentials refused to start — blocked by the licence terms of a model it was
# never going to load.
#
# Exits 0 with a note rather than skipping silently, because a gate that stops
# reporting is indistinguishable from a gate that stopped mattering.
if ENV["LORA_BASE"].to_s.strip.downcase == "sdxl"
  puts "ok: base is SDXL, which is not licence-gated — no Hugging Face token needed"
  exit 0
end

FLUX_REPO = ENV.fetch("LORA_FLUX_MODEL", "black-forest-labs/FLUX.1-dev")
FLUX_URL = "https://huggingface.co/#{FLUX_REPO}"
TOKEN_PATHS = [
  File.expand_path("~/.cache/huggingface/token"),
  File.expand_path("~/.huggingface/token"),
].freeze

def read_token
  %w[HF_TOKEN HUGGINGFACE_HUB_TOKEN].each do |key|
    value = ENV.fetch(key, "").strip
    return value unless value.empty?
  end

  TOKEN_PATHS.each do |path|
    next unless File.file?(path)

    value = File.read(path, encoding: "UTF-8").strip
    return value unless value.empty?
  end

  nil
end

def local_flux_path
  path = ENV.fetch("LORA_FLUX_MODEL_PATH", "").strip
  path.empty? || !File.directory?(path) ? nil : path
end

def hf_get(url, token)
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 20, read_timeout: 60) do |http|
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}" unless token.to_s.empty?
    http.request(request)
  end
end

def gated?(response)
  body = response.body.to_s
  response.code == "403" || body.include?("authorized list") || body.include?("gated")
end

def main
  local = local_flux_path
  if local
    puts "ok: local FLUX at #{local}"
    return 0
  end

  token = read_token
  unless token
    warn "warn: Hugging Face auth missing"
    warn "fix: set HF_TOKEN or run hf auth login"
    return 1
  end

  whoami = hf_get("https://huggingface.co/api/whoami-v2", token)
  unless whoami.code.to_i.between?(200, 299)
    warn "warn: invalid Hugging Face token (#{whoami.code})"
    return 1
  end

  user = JSON.parse(whoami.body).fetch("name", "unknown")
  puts "ok: HF user #{user}"

  model_index_url = "https://huggingface.co/#{FLUX_REPO}/resolve/main/model_index.json"
  index = hf_get(model_index_url, token)
  if index.code.to_i.between?(200, 299)
    puts "ok: authorized for #{FLUX_REPO}"
    puts "ok: model_index #{model_index_url}"
    return 0
  end

  warn "warn: cannot access #{FLUX_REPO}"
  if gated?(index)
    warn "fix: open #{FLUX_URL} as #{user}, accept license, rerun"
  else
    warn "reason: HTTP #{index.code} #{index.body.to_s.strip[0, 200]}"
  end
  warn "fix: or set LORA_FLUX_MODEL_PATH to local FLUX.1-dev"
  2
end

exit(main) if $PROGRAM_NAME == __FILE__
