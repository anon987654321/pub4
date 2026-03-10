```zsh
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# BSDPorts - OpenBSD Package Repository Browser

APP_NAME="bsdports"

BASE_DIR="/home/dev/rails"

SERVER_IP="185.52.176.18"

APP_PORT=$((10000 + RANDOM % 10000))

SCRIPT_DIR="${0:a:h}"

source "${SCRIPT_DIR}/@shared_functions.sh"

# Validate port availability
validate_port_available() {
  # Try to bind to the port to check if it's truly available
  if command -v ruby >/dev/null 2>&1; then
    ruby -rsocket -e "
      begin
        socket = Socket.new(:INET, :STREAM)
        socket.bind(Addrinfo.tcp('127.0.0.1', $1))
        socket.close
        exit 0
      rescue Errno::EADDRINUSE
        exit 1
      end
    " 2>/dev/null
    return $?
  elif command -v nc >/dev/null 2>&1; then
    if nc -z localhost $1 2>/dev/null; then
      return 1
    fi
  fi
  return 0
}

while ! validate_port_available $APP_PORT; do
  APP_PORT=$((10000 + RANDOM % 10000))
done

bin/rails db:migrate

# -- CREATE SEEDS.RB --

echo "Creating seeds.rb with FTP download and database import logic..."

cat << "EOF" > db/seeds.rb

require "net/ftp"
require "rubygems/package"
require "zlib"
require "fileutils"
require "open-uri"

def untar(io, destination)
  begin
    Zlib::GzipReader.wrap(io) do |gzip|
      Gem::Package::TarReader.new(gzip) do |tar|
        tar.each do |tarfile|
          destination_file = File.join(destination, tarfile.full_name)
          if tarfile.directory?
            FileUtils.mkdir_p(destination_file)
          else
            destination_directory = File.dirname(destination_file)
            FileUtils.mkdir_p(destination_directory) unless File.directory?(destination_directory)
            File.open(destination_file, "wb") do |f|
              f.write(tarfile.read)
            end
          end
        end
      end
    end
  rescue => e
    puts "Error extracting archive: #{e.message}"
    raise
  end
end

def fetch_ftp_filename(server, root_dir)
  retries = 3
  begin
    ftp = Net::FTP.new(server)
    ftp.login
    ftp.chdir(root_dir)
    files = ftp.nlst("*.tar.gz")
    ftp.close
    files.first
  rescue Net::FTPError, SocketError, Net::FTPPermError => e
    if retries > 0
      retries -= 1
      sleep 2
      retry
    end
    puts "FTP Error fetching file list: #{e.message}"
    nil
  end
end

def download_file(server, remote_path, local_path)
  retries =)
    ftp.close
    true
  rescue Net::FTPError    if retries > 0
      retries -= 1
      sleep 2
      retry
    end
    puts "FTP Error downloading file: #{e.message}"
    false
  end
end

def go_fetch(platform, server, root, tgz_filename = nil)
  tgz_filename ||= fetch_ftp_filename(server, root)
  return unless tgz_filename

  tmp_dir = "/tmp/bsdports_#{Time.now.to_i}"
  FileUtils.mkdir_p(tmp_dir)
  local_tgz_path = File.join(tmp_dir, tgz_filename)

  begin
    unless download_file(server, File.join(root, tgz_filename), local_tgz_path)
      FileUtils.rm_rf(tmp_dir) if File.directory?(tmp_dir)
      return
    end

    # Extract the archive
    File.open(local_tgz_path, "rb") do |file|
      untar(file, tmp_dir)
    end

    # Process ports data
    ports_dir = File.join(tmp_dir, "ports")
    if File.directory?(ports_dir)
      Dir.chdir(ports_dir) do
        # Process each port category
        Dir.glob("*").each do |category|
          next unless File.directory?(category)

          Dir.chdir(category) do
            Dir.glob("*").each do |port_name|
              next unless File.directory?(port_name)

              # Read port metadata (Makefile, pkg/DESCR, etc.)
              makefile_path = File.join(port_name, "Makefile")
              descr_path = File.join(port_name, "pkg", "DESCR")

              if File.exist?(makefile_path)
                # Parse basic port information
                port_data = {
                  name: port_name,
                  category: category,
                  platform: platform,
                  makefile: File.read(makefile_path),
                  description: File.exist?(descr_path) ? File.read(descr_path) : ""
                }

                # Create or update port record
                port = Port.find_or_initialize_by(
                  name: port_name,
                  category: category,
                  platform: platform
                )

                port.update!(
                  makefile: port_data[:makefile],
                  description: port_data[:description]
                )

                puts "Processed port: #{category}/#{port_name}"
              end
            end
          end
        end
      end
    end

  rescue => e
    puts "Error processing ports data: #{e.message}"
    puts e.backtrace.join("\n")
  ensure
    # Cleanup
    FileUtils.rm_rf(tmp_dir) if File.directory?(tmp_dir)
  end
end

# Main execution
begin
  # Allow configuration via environment variables
  server = ENV['FTP_SERVER'] || 'ftp.openbsd.org'
  platform = ENV['PLATFORM'] || 'openbsd'
  root_dir = ENV['FTP_ROOT_DIR'] || '/pub/OpenBSD/snapshots/packages'

  puts "Starting ports import from #{server}#{root_dir}"

  go_fetch(platform, server, root_dir)

  puts "Ports import completed successfully"
rescue => e
  puts "Fatal error during ports import: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end
EOF

# Run seeds
bin/rails db:seed
```
