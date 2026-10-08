# frozen_string_literal: true

require "fileutils"
require "tempfile"

module Studio
  module AtomicWrite
    def write_atomic(path, content)
      directory = File.dirname(path)
      FileUtils.mkdir_p(directory)
      mode = File.file?(path) ? File.stat(path).mode & 0o7777 : 0o640
      Tempfile.create(["studio-", ".tmp"], directory, binmode: true) do |tmp|
        tmp.write(content.to_s)
        tmp.flush
        tmp.fsync
        tmp.close
        File.chmod(mode, tmp.path)
        File.rename(tmp.path, path)
      end
      path
    end
  end
end
