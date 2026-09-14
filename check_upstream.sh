#!/bin/bash
# 检查 khairudinfahmi/WindowsPrinterSharingFix 上游是否有新的提交（尚未合并到本地）
# 用于 cron trigger：有新提交时输出 {"fire": true, ...}

cd ~/.openclaw/workspace/WindowsPrinterSharingFix || exit 1

# 静默拉取上游最新状态
git fetch origin --quiet 2>/dev/null

# 检测 origin/main 上是否有本地 main 没有的提交
NEW_COMMITS=$(git log --oneline main..origin/main 2>/dev/null)

if [ -n "$NEW_COMMITS" ]; then
    COMMIT_COUNT=$(echo "$NEW_COMMITS" | wc -l)
    COMMITS_JSON=$(echo "$NEW_COMMITS" | head -10 | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    echo "{\"fire\": true, \"reason\": \"检测到上游 ${COMMIT_COUNT} 个新提交\", \"commits\": \"${COMMITS_JSON}\"}"
else
    echo '{"fire": false, "reason": "上游无新提交"}'
fi