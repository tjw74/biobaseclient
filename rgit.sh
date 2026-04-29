#!/bin/bash
# Quick git workflow script
# Usage: ./rgit.sh "Your commit message here"

if [ $# -eq 0 ]; then
    echo "Error: Please provide a commit message"
    echo "Usage: ./rgit.sh \"Your commit message here\""
    exit 1
fi

echo "Select agent:"
echo "  1) claude (default)"
echo "  2) codex"
echo "  3) cursor"
read -r CHOICE

case $CHOICE in
    2) AGENT="codex" ;;
    3) AGENT="cursor" ;;
    *) AGENT="claude" ;;
esac

echo "Using: $AGENT"
echo "Adding all changes..."
git add .
echo "Committing with message: $1"
git commit -m "$1"
echo "Updating wiki..."
$AGENT "/wiki-update"
echo "Pushing to origin (current branch)..."
BR="$(git rev-parse --abbrev-ref HEAD)"
if ! git remote get-url origin >/dev/null 2>&1; then
	echo "WARN: No git remote 'origin' configured — skip push. Add with: git remote add origin <url>"
else
	git push origin "$BR" --force
fi
echo "Done!"
