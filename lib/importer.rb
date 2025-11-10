#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'base64'
require 'fileutils'

# GitHub API importer using stdlib only
class Importer
  API_BASE = 'https://api.github.com'
  
  def initialize(config_path = 'master.json')
    @config = JSON.parse(File.read(config_path))
    @imports_config = @config['imports']
    
    raise "Missing 'imports' section in config" unless @imports_config
    
    @owner = @imports_config['owner']
    @repos = @imports_config['repos'] || []
    @branch = @imports_config['branch'] || 'main'
    @include_extensions = @imports_config['include_extensions'] || []
    @exclude_paths = @imports_config['exclude_paths'] || []
    @dest_dir = @imports_config['dest_dir'] || 'imports'
    
    # Get GitHub token from environment if available (optional)
    @token = ENV['GITHUB_TOKEN']
  end
  
  def import_all
    puts "Starting import from #{@repos.length} repository(ies)..."
    puts "Owner: #{@owner}"
    puts "Branch: #{@branch}"
    puts "Destination: #{@dest_dir}"
    puts "=" * 60
    
    @repos.each do |repo|
      import_repo(repo)
    end
    
    puts "\n" + "=" * 60
    puts "Import complete!"
  end
  
  def import_repo(repo)
    puts "\nImporting #{@owner}/#{repo}..."
    
    # Get the tree using Git Trees API with recursive=1
    tree = fetch_tree(repo)
    
    unless tree
      puts "  ✗ Failed to fetch tree for #{repo}"
      return
    end
    
    # Filter files
    files = filter_files(tree)
    puts "  Found #{files.length} file(s) to import"
    
    # Download each file
    files.each_with_index do |file_info, idx|
      download_file(repo, file_info, idx + 1, files.length)
    end
    
    puts "  ✓ Completed #{repo}"
  end
  
  private
  
  def fetch_tree(repo)
    # First get the commit SHA for the branch
    sha = fetch_branch_sha(repo)
    return nil unless sha
    
    # Then get the tree recursively
    url = "#{API_BASE}/repos/#{@owner}/#{repo}/git/trees/#{sha}?recursive=1"
    
    response = make_request(url)
    return nil unless response
    
    data = JSON.parse(response.body)
    data['tree']
  rescue => e
    puts "  Error fetching tree: #{e.message}"
    nil
  end
  
  def fetch_branch_sha(repo)
    url = "#{API_BASE}/repos/#{@owner}/#{repo}/git/refs/heads/#{@branch}"
    
    response = make_request(url)
    return nil unless response
    
    data = JSON.parse(response.body)
    data.dig('object', 'sha')
  rescue => e
    puts "  Error fetching branch SHA: #{e.message}"
    nil
  end
  
  def filter_files(tree)
    tree.select do |item|
      # Only files (not trees/directories)
      next false unless item['type'] == 'blob'
      
      path = item['path']
      
      # Check extension
      ext = File.extname(path)[1..]
      next false unless @include_extensions.include?(ext)
      
      # Check excluded paths
      excluded = @exclude_paths.any? { |exclude| path.start_with?(exclude) || path.include?("/#{exclude}") }
      next false if excluded
      
      true
    end
  end
  
  def download_file(repo, file_info, current, total)
    path = file_info['path']
    sha = file_info['sha']
    
    print "\r  [#{current}/#{total}] Downloading #{path}..."
    
    # Download blob content
    url = "#{API_BASE}/repos/#{@owner}/#{repo}/git/blobs/#{sha}"
    
    response = make_request(url)
    unless response
      puts "\n  ✗ Failed to download #{path}"
      return
    end
    
    data = JSON.parse(response.body)
    
    # Decode content (it's Base64 encoded)
    content = if data['encoding'] == 'base64'
                Base64.decode64(data['content'])
              else
                data['content']
              end
    
    # Write to destination
    dest_path = File.join(@dest_dir, repo, path)
    FileUtils.mkdir_p(File.dirname(dest_path))
    File.write(dest_path, content)
    
  rescue => e
    puts "\n  ✗ Error downloading #{path}: #{e.message}"
  end
  
  def make_request(url)
    uri = URI.parse(url)
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30
    
    request = Net::HTTP::Get.new(uri.request_uri)
    request['Accept'] = 'application/vnd.github.v3+json'
    request['User-Agent'] = 'pub4-importer'
    
    # Add auth token if available
    request['Authorization'] = "token #{@token}" if @token
    
    response = http.request(request)
    
    case response
    when Net::HTTPSuccess
      response
    when Net::HTTPNotFound
      puts "\n  ✗ Resource not found: #{url}"
      nil
    when Net::HTTPUnauthorized, Net::HTTPForbidden
      puts "\n  ✗ Authentication failed. Set GITHUB_TOKEN environment variable for private repos."
      nil
    when Net::HTTPTooManyRequests
      # Handle rate limiting
      retry_after = response['Retry-After']&.to_i || 60
      puts "\n  ! Rate limited. Waiting #{retry_after} seconds..."
      sleep retry_after
      make_request(url)
    else
      puts "\n  ✗ HTTP #{response.code}: #{response.message}"
      nil
    end
  rescue => e
    puts "\n  ✗ Request error: #{e.message}"
    nil
  end
end

# CLI interface
if __FILE__ == $PROGRAM_NAME
  begin
    config_path = ARGV[0] || 'master.json'
    
    unless File.exist?(config_path)
      puts "Error: Config file not found: #{config_path}"
      puts "Usage: ruby lib/importer.rb [config_path]"
      exit 1
    end
    
    importer = Importer.new(config_path)
    importer.import_all
    
  rescue Interrupt
    puts "\n\nInterrupted. Exiting..."
    exit 0
  rescue => e
    puts "Error: #{e.message}"
    puts e.backtrace.join("\n")
    exit 1
  end
end
