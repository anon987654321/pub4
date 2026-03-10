# frozen_string_literal: true

module MASTER
  # Detects DRY violations and patterns that span multiple files.
  module CrossFileAnalyzer
    MIN_DUPLICATE_LINES = 4  # minimum block size to flag as duplicate
    MIN_OCCURRENCES     = 2  # must appear in at least N files

    module_function

    def analyze(paths)
      findings = []
      files = load_files(paths)

      findings.concat(detect_duplicate_blocks(files))
      findings.concat(detect_magic_numbers(files))
      findings.concat(detect_scattered_config(files))

      findings
    end

    def load_files(paths)
      paths.filter_map do |p|
        next unless File.file?(p) && p.end_with?(".rb")
        { path: p, lines: File.readlines(p, chomp: true, encoding: "utf-8:utf-8") }
      rescue StandardError
        nil
      end
    end

    def detect_duplicate_blocks(files)
      # Sliding window: extract N-line blocks, find blocks appearing in 2+ files
      block_map = Hash.new { |h, k| h[k] = [] }
      files.each do |f|
        f[:lines].each_cons(MIN_DUPLICATE_LINES).with_index do |block, idx|
          key = block.map(&:strip).join("\n")
          next if key.gsub(/\s/, "").length < 40  # skip trivial blocks
          block_map[key] << { file: f[:path], line: idx + 1 }
        end
      end

      block_map.filter_map do |_block, locations|
        next unless locations.map { |l| l[:file] }.uniq.size >= MIN_OCCURRENCES
        {
          type: :duplicate_block,
          smell: "copy_paste_block",
          message: "#{MIN_DUPLICATE_LINES}-line block duplicated in #{locations.size} files",
          locations: locations,
          severity: :medium,
        }
      end
    end

    def detect_magic_numbers(files)
      number_map = Hash.new { |h, k| h[k] = [] }
      files.each do |f|
        f[:lines].each_with_index do |line, idx|
          line.scan(/\b([2-9]\d{2,})\b/).flatten.each do |num|  # numbers >= 200
            number_map[num] << { file: f[:path], line: idx + 1 }
          end
        end
      end

      number_map.filter_map do |num, locations|
        next unless locations.map { |l| l[:file] }.uniq.size >= MIN_OCCURRENCES
        {
          type: :magic_number,
          smell: "magic_number_spread",
          message: "Magic number #{num} appears in #{locations.size} files — extract to constant",
          locations: locations,
          severity: :low,
        }
      end
    end

    def detect_scattered_config(files)
      # Flag hardcoded URLs, ports, paths appearing in multiple files
      config_map = Hash.new { |h, k| h[k] = [] }
      files.each do |f|
        f[:lines].each_with_index do |line, idx|
          line.scan(%r{(https?://[^\s"']+|:\d{4,5}\b|/[a-z][a-z0-9/_-]{5,})}).flatten.each do |val|
            config_map[val] << { file: f[:path], line: idx + 1 }
          end
        end
      end

      config_map.filter_map do |val, locations|
        next unless locations.map { |l| l[:file] }.uniq.size >= MIN_OCCURRENCES
        {
          type: :scattered_config,
          smell: "scattered_config",
          message: "Config value #{val.inspect} hardcoded in #{locations.size} files",
          locations: locations,
          severity: :low,
        }
      end
    end
  end
end
