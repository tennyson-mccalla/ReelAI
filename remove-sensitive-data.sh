#!/bin/bash

# Check if git-filter-repo is installed
if ! command -v git-filter-repo &> /dev/null; then
    echo "git-filter-repo is not installed. Installing..."
    pip3 install git-filter-repo
fi

# Backup the repository
cp -r .git .git.bak

# Example commands to remove sensitive data
# Uncomment and modify the ones you need

# Remove file completely
# git-filter-repo --path GoogleService-Info.plist --invert-paths

# Replace content matching pattern
# git-filter-repo --replace-text <(echo 'api_key=YOUR_KEY==>api_key=REMOVED_KEY')

# Remove files matching pattern
# git-filter-repo --path-glob '*.pem' --invert-paths

echo "After running the appropriate commands:"
echo "1. git push origin --force --all"
echo "2. git push origin --force --tags"
echo "3. Ask all collaborators to:"
echo "   - Delete their local repo"
echo "   - Clone fresh"
echo "   - Reset any branches" 