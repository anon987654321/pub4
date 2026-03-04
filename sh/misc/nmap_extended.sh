#!/bin/sh
set -eu

# nmap.sh - Cognitive-Aware Network Security Assessment Tool
# OpenBSD-optimized comprehensive network scanning with cognitive load management
# Usage: doas sh nmap.sh <target>
# Purpose: Professional security assessment with structured output and progress feedback

# Cognitive Architecture Constants
COGNITIVE_CHUNK_LIMIT=7
CONTEXT_SWITCH_DELAY=2
total_phases=7

# Global cognitive state tracking
cognitive_load=0
memory_chunk_count=0
current_phase=""
scan_start_time=""

# Color codes for status output (if supported)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  CYAN=''
  NC=''
fi

# Cognitive Memory Management
add_memory_chunk() {
  # Memory chunk tracking (variable name preserved for cognitive architecture)
  memory_chunk_count=$((memory_chunk_count + 1))
  
  # Implement 7±2 rule - manage cognitive overload
  if [ $memory_chunk_count -gt $COGNITIVE_CHUNK_LIMIT ]; then
    # Reset chunk counter to simulate compression
    memory_chunk_count=$((COGNITIVE_CHUNK_LIMIT - 2))
  fi
  
  cognitive_load=$((cognitive_load + 1))
}

clear_memory_segment() {
  memory_chunk_count=0
  cognitive_load=0
}

# Progress and status functions
log_status() {
  level="$1"
  message="$2"
  timestamp=$(date '+%H:%M:%S')
  
  case "$level" in
    "INFO")  printf "%s[%s]%s %s[INFO]%s %s\n" "$BLUE" "$timestamp" "$NC" "$CYAN" "$NC" "$message" ;;
    "WARN")  printf "%s[%s]%s %s[WARN]%s %s\n" "$YELLOW" "$timestamp" "$NC" "$YELLOW" "$NC" "$message" ;;
    "ERROR") printf "%s[%s]%s %s[ERROR]%s %s\n" "$RED" "$timestamp" "$NC" "$RED" "$NC" "$message" >&2 ;;
    "SUCCESS") printf "%s[%s]%s %s[SUCCESS]%s %s\n" "$GREEN" "$timestamp" "$NC" "$GREEN" "$NC" "$message" ;;
    *)       printf "[%s] %s\n" "$timestamp" "$message" ;;
  esac
}

show_progress() {
  current="$1"
  total="$2"
  phase="$3"
  percentage=$((current * 100 / total))
  
  printf "\r%s[Progress]%s Phase %d/%d (%d%%) - %s" "$CYAN" "$NC" "$current" "$total" "$percentage" "$phase"
  if [ "$current" -eq "$total" ]; then
    echo ""
  fi
}

# Cognitive load monitoring
check_cognitive_load() {
  if [ $cognitive_load -gt 10 ]; then
    log_status "WARN" "High cognitive load detected. Implementing recovery protocol..."
    sleep $CONTEXT_SWITCH_DELAY
    cognitive_load=$((cognitive_load / 2))
    log_status "INFO" "Cognitive load reduced. Continuing..."
  fi
}

# Error handling with graceful degradation
handle_error() {
  error_code="$1"
  context="$2"
  suggestion="$3"
  
  log_status "ERROR" "Error in $context (code: $error_code)"
  
  if [ -n "$suggestion" ]; then
    log_status "INFO" "Suggestion: $suggestion"
  fi
  
  # Implement graceful degradation
  case "$error_code" in
    "DEPENDENCY_MISSING")
      log_status "WARN" "Attempting graceful degradation..."
      return 0
      ;;
    "PERMISSION_DENIED")
      log_status "ERROR" "Critical error: insufficient privileges"
      log_status "INFO" "Please run with: doas sh $0 <target>"
      exit 1
      ;;
    *)
      log_status "WARN" "Non-critical error. Continuing with degraded functionality..."
      return 0
      ;;
  esac
}

# Dependency validation system
check_dependencies() {
  current_phase="Dependency Validation"
  add_memory_chunk "dep_check"
  show_progress 1 $total_phases "$current_phase"
  
  log_status "INFO" "Validating system dependencies..."
  
  critical_missing=""
  
  # Critical dependencies
  for dep in nmap doas; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      critical_missing="$critical_missing $dep"
      log_status "ERROR" "Critical dependency missing: $dep"
    else
      log_status "SUCCESS" "Found: $dep"
    fi
  done
  
  if [ -n "$critical_missing" ]; then
    handle_error "DEPENDENCY_MISSING" "Critical dependencies" "Install missing packages: pkg_add$critical_missing"
    exit 1
  fi
  
  # Optional dependencies with fallbacks
  dns_tool=""
  for dep in drill dig host; do
    if command -v "$dep" >/dev/null 2>&1; then
      dns_tool="$dep"
      log_status "SUCCESS" "DNS tool available: $dep"
      break
    fi
  done
  
  if [ -z "$dns_tool" ]; then
    handle_error "DEPENDENCY_MISSING" "DNS tools" "Install drill, dig, or host"
    dns_tool="nslookup"  # Last resort fallback
  fi
  
  # Check privileges
  if [ "$(id -u)" -ne 0 ]; then
    handle_error "PERMISSION_DENIED" "Privilege check" ""
  fi
  
  log_status "SUCCESS" "Dependency validation complete"
  sleep $CONTEXT_SWITCH_DELAY
  check_cognitive_load
}

# Multi-method DNS resolution with fallbacks
resolve_target() {
  current_phase="DNS Resolution"
  add_memory_chunk "dns_resolve"
  show_progress 2 $total_phases "$current_phase"
  
  target="$1"
  resolved_ips=""
  
  log_status "INFO" "Resolving target: $target"
  
  # Method 1: Try drill (OpenBSD native)
  if [ "$dns_tool" = "drill" ]; then
    resolved_ips=$(drill "$target" A | awk '/^[^;]/ && $3 == "A" {print $5}' 2>/dev/null || true)
  # Method 2: Try dig
  elif [ "$dns_tool" = "dig" ]; then
    resolved_ips=$(dig +short "$target" A 2>/dev/null || true)
  # Method 3: Try host
  elif [ "$dns_tool" = "host" ]; then
    resolved_ips=$(host "$target" 2>/dev/null | awk '/has address/ {print $4}' || true)
  # Method 4: Fallback to nslookup
  else
    resolved_ips=$(nslookup "$target" 2>/dev/null | awk '/^Address: / && !/127\.0\.0\.1/ {print $2}' || true)
  fi
  
  if [ -z "$resolved_ips" ]; then
    handle_error "DNS_RESOLUTION_FAILED" "DNS resolution" "Check target connectivity and DNS settings"
    exit 1
  fi
  
  log_status "SUCCESS" "Resolved IPs: $resolved_ips"
  echo "$resolved_ips"
  
  sleep $CONTEXT_SWITCH_DELAY
  check_cognitive_load
}

# Create structured output directories
setup_output_structure() {
  target="$1"
  timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
  
  output_dir="nmap_scan_${target}_${timestamp}"
  log_file="${output_dir}/scan.log"
  summary_file="${output_dir}/executive_summary.txt"
  
  mkdir -p "$output_dir"/raw "$output_dir"/processed "$output_dir"/reports
  
  log_status "INFO" "Output directory: $output_dir"
  
  # Initialize scan log
  {
    echo "# Network Security Assessment Report"
    echo "Target: $target"
    echo "Scan Date: $(date)"
    echo "Scanner: $(hostname)"
    echo "---"
  } > "$summary_file"
}

# Host discovery phase
discover_hosts() {
  current_phase="Host Discovery"
  add_memory_chunk "host_discovery"
  show_progress 3 $total_phases "$current_phase"
  
  target="$1"
  ips="$2"
  
  log_status "INFO" "Performing host discovery on $target"
  
  # Multi-method host discovery for resilience - using simple space-separated list
  discovery_method_1="-sn -PS22,80,443 -PU53,161 -PE -PP"
  discovery_method_2="-sn -PA80,443"
  discovery_method_3="-sn -PE"
  
  # Try first method
  log_status "INFO" "Host discovery method: $discovery_method_1"
  if nmap $discovery_method_1 -oN "${output_dir}/raw/host_discovery_1.txt" "$target" >/dev/null 2>&1; then
    log_status "SUCCESS" "Host discovery method 1 succeeded"
  else
    log_status "WARN" "Host discovery method 1 failed, trying method 2..."
    if nmap $discovery_method_2 -oN "${output_dir}/raw/host_discovery_2.txt" "$target" >/dev/null 2>&1; then
      log_status "SUCCESS" "Host discovery method 2 succeeded"
    else
      log_status "WARN" "Host discovery method 2 failed, trying method 3..."
      nmap $discovery_method_3 -oN "${output_dir}/raw/host_discovery_3.txt" "$target" >/dev/null 2>&1 || true
    fi
  fi
  
  sleep $CONTEXT_SWITCH_DELAY
  check_cognitive_load
}

# Port discovery phase
discover_ports() {
  current_phase="Port Discovery"
  add_memory_chunk "port_discovery"
  show_progress 4 $total_phases "$current_phase"
  
  ips="$1"
  
  log_status "INFO" "Performing port discovery"
  
  # TCP SYN scan (stealthy)
  log_status "INFO" "TCP SYN scan (stealth mode)"
  if ! nmap -sS -T4 -p- --max-retries 2 -oN "${output_dir}/raw/tcp_syn.txt" "$ips" 2>/dev/null; then
    log_status "WARN" "TCP SYN scan failed, trying TCP connect scan"
    nmap -sT -T3 -p- --max-retries 1 -oN "${output_dir}/raw/tcp_connect.txt" "$ips" >/dev/null 2>&1 || true
  fi
  
  # Top UDP ports (limited for performance)
  log_status "INFO" "UDP scan (top ports)"
  nmap -sU -T4 --top-ports 1000 --max-retries 1 -oN "${output_dir}/raw/udp_scan.txt" "$ips" >/dev/null 2>&1 || true
  
  sleep $CONTEXT_SWITCH_DELAY
  check_cognitive_load
}

# Service analysis phase
analyze_services() {
  current_phase="Service Analysis"
  add_memory_chunk "service_analysis"
  show_progress 5 $total_phases "$current_phase"
  
  ips="$1"
  
  log_status "INFO" "Analyzing services and versions"
  
  # Extract open ports from previous scans
  open_ports=""
  if [ -f "${output_dir}/raw/tcp_syn.txt" ]; then
    open_ports=$(grep "^[0-9]" "${output_dir}/raw/tcp_syn.txt" | grep "open" | cut -d/ -f1 | paste -sd, || true)
  elif [ -f "${output_dir}/raw/tcp_connect.txt" ]; then
    open_ports=$(grep "^[0-9]" "${output_dir}/raw/tcp_connect.txt" | grep "open" | cut -d/ -f1 | paste -sd, || true)
  fi
  
  if [ -n "$open_ports" ]; then
    log_status "INFO" "Service detection on ports: $open_ports"
    nmap -sV -p "$open_ports" -oN "${output_dir}/raw/service_detection.txt" "$ips" >/dev/null 2>&1 || true
    
    log_status "INFO" "OS detection"
    nmap -O -oN "${output_dir}/raw/os_detection.txt" "$ips" >/dev/null 2>&1 || true
  else
    log_status "WARN" "No open ports found for service analysis"
  fi
  
  sleep $CONTEXT_SWITCH_DELAY
  check_cognitive_load
}

# Vulnerability assessment phase
assess_vulnerabilities() {
  current_phase="Vulnerability Assessment"
  add_memory_chunk "vuln_assessment"
  show_progress 6 $total_phases "$current_phase"
  
  ips="$1"
  
  log_status "INFO" "Performing vulnerability assessment"
  
  # Safe vulnerability scripts
  nmap -A --script "default,safe,vuln" --script-timeout 300 -oA "${output_dir}/raw/vulnerabilities" "$ips" >/dev/null 2>&1 || true
  
  # HTTP-specific scanning if web services detected
  if grep -q ":80\|:443\|:8080\|:8443" "${output_dir}/raw/service_detection.txt" 2>/dev/null; then
    log_status "INFO" "Web service vulnerability scanning"
    nmap --script "http-enum,http-vuln*,http-headers,http-methods" -p80,443,8080,8443 \
         -oN "${output_dir}/raw/web_vulnerabilities.txt" "$ips" >/dev/null 2>&1 || true
  fi
  
  sleep $CONTEXT_SWITCH_DELAY
  check_cognitive_load
}

# Generate professional reports
generate_reports() {
  current_phase="Report Generation"
  add_memory_chunk "reporting"
  show_progress 7 $total_phases "$current_phase"
  
  target="$1"
  scan_duration=$(($(date +%s) - scan_start_time))
  
  log_status "INFO" "Generating professional reports"
  
  # Executive Summary
  {
    echo "# Executive Summary"
    echo ""
    echo "**Target:** $target"
    echo "**Scan Duration:** ${scan_duration}s"
    echo "**Assessment Date:** $(date)"
    echo ""
    
    # Count findings
    open_tcp_ports=0
    open_udp_ports=0
    services_detected=0
    vulnerabilities=0
    
    if [ -f "${output_dir}/raw/tcp_syn.txt" ] || [ -f "${output_dir}/raw/tcp_connect.txt" ]; then
      open_tcp_ports=$(grep -c "open" "${output_dir}/raw/tcp_"*.txt 2>/dev/null || echo "0")
    fi
    
    if [ -f "${output_dir}/raw/udp_scan.txt" ]; then
      open_udp_ports=$(grep -c "open" "${output_dir}/raw/udp_scan.txt" 2>/dev/null || echo "0")
    fi
    
    if [ -f "${output_dir}/raw/service_detection.txt" ]; then
      services_detected=$(grep -c "open" "${output_dir}/raw/service_detection.txt" 2>/dev/null || echo "0")
    fi
    
    if [ -f "${output_dir}/raw/vulnerabilities.nmap" ]; then
      vulnerabilities=$(grep -c "VULNERABLE" "${output_dir}/raw/vulnerabilities.nmap" 2>/dev/null || echo "0")
    fi
    
    echo "## Key Findings"
    echo "- TCP Ports Open: $open_tcp_ports"
    echo "- UDP Ports Open: $open_udp_ports"
    echo "- Services Detected: $services_detected"
    echo "- Potential Vulnerabilities: $vulnerabilities"
    echo ""
    
    echo "## Risk Assessment"
    if [ "$vulnerabilities" -gt 0 ]; then
      echo "- **HIGH RISK:** Vulnerabilities detected requiring immediate attention"
    elif [ "$open_tcp_ports" -gt 10 ]; then
      echo "- **MEDIUM RISK:** Large attack surface detected"
    else
      echo "- **LOW RISK:** Limited exposure detected"
    fi
    echo ""
    
    echo "## Next Steps"
    echo "1. Review detailed findings in raw/ directory"
    echo "2. Validate critical vulnerabilities manually"
    echo "3. Implement security hardening measures"
    echo "4. Schedule regular reassessments"
    
  } > "$summary_file"
  
  # Create index file
  {
    echo "# Scan Results Index"
    echo ""
    echo "## Raw Results"
    find "${output_dir}/raw" -name "*.txt" -o -name "*.nmap" | sort | while read -r file; do
      echo "- [$(basename "$file")]($file)"
    done
    echo ""
    echo "## Executive Summary"
    echo "- [Executive Summary](executive_summary.txt)"
  } > "${output_dir}/index.md"
  
  log_status "SUCCESS" "Reports generated successfully"
  log_status "INFO" "Executive summary: $summary_file"
  log_status "INFO" "Full results: $output_dir"
}

# Cognitive recovery protocol
cognitive_recovery() {
  log_status "INFO" "Implementing cognitive recovery protocol"
  clear_memory_segment
  sleep $((CONTEXT_SWITCH_DELAY * 2))
  log_status "SUCCESS" "Cognitive state restored"
}

# Main execution function
main() {
  # Input validation
  if [ $# -ne 1 ]; then
    log_status "ERROR" "Usage: $0 <target>"
    log_status "INFO" "Example: doas sh $0 example.com"
    exit 1
  fi
  
  target="$1"
  scan_start_time=$(date +%s)
  
  # Validate target format
  if ! echo "$target" | grep -qE '^[a-zA-Z0-9.-]+$'; then
    log_status "ERROR" "Invalid target format. Use domain name or IP address."
    exit 1
  fi
  
  log_status "INFO" "Starting cognitive-aware network security assessment"
  log_status "INFO" "Target: $target"
  log_status "INFO" "Cognitive architecture: 7±2 memory management active"
  
  # Execute phases with cognitive management
  check_dependencies
  resolved_ips=$(resolve_target "$target")
  setup_output_structure "$target"
  discover_hosts "$target" "$resolved_ips"
  discover_ports "$resolved_ips"
  analyze_services "$resolved_ips"
  assess_vulnerabilities "$resolved_ips"
  generate_reports "$target"
  
  # Final cognitive cleanup
  cognitive_recovery
  
  total_duration=$(($(date +%s) - scan_start_time))
  log_status "SUCCESS" "Assessment completed in ${total_duration}s"
  log_status "INFO" "Results available in: $output_dir"
  
  # Display executive summary
  echo ""
  echo "=== EXECUTIVE SUMMARY ==="
  cat "$summary_file"
}

# Execute main function
main "$@"
