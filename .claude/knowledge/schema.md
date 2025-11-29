# RAG 메타데이터 스키마

> 벡터 검색 전환 시 사용할 표준 구조

## 포스트 메타데이터

```python
{
    # 기본 정보
    "id": "2025-11-29-claude-code-anatomy",      # 고유 ID (파일명 기반)
    "source": "content/posts/xxx.md",            # 원본 파일 경로
    "title": "포스트 제목",
    "date": "2025-11-29",
    "url": "/dev-notes/posts/xxx/",              # 배포 URL

    # 분류
    "tags": ["Claude Code", "AI", "MCP"],
    "categories": ["기술 분석"],
    "series": "AI 자동화 블로그",
    "series_order": 2,

    # 검색용
    "summary": "포스트 요약 (front matter)",
    "keywords": ["Tool Use", "컨텍스트 계층"],   # H2 헤딩에서 추출

    # 청킹 정보 (벡터 검색 시)
    "chunk_id": 0,                               # 청크 순서
    "chunk_total": 5,                            # 전체 청크 수
    "chunk_type": "section",                     # section, paragraph

    # 임베딩 정보 (벡터 검색 시)
    "embedding_model": "voyage-3",
    "embedding_dim": 1024,
    "indexed_at": "2025-11-30T00:30:00"
}
```

## 청킹 전략

### Phase 1: 현재 (키워드 검색)
- 청킹 없음
- post-index.md에 메타데이터만 저장

### Phase 2: 전문 검색 (50개+)
- 섹션 단위 청킹 (H2 기준)
- SQLite FTS5 활용

### Phase 3: 벡터 검색 (100개+)
```python
from langchain.text_splitter import RecursiveCharacterTextSplitter

splitter = RecursiveCharacterTextSplitter(
    chunk_size=512,
    chunk_overlap=102,  # 20%
    separators=["\n## ", "\n### ", "\n\n", "\n", " "]
)
```

## 인덱스 파일 구조

```
.claude/knowledge/
├── post-index.md      # 현재: 사람이 읽는 인덱스
├── schema.md          # 이 파일: 스키마 정의
├── posts.json         # Phase 2: 구조화된 메타데이터
└── embeddings.db      # Phase 3: SQLite + 벡터
```

## 마이그레이션 경로

1. **현재** → posts.json 생성 스크립트 추가
2. **50개+** → SQLite FTS5 + posts.json
3. **100개+** → sqlite-vec + Voyage-3 임베딩

## 호환성 유지

- post-index.md는 항상 생성 (사람용)
- posts.json은 기계용 (Claude가 참조)
- 벡터 DB는 검색 성능용
