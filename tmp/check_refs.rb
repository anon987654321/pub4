# frozen_string_literal: true
# encoding: utf-8

BASE = "/home/dev/pub4/MASTER"
deleted = %w[CognitiveMonitor Friction AutoTesting Experience ApplyDiff features.yml fallback_models.yml governance.yml]

Dir.glob(File.join(BASE, "lib/**/*.rb")).each do |f|
  content = File.read(f, encoding: "utf-8")
  deleted.each do |d|
    puts "#{f.sub(BASE + '/', '')}: references #{d}" if content.include?(d)
  end
end
puts "done"
