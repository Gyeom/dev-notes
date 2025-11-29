#!/bin/bash
# 자동 포스팅 스크립트 - 내용을 받아서 자동으로 포스트 생성 및 배포
# 사용법: echo "내용" | ./scripts/auto-post.sh "제목" "태그" "카테고리"
# 또는: ./scripts/auto-post.sh "제목" "태그" "카테고리" < content.md

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

TITLE="${1:-Untitled}"
TAGS="${2:-일반}"
CATEGORY="${3:-일반}"
SUMMARY="${4:-}"

# 파일명 생성
FILENAME=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
if [ -z "$FILENAME" ]; then
    FILENAME="post-$(date +%Y%m%d-%H%M%S)"
fi

DATE=$(date +%Y-%m-%d)
FILEPATH="content/posts/${DATE}-${FILENAME}.md"

# 태그 배열 생성
IFS=',' read -ra TAG_ARRAY <<< "$TAGS"
TAG_LIST=""
for tag in "${TAG_ARRAY[@]}"; do
    TAG_LIST="$TAG_LIST\"$(echo $tag | xargs)\", "
done
TAG_LIST="[${TAG_LIST%, }]"

# stdin에서 내용 읽기
CONTENT=$(cat)

# 자동 요약 생성 (첫 100자)
if [ -z "$SUMMARY" ]; then
    SUMMARY=$(echo "$CONTENT" | head -c 150 | tr '\n' ' ')...
fi

# 포스트 생성
cat > "$FILEPATH" << EOF
---
title: "$TITLE"
date: $DATE
draft: false
tags: $TAG_LIST
categories: ["$CATEGORY"]
summary: "$SUMMARY"
---

$CONTENT
EOF

echo "Created: $FILEPATH"

# Git 자동 커밋 및 푸시 (옵션)
if [ "$AUTO_PUSH" = "true" ]; then
    git add "$FILEPATH"
    git commit -m "Add: $TITLE"
    git push
    echo "Pushed to remote!"
fi
