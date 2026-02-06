# frozen_string_literal: true

# Test new features: TTY, Quality, InfoArch, Circuit Breakers, Typography

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'loader'

def assert(condition, message = 'Assertion failed')
  raise message unless condition
  print '.'
end

def test_suite(name)
  print "\nTesting #{name}... "
  yield
  puts " ✓"
rescue => e
  puts " ✗"
  puts "  Error: #{e.message}"
  puts e.backtrace.first(3).map { |l| "    #{l}" }.join("\n")
  exit 1
end

# TTY Module Tests
test_suite('TTY') do
  assert MASTER::TTY.size.is_a?(Array), 'size should return array'
  assert MASTER::TTY.size.length == 2, 'size should return [rows, cols]'
  assert MASTER::TTY.width > 0, 'width should be positive'
  assert MASTER::TTY.height > 0, 'height should be positive'
  
  # Box drawing
  box = MASTER::TTY::Box.draw('Test', style: :single)
  assert box.include?('Test'), 'box should contain text'
  assert box.include?('┌'), 'box should have corners'
  
  # Progress bar (without rendering)
  pb = MASTER::TTY::ProgressBar.new(total: 100, width: 20)
  assert pb.current == 0, 'progress starts at 0'
  pb.advance(10)
  assert pb.current == 10, 'progress advances'
end

# Quality Module Tests
test_suite('Quality') do
  q = MASTER::Quality.new
  
  # Check deletions with no deletions
  result = q.check_deletions('')
  assert result.ok?, 'no deletions should pass'
  
  # Check autoloads
  result = q.check_autoloads
  assert result.ok?, 'autoload check should work'
end

# InfoArch Module Tests
test_suite('InfoArch') do
  # Breadcrumb
  bc = MASTER::InfoArch::Breadcrumb.new
  bc.push('A')
  bc.push('B')
  assert bc.to_s == 'A → B', 'breadcrumb should format correctly'
  assert bc.depth == 2, 'breadcrumb depth should be 2'
  bc.pop
  assert bc.depth == 1, 'breadcrumb depth should be 1 after pop'
  
  # Hierarchy
  h = MASTER::InfoArch::Hierarchy.new('Root')
  h.add_child('Child1')
  rendered = h.render
  assert rendered.include?('Root'), 'hierarchy should include root'
  assert rendered.include?('Child1'), 'hierarchy should include children'
  
  # Paginator
  p = MASTER::InfoArch::Paginator.new(total: 100, per_page: 20, page: 2)
  assert p.total_pages == 5, 'should calculate total pages'
  assert p.offset == 20, 'should calculate offset'
  assert p.has_next?, 'page 2 should have next'
  assert p.has_prev?, 'page 2 should have prev'
end

# LLM Circuit Breaker Tests
test_suite('LLM Circuit Breaker') do
  llm = MASTER::LLM.new(session_budget: 10.0, day_budget: 50.0)
  
  # Circuit breaker
  cb = llm.circuit_breaker
  assert cb.status[:failures].empty?, 'circuit breaker starts with no failures'
  cb.record_failure('test_provider')
  assert cb.status[:failures]['test_provider'] == 1, 'should record failure'
  cb.record_success('test_provider')
  assert cb.status[:failures]['test_provider'] == 0, 'should reset on success'
  
  # Cost tracker
  ct = llm.cost_tracker
  assert ct.session_cost == 0.0, 'cost tracker starts at 0'
  ct.track(1.5, tier: :test)
  assert ct.session_cost == 1.5, 'should track cost'
  assert ct.within_session_budget?(5.0), 'should be within budget'
  assert !ct.within_session_budget?(20.0), 'should exceed budget'
end

# Typography Tests
test_suite('Typography') do
  require 'ui'
  
  # Quotes
  text = '"test"'
  enhanced = MASTER::UI::Typography.typographic_quotes(text)
  assert enhanced.include?("\u201C"), 'should have left quote'
  assert enhanced.include?("\u201D"), 'should have right quote'
  
  # Em dashes
  text = 'test--test'
  enhanced = MASTER::UI::Typography.em_dashes(text)
  assert enhanced.include?('—'), 'should have em dash'
  
  # Ellipsis
  text = 'test...'
  enhanced = MASTER::UI::Typography.ellipsis(text)
  assert enhanced.include?('…'), 'should have ellipsis'
  
  # Wrapping
  text = 'a ' * 100
  wrapped = MASTER::UI::Typography.wrap(text, width: 40)
  lines = wrapped.split("\n")
  assert lines.all? { |l| l.length <= 40 }, 'all lines should be <= 40 chars'
end

# OpenBSD Config Generation Tests
test_suite('OpenBSD Config') do
  # relayd.conf
  conf = MASTER::OpenBSD.generate_relayd_conf(
    backend_host: 'localhost',
    backend_port: 3000
  )
  assert conf.include?('relay'), 'should have relay block'
  assert conf.include?('localhost:3000'), 'should have backend'
  
  # httpd.conf
  conf = MASTER::OpenBSD.generate_httpd_conf(
    server_name: 'test.com',
    root_path: '/var/www'
  )
  assert conf.include?('server'), 'should have server block'
  assert conf.include?('test.com'), 'should have server name'
  
  # pf.conf
  conf = MASTER::OpenBSD.generate_pf_rules(ports: [80, 443])
  assert conf.include?('block all'), 'should have default deny'
  assert conf.include?('pass in'), 'should have pass rules'
  assert conf.include?('80 443'), 'should have web ports'
end

# Evolve Saga Rollback Test
test_suite('Evolve Saga Rollback') do
  require 'evolve'
  require 'llm'
  require 'chamber'
  
  llm = MASTER::LLM.new
  evolve = MASTER::Evolve.new(llm)
  
  # Create a temp file to test rollback
  test_file = '/tmp/test_evolve_rollback.rb'
  File.write(test_file, "# original content\n")
  
  # Test successful modification
  result = evolve.safe_modify(test_file) do
    File.write(test_file, "# modified content\n")
  end
  
  assert result.ok?, 'safe_modify should succeed'
  assert File.read(test_file).include?('modified'), 'file should be modified'
  
  # Test rollback on syntax error
  File.write(test_file, "# valid ruby\n")
  result = evolve.safe_modify(test_file) do
    File.write(test_file, "invalid ruby syntax {{\n")
  end
  
  assert !result.ok?, 'safe_modify should fail on syntax error'
  assert File.read(test_file).include?('valid ruby'), 'file should be rolled back'
  
  File.delete(test_file)
end

puts "\n\nAll tests passed! ✓"
