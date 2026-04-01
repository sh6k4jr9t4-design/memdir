#!/usr/bin/env bash
# memory_search.sh - 增强版记忆搜索
# 结合索引元数据和文件内容，按相关性排序返回结果
# 用法:
#   memory_search.sh <keyword>             # 关键词搜索
#   memory_search.sh <keyword> --tag=<tag> # 按标签过滤
#   memory_search.sh <keyword> --min-imp=0.5  # 最低重要性
#   memory_search.sh <keyword> --limit=5   # 限制结果数

set -euo pipefail

MEMORY_DIR="${MEMORY_DIR:-$(dirname "$(realpath "$0")")/..}"
INDEX_FILE="$MEMORY_DIR/memory/index.json"
SNIPPETS_DIR="$MEMORY_DIR/memory/snippets"

KEYWORD=""
TAG_FILTER=""
MIN_IMP=0
LIMIT=10

# 解析参数
for arg in "$@"; do
    case "$arg" in
        --tag=*) TAG_FILTER="${arg#--tag=}" ;;
        --min-imp=*) MIN_IMP="${arg#--min-imp=}" ;;
        --limit=*) LIMIT="${arg#--limit=}" ;;
        *) [[ -z "$KEYWORD" ]] && KEYWORD="$arg" ;;
    esac
done

if [[ -z "$KEYWORD" ]]; then
    echo "Usage: memory_search.sh <keyword> [--tag=<tag>] [--min-imp=<float>] [--limit=<n>]"
    exit 1
fi

if [[ ! -f "$INDEX_FILE" ]]; then
    echo "No index found. Run memory_index.sh init first."
    exit 1
fi

python3 -c "
import json, os, re, sys

INDEX_FILE = '$INDEX_FILE'
SNIPPETS_DIR = '$SNIPPETS_DIR'
KEYWORD = '$KEYWORD'.lower()
TAG_FILTER = '$TAG_FILTER'
MIN_IMP = float('$MIN_IMP')
LIMIT = int('$LIMIT')

with open(INDEX_FILE, 'r') as f:
    data = json.load(f)

snippets = data.get('snippets', {})
results = []

for sid, info in snippets.items():
    imp = info.get('importance', 0)
    if imp < MIN_IMP:
        continue

    tags = info.get('tags', [])
    if TAG_FILTER and TAG_FILTER not in tags:
        continue

    score = 0.0
    match_reasons = []

    # 1. 摘要匹配（权重 3）
    summary = info.get('summary', '').lower()
    if KEYWORD in summary:
        score += 3.0
        match_reasons.append('summary')

    # 2. 标签匹配（权重 2）
    tags_lower = ' '.join(tags).lower()
    if KEYWORD in tags_lower:
        score += 2.0
        match_reasons.append('tags')

    # 3. 文件名匹配（权重 1）
    filename = info.get('file', '').lower()
    if KEYWORD in filename:
        score += 1.0
        match_reasons.append('filename')

    # 4. 文件内容匹配（权重 1）
    content_score = 0
    filepath = os.path.join('$MEMORY_DIR/memory', info.get('file', ''))
    try:
        with open(filepath, 'r') as f:
            content = f.read().lower()
        occurrences = content.count(KEYWORD)
        if occurrences > 0:
            content_score = min(occurrences * 0.5, 2.0)
            score += content_score
            match_reasons.append(f'content({occurrences}x)')
    except:
        pass

    # 5. importance 加成
    score *= (0.5 + imp * 0.5)

    # 6. 访问频率加成
    access_count = info.get('access_count', 0)
    if access_count > 5:
        score *= 1.1

    if score > 0:
        results.append({
            'id': sid,
            'score': round(score, 2),
            'importance': imp,
            'reasons': match_reasons,
            'summary': info.get('summary', ''),
            'file': info.get('file', ''),
            'tags': tags,
            'last_accessed': info.get('last_accessed', ''),
        })

results.sort(key=lambda x: -x['score'])
results = results[:LIMIT]

if not results:
    print(f'No results for: {KEYWORD}')
    if TAG_FILTER:
        print(f'(filtered by tag: {TAG_FILTER})')
else:
    print(f'Search: \"{KEYWORD}\" ({len(results)} results)')
    if TAG_FILTER:
        print(f'Filter: tag={TAG_FILTER}, min_importance={MIN_IMP}')
    print()
    for r in results:
        print(f'  {r[\"id\"]}  score={r[\"score\"]}  imp={r[\"importance\"]:.2f}')
        print(f'    {r[\"summary\"]}')
        print(f'    matched: {\", \".join(r[\"reasons\"])}')
        print(f'    tags: [{\", \".join(r[\"tags\"])}]')
        print(f'    file: {r[\"file\"]}')
        print()

    # 输出 top result 的内容
    top = results[0]
    top_file = os.path.join('$MEMORY_DIR/memory', top['file'])
    try:
        with open(top_file, 'r') as f:
            content = f.read()
        print(f'--- Top result content ({top[\"id\"]}) ---')
        print(content[:500])
        if len(content) > 500:
            print(f'... ({len(content)} chars total)')
    except:
        pass

# 标记访问
import subprocess
for r in results[:3]:
    subprocess.run(['bash', '$MEMORY_DIR/../memdir/memory_index.sh', 'access', r['id']],
                   capture_output=True)
"
