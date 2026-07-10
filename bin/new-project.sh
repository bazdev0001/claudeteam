#!/usr/bin/env bash
# Scaffold a new project from the standard template.
# Usage: new-project.sh <project-name> [description]
set -euo pipefail

NAME="${1:-}"
DESC="${2:-A new project}"
TEMPLATE="$HOME/ruflo/projects/_template"
DEST="$HOME/ruflo/projects/$NAME"

[ -z "$NAME" ] && { echo "Usage: new-project.sh <project-name> [description]" >&2; exit 1; }
[ -d "$DEST" ] && { echo "Project '$NAME' already exists at $DEST" >&2; exit 1; }
[ -d "$TEMPLATE" ] || { echo "Template missing at $TEMPLATE" >&2; exit 1; }

cp -r "$TEMPLATE" "$DEST"

# Replace [Project Name] placeholder
find "$DEST" -type f -name "*.md" -exec sed -i "s/\[Project Name\]/$NAME/g; s/\[project-name\]/$NAME/g" {} \;

# Init git and create GitHub repo if gh is available
cd "$DEST"
git init -q
cat > .gitignore << 'EOF'
node_modules/
.expo/
dist/
build/
.env
.env.*
*.log
EOF

echo "✓ Project '$NAME' created at $DEST"
echo "Next: cd $DEST && edit docs/PRD.md, then run ruflo agents to build"

# Optionally create GitHub repo
if command -v gh &>/dev/null; then
    echo "Run: gh repo create bazdev0001/$NAME --private --source=. --push"
fi
