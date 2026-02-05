# Zsh Native Patterns

MASTER prefers zsh over bash for shell execution. Native parameter expansion avoids forking to awk/sed/grep/tr, improving performance and reducing token usage.

## String Operations

```zsh
# Remove CRLF
cleaned=${var//$'\r'/}

# Case conversion
lower=${(L)var}
upper=${(U)var}

# Replace all
result=${var//search/replace}

# Trim whitespace
trimmed=${${var##[[:space:]]#}%%[[:space:]]#}

# Extract field (comma-delimited)
fourth=${${(s:,:)line}[4]}

# Split to array
arr=( ${(s:delim:)var} )
```

## Array Operations

```zsh
# Filter matching (grep)
matches=( ${(M)arr:#*pattern*} )

# Exclude matching (grep -v)
non_matches=( ${arr:#*pattern*} )

# Unique (uniq)
unique=( ${(u)arr} )

# Join with delimiter
joined=${(j:,:)arr}

# Sort
sorted=( ${(o)arr} )
```

## File Operations

```zsh
# Read file to variable
content=$(<file.txt)

# Read lines to array
lines=( ${(f)"$(<file.txt)"} )

# Basename/dirname
name=${path:t}
dir=${path:h}
ext=${path:e}
noext=${path:r}
```

## Why zsh > bash

1. **No forks** - Parameter expansion replaces awk/sed/tr/grep
2. **Token efficient** - Shorter syntax, less verbose
3. **OpenBSD default** - Native on target platform
4. **Rich arrays** - Better than bash for list processing
