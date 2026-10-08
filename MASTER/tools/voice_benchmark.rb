# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "../lib/master"
require_relative "../lib/voice/benchmark"
require_relative "../lib/trace/dmesg"

root = File.expand_path("..", __dir__)
out_dir = File.join(root, ".master", "voice_benchmark")
FileUtils.mkdir_p(out_dir)

unless Master::Voice::Benchmark.available?
  Master::Trace::Dmesg.status("voice0", "ffmpeg/ffprobe unavailable, audio gate skipped", io: $stderr)
  exit 0
end

results = []
Master::Voice::Benchmark.torture_prompts.each_with_index do |prompt, index|
  path = File.join(out_dir, format("%02d.mp3", index + 1))
  next unless Master::Voice::Speech.synthesize(prompt, path)

  metrics = Master::Voice::Benchmark.analyze(path, words: prompt.split.size)
  result = Master::Voice::Benchmark.score(metrics, text: prompt)
  results << { index: index + 1, text: prompt, metrics:, result: }
end

report = {
  generated_at: Time.now.utc.iso8601,
  samples: results,
  summary: {
    samples: results.length,
    mean_score: results.empty? ? 0.0 : (results.sum { |r| r[:result][:score] } / results.length).round(1),
    engines: results.filter_map { |r| r[:metrics][:engine] }.uniq,
  },
}

File.write(File.join(out_dir, "report.json"), JSON.pretty_generate(report))
Master::Trace::Dmesg.attach("voice0", "master0", "#{report[:summary][:samples]} samples, engines #{report[:summary][:engines].join(", ")}")
Master::Trace::Dmesg.status("voice0", "mean score #{report[:summary][:mean_score]}")
if results.empty?
  Master::Trace::Dmesg.status("voice0", "failed, no samples synthesized", io: $stderr)
  exit 1
end

threshold = Master::Voice::Benchmark.config["min_score"].to_f
if report[:summary][:mean_score] < threshold
  Master::Trace::Dmesg.status("voice0", "below threshold, #{report[:summary][:mean_score]}, threshold #{threshold}", io: $stderr)
  exit 1
end
