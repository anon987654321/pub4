#!/bin/bash

require 'octokit'
require 'net/http'
require 'uri'
require 'json'

# Configuration
GITHUB_ACCESS_TOKEN = ENV['GITHUB_ACCESS_TOKEN']
GITHUB_REPO = 'user/repo'  # Replace with the target GitHub repository
CODE_CONVERSION_API = 'http://localhost:3000/convert'  # Your code conversion endpoint
PROMPTS_FILE = 'prompts.txt' # Path to your prompts file

# Initialize GitHub Client
client = Octokit::Client.new(access_token: GITHUB_ACCESS_TOKEN)

# Load prompts from file
def load_prompts(file_path)
  File.read(file_path).split("\n")
rescue Errno::ENOENT
  puts "Prompts file not found!"
  []
end

# Function to crawl and convert code
def crawl_and_convert_code(client)
  # Load prompts
  prompts = load_prompts(PROMPTS_FILE)

  # Fetch repositories
  repos = client.repositories

  repos.each do |repo|
    # Fetch the files in the repository
    tree = client.repository_contents(repo.full_name)
    tree.each do |file|
      next unless file[:name].end_with?('.py') # Only process Python files

      # Fetch the Python file content
      content = client.contents(repo.full_name, path: file[:path])
      python_code = content[:content]

      # Apply prompts to the Python code
      enhanced_code = apply_prompts(python_code, prompts)

      # Convert Python code to Ruby
      ruby_code = convert_python_to_ruby(enhanced_code)

      # Commit changes as a PR
      create_pull_request(client, repo, file[:path], ruby_code)
    end
  end
end

# Function to apply prompts to the Python code
def apply_prompts(python_code, prompts)
  # Modify the python_code based on prompts
  prompts.each do |prompt|
    # Example logic to enhance the python code based on the prompt
    python_code = "#{prompt}\n#{python_code}"  # This is a simplistic approach
  end
  python_code
end

# Function to convert Python code to Ruby using a local service
def convert_python_to_ruby(python_code)
  uri = URI.parse(CODE_CONVERSION_API)
  http = Net::HTTP.new(uri.host, uri.port)
  
  request = Net::HTTP::Post.new(uri.path, { 'Content-Type' => 'application/json' })
  request.body = { code: python_code }.to_json
  
  response = http.request(request)
  JSON.parse(response.body)['ruby_code']
end

# Function to create a pull request
def create_pull_request(client, repo, file_path, ruby_code)
  # Create a new branch
  branch_name = "convert-#{File.basename(file_path, '.py')}-to-ruby"
  client.create_ref(repo.full_name, "heads/#{branch_name}", client.ref(repo.full_name, 'heads/master').object.sha)

  # Create a new file with Ruby code in the new branch
  client.create_contents(repo.full_name, "path/to/#{File.basename(file_path, '.py')}.rb", "Converted Python code to Ruby", ruby_code, branch: branch_name)

  # Create a pull request
  client.create_pull_request(repo.full_name, 'master', branch_name, "Convert #{File.basename(file_path)} to Ruby")
end

# Run the script
crawl_and_convert_code(client)

