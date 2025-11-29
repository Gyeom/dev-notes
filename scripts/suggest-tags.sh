#!/bin/bash
# 포스트 작성 후 태그 추천 힌트 제공
# Hook에서 호출됨

FILE="$1"

if [ -z "$FILE" ]; then
  echo "📝 포스트가 작성되었습니다."
  echo ""
  echo "다음 단계:"
  echo "  /preview  - 로컬 미리보기"
  echo "  /review   - 문체/SEO 검토"
  echo "  /pr       - PR로 배포 (권장)"
  echo "  /deploy   - 직접 배포"
  exit 0
fi

# front matter에서 태그 추출
TAGS=$(grep -A1 "^tags:" "$FILE" 2>/dev/null | tail -1 | tr -d '[]"' | tr ',' '\n' | wc -l)

echo "📝 포스트가 작성되었습니다."
echo ""

if [ "$TAGS" -lt 3 ]; then
  echo "⚠️  태그가 ${TAGS}개입니다. 3-7개를 권장합니다."
  echo "   auto-tagger로 태그를 추천받으세요."
  echo ""
fi

echo "다음 단계:"
echo "  /preview  - 로컬 미리보기"
echo "  /review   - 문체/SEO 검토"
echo "  /pr       - PR로 배포 (권장)"
echo "  /deploy   - 직접 배포"
