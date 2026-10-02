# frozen_string_literal: true

# ruby STUDIO/test/support/dilla_snapshot/compare.rb <labelA> <labelB>
#
# Reads two snapshots taken by snap.rb and prints one verdict per configuration.
# PASS means the normalised command lists are identical, integrated loudness is
# within 0.2 LU, the durations match, and every stem is within 0.5 LU or silent
# in both. The output SHA is printed and does not decide; snap.rb says why.
require "json"

module DillaSnapshotCompare
  REPO = File.expand_path("../../../..", __dir__)
  ROOT = ENV.fetch("DILLA_SNAPSHOT_DIR", File.join(REPO, "STUDIO", "dilla", "scratch", "snapshot"))

  LOUDNESS_LU = 0.2
  STEM_LU = 0.5
  SILENT_LUFS = -70

  module_function

  def main(argv)
    abort "usage: ruby #{File.basename(__FILE__)} <labelA> <labelB>" unless argv.size == 2

    a, b = argv.map { |label| File.join(ROOT, label) }
    [a, b].each { |dir| abort "no snapshot at #{dir}" unless Dir.exist?(dir) }
    Dir.children(a).sort.each { |name| report(name, a, b) }
  end

  def result(dir, name)
    path = File.join(dir, name, "result.json")
    File.file?(path) ? JSON.parse(File.read(path)) : nil
  end

  # One list per process, each in the order it ran, and the processes sorted:
  # jobs render in parallel, so which process started first is not part of the
  # sound. Measured loudness corrections land in volume= and move by a few
  # hundredths of a dB between two runs of unchanged code, so the gain is a token.
  def commands(dir, name)
    path = File.join(dir, name, "cmds.jsonl")
    return [] unless File.file?(path)

    rows = File.readlines(path).map { |line| JSON.parse(line) }
    rows.group_by(&:first).values.map do |process|
      process.sort_by { |row| row[1] }.map { |_, _, kind, command| "#{kind} #{command.gsub(/volume=-?[\d.]+dB/, 'volume=<G>dB')}" }
    end.sort
  end

  def report(name, a, b)
    ra = result(a, name)
    return unless ra

    rb = result(b, name)
    return puts("#{name}: missing in B") unless rb

    ca = commands(a, name)
    cb = commands(b, name)
    if ra["exit"] != 0 || rb["exit"] != 0 || ca.empty? || cb.empty?
      puts format("%-20s INVALID  exit %s/%s  commands %d/%d — nothing to compare",
                  name, ra["exit"], rb["exit"], ca.flatten.size, cb.flatten.size)
      return
    end

    stems_off = stem_differences(ra, rb)
    loud_ok = loudness_matches?(ra, rb) && stems_off.empty?
    verdict = ca == cb && loud_ok ? "PASS" : "FAIL"
    puts "    stems off: #{stems_off.join(', ')}" unless stems_off.empty?
    puts format("%-20s %s  commands %s (%d)  lufs %s/%s  dur %s/%s  bits %s", name, verdict, ca == cb ? "same" : "DIFF",
                ca.flatten.size, ra["lufs"], rb["lufs"], ra["duration"], rb["duration"],
                ra["output_sha"] == rb["output_sha"] ? "identical" : "differ")
    return if ca == cb

    (ca.flatten - cb.flatten).first(3).each { |line| puts "    A only: #{line[0, 300]}" }
    (cb.flatten - ca.flatten).first(3).each { |line| puts "    B only: #{line[0, 300]}" }
  end

  def loudness_matches?(ra, rb)
    ra["lufs"] && rb["lufs"] && (ra["lufs"] - rb["lufs"]).abs <= LOUDNESS_LU && ra["duration"] == rb["duration"]
  end

  # master.wav is the mix, which the output's own loudness already covers.
  def stem_differences(ra, rb)
    sa = ra["stems"] || {}
    sb = rb["stems"] || {}
    names = (sa.keys | sb.keys) - ["master.wav"]
    names.reject { |stem| stem_matches?(sa[stem], sb[stem]) }.map { |stem| "#{stem} #{sa[stem]}/#{sb[stem]}" }
  end

  def stem_matches?(la, lb)
    return false unless la && lb

    (la - lb).abs <= STEM_LU || (la < SILENT_LUFS && lb < SILENT_LUFS)
  end
end

DillaSnapshotCompare.main(ARGV) if __FILE__ == $PROGRAM_NAME
