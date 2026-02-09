require 'json'

module MASTER
  # HTMLView - Generates visual dashboards for code quality
  # Provides real-time metrics and interactive refactoring UI
  class HTMLView
    attr_reader :template_dir

    def initialize(options = {})
      @template_dir = options[:template_dir] || File.join(MASTER.root, 'views')
      @theme = options[:theme] || 'dark'
    end

    # Generate dashboard HTML for a path
    def generate_dashboard(path)
      data = collect_metrics(path)
      render_template('dashboard', data)
    end

    # Generate violation cards
    def generate_violations(path)
      violations = detect_violations(path)
      render_violations_html(violations)
    end

    # Generate suggestions list
    def generate_suggestions(path)
      suggester = SmartSuggest.new
      suggestions = suggester.batch_analyze([path])
      render_suggestions_html(suggestions)
    end

    # Collect metrics for a path
    def collect_metrics(path)
      files = if File.directory?(path)
        Dir.glob(File.join(path, '**', '*.rb'))
      else
        [path]
      end

      metrics = {
        total_files: files.size,
        total_lines: 0,
        total_methods: 0,
        avg_complexity: 0,
        violations: [],
        suggestions: [],
        score: 0
      }

      files.each do |file|
        code = File.read(file)
        metrics[:total_lines] += code.lines.count
        metrics[:total_methods] += code.scan(/^\s*def\s+/).count
      end

      # Calculate quality score
      suggester = SmartSuggest.new
      all_suggestions = suggester.batch_analyze([path])
      metrics[:suggestions] = all_suggestions.take(10)
      
      # Calculate violations
      metrics[:violations] = detect_violations(path)
      
      # Calculate overall score (simplified)
      base_score = 100
      base_score -= metrics[:violations].size * 5
      base_score -= all_suggestions.size * 2
      metrics[:score] = [base_score, 0].max

      metrics
    end

    # Detect code violations
    def detect_violations(path)
      violations = []
      
      files = if File.directory?(path)
        Dir.glob(File.join(path, '**', '*.rb'))
      else
        [path]
      end

      files.each do |file|
        code = File.read(file)
        lines = code.lines.count
        methods = code.scan(/^\s*def\s+/).count
        
        # God class
        if lines > 500
          violations << {
            type: 'critical',
            title: "God Class: #{File.basename(file)}",
            description: "#{lines} lines, #{methods} methods",
            file: file,
            action: 'refactor'
          }
        end
        
        # Long method
        code.scan(/def\s+(\w+).*?^end/m).each do |match|
          method_name = match[0]
          method_code = match[0]
          if method_code && method_code.lines.count > 30
            violations << {
              type: 'warning',
              title: "Long Method: #{method_name}",
              description: "#{method_code.lines.count} lines",
              file: file,
              action: 'extract_method'
            }
          end
        end
      end

      violations
    end

    # Render template with data
    def render_template(template_name, data)
      template_file = File.join(@template_dir, "#{template_name}.html.erb")
      
      if File.exist?(template_file)
        template = File.read(template_file)
        render_erb(template, data)
      else
        # Generate default dashboard HTML
        generate_default_dashboard(data)
      end
    end

    private

    def render_erb(template, data)
      # Simple ERB-like rendering without requiring ERB
      # Replace <%= expressions %> with actual data
      html = template.dup
      
      data.each do |key, value|
        html.gsub!("<%=\s*#{key}\s*%>", value.to_s)
      end
      
      html
    end

    def generate_default_dashboard(data)
      html = <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>MASTER Dashboard</title>
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
              background: #{@theme == 'dark' ? '#1a1a1a' : '#f5f5f5'};
              color: #{@theme == 'dark' ? '#e0e0e0' : '#333'};
              padding: 20px;
            }
            .master-dashboard {
              max-width: 1200px;
              margin: 0 auto;
            }
            h1 {
              font-size: 2.5em;
              margin-bottom: 10px;
              color: #{@theme == 'dark' ? '#4CAF50' : '#2196F3'};
            }
            .score {
              font-size: 4em;
              font-weight: bold;
              color: #{get_score_color(data[:score])};
              margin: 20px 0;
            }
            .metrics {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
              gap: 20px;
              margin: 30px 0;
            }
            .metric-card {
              background: #{@theme == 'dark' ? '#2a2a2a' : 'white'};
              padding: 20px;
              border-radius: 8px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            .metric-card h3 {
              font-size: 0.9em;
              text-transform: uppercase;
              color: #888;
              margin-bottom: 10px;
            }
            .metric-card .value {
              font-size: 2em;
              font-weight: bold;
            }
            .violations {
              margin: 30px 0;
            }
            .violation {
              background: #{@theme == 'dark' ? '#2a2a2a' : 'white'};
              padding: 20px;
              border-radius: 8px;
              margin-bottom: 15px;
              border-left: 4px solid;
            }
            .violation.critical { border-left-color: #f44336; }
            .violation.warning { border-left-color: #ff9800; }
            .violation.info { border-left-color: #2196F3; }
            .violation h3 {
              margin-bottom: 10px;
              font-size: 1.2em;
            }
            .violation p {
              color: #888;
              margin-bottom: 15px;
            }
            .violation button {
              background: #4CAF50;
              color: white;
              border: none;
              padding: 10px 20px;
              border-radius: 4px;
              cursor: pointer;
              font-size: 1em;
            }
            .violation button:hover {
              background: #45a049;
            }
            .suggestions {
              margin: 30px 0;
            }
            .suggestions h2 {
              margin-bottom: 20px;
            }
            .suggestions ul {
              list-style: none;
            }
            .suggestions li {
              background: #{@theme == 'dark' ? '#2a2a2a' : 'white'};
              padding: 15px;
              margin-bottom: 10px;
              border-radius: 8px;
              display: flex;
              justify-content: space-between;
              align-items: center;
            }
            .suggestion-impact {
              display: inline-block;
              padding: 4px 8px;
              border-radius: 4px;
              font-size: 0.8em;
              margin-left: 10px;
            }
            .impact-high { background: #f44336; color: white; }
            .impact-medium { background: #ff9800; color: white; }
            .impact-low { background: #4CAF50; color: white; }
          </style>
        </head>
        <body>
          <div class="master-dashboard">
            <h1>MASTER Code Quality Dashboard</h1>
            <div class="score">#{data[:score]}/100</div>
            
            <div class="metrics">
              <div class="metric-card">
                <h3>Files</h3>
                <div class="value">#{data[:total_files]}</div>
              </div>
              <div class="metric-card">
                <h3>Lines of Code</h3>
                <div class="value">#{data[:total_lines]}</div>
              </div>
              <div class="metric-card">
                <h3>Methods</h3>
                <div class="value">#{data[:total_methods]}</div>
              </div>
              <div class="metric-card">
                <h3>Violations</h3>
                <div class="value">#{data[:violations].size}</div>
              </div>
            </div>

            #{render_violations_html(data[:violations])}
            #{render_suggestions_html(data[:suggestions])}
          </div>

          <script>
            function refactor(file) {
              alert('Refactoring ' + file + '... (not implemented in demo)');
              // In production, this would make an API call to trigger refactoring
            }
          </script>
        </body>
        </html>
      HTML

      html
    end

    def render_violations_html(violations)
      return "" if violations.empty?
      
      html = "<div class=\"violations\">\n"
      html += "  <h2>🚨 Code Violations</h2>\n"
      
      violations.each do |v|
        html += <<~HTML
          <div class="violation #{v[:type]}">
            <h3>#{v[:title]}</h3>
            <p>#{v[:description]}</p>
            <button onclick="refactor('#{v[:file]}')">Auto-Fix</button>
          </div>
        HTML
      end
      
      html += "</div>\n"
      html
    end

    def render_suggestions_html(suggestions)
      return "" if suggestions.empty?
      
      html = "<div class=\"suggestions\">\n"
      html += "  <h2>💡 Smart Suggestions</h2>\n"
      html += "  <ul>\n"
      
      suggestions.each do |s|
        impact_class = "impact-#{s.impact}"
        html += <<~HTML
          <li>
            <span>
              #{s.description}
              <span class="suggestion-impact #{impact_class}">+#{s.priority.round} maintainability</span>
            </span>
            <button onclick="refactor('#{s.file}')">Apply</button>
          </li>
        HTML
      end
      
      html += "  </ul>\n"
      html += "</div>\n"
      html
    end

    def get_score_color(score)
      if score >= 90
        '#4CAF50'
      elsif score >= 70
        '#ff9800'
      else
        '#f44336'
      end
    end
  end
end
