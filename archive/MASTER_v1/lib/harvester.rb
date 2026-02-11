# frozen_string_literal: true

require 'yaml'
require 'json'
require 'fileutils'
require 'net/http'
require 'uri'
require 'base64'

module MASTER
  # Ecosystem intelligence harvester
  # Gathers skill information from OpenClaw ecosystem
  class Harvester
    GITHUB_API = 'https://api.github.com'
    RATE_LIMIT_DELAY = 1.0 # seconds between requests
    
    SOURCES = [
      { owner: 'VoltAgent', repo: 'awesome-openclaw-skills' },
      { owner: 'openclaw', repo: 'skills' }
    ].freeze
    
    attr_reader :harvested_data, :stats
    
    def initialize(github_token: nil)
      @github_token = github_token || ENV['GITHUB_TOKEN']
      @harvested_data = []
      @stats = {
        repos_scanned: 0,
        skills_found: 0,
        errors: 0,
        started_at: Time.now
      }
    end
    
    # Harvest ecosystem intelligence
    # @return [Hash] Harvested data and statistics
    def harvest
      puts "🌾 Starting ecosystem harvest..."
      
      SOURCES.each do |source|
        begin
          puts "  Scanning #{source[:owner]}/#{source[:repo]}..."
          scan_repository(source[:owner], source[:repo])
          @stats[:repos_scanned] += 1
        rescue => e
          puts "  ✗ Error scanning #{source[:owner]}/#{source[:repo]}: #{e.message}"
          @stats[:errors] += 1
        end
        
        sleep RATE_LIMIT_DELAY
      end
      
      @stats[:completed_at] = Time.now
      @stats[:duration] = @stats[:completed_at] - @stats[:started_at]
      
      puts "\n✓ Harvest complete:"
      puts "  Repos: #{@stats[:repos_scanned]}"
      puts "  Skills: #{@stats[:skills_found]}"
      puts "  Duration: #{@stats[:duration].round(1)}s"
      
      {
        data: @harvested_data,
        stats: @stats,
        trends: analyze_trends
      }
    end
    
    # Save harvested data
    # @param output_dir [String] Directory to save output
    def save(output_dir = nil)
      output_dir ||= File.join(Paths.root, 'data', 'intelligence')
      FileUtils.mkdir_p(output_dir)
      
      filename = "harvested_#{Time.now.strftime('%Y-%m-%d')}.yml"
      filepath = File.join(output_dir, filename)
      
      data = {
        metadata: {
          harvested_at: Time.now.iso8601,
          sources: SOURCES,
          stats: @stats
        },
        skills: @harvested_data,
        trends: analyze_trends
      }
      
      File.write(filepath, YAML.dump(data))
      puts "\n💾 Saved to: #{filepath}"
      
      filepath
    end
    
    private
    
    # Scan a GitHub repository for skills
    def scan_repository(owner, repo)
      # Get repository info
      repo_data = github_request("/repos/#{owner}/#{repo}")
      return unless repo_data
      
      # Get repository contents
      contents = github_request("/repos/#{owner}/#{repo}/contents")
      return unless contents
      
      # Look for SKILL.md files or skill directories
      extract_skills(owner, repo, contents, repo_data)
    end
    
    # Extract skills from repository contents
    def extract_skills(owner, repo, contents, repo_data)
      contents.each do |item|
        next unless item['type']
        
        if item['type'] == 'file' && item['name'] =~ /SKILL\.md$/i
          extract_skill_from_file(owner, repo, item['path'], repo_data)
        elsif item['type'] == 'dir'
          # Recursively check directories (limited depth)
          subcontents = github_request("/repos/#{owner}/#{repo}/contents/#{item['path']}")
          extract_skills(owner, repo, subcontents, repo_data) if subcontents
        end
      end
    rescue => e
      puts "    Warning: Error extracting skills: #{e.message}"
    end
    
    # Extract skill information from SKILL.md file
    def extract_skill_from_file(owner, repo, path, repo_data)
      content = github_request("/repos/#{owner}/#{repo}/contents/#{path}")
      return unless content && content['content']
      
      # Decode base64 content
      decoded = Base64.decode64(content['content'])
      
      # Extract YAML frontmatter
      skill_data = parse_skill_markdown(decoded)
      
      return unless skill_data
      
      # Enrich with repository metadata
      skill_data[:repository] = {
        owner: owner,
        repo: repo,
        stars: repo_data['stargazers_count'],
        updated_at: repo_data['updated_at'],
        url: repo_data['html_url'],
        path: path
      }
      
      @harvested_data << skill_data
      @stats[:skills_found] += 1
      
      puts "    ✓ Found: #{skill_data[:name]}"
    rescue => e
      puts "    Warning: Error parsing #{path}: #{e.message}"
    end
    
    # Parse SKILL.md content
    def parse_skill_markdown(content)
      # Extract YAML frontmatter
      if content =~ /^---\s*\n(.*?)\n---\s*\n/m
        frontmatter = YAML.safe_load($1, symbolize_names: true)
        
        {
          name: frontmatter[:name],
          description: frontmatter[:description],
          metadata: frontmatter[:metadata] || {},
          content: content
        }
      else
        # Try to extract basic info from markdown
        name = content[/^#\s+(.+)$/, 1]
        description = content[/^>\s+(.+)$/, 1]
        
        return nil unless name
        
        {
          name: name,
          description: description,
          metadata: {},
          content: content
        }
      end
    end
    
    # Make GitHub API request
    def github_request(path)
      uri = URI("#{GITHUB_API}#{path}")
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      
      request = Net::HTTP::Get.new(uri)
      request['Accept'] = 'application/vnd.github.v3+json'
      request['Authorization'] = "Bearer #{@github_token}" if @github_token
      
      response = http.request(request)
      
      if response.code.to_i == 200
        JSON.parse(response.body)
      elsif response.code.to_i == 403
        # Rate limit hit
        puts "    ⚠ Rate limit reached, waiting..."
        sleep 60
        nil
      else
        puts "    ⚠ API error: #{response.code}"
        nil
      end
    rescue => e
      puts "    ⚠ Request error: #{e.message}"
      nil
    end
    
    # Analyze trends from harvested data
    def analyze_trends
      return {} if @harvested_data.empty?
      
      # Extract OS requirements
      os_counts = Hash.new(0)
      @harvested_data.each do |skill|
        os_list = skill.dig(:metadata, :master, :os) || []
        os_list.each { |os| os_counts[os] += 1 }
      end
      
      # Extract required gems
      gem_counts = Hash.new(0)
      @harvested_data.each do |skill|
        gems = skill.dig(:metadata, :master, :requires, :gems) || []
        gems.each { |gem| gem_counts[gem] += 1 }
      end
      
      # Star distribution
      stars = @harvested_data.map { |s| s.dig(:repository, :stars) }.compact
      
      {
        os_distribution: os_counts.sort_by { |_, count| -count }.to_h,
        popular_gems: gem_counts.sort_by { |_, count| -count }.first(10).to_h,
        star_stats: {
          total: stars.sum,
          average: stars.empty? ? 0 : stars.sum / stars.size,
          max: stars.max,
          min: stars.min
        },
        total_skills: @harvested_data.size
      }
    end
  end
end

# CLI execution
if __FILE__ == $0
  require_relative 'loader'
  
  harvester = MASTER::Harvester.new
  result = harvester.harvest
  harvester.save
end
