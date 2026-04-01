#!/usr/bin/env bash
# memory_age.sh - 记忆老化处理
# 降低长期未访问记忆的 importance，清理过期记忆
# 用法:
#   memory_age.sh run          # 执行老化
#   memory_age.sh preview      # 预览将要发生的变化（不执行）
#   memory_age.sh report       # 生成老化报告

set -euo pipefail

MEMORY_DIR="${MEMORY_DIR:-$(dirname "$(realpath "$0")")/..}"
INDEX_FILE="$MEMORY_DIR/memory/index.json"

# 老化参数
DECAY_RATE=0.02           # 每天衰减 2%（未访问时）
MIN_IMPORTANCE=0.1        # 低于此值标记为候选删除
STALE_DAYS_WARN=30        # 30 天未访问开始显著衰减
STALE_DAYS_DELETE=90      # 90 天未访问且低 importance 则删除

TODAY=$(date +%Y-%m-%d)
TODAY_TS=$(date -d "$TODAY" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$TODAY" +%s 2>/dev/null)

if [[ ! -f "$INDEX_FILE" ]]; then
    echo "Error: index.json not found. Run memory_index.sh init first."
    exit 1
fi

# 执行老化
run_aging() {
    local dry_run="${1:-false}"

    python3 -c "
import json
from datetime import datetime, timedelta

INDEX_FILE = '$INDEX_FILE'
TODAY = '$TODAY'
DECAY_RATE = $DECAY_RATE
MIN_IMPORTANCE = $MIN_IMPORTANCE
STALE_DAYS_WARN = $STALE_DAYS_WARN
STALE_DAYS_DELETE = $STALE_DAYS_DELETE
DRY_RUN = ('$dry_run' == 'true')

with open(INDEX_FILE, 'r') as f:
    data = json.load(f)

snippets = data.get('snippets', {})
changes = []
to_delete = []

for sid, info in snippets.items():
    last_accessed = info.get('last_accessed', info.get('created', TODAY))
    days_stale = (datetime.strptime(TODAY, '%Y-%m-%d') - datetime.strptime(last_accessed, '%Y-%m-%d')).days

    if days_stale <= 0:
        continue

    old_importance = info.get('importance', 0.5)
    new_importance = old_importance
    action = 'none'

    if days_stale > STALE_DAYS_DELETE and old_importance < MIN_IMPORTANCE:
        to_delete.append(sid)
        action = f'DELETE (stale {days_stale}d, importance {old_importance:.2f})'
    else:
        if days_stale > STALE_DAYS_WARN:
            stale_factor = 1.0 + (days_stale - STALE_DAYS_WARN) / STALE_DAYS_WARN
        else:
            stale_factor = 0.3

        new_importance = old_importance * (1 - DECAY_RATE * stale_factor)
        new_importance = max(0.0, round(new_importance, 4))

        if abs(new_importance - old_importance) > 0.001:
            action = f'DECAY {old_importance:.2f} -> {new_importance:.2f} (stale {days_stale}d)'

    if action != 'none':
        changes.append((sid, action, old_importance, new_importance))

    if not DRY_RUN and action != 'none' and sid not in to_delete:
        snippets[sid]['importance'] = new_importance

for sid in to_delete:
    info = snippets.pop(sid)
    snippet_file = info.get('file', '')
    if not DRY_RUN:
        import os
        full_path = os.path.join('$MEMORY_DIR/memory', snippet_file)
        if os.path.exists(full_path):
            os.remove(full_path)
    for date_key, refs in data.get('daily_refs', {}).items():
        if sid in refs:
            refs.remove(sid)

if not DRY_RUN:
    data['last_maintained'] = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
    with open(INDEX_FILE, 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

if not changes and not to_delete:
    print('No aging changes needed. All memories are fresh.')
else:
    print(f'Aging Report ({\"DRY RUN\" if DRY_RUN else \"EXECUTED\"})')
    print(f'================================')
    print(f'Snippets processed: {len(snippets) + len(to_delete)}')
    print(f'Changes made: {len(changes)}')
    print(f'Deleted: {len(to_delete)}')
    print()

    if changes:
        print('Changes:')
        for sid, action, old, new in changes:
            print(f'  {sid}: {action}')
        print()

    if to_delete:
        print('Deleted:')
        for sid in to_delete:
            print(f'  {sid}: removed')
        print()

    print(f'Maintenance timestamp updated.')
"
}

# 生成报告
generate_report() {
    python3 -c "
import json
from datetime import datetime

INDEX_FILE = '$INDEX_FILE'
TODAY = '$TODAY'

with open(INDEX_FILE, 'r') as f:
    data = json.load(f)

snippets = data.get('snippets', {})

print('Memory Health Report')
print('====================')
print()

categories = {'fresh': [], 'aging': [], 'stale': [], 'critical': []}

for sid, info in snippets.items():
    last_accessed = info.get('last_accessed', info.get('created', TODAY))
    days = (datetime.strptime(TODAY, '%Y-%m-%d') - datetime.strptime(last_accessed, '%Y-%m-%d')).days
    imp = info.get('importance', 0.5)

    if days <= 7:
        categories['fresh'].append((sid, days, imp))
    elif days <= 30:
        categories['aging'].append((sid, days, imp))
    elif days <= 90:
        categories['stale'].append((sid, days, imp))
    else:
        categories['critical'].append((sid, days, imp))

for cat, items in categories.items():
    emoji = {'fresh': '🟢', 'aging': '🟡', 'stale': '🟠', 'critical': '🔴'}[cat]
    print(f'{emoji} {cat.upper()} ({len(items)} snippets)')
    for sid, days, imp in sorted(items, key=lambda x: x[2]):
        print(f'  {sid}: {days}d stale, importance={imp:.2f}, summary={snippets[sid].get(\"summary\",\"\")[:40]}')
    print()
"
}

# 主入口
case "${1:-help}" in
    run)
        run_aging false
        ;;
    preview)
        run_aging true
        ;;
    report)
        generate_report
        ;;
    help|*)
        echo "Usage: memory_age.sh <command>"
        echo ""
        echo "Commands:"
        echo "  run       Execute aging (decay importance, delete stale)"
        echo "  preview   Preview changes without executing"
        echo "  report    Generate health report"
        ;;
esac
