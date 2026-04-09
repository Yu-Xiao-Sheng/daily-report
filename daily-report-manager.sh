#!/bin/bash
# daily-report-manager.sh - 日报管理脚本
# 功能：上传报告、滚动删除、本地归档

set -e

# 配置
REPO_DIR="$HOME/daily-report"
ARCHIVE_DIR="$HOME/daily-report-archive"
REPO_URL="git@github.com:Yu-Xiao-Sheng/daily-report.git"
KEEP_DAYS=7

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 用法说明
usage() {
    echo "用法: $0 <命令> [参数]"
    echo ""
    echo "命令:"
    echo "  upload <html-file> <date> <type>   上传报告"
    echo "       date: YYYY-MM-DD"
    echo "       type: morning|noon|evening"
    echo "  cleanup                            清理超过7天的报告"
    echo "  list                               列出当前报告"
    echo "  init                               初始化仓库"
    echo ""
    echo "示例:"
    echo "  $0 upload report-2026-04-09-morning.html 2026-04-09 morning"
    exit 1
}

# 初始化仓库
init_repo() {
    log_info "初始化仓库..."
    
    # 创建本地归档目录
    mkdir -p "$ARCHIVE_DIR"
    
    # 进入仓库目录
    cd "$REPO_DIR"
    
    # 配置 git
    git config user.email "yuxs@example.com"
    git config user.name "OpenClaw Bot"
    
    # 创建初始提交
    git add -A
    git commit -m "初始化日报仓库" || true
    git push -u origin main || git push -u origin master
    
    log_info "仓库初始化完成"
}

# 上传报告
upload_report() {
    local html_file="$1"
    local date="$2"
    local type="$3"
    
    if [[ ! -f "$html_file" ]]; then
        log_error "文件不存在: $html_file"
        exit 1
    fi
    
    log_info "上传报告: $date - $type"
    
    # 进入仓库
    cd "$REPO_DIR"
    git pull --rebase
    
    # 创建日期目录
    mkdir -p "$date"
    
    # 复制文件到仓库
    cp "$html_file" "$date/$type.html"
    
    # 本地归档（永久保留）
    mkdir -p "$ARCHIVE_DIR/$date"
    cp "$html_file" "$ARCHIVE_DIR/$date/$type.html"
    log_info "已归档到本地: $ARCHIVE_DIR/$date/$type.html"
    
    # 更新 reports.json
    update_reports_json "$date" "$type"
    
    # 提交并推送
    git add -A
    git commit -m "添加报告: $date - $type" || true
    git push
    
    log_info "报告上传成功"
    
    # 输出访问链接
    echo ""
    echo "📄 报告链接: https://yu-xiao-sheng.github.io/daily-report/$date/$type.html"
}

# 更新 reports.json
update_reports_json() {
    local date="$1"
    local type="$2"
    
    cd "$REPO_DIR"
    
    # 读取现有数据
    if [[ -f "reports.json" ]]; then
        reports=$(cat reports.json)
    else
        reports='{"reports": []}'
    fi
    
    # 使用 Python 更新 JSON（更可靠）
    python3 << EOF
import json
import sys

with open('reports.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# 查找或创建日期条目
date_entry = None
for r in data['reports']:
    if r['date'] == '$date':
        date_entry = r
        break

if date_entry is None:
    date_entry = {'date': '$date'}
    data['reports'].insert(0, date_entry)

# 更新类型链接
date_entry['$type'] = f'$date/$type.html'

# 按日期排序（最新在前）
data['reports'].sort(key=lambda x: x['date'], reverse=True)

with open('reports.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
EOF
}

# 清理旧报告（保留近7天）
cleanup_old_reports() {
    log_info "清理超过 $KEEP_DAYS 天的报告..."
    
    cd "$REPO_DIR"
    git pull --rebase
    
    # 计算截止日期
    cutoff_date=$(date -d "-$KEEP_DAYS days" +%Y-%m-%d 2>/dev/null || date -v-${KEEP_DAYS}d +%Y-%m-%d)
    
    log_info "截止日期: $cutoff_date"
    
    # 查找需要删除的目录
    deleted_count=0
    for dir in */ ; do
        dir=${dir%/}
        # 检查是否是日期格式的目录
        if [[ "$dir" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            if [[ "$dir" < "$cutoff_date" ]]; then
                log_info "删除: $dir"
                rm -rf "$dir"
                deleted_count=$((deleted_count + 1))
            fi
        fi
    done
    
    if [[ $deleted_count -gt 0 ]]; then
        # 更新 reports.json（移除旧报告）
        python3 << EOF
import json
from datetime import datetime, timedelta

cutoff = '$cutoff_date'

with open('reports.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# 过滤掉旧报告
data['reports'] = [r for r in data['reports'] if r['date'] >= cutoff]

with open('reports.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
EOF
        
        git add -A
        git commit -m "清理旧报告（保留近 $KEEP_DAYS 天）" || true
        git push
        
        log_info "已清理 $deleted_count 个旧报告目录"
    else
        log_info "没有需要清理的报告"
    fi
    
    log_info "本地归档目录保留所有报告: $ARCHIVE_DIR"
}

# 列出当前报告
list_reports() {
    cd "$REPO_DIR"
    
    if [[ -f "reports.json" ]]; then
        echo "当前报告列表:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        python3 -c "
import json
with open('reports.json', 'r') as f:
    data = json.load(f)
    for r in data.get('reports', []):
        print(f\"📅 {r['date']}\")
        if 'morning' in r: print(f\"   🌅 早报: {r['morning']}\")
        if 'noon' in r: print(f\"   ☀️ 午报: {r['noon']}\")
        if 'evening' in r: print(f\"   🌙 晚报: {r['evening']}\")
        print()
"
    else
        echo "暂无报告"
    fi
}

# 主入口
case "${1:-}" in
    upload)
        if [[ $# -ne 4 ]]; then usage; fi
        upload_report "$2" "$3" "$4"
        ;;
    cleanup)
        cleanup_old_reports
        ;;
    list)
        list_reports
        ;;
    init)
        init_repo
        ;;
    *)
        usage
        ;;
esac
