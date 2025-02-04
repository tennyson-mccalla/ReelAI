#!/bin/bash

echo "🔍 Scanning repository for potential sensitive data..."

# Patterns to search for
PATTERNS=(
    # API Keys and Tokens
    '[a-zA-Z0-9_-]*[aA][pP][iI][_-][kK][eE][yY][a-zA-Z0-9_-]*'
    '[a-zA-Z0-9_-]*[tT][oO][kK][eE][nN][a-zA-Z0-9_-]*'
    
    # Firebase specific
    'GoogleService-Info\.plist'
    'AIza[0-9A-Za-z_-]{35}'  # Fixed the range syntax
    
    # Generic secrets
    '[a-zA-Z0-9_-]*[sS][eE][cC][rR][eE][tT][a-zA-Z0-9_-]*'
    '[a-zA-Z0-9_-]*[pP][aA][sS][sS][wW][oO][rR][dD][a-zA-Z0-9_-]*'
    
    # Email addresses
    '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,6}'
    
    # Private keys (using fixed strings instead of patterns)
    'BEGIN PRIVATE KEY'
    'BEGIN RSA PRIVATE KEY'
    'BEGIN DSA PRIVATE KEY'
    'BEGIN EC PRIVATE KEY'
    
    # Certificate files
    '\.p12'
    '\.pem'
    '\.cer'
    '\.mobileprovision'
)

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Get repository root
REPO_ROOT=$(git rev-parse --show-toplevel)

echo -e "${YELLOW}Repository root: ${REPO_ROOT}${NC}"

# Function to check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo -e "${RED}Error: Not in a git repository${NC}"
        exit 1
    fi
}

# Check if we're in a git repo
check_git_repo

# Search through all commits
echo -e "\n${YELLOW}Scanning git history...${NC}"
for pattern in "${PATTERNS[@]}"; do
    echo -e "\n${YELLOW}Searching for: ${pattern}${NC}"
    
    # Search in commit history without pager, using grep -E for extended regex
    if git --no-pager log -p | grep -E "$pattern" > /dev/null 2>&1; then
        echo -e "${RED}⚠️  Found potential sensitive data in commits matching: ${pattern}${NC}"
        echo "Commits containing this pattern:"
        git --no-pager log --all --pretty=format:"%h - %s - %an, %ar" | grep -E "$pattern" 2>/dev/null
    else
        echo -e "${GREEN}✓ No matches found in commit history${NC}"
    fi
done

# Search in current files
echo -e "\n${YELLOW}Scanning current files...${NC}"
for pattern in "${PATTERNS[@]}"; do
    echo -e "\nChecking files for: ${pattern}"
    # Use grep -E for extended regex and redirect stderr to suppress errors
    result=$(git --no-pager grep -E "$pattern" 2>/dev/null || true)
    if [ ! -z "$result" ]; then
        echo -e "${RED}⚠️  Found potential sensitive data in current files:${NC}"
        echo "$result"
    else
        echo -e "${GREEN}✓ No matches found in current files${NC}"
    fi
done

# Final summary
echo -e "\n${YELLOW}=== Scan Summary ===${NC}"
echo -e "To remove sensitive data from git history, you can:"
echo "1. Use git-filter-repo (recommended):"
echo "   ./remove-sensitive-data.sh"
echo "2. Use BFG Repo Cleaner"
echo "3. Use git filter-branch (last resort)"
echo -e "\n${YELLOW}Note: If sensitive data was found, review carefully and take appropriate action${NC}" 