#!/bin/bash
# 포스트 작성/수정 전 민감 정보 검사
# PreToolUse Hook에서 호출됨

# 검사 대상: 스테이징된 content/posts 파일
STAGED_POSTS=$(git diff --cached --name-only 2>/dev/null | grep "^content/posts/.*\.md$")

if [ -z "$STAGED_POSTS" ]; then
  exit 0
fi

# 민감 정보 패턴
PATTERNS=(
  # API 키/토큰
  'sk-[a-zA-Z0-9]{20,}'                    # OpenAI API key
  'ghp_[a-zA-Z0-9]{36}'                    # GitHub PAT
  'gho_[a-zA-Z0-9]{36}'                    # GitHub OAuth
  'github_pat_[a-zA-Z0-9]{22}_[a-zA-Z0-9]{59}'  # GitHub fine-grained PAT
  'xoxb-[0-9]{10,13}-[0-9]{10,13}-[a-zA-Z0-9]{24}'  # Slack bot token
  'xoxp-[0-9]{10,13}-[0-9]{10,13}-[a-zA-Z0-9]{24}'  # Slack user token

  # AWS
  'AKIA[0-9A-Z]{16}'                       # AWS Access Key
  '[a-zA-Z0-9/+]{40}'                      # AWS Secret Key (주의: 오탐 가능)

  # 개인정보
  '[0-9]{6}-[0-9]{7}'                      # 주민번호
  '01[0-9]-[0-9]{4}-[0-9]{4}'              # 전화번호

  # 비밀번호 하드코딩
  'password\s*=\s*["\x27][^"\x27]{8,}["\x27]'
  'passwd\s*=\s*["\x27][^"\x27]{8,}["\x27]'
  'secret\s*=\s*["\x27][^"\x27]{8,}["\x27]'
)

FOUND=0

for file in $STAGED_POSTS; do
  if [ ! -f "$file" ]; then
    continue
  fi

  for pattern in "${PATTERNS[@]}"; do
    if grep -qE "$pattern" "$file" 2>/dev/null; then
      if [ $FOUND -eq 0 ]; then
        echo "⚠️  민감 정보 의심 패턴 발견:" >&2
        FOUND=1
      fi
      echo "  📄 $file" >&2
      grep -nE "$pattern" "$file" 2>/dev/null | head -3 | while read line; do
        echo "     $line" >&2
      done
    fi
  done
done

if [ $FOUND -eq 1 ]; then
  echo "" >&2
  echo "❌ 민감 정보가 포함된 것 같습니다. 확인 후 진행하세요." >&2
  echo "   실제 API 키라면 제거하고, 예시라면 'sk-xxx...' 형태로 마스킹하세요." >&2
  exit 2
fi

exit 0
