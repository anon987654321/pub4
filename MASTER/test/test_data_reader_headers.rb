# frozen_string_literal: true

require_relative "test_helper"

# A data file may declare its consumer with a `# reader: <constant>` header. This
# does not force the convention on every file — a grep-based "does any code read
# this key" gate could not be made precise here (46% false positive; dynamic dig
# everywhere). It verifies the files that opt in, so a header naming a reader that
# was later renamed or deleted fails loudly instead of rotting into the same
# inert-config drift the wishlist is about. Seeded on the single-reader config
# files; new single-purpose config should adopt the header.
class TestDataReaderHeaders < Minitest::Test
  DATA = File.join(Master::ROOT, "data")
  CONSTANT = /\AMaster(?:::[A-Z]\w*)+\z/

  def reader_for(path)
    File.foreach(path).first(3).each do |line|
      match = line.match(/\A#\s*reader:\s*(\S+)/)
      return match[1] if match
    end
    nil
  end

  def test_declared_readers_resolve
    declared = Dir.glob(File.join(DATA, "**/*.yml")).sort.filter_map do |path|
      reader = reader_for(path)
      [path, reader] if reader
    end

    refute_empty declared, "no data file declares a `# reader:` header — seed at least one"

    declared.each do |path, reader|
      next unless reader.match?(CONSTANT)

      resolved =
        begin
          Object.const_get(reader)
        rescue NameError
          nil
        end
      relative = path.delete_prefix("#{Master::ROOT}/")
      assert resolved, "#{relative} declares `# reader: #{reader}` but that constant does not resolve"
    end
  end
end
