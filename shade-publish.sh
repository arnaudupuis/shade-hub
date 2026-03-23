#!/bin/bash
# shade-publish.sh — Shade Hub Publishing Script
# Usage: bash shade-publish.sh <file> <category> <title>
# Example: bash shade-publish.sh Barry_Callebaut_Analysis.html accounts "Barry Callebaut — Account Analysis"
#
# Setup: export GITHUB_TOKEN=your_personal_access_token

set -e

FILE="$1"
CATEGORY="$2"
TITLE="$3"
DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EXT="${FILE##*.}"
FILENAME=$(basename "$FILE")
DEST="$CATEGORY/$FILENAME"
TOKEN="${GITHUB_TOKEN}"
REPO="arnaudupuis/shade-hub"

if [ -z "$FILE" ] || [ -z "$CATEGORY" ] || [ -z "$TITLE" ]; then
  echo "Usage: $0 <file> <category> <title>"
  exit 1
fi

if [ -z "$TOKEN" ]; then
  echo "Error: Set GITHUB_TOKEN environment variable first"
  echo "export GITHUB_TOKEN=your_github_personal_access_token"
  exit 1
fi

echo "📤 Uploading $FILE → $DEST"

# Upload file
CONTENT=$(base64 -w 0 "$FILE")
SHA=$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO/contents/$DEST" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get("sha",""))" 2>/dev/null || echo "")

if [ -n "$SHA" ]; then
  BODY=$(python3 -c "import json; print(json.dumps({"message": "Update $DEST", "content": "$CONTENT", "sha": "$SHA"}))")
else
  BODY=$(python3 -c "import json; print(json.dumps({"message": "Add $DEST", "content": "$CONTENT"}))")
fi

curl -s -X PUT "https://api.github.com/repos/$REPO/contents/$DEST" \
  -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$BODY" > /dev/null

echo "✅ File uploaded"

# Update manifest.json
MANIFEST_RAW=$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO/contents/manifest.json")
MANIFEST_SHA=$(echo "$MANIFEST_RAW" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get("sha",""))")
MANIFEST_CONTENT=$(echo "$MANIFEST_RAW" | python3 -c "import sys,json,base64; d=json.load(sys.stdin); print(base64.b64decode(d.get("content","")+"=").decode())")

NEW_MANIFEST=$(python3 -c "
import json, sys
manifest = json.loads(sys.argv[1])
manifest["lastUpdated"] = sys.argv[2]
url = "https://arnaudupuis.github.io/shade-hub/" + sys.argv[3]
manifest["files"] = [f for f in manifest["files"] if f["url"] != url]
manifest["files"].append({"title": sys.argv[4], "url": url, "type": sys.argv[5], "category": sys.argv[6], "date": sys.argv[2]})
print(json.dumps(manifest, indent=2))
" "$MANIFEST_CONTENT" "$DATE" "$DEST" "$TITLE" "$EXT" "$CATEGORY")

NEW_MANIFEST_B64=$(echo "$NEW_MANIFEST" | base64 -w 0)
MANIFEST_BODY=$(python3 -c "import json; print(json.dumps({"message": "Update manifest for $TITLE", "content": "$NEW_MANIFEST_B64", "sha": "$MANIFEST_SHA"}))")

curl -s -X PUT "https://api.github.com/repos/$REPO/contents/manifest.json" \
  -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$MANIFEST_BODY" > /dev/null

echo "✅ Manifest updated"
echo "🌐 Live at: https://arnaudupuis.github.io/shade-hub/$DEST"
