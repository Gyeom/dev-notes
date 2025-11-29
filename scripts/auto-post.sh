#!/bin/bash
# 자동 포스팅 스크립트 - 내용을 받아서 자동으로 포스트 생성 및 배포
# 사용법: echo "내용" | ./scripts/auto-post.sh "제목" "태그" "카테고리"
# 또는: ./scripts/auto-post.sh "제목" "태그" "카테고리" < content.md

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/post-utils.sh"

cd "$(dirname "$SCRIPT_DIR")"

TITLE="${1:-Untitled}"
TAGS="${2:-일반}"
CATEGORY="${3:-일반}"
SUMMARY="${4:-}"

FILENAME=$(generate_filename "$TITLE")
FILEPATH=$(generate_post_path "$FILENAME")

# stdin에서 내용 읽기
CONTENT=$(cat)

# 자동 요약 생성 (첫 150자)
if [ -z "$SUMMARY" ]; then
    SUMMARY="$(echo "$CONTENT" | head -c 150 | tr '\n' ' ')..."
fi

# 포스트 생성
generate_front_matter "$TITLE" "$TAGS" "$CATEGORY" "$SUMMARY" > "$FILEPATH"
echo "" >> "$FILEPATH"
echo "$CONTENT" >> "$FILEPATH"

echo "Created: $FILEPATH"

# Git 자동 커밋 및 푸시 (옵션)
if [ "$AUTO_PUSH" = "true" ]; then
    git add "$FILEPATH"
    git commit -m "Add: $TITLE"
    git push
    echo "Pushed to remote!"
fi
