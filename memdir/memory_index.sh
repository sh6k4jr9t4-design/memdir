#!/usr/bin/env bash
# memory_index.sh - 记忆索引管理
# 用法:
#   memory_index.sh init                    # 初始化索引
#   memory_index.sh add <file> <tags> <importance> <summary>  # 添加记忆片段
#   memory_index.sh update <id> <field> <value>  # 更新元数据
#   memory_index.sh access <id>             # 标记访问
#   memory_index.sh list [--sort=importance|date|access]  # 列出所有片段
#   memory_index.sh search <keyword>        # 关键词搜索
#   memory_index.sh stats                   # 统计信息

set -euo pipefail

MEMORY_DIR="${MEMORY_DIR:-$(dirname "$(realpath "$0")")/..}"
INDEX_FILE="$MEMORY_DIR/memory/index.json"
SNIPPETS_DIR="$MEMORY_DIR/memory/snippets"
TODAY=$(date +%Y-%m-%d)

# 确保目录存在
mkdir -p "$SNIPPETS_DIR"

# 初始化索引
init_index() {
    if [[ -f "$INDEX_FILE" ]]; then
        echo "Index already exists at $INDEX_FILE"
        return 0
    fi
    cat > "$INDEX_FILE" << 'EOF'
{
  "version": 1,
  "last_maintained": "",
  "snippets": {},
  "daily_refs": {}
}
EOF
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%S+08:00)
    python3 -c "
import json
with open('$INDEX_FILE', 'r') as f:
    data = json.load(f)
data['last_maintained'] = '$ts'
with open('$INDEX_FILE', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
"
    echo "Index initialized at $INDEX_FILE"
}

# 添加记忆片段
add_snippet() {
    local file="$1"
    local tags="$2"
    local importance="${3:-0.5}"
    local summary="${4:-}"

    if [[ ! -f "$file" ]]; then
        echo "Error: file $file not found"
        return 1
    fi

    local count
    count=$(python3 -c "
import json
with open('$INDEX_FILE', 'r') as f:
    data = json.load(f)
print(len(data['snippets']))
")
    local id="s$(printf '%03d' $((count + 1)))"
    local filename=$(basename "$file")
    local dest="$SNIPPETS_DIR/${id}_${filename}"

    cp "$file" "$dest"

    if [[ -z "$summary" ]]; then
        summary=$(head -1 "$file" | sed 's/^#*\s*//' | head -c 80)
    fi

    python3 -c "
import json
from datetime import datetime

with open('$INDEX_FILE', 'r') as f:
    data = json.load(f)

data['snippets']['$id'] = {
    'file': 'snippets/${id}_${filename}',
    'tags': '$tags'.split(','),
    'created': '$TODAY',
    'last_accessed': '$TODAY',
    'access_count': 1,
    'importance': float('$importance'),
    'ttl_days': None,
    'summary': '''$summary'''
}

if '$TODAY' not in data['daily_refs']:
    data['daily_refs']['$TODAY'] = []
data['daily_refs']['$TODAY'].append('$id')

data['last_maintained'] = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S+08:00')

with open('$INDEX_FILE', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
"
    echo "Added snippet: $id -> $dest (tags=$tags, importance=$importance)"
}

# 标记访问
mark_access() {
    local id="$1"
    python3 -c "
import json
with open('$INDEX_FILE', 'r') as f:
    data = json.load(f)

if '$id' in data['snippets']:
    data['snippets']['$id']['last_accessed'] = '$TODAY'
    data['snippets']['$id']['access_count'] += 1
    with open('$INDEX_FILE', 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f'Accessed: $id (count: {data[\"snippets\"][\"$id\"][\"access_count\"]})')
else:
    print(f'Error: snippet $id not found')
"
}

# 列出片段
list_snippets() {
    local sort_by="${1:-importance}"
    python3 -c "
import json, sys

with open('$INDEX_FILE', 'r') as f:
    data = json.load(f)

snippets = data.get('snippets', {})
if not snippets:
    print('No snippets yet.')
    sys.exit(0)

items = [(k, v) for k, v in snippets.items()]

sort_key = '$sort_by'
if sort_key == 'importance':
    items.sort(key=lambda x: -x[1].get('importance', 0))
elif sort_key == 'date':
    items.sort(key=lambda x: x[1].get('created', ''))
elif sort_key == 'access':
    items.sort(key=lambda x: -x[1].get('access_count', 0))

print(f'Total snippets: {len(items)}')
print()
for sid, info in items:
    tags = ','.join(info.get('tags', []))
    imp = info.get('importance', 0)
    acc = info.get('access_count', 0)
    print(f'{sid}  imp={imp:.2f}  acc={acc}  tags=[{tags}]')
    print(f'  {info.get(\"summary\", \"\")}')
    print(f'  -> {info.get(\"file\", \"\")}')
    print()
"
}

# 关键词搜索
search_snippets() {
    local keyword="$1"
    python3 -c "
import json

with open('$INDEX_FILE', 'r') as f:
    data = json.load(f)

keyword = '$keyword'.lower()
results = []

for sid, info in data.get('snippets', {}).items():
    score = 0
    summary = info.get('summary', '').lower()
    tags = ' '.join(info.get('tags', [])).lower()

    if keyword in summary:
        score += 3
    if keyword in tags:
        score += 2
    if keyword in sid.lower():
        score += 1

    try:
        with open('$MEMORY_DIR/memory/' + info.get('file', ''), 'r') as f:
            content = f.read().lower()
        if keyword in content:
            score += 1
    except:
        pass

    if score > 0:
        results.append((score, sid, info))

results.sort(key=lambda x: -x[0])

if not results:
    print(f'No results for: $keyword')
else:
    print(f'Results for: $keyword ({len(results)} found)')
    print()
    for score, sid, info in results:
        print(f'{sid}  score={score}  imp={info.get(\"importance\",0):.2f}')
        print(f'  {info.get(\"summary\",\"\")}')
        print()
"
}

# 统计信息
show_stats() {
    python3 -c "
import json
from datetime import datetime

with open('$INDEX_FILE', 'r') as f:
    data = json.load(f)

snippets = data.get('snippets', {})
today = datetime.now().strftime('%Y-%m-%d')

total = len(snippets)
if total == 0:
    print('No snippets.')
    exit()

total_access = sum(s.get('access_count', 0) for s in snippets.values())
avg_importance = sum(s.get('importance', 0) for s in snippets.values()) / total
high_importance = sum(1 for s in snippets.values() if s.get('importance', 0) >= 0.8)
stale = sum(1 for s in snippets.values() if s.get('last_accessed', today) < today)

tags = {}
for s in snippets.values():
    for t in s.get('tags', []):
        tags[t] = tags.get(t, 0) + 1

print(f'Memory Statistics')
print(f'================')
print(f'Total snippets: {total}')
print(f'Total accesses: {total_access}')
print(f'Avg importance: {avg_importance:.2f}')
print(f'High importance (>=0.8): {high_importance}')
print(f'Stale (not accessed today): {stale}')
print(f'Last maintained: {data.get(\"last_maintained\", \"never\")}')
print()
print(f'Tag distribution:')
for tag, count in sorted(tags.items(), key=lambda x: -x[1]):
    print(f'  {tag}: {count}')
"
}

# 主入口
case "${1:-help}" in
    init)
        init_index
        ;;
    add)
        add_snippet "$2" "$3" "${4:-0.5}" "${5:-}"
        ;;
    access)
        mark_access "$2"
        ;;
    list)
        list_snippets "${2:-importance}"
        ;;
    search)
        search_snippets "$2"
        ;;
    stats)
        show_stats
        ;;
    help|*)
        echo "Usage: memory_index.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  init                         Initialize index"
        echo "  add <file> <tags> [imp] [summary]  Add snippet"
        echo "  access <id>                  Mark access"
        echo "  list [importance|date|access] List snippets"
        echo "  search <keyword>             Search snippets"
        echo "  stats                        Show statistics"
        ;;
esac
