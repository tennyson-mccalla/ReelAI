#!/bin/bash

# Directories/patterns to exclude
EXCLUDE_PATTERNS=(
    -not -path "*/\.*"           # Hidden files/folders
    -not -path "*/node_modules/*" # Node modules
    -not -path "*/Pods/*"        # CocoaPods
    -not -path "*/build/*"       # Build directories
    -not -path "*/vendor/*"      # Vendor directories
    -not -path "*/xcuserdata/*"  # Xcode user data
    -not -path "*/DerivedData/*" # Xcode derived data
)

# File extensions to exclude
EXCLUDE_EXTENSIONS=(
    -not -name "*.md"        # Markdown files
    -not -name "*.pbxproj"   # Xcode project files
    -not -name "*.json"      # JSON files
    -not -name "*.png"       # PNG images
    -not -name "*.jpg"       # JPEG images
    -not -name "*.jpeg"      # JPEG images
    -not -name "*.gif"       # GIF images
    -not -name "*.svg"       # SVG images
    -not -name "*.ico"       # Icon files
    -not -name "*.lock"      # Lock files
    -not -name "*.plist"     # Property list files
    -not -name "*.xcscheme"  # Xcode scheme files
)

# Find all files, count lines, sort by line count, and take top 10
find . -type f "${EXCLUDE_PATTERNS[@]}" "${EXCLUDE_EXTENSIONS[@]}" -exec wc -l {} \; | \
    sort -nr | \
    head -n 10 | \
    awk '{
        printf "%6d lines  ", $1;  # Print line count
        for(i=2; i<=NF; i++) {    # Print filename without "./"
            if(i>2) printf " ";
            sub(/^\.\//, "", $i);  # Remove leading "./"
            printf "%s", $i
        }
        printf "\n"
    }'
