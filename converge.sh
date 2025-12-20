#!/usr/bin/env zsh
# Convergence loop - auto-iterative quality enforcement
# Implements: assess → detect → fix → verify → repeat

set -euo pipefail

readonly SCRIPT_DIR="${0:a:h}"
readonly LIB_DIR="${SCRIPT_DIR}/lib/converge"
readonly STATE_FILE="${SCRIPT_DIR}/.convergence_state.json"
readonly TMP_DIR="/tmp/converge_$$"
readonly MAX_ITERATIONS=10
readonly TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Config from master.yml
typeset -a TARGETS
TARGETS=(
  "rails/**/*.rb"
  "rails/**/*.sh"
  "openbsd/**/*.sh"
)

# Flags
AUTO_FIX=true
STOP_ON_ERROR=false
CI_MODE=false
DRY_RUN=false

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ci-mode)
      CI_MODE=true
      AUTO_FIX=false
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --no-fix)
      AUTO_FIX=false
      ;;
    --stop-on-error)
      STOP_ON_ERROR=true
      ;;
    --max-iterations)
      MAX_ITERATIONS=$2
      shift
      ;;
    *)
      print "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

# Logging
log() {
  local level="$1"
  shift
  printf '[%s] %-5s %s\n' "$(date +%H:%M:%S)" "$level" "$*"
}

error() {
  log "ERROR" "$*"
  exit 1
}

# Setup
mkdir -p "$TMP_DIR"
trap "rm -rf '$TMP_DIR'" EXIT INT TERM

# Check dependencies
check_deps() {
  log "INFO" "Checking dependencies..."
  
  command -v ruby >/dev/null 2>&1 || error "ruby not found"
  command -v git >/dev/null 2>&1 || error "git not found"
  
  [[ -f "${LIB_DIR}/analyzer.rb" ]] || error "analyzer.rb not found"
  [[ -f "${LIB_DIR}/shell_analyzer.rb" ]] || error "shell_analyzer.rb not found"
  [[ -f "${LIB_DIR}/reporter.rb" ]] || error "reporter.rb not found"
  [[ -f "${LIB_DIR}/fixer.rb" ]] || error "fixer.rb not found"
  
  log "INFO" "Dependencies OK"
}

# Analyze code
analyze() {
  local iteration=$1
  log "INFO" "Iteration ${iteration}: Analyzing..."
  
  local ruby_out="${TMP_DIR}/ruby_violations_${iteration}.json"
  local shell_out="${TMP_DIR}/shell_violations_${iteration}.json"
  local merged="${TMP_DIR}/violations_${iteration}.json"
  
  # Analyze Ruby files
  ruby "${LIB_DIR}/analyzer.rb" ${TARGETS[@]} > "$ruby_out" 2>/dev/null || {
    log "WARN" "Ruby analysis failed"
    print '{"violations":[]}' > "$ruby_out"
  }
  
  # Analyze shell files
  ruby "${LIB_DIR}/shell_analyzer.rb" ${TARGETS[@]} > "$shell_out" 2>/dev/null || {
    log "WARN" "Shell analysis failed"
    print '{"violations":[]}' > "$shell_out"
  }
  
  # Merge reports
  ruby "${LIB_DIR}/reporter.rb" "$ruby_out" "$shell_out" > "${TMP_DIR}/report_${iteration}.txt"
  
  # Count violations using ruby for JSON parsing
  local ruby_count=$(ruby -rjson -e "puts JSON.parse(File.read('$ruby_out'))['violations'].size" 2>/dev/null || print "0")
  local shell_count=$(ruby -rjson -e "puts JSON.parse(File.read('$shell_out'))['violations'].size" 2>/dev/null || print "0")
  
  # Create merged violations file
  cat "$ruby_out" "$shell_out" | ruby -rjson -e 'data = ARGF.read; jsons = data.scan(/\{[^}]+\}.*?\}/m); violations = []; jsons.each { |j| begin; parsed = JSON.parse(j); violations.concat(parsed["violations"] || []); rescue; end }; puts JSON.generate({violations: violations})' > "$merged"
  
  log "INFO" "Found violations: Ruby=${ruby_count} Shell=${shell_count}"
  
  print "$merged"
}

  # Auto-fix violations
auto_fix() {
  local violations_file="$1"
  local iteration=$2
  
  [[ "$AUTO_FIX" == "false" ]] && return 0
  
  log "INFO" "Iteration ${iteration}: Attempting auto-fixes..."
  
  local fix_out="${TMP_DIR}/fixes_${iteration}.json"
  local dry_run_flag=""
  [[ "$DRY_RUN" == "true" ]] && dry_run_flag="--dry-run"
  
  ruby "${LIB_DIR}/fixer.rb" "$violations_file" $dry_run_flag > "$fix_out" 2>/dev/null || {
    log "WARN" "Auto-fix failed"
    return 1
  }
  
  # Count fixes using ruby
  local fixes_count=$(ruby -rjson -e "puts JSON.parse(File.read('$fix_out'))['fixes_applied']" 2>/dev/null || print "0")
  log "INFO" "Applied ${fixes_count} fixes"
  
  return 0
}

# Check convergence
check_convergence() {
  local violations_file="$1"
  
  # Count total violations using ruby
  local count=$(ruby -rjson -e "puts JSON.parse(File.read('$violations_file'))['violations'].size" 2>/dev/null || print "0")
  
  [[ "$count" -eq 0 ]]
}

# Save state
save_state() {
  local iteration=$1
  local violations_count=$2
  local converged=$3
  
  cat > "$STATE_FILE" << EOF
{
  "timestamp": "$TIMESTAMP",
  "iterations": $iteration,
  "violations": $violations_count,
  "converged": $converged,
  "auto_fix": $AUTO_FIX,
  "ci_mode": $CI_MODE
}
EOF
}

# Main convergence loop
main() {
  log "INFO" "=== Convergence Loop Started ==="
  log "INFO" "Max iterations: $MAX_ITERATIONS"
  log "INFO" "Auto-fix: $AUTO_FIX"
  log "INFO" "CI mode: $CI_MODE"
  
  check_deps
  
  local iteration=0
  local converged=false
  local prev_violations=-1
  
  while [[ $iteration -lt $MAX_ITERATIONS ]]; do
    iteration=$((iteration + 1))
    
    log "INFO" "=== Iteration ${iteration}/${MAX_ITERATIONS} ==="
    
    # Analyze
    local violations_file=$(analyze $iteration)
    
    # Check for convergence
    if check_convergence "$violations_file"; then
      log "INFO" "✓ Converged! No violations found."
      converged=true
      save_state $iteration 0 true
      break
    fi
    
    # Count current violations using ruby
    local current_violations=$(ruby -rjson -e "puts JSON.parse(File.read('$violations_file'))['violations'].size" 2>/dev/null || print "0")
    
    log "INFO" "Current violations: $current_violations"
    
    # Check if we're making progress
    if [[ $prev_violations -ne -1 && $current_violations -ge $prev_violations ]]; then
      log "WARN" "No progress made (${current_violations} >= ${prev_violations})"
      
      if [[ "$STOP_ON_ERROR" == "true" ]]; then
        log "ERROR" "Stopping due to lack of progress"
        save_state $iteration $current_violations false
        exit 1
      fi
    fi
    
    prev_violations=$current_violations
    
    # Attempt fixes
    if [[ "$AUTO_FIX" == "true" ]]; then
      auto_fix "$violations_file" $iteration
    fi
    
    # In CI mode, fail if violations exist
    if [[ "$CI_MODE" == "true" ]]; then
      log "ERROR" "CI mode: violations detected"
      cat "${TMP_DIR}/report_${iteration}.txt"
      save_state $iteration $current_violations false
      exit 1
    fi
    
    # Small delay between iterations
    sleep 1
  done
  
  if [[ "$converged" == "false" ]]; then
    log "WARN" "Did not converge after $MAX_ITERATIONS iterations"
    log "INFO" "Remaining violations: $prev_violations"
    save_state $MAX_ITERATIONS $prev_violations false
    
    # Show final report
    [[ -f "${TMP_DIR}/report_${iteration}.txt" ]] && cat "${TMP_DIR}/report_${iteration}.txt"
    
    [[ "$CI_MODE" == "true" ]] && exit 1
  fi
  
  log "INFO" "=== Convergence Loop Complete ==="
}

main
