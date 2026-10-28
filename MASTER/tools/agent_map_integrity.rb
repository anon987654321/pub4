# frozen_string_literal: true

require_relative "../lib/master"
require_relative "../lib/ground/map"

findings = Master::Ground::Map::Agent.integrity
unless findings.empty?
  findings.each { |finding| warn "agent_map: #{finding}" }
  abort "agent_map: #{findings.size} integrity finding(s)"
end

data = Master::Ground::Map::Agent.load
topics = data.fetch("topics")
references = topics.values.sum { |entry| Array(entry["files"]).size } + data.fetch("patch_briefs").size
puts "agent_map: #{topics.size} topics, #{references} path references clean"
