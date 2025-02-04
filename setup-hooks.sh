#!/bin/bash

# Copy pre-commit hook
cp pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# Copy pre-push hook
cp pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push

echo "Git hooks installed successfully!" 