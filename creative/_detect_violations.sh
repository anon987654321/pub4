#!/usr/bin/env zsh
set -euo pipefail

# Master.yml detector runner
# Implements master.yml v13.20.0 detectors using zsh builtins only

detect_violations() {
  local file=$1
  local violations=0
  
  echo "Scanning: $file"
  
  # DRY: logic_repeated_3x
  content=$(<$file)
  lines=(${(f)content})
  typeset -A seen
  for ((i=1; i<=${#lines}; i++)); do
    line=${lines[$i]##[[:space:]]##}
    [[ -z $line || $line =~ ^# ]] && continue
    ((seen[$line]++))
    if ((seen[$line] == 3)); then
      echo "  DRY: line repeated 3x at $i: ${line[1,60]}"
      ((violations++))
    fi
  done
  
  # KISS: nesting_exceeds_2
  max_nesting=0
  for ((i=1; i<=${#lines}; i++)); do
    line=${lines[$i]}
    indent=${#${line%%[^[:space:]]*}}
    nesting=$((indent / 2))
    ((nesting > max_nesting)) && max_nesting=$nesting
    if ((nesting > 2)); then
      echo "  KISS: nesting=$nesting exceeds 2 at line $i"
      ((violations++))
    fi
  done
  
  # STRUNK_WHITE: passive_voice
  passives=("is being" "was being" "has been" "have been" "will be" "should be" "can be" "could be" "may be" "might be")
  for ((i=1; i<=${#lines}; i++)); do
    line=${lines[$i]}
    [[ $line =~ : || $line =~ ^[[:space:]]*# || $line =~ ^[[:space:]]*$ ]] && continue
    for indicator in $passives; do
      if [[ ${(L)line} =~ ${indicator} ]]; then
        echo "  STRUNK_WHITE: passive voice at $i ('$indicator')"
        ((violations++))
        break
      fi
    done
  done
  
  # STRUNK_WHITE: vague_language
  vague=("very" "really" "quite" "rather" "somewhat" "fairly" "basically" "generally" "usually" "typically" "stuff" "things")
  for ((i=1; i<=${#lines}; i++)); do
    line=${lines[$i]}
    [[ $line =~ : || $line =~ ^[[:space:]]*# || $line =~ ^[[:space:]]*$ ]] && continue
    for term in $vague; do
      if [[ ${(L)line} =~ "[[:space:]]${term}[[:space:]]" ]]; then
        echo "  STRUNK_WHITE: vague at $i ('$term')"
        ((violations++))
        break
      fi
    done
  done
  
  echo "  Total violations: $violations"
  echo ""
  return $violations
}

total=0
for file in dilla.rb postpro.rb repligen.rb; do
  if [[ -f $file ]]; then
    detect_violations $file
    total=$((total + $?))
  fi
done

echo "Grand total violations: $total"
exit $total
