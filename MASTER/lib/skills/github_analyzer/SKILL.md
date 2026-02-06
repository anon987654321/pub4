---
name: github-analyzer
description: Analyze GitHub repositories for metrics, activity, and trends
metadata:
  master:
    emoji: "📊"
    os: [darwin, linux, openbsd]
    requires:
      bins: []
      gems: [json]
    install:
      - kind: builtin
        name: json
---

# Usage

Analyze GitHub repositories to extract metrics like stars, commits, contributors, and activity patterns. Useful for ecosystem intelligence gathering and trend analysis.

## Examples

1. **Analyze a single repository**
   ```ruby
   analyzer = GitHubAnalyzer.new('owner/repo')
   stats = analyzer.analyze
   puts "Stars: #{stats[:stars]}, Forks: #{stats[:forks]}"
   ```

2. **Track repository activity**
   ```ruby
   analyzer = GitHubAnalyzer.new('owner/repo')
   activity = analyzer.recent_activity(days: 30)
   puts "Commits in last 30 days: #{activity[:commits]}"
   ```

3. **Compare multiple repositories**
   ```ruby
   repos = ['owner/repo1', 'owner/repo2', 'owner/repo3']
   comparison = GitHubAnalyzer.compare(repos)
   comparison.each { |repo, stats| puts "#{repo}: #{stats[:stars]} stars" }
   ```

## Requirements

- Ruby 3.0+
- OpenBSD 7.7+ (or macOS/Linux)
- GitHub API token (optional, for higher rate limits)

## Installation

### Via RubyGems
```sh
# JSON gem is included in Ruby standard library
# No additional installation needed
```

### Environment Setup
```sh
# Optional: Set GitHub token for higher API rate limits
export GITHUB_TOKEN=your_token_here
```

## Configuration

Set GitHub API token in environment:

```ruby
# Or configure in code
ENV['GITHUB_TOKEN'] = 'your_token_here'
```

## Notes

- Without authentication: 60 requests/hour
- With authentication: 5,000 requests/hour
- Respects GitHub API rate limits automatically
- Caches results to minimize API calls

## See Also

- MASTER Harvester (lib/harvester.rb) - Uses this skill
- GitHub API Documentation: https://docs.github.com/en/rest
- Related: ecosystem intelligence, skill discovery
