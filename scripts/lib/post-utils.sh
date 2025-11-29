#!/bin/bash
# 포스트 생성 공통 유틸리티

# 파일명 생성 (영문, 숫자, 하이픈만 허용)
generate_filename() {
    local title="$1"
    local filename=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

    if [ -z "$filename" ]; then
        filename="post-$(date +%Y%m%d-%H%M%S)"
    fi

    echo "$filename"
}

# 태그 배열 생성 (쉼표 구분 문자열 → JSON 배열)
generate_tag_list() {
    local tags="$1"
    local tag_list=""

    IFS=',' read -ra TAG_ARRAY <<< "$tags"
    for tag in "${TAG_ARRAY[@]}"; do
        tag_list="$tag_list\"$(echo $tag | xargs)\", "
    done

    echo "[${tag_list%, }]"
}

# 포스트 경로 생성
generate_post_path() {
    local filename="$1"
    local date=$(date +%Y-%m-%d)
    echo "content/posts/${date}-${filename}.md"
}

# Front matter 생성
generate_front_matter() {
    local title="$1"
    local tags="$2"
    local category="$3"
    local summary="$4"
    local draft="${5:-false}"
    local date=$(date +%Y-%m-%d)
    local tag_list=$(generate_tag_list "$tags")

    cat << EOF
---
title: "$title"
date: $date
draft: $draft
tags: $tag_list
categories: ["$category"]
summary: "$summary"
---
EOF
}
