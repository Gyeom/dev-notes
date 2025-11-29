#!/usr/bin/env python3
"""
포스트 인덱스 자동 갱신 스크립트
Hook에서 호출됨: PostToolUse(Write/Edit content/posts/*)

생성 파일:
- post-index.md: 사람이 읽는 마크다운 인덱스
- posts.json: 기계가 읽는 구조화된 메타데이터 (벡터 검색 대비)
"""

import os
import re
import json
from pathlib import Path
from datetime import datetime
from collections import defaultdict

POSTS_DIR = Path("content/posts")
INDEX_FILE = Path(".claude/knowledge/post-index.md")
JSON_FILE = Path(".claude/knowledge/posts.json")


def extract_front_matter(content: str) -> dict:
    """YAML front matter 추출"""
    match = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
    if not match:
        return {}

    fm = {}
    for line in match.group(1).split('\n'):
        if ':' in line:
            key, value = line.split(':', 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")

            # 배열 처리 [item1, item2]
            if value.startswith('[') and value.endswith(']'):
                value = [v.strip().strip('"').strip("'") for v in value[1:-1].split(',')]

            fm[key] = value
    return fm


def extract_keywords(content: str) -> list:
    """H2 헤딩에서 핵심 키워드 추출"""
    headings = re.findall(r'^## (.+)$', content, re.MULTILINE)
    return headings[:5]


def generate_index():
    """인덱스 생성"""
    posts = []
    tag_posts = defaultdict(list)
    series_posts = defaultdict(list)

    # 포스트 수집
    for post_file in sorted(POSTS_DIR.glob("*.md"), reverse=True):
        content = post_file.read_text(encoding='utf-8')
        fm = extract_front_matter(content)

        filename = post_file.name
        title = fm.get('title', filename)
        date = str(fm.get('date', ''))[:10]
        tags = fm.get('tags', [])
        if isinstance(tags, str):
            tags = [t.strip() for t in tags.split(',')]
        series = fm.get('series', '')
        if isinstance(series, list):
            series = series[0] if series else ''
        summary = fm.get('summary', '')

        keywords = extract_keywords(content)

        post_info = {
            'filename': filename,
            'title': title,
            'date': date,
            'tags': tags,
            'series': series,
            'summary': summary,
            'keywords': keywords
        }
        posts.append(post_info)

        # 태그별 분류
        for tag in tags:
            if tag:
                tag_posts[tag].append(post_info)

        # 시리즈별 분류
        if series:
            series_posts[series].append(post_info)

    # 인덱스 파일 생성
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M')
    lines = [
        "# 포스트 인덱스",
        "",
        "> 자동 생성됨. 수동 편집 금지.",
        f"> 마지막 갱신: {timestamp}",
        "",
        f"## 전체 포스트 ({len(posts)}개)",
        "",
        "| 파일 | 제목 | 날짜 | 태그 | 키워드 |",
        "|------|------|------|------|--------|",
    ]

    for p in posts:
        tags_str = ', '.join(p['tags'][:5])
        keywords_str = ', '.join(p['keywords'][:3])
        lines.append(f"| {p['filename']} | {p['title'][:40]} | {p['date']} | {tags_str} | {keywords_str} |")

    # 태그별 분류
    lines.extend(["", "## 태그별 분류", ""])
    for tag in sorted(tag_posts.keys()):
        lines.append(f"### {tag}")
        for p in tag_posts[tag]:
            lines.append(f"- {p['filename']} - {p['title'][:50]}")
        lines.append("")

    # 시리즈별 분류
    if series_posts:
        lines.extend(["## 시리즈", ""])
        for series in sorted(series_posts.keys()):
            lines.append(f"### {series}")
            for p in sorted(series_posts[series], key=lambda x: x['date']):
                lines.append(f"- {p['filename']} - {p['title'][:50]}")
            lines.append("")

    # 마크다운 인덱스 저장
    INDEX_FILE.parent.mkdir(parents=True, exist_ok=True)
    INDEX_FILE.write_text('\n'.join(lines), encoding='utf-8')

    # JSON 메타데이터 저장 (벡터 검색 대비)
    json_data = {
        "version": "1.0",
        "generated_at": timestamp,
        "post_count": len(posts),
        "posts": posts,
        "tags": {tag: [p['filename'] for p in ps] for tag, ps in tag_posts.items()},
        "series": {s: [p['filename'] for p in ps] for s, ps in series_posts.items()}
    }
    JSON_FILE.write_text(json.dumps(json_data, ensure_ascii=False, indent=2), encoding='utf-8')

    print(f"✅ 인덱스 갱신 완료: {len(posts)}개 포스트")


if __name__ == "__main__":
    os.chdir(Path(__file__).parent.parent)
    generate_index()
