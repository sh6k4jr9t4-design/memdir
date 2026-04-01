#!/usr/bin/env bash
# memory_consolidate.sh - 从每日日志中提取重要信息到结构化片段
# 用法:
#   memory_consolidate.sh [date]        # 整理指定日期（默认今天）
#   memory_consolidate.sh all           # 整理所有未整理的日志
#   memory_consolidate.sh status        # 查看整理状态

set -euo pipefail

MEMORY_DIR="${MEMORY_DIR:-$(dirname "$(realpath "$0")")/..}"
MEMORY_BASE="$MEMORY_DIR/memory"
INDEX_FILE="$MEMORY_BASE/index.json"
INDEX_SCRIPT="$(dirname "$(realpath "$0")")/memory_index.sh"

TODAY=$(date +%Y-%m-%d)

if [[ ! -f "$INDEX_FILE" ]]; then
    echo "Initializing index..."
    bash "$INDEX_SCRIPT" init
fi

# 检查某天是否已整理
is_consolidated() {
    local date="$1"
    python3 -c "
import json
with open('$INDEX_FILE', 'r') as f:
    data = json.load(f)
refs = data.get('daily_refs', {}).get('$date', [])
print('yes' if refs else 'no')
"
}

# 从日志中提取关键段落
consolidate_day() {
    local date="$1"
    local log_file="$MEMORY_BASE/${date}.md"

    if [[ ! -f "$log_file" ]]; then
        echo "No log file for $date"
        return 0
    fi

    local consolidated
    consolidated=$(is_consolidated "$date")
    if [[ "$consolidated" == "yes" ]]; then
        echo "$date already consolidated. Use 'force' to re-process."
        return 0
    fi

    echo "Consolidating $date..."

    local section_num=0
    local current_section=""
    local current_title=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^## ]]; then
            if [[ -n "$current_section" && ${#current_section} -gt 50 ]]; then
                section_num=$((section_num + 1))
                local snippet_file="$MEMORY_BASE/snippets/${date}_s${section_num}.md"
                echo "$current_section" > "$snippet_file"

                local tags="daily,$date"
                if [[ "$current_title" =~ (决定|decision|决策) ]]; then
                    tags="$tags,decision"
                fi
                if [[ "$current_title" =~ (教训|lesson|错误|error) ]]; then
                    tags="$tags,lesson"
                fi
                if [[ "$current_title" =~ (待办|todo|计划|plan) ]]; then
                    tags="$tags,todo"
                fi
                if [[ "$current_title" =~ (身份|identity|性格|personality) ]]; then
                    tags="$tags,identity"
                fi

                local importance=0.3
                if echo "$current_section" | grep -qiE "(重要|关键|必须|核心|决定|教训|错误)"; then
                    importance=0.7
                fi
                if echo "$current_section" | grep -qiE "(红线|安全|密码|API|token)"; then
                    importance=0.9
                fi

                local summary
                summary=$(echo "$current_title" | head -c 80)

                bash "$INDEX_SCRIPT" add "$snippet_file" "$tags" "$importance" "$summary"
            fi

            current_title="$line"
            current_section="$line"
        else
            current_section="$current_section
$line"
        fi
    done < "$log_file"

    # 处理最后一个段落
    if [[ -n "$current_section" && ${#current_section} -gt 50 ]]; then
        section_num=$((section_num + 1))
        local snippet_file="$MEMORY_BASE/snippets/${date}_s${section_num}.md"
        echo "$current_section" > "$snippet_file"

        local tags="daily,$date"
        local importance=0.3
        if echo "$current_section" | grep -qiE "(重要|关键|必须|核心|决定|教训|错误)"; then
            importance=0.7
        fi
        local summary
        summary=$(echo "$current_title" | head -c 80)

        bash "$INDEX_SCRIPT" add "$snippet_file" "$tags" "$importance" "$summary"
    fi

    echo "Consolidated $date: $section_num snippets extracted"
}

# 整理所有未整理的日志
consolidate_all() {
    local count=0
    for log_file in "$MEMORY_BASE"/*.md; do
        local basename
        basename=$(basename "$log_file" .md)
        if [[ "$basename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            local consolidated
            consolidated=$(is_consolidated "$basename")
            if [[ "$consolidated" == "no" ]]; then
                consolidate_day "$basename"
                count=$((count + 1))
            fi
        fi
    done
    echo "Done. Consolidated $count daily logs."
}

# 查看整理状态
show_status() {
    python3 -c "
import json, os, re
from datetime import datetime

MEMORY_DIR = '$MEMORY_BASE'
INDEX_FILE = '$INDEX_FILE'

with open(INDEX_FILE, 'r') as f:
    data = json.load(f)

log_files = []
for f in os.listdir(MEMORY_DIR):
    if re.match(r'^\d{4}-\d{2}-\d{2}\.md$', f):
        log_files.append(f.replace('.md', ''))

log_files.sort()

print('Consolidation Status')
print('====================')
print(f'Total daily logs: {len(log_files)}')
print()

for date in log_files:
    refs = data.get('daily_refs', {}).get(date, [])
    if refs:
        print(f'  {date}: ✅ consolidated ({len(refs)} snippets)')
    else:
        print(f'  {date}: ⏳ not consolidated')

print()
total_snippets = len(data.get('snippets', {}))
print(f'Total snippets: {total_snippets}')
"
}

# 主入口
case "${1:-help}" in
    all)
        consolidate_all
        ;;
    status)
        show_status
        ;;
    help|*)
        if [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            consolidate_day "$1"
        elif [[ -z "$1" || "$1" == "help" ]]; then
            echo "Usage: memory_consolidate.sh [date|all|status]"
            echo ""
            echo "Commands:"
            echo "  [date]     Consolidate specific date (default: today)"
            echo "  all        Consolidate all unprocessed daily logs"
            echo "  status     Show consolidation status"
        else
            consolidate_day "$1"
        fi
        ;;
esac
