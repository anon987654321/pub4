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

# Validate port availability using lsof for reliability
validate_port_available() {
  if command -v lsof >/dev/null 2>&1; then
    if lsof -i :$1 >/dev/null 2>&1; then
      return 1
    else
      return 0
    fi
  elif command -v ss >/dev/null 2>&1; then
    if ss -lnt | grep -q :$1; then
      return 1
    else
      return 0
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -lnt | grep -q :$1; then
      return 1
    else
      return 0
    fi
  else
    # Fallback to Ruby method if no system tools available
    if command -v ruby >/dev/null 2>& begin
          socket = Socket.new(:INET, :STREAM)
          rescue Errno::EADDRINUSE
          exit 1
        end
      " 2>/dev/null
      return $?
    fi
    return 0
  fi
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
require "timeout"

def with_retries(max_retblock)
  retries = 0
  begin
    yield
  rescue => e
    if retries < max_retries
      (retries - 1))
      puts "Retry #{retries}/#{max_retries} after #{delay}s: #{e.message}"
      sleep delay
      retry
    else
      puts "Failed after #{max_retries} retries: #{e.message}"
      raise
    end
  end
end

def safe_eval(expression, context)
  # Restricted evaluation - only allow basic arithmetic and variable access
  sanitized = expression.gsub(/[^a-zA-Z0-9\s\+\-\*\/\(\)\.]/, '')
  begin
    context.instance_eval(sanitized)
  rescue => e
    puts "Error evaluating expression: #{expression} - #{e.message}"
    nil
  end
end

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
  with_retries do
    Timeout.timeout(30) do
      Net::FTP.open(server) do |ftp|
        ftp.login
        ftp.chdir(root_dir)
        files = ftp.list('*').map { |entry| entry.split.last }
        files.find { |f| f.end_with?('.tgz') }
      end
    end
  end
rescue Timeout::Error
  puts "Timeout connecting to FTP server: #{server}"
  nil
rescue => e
  puts "Error fetching FTP filename: #{e.message}"
  nil
end

def_size = ftp.size(remote_file)
  downloaded = 0

  ftp.getbinaryfile(remote_file, local_path) dodownloaded.to_f / total_size * 100).round(2)
    print "\rDownloading: #{progress}% (#{downloaded}/#{total_size} bytes)"
  end
  puts
end {} unless File.exist?(makefile_path)

  makefile_content = File.read(makefile_path)
  variables = {}

  makefile_content.scan(/^(\w+)\s*=\s*(.+)$/) do |key, value|
    variables[key.strip] = value.strip
  end

  variables
end

def read_pkg_descr(descr_path)
  return "" unless File.exist?(descr_path)
  File.read(descr_path).strip
rescue => e
  puts "Error reading pkg/DESCR: #{e.message}"
  ""
end

def go_fetch(platform, &block)
  puts "Processing platform: #{platform}"

  temp_dir = Dir.mktmpdir("bsdports_")
  begin
    with_retries do
      Timeout.timeout(120) do
        Net::FTP.open('ftp.openbsd.org') do |ftp|
          ftp.login

          # Use safe evaluation instead of eval
          rootp.chdir(root_dir)

          filename = fetch_ftp_filename('ftp.openbsd.org', root_dir)
          unless filename
            puts "No package file found in #{root_dir}"
            next
          end

          local_file = File.join(temp_dir, filename)
          puts "Downloading #{filename}..."
          download_file(ftp, filename, local_file)

          # Extract and process
          puts "Extracting #{filename}..."
          File.open(local_file, 'rb') do |file|
            untar(file, temp_dir)
          end

          # Read Makefile and pkg/DESCR
          makefile_path = File.join(temp_dir, "Makefile")
          descr_path = File.join(temp_dir, "pkg", "DESCR")

          makefile_vars = read_makefile(makefile_path)
          descr_content = read_pkg_descr(descr_path)

          yield({
            platform: platform,
            filename: filename,
            makefile: makefile_vars,
            description: descr_content,
            temp_dir: temp_dir
          })
        end
      end
    end
  rescue Timeout::Error
    puts "Timeout during FTP operations for platform: #{platform}"
  rescue => e
    puts "Error processing platform #{platform}: #{e.message}"
  ensure
    # Cleanup temporary directory
    FileUtils.remove_entry(temp_dir) if File.directory?(temp_dir)
  end
end

# Main execution
begin
  platforms = [
    'pub/OpenBSD/7.4/packages/amd64',
    'pub/OpenBSD/7.3/packages/amd64',
    'pub/OpenBSD/7.2/packages/amd64'
  ]

  platforms.each do |platform|
    go_fetch(platform) do |package_data|
      puts "Processing package: #{package_data[:filename]}"

      # Create or update package record
      package = Package.find_or_initialize_by(
        name: package_data[:makefile]['PKGNAME'] || package_data[:filename],
        platform: platform
      )

      package.assign_attributes(
        version: package_data[:makefile]['VERSION'],
        description: package_data[:description],
        maintainer: package_data[:makefile]['MAINTAINER'],
        categories: package_data[:makefile]['CATEGORIES']&.split,
        dependencies: package_data[:makefile]['DEPENDS']&.split,
        build_dependencies: package_data[:makefile]['BUILD_DEPENDS']&.split,
        filename: package_data[:filename]
      )

      if package.save
        puts "Saved package: #{package.name}"
      else
        puts "Failed to save package: #{package.errors.full_messages.join(', ')}"
      end
    end
  end

  puts "Seed data import completed successfully!"

rescue => e
  puts "Fatal error during seed generation: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end
EOF

echo "Seeds.rb created successfully!"
```
