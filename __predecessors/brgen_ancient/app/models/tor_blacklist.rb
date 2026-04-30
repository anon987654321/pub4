class TorBlacklist
  attr_accessor :current_mtime

  def self.tor_ips?(ip)
    ips.include?(ip)
  end

  def self.ips
    reset if file_updated?
    @ips ||= read_blacklist_file.map(&:strip)
  end

  def self.read_blacklist_file
    self.current_mtime = File.stat(blacklist_file_path).mtime
    IO.readlines(blacklist_file_path)
  end

  def self.blacklist_file_path(root = Rails.root)
    root.join("db/tor.db")
  end

  def self.file_updated?
    current_mtime and (current_mtime < new_mtime)
  end

  def self.reset
    @ips = nil
  end

  def self.new_mtime
    File.stat(blacklist_file_path).mtime
  end
end

