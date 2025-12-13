#!/usr/bin/env ruby
# VPS Upload Proof of Concept
# Uploads videos to OpenBSD VPS for hosting/serving

require "fileutils"

def upload_to_vps(local_file, remote_host, remote_user = "root", remote_path = "/root")
  puts "📤 Uploading #{local_file} to VPS..."
  puts "   Target: #{remote_user}@#{remote_host}:#{remote_path}/"
  
  # Try multiple connection methods
  methods = [
    # Method 1: Direct SCP with key
    -> { system("scp", local_file, "#{remote_user}@#{remote_host}:#{remote_path}/") },
    
    # Method 2: SCP with specific key
    -> { system("scp", "-i", "#{ENV['HOME']}/.ssh/id_rsa", local_file, "#{remote_user}@#{remote_host}:#{remote_path}/") },
    
    # Method 3: SCP via SSH config alias
    -> { system("scp", local_file, "vps:#{remote_path}/") },
    
    # Method 4: SFTP
    -> {
      puts "Trying SFTP..."
      IO.popen("sftp #{remote_user}@#{remote_host}", "w") do |sftp|
        sftp.puts "cd #{remote_path}"
        sftp.puts "put #{local_file}"
        sftp.puts "bye"
      end
      $?.success?
    }
  ]
  
  methods.each_with_index do |method, i|
    puts "\n[Attempt #{i+1}/#{methods.size}]"
    begin
      if method.call
        puts "✓ Upload successful!"
        return true
      end
    rescue => e
      puts "✗ Failed: #{e.message}"
    end
  end
  
  puts "\n❌ All upload methods failed."
  puts "\nManual upload command:"
  puts "  scp #{local_file} your_user@your_vps_ip:/root/"
  false
end

if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: ruby upload_vps.rb <file> [host] [user] [path]"
    puts "\nExample:"
    puts "  ruby upload_vps.rb ra2_motion_20251212_234146.mp4 your.vps.ip root /root"
    exit 1
  end
  
  file = ARGV[0]
  host = ARGV[1] || ENV["VPS_HOST"] || "dev"
  user = ARGV[2] || "root"
  path = ARGV[3] || "/root"
  
  unless File.exist?(file)
    puts "❌ File not found: #{file}"
    exit 1
  end
  
  upload_to_vps(file, host, user, path)
end
