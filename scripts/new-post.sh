#!/bin/bash
# 새 포스트 생성 스크립트
# 사용법: ./scripts/new-post.sh "포스트 제목" "태그1,태그2" "카테고리"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/post-utils.sh"

cd "$(dirname "$SCRIPT_DIR")"

TITLE="${1:-Untitled}"
TAGS="${2:-일반}"
CATEGORY="${3:-일반}"

FILENAME=$(generate_filename "$TITLE")
FILEPATH=$(generate_post_path "$FILENAME")

# 포스트 생성
generate_front_matter "$TITLE" "$TAGS" "$CATEGORY" "" > "$FILEPATH"
cat >> "$FILEPATH" << 'EOF'

## 개요

내용을 작성하세요.

## 본문

## 결론

EOF

echo "Created: $FILEPATH"
echo "Edit the file and run: git add . && git commit -m 'Add: $TITLE' && git push"
