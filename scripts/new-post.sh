#!/bin/bash
# 새 포스트 생성 스크립트
# 사용법: ./scripts/new-post.sh "포스트 제목" "태그1,태그2" "카테고리"

set -e

TITLE="${1:-Untitled}"
TAGS="${2:-일반}"
CATEGORY="${3:-일반}"

# 파일명 생성 (한글 제거, 공백을 하이픈으로)
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

# 포스트 생성
cat > "$FILEPATH" << EOF
---
title: "$TITLE"
date: $DATE
draft: false
tags: $TAG_LIST
categories: ["$CATEGORY"]
summary: ""
---

## 개요

내용을 작성하세요.

## 본문

## 결론

EOF

echo "Created: $FILEPATH"
echo "Edit the file and run: git add . && git commit -m 'Add: $TITLE' && git push"
