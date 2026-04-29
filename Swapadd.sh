#!/bin/bash
# ============================================
# Ubuntu Swap 完全清理与智能扩容脚本
# 功能：先检查并清理所有现有 Swap，然后创建新的 Swap 文件
#一键运行命令
#curl -sL https://raw.githubusercontent.com/WangryWang/IT-Soc-Dev/main/my_linuxOpen.sh | sudo bash
# ============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 请使用 root 权限运行此脚本${NC}"
        echo "使用: sudo $0"
        exit 1
    fi
}

# 获取当前系统信息
get_system_info() {
    echo -e "${BLUE}正在检测系统信息...${NC}\n"
    
    # 获取内存信息 (单位: MB)
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    AVAIL_MEM=$(free -m | awk '/^Mem:/{print $7}')
    
    # 获取 Swap 详细信息
    if swapon --show 2>/dev/null | grep -q "swap"; then
        CURRENT_SWAP=$(free -m | awk '/^Swap:/{print $2}')
        CURRENT_SWAP=${CURRENT_SWAP:-0}
        
        # 获取所有 swap 设备/文件
        mapfile -t SWAP_DEVICES < <(swapon --show --noheadings | awk '{print $1}')
        SWAP_COUNT=${#SWAP_DEVICES[@]}
        
        # 判断类型
        if [[ "${SWAP_DEVICES[0]}" == "/swapfile" ]]; then
            SWAP_TYPE_NAME="文件"
        else
            SWAP_TYPE_NAME="分区"
        fi
    else
        CURRENT_SWAP=0
        SWAP_TYPE_NAME="无"
        SWAP_DEVICES=()
        SWAP_COUNT=0
    fi
    
    # 获取 CPU 信息
    CPU_CORES=$(nproc)
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
    
    # 获取磁盘可用空间
    ROOT_AVAIL=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    ROOT_AVAIL_MB=$(df -BM / | awk 'NR==2 {print $4}' | sed 's/M//')
    
    # 显示系统信息
    echo -e "${GREEN}========== 系统信息 ==========${NC}"
    echo -e "${YELLOW}CPU:${NC} $CPU_MODEL"
    echo -e "${YELLOW}CPU 核心数:${NC} $CPU_CORES"
    echo -e "${YELLOW}物理内存总量:${NC} ${TOTAL_MEM}MB"
    echo -e "${YELLOW}可用物理内存:${NC} ${AVAIL_MEM}MB"
    echo -e "${YELLOW}当前 Swap 大小:${NC} ${CURRENT_SWAP}MB (类型: $SWAP_TYPE_NAME)"
    echo -e "${YELLOW}当前 Swap 设备数量:${NC} $SWAP_COUNT"
    if [ $SWAP_COUNT -gt 0 ]; then
        echo -e "${YELLOW}Swap 设备列表:${NC}"
        for device in "${SWAP_DEVICES[@]}"; do
            echo "  - $device"
        done
    fi
    echo -e "${YELLOW}根目录可用空间:${NC} ${ROOT_AVAIL}GB"
    echo -e "${GREEN}================================${NC}\n"
}

# 清理所有现有 Swap
clean_all_swap() {
    echo -e "${BLUE}========== 开始清理现有 Swap ==========${NC}\n"
    
    # 1. 显示当前 Swap 状态
    echo -e "${YELLOW}当前 Swap 状态:${NC}"
    swapon --show 2>/dev/null || echo "无活动 Swap"
    free -h | grep Swap
    
    # 2. 关闭所有 Swap
    echo -e "\n${YELLOW}步骤 1/5: 关闭所有 Swap...${NC}"
    swapoff -a 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 所有 Swap 已关闭${NC}"
    else
        echo -e "${YELLOW}⚠ 关闭 Swap 时出现警告（可能已关闭）${NC}"
    fi
    
    # 3. 再次确认所有 Swap 已关闭
    echo -e "\n${YELLOW}步骤 2/5: 验证 Swap 状态...${NC}"
    sleep 1
    if swapon --show 2>/dev/null | grep -q "swap"; then
        echo -e "${RED}✗ 仍有 Swap 活动，尝试强制关闭...${NC}"
        swapoff -a --verbose 2>&1 | tee /tmp/swapoff.log
        if [ $? -ne 0 ]; then
            echo -e "${RED}无法关闭某些 Swap 设备，请手动检查${NC}"
            swapon --show
            exit 1
        fi
    else
        echo -e "${GREEN}✓ 所有 Swap 已成功关闭${NC}"
    fi
    
    # 4. 删除 Swap 文件（如果存在）
    echo -e "\n${YELLOW}步骤 3/5: 删除 Swap 文件...${NC}"
    SWAP_FILES=("/swapfile" "/swap.img" "/var/swapfile" "/var/swap.img")
    for swapfile in "${SWAP_FILES[@]}"; do
        if [ -f "$swapfile" ]; then
            echo -e "  删除: $swapfile"
            rm -f "$swapfile"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}  ✓ 已删除 $swapfile${NC}"
            else
                echo -e "${RED}  ✗ 无法删除 $swapfile${NC}"
            fi
        fi
    done
    
    # 5. 清理 /etc/fstab 中的 Swap 条目
    echo -e "\n${YELLOW}步骤 4/5: 清理 /etc/fstab 配置...${NC}"
    if [ -f /etc/fstab ]; then
        # 备份 fstab
        cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
        echo -e "${GREEN}✓ 已备份 /etc/fstab${NC}"
        
        # 移除所有 swap 相关条目
        sed -i '/swap/d' /etc/fstab
        sed -i '/SWAP/d' /etc/fstab
        echo -e "${GREEN}✓ 已清理 fstab 中的 Swap 条目${NC}"
    fi
    
    # 6. 清理 sysctl.conf 中的 swappiness 设置（可选）
    echo -e "\n${YELLOW}步骤 5/5: 可选 - 重置 swappiness 配置${NC}"
    read -p "是否重置 swappiness 为默认值 60？[y/N]: " RESET_SWAPPINESS
    if [[ $RESET_SWAPPINESS =~ ^[Yy]$ ]]; then
        sed -i '/vm.swappiness/d' /etc/sysctl.conf
        sysctl vm.swappiness=60
        echo -e "${GREEN}✓ swappiness 已重置为 60${NC}"
    else
        echo -e "${YELLOW}跳过 swappiness 重置${NC}"
    fi
    
    # 最终验证
    echo -e "\n${GREEN}========== 清理完成 ==========${NC}"
    echo -e "${YELLOW}清理后 Swap 状态:${NC}"
    free -h
    echo -e "\n${GREEN}✓ 系统已无活动 Swap${NC}"
}

# 推荐 Swap 大小
recommend_swap_size() {
    echo -e "\n${BLUE}========== 智能推荐 Swap 大小 ==========${NC}\n"
    
    # 根据内存大小推荐
    if [ $TOTAL_MEM -le 2048 ]; then
        RECOMMENDED_SIZES="2G, 4G, 8G"
        DEFAULT_SIZE=4
        REASON="内存较小(≤2GB)，建议设置 2-4GB Swap"
    elif [ $TOTAL_MEM -le 4096 ]; then
        RECOMMENDED_SIZES="4G, 8G, 12G"
        DEFAULT_SIZE=8
        REASON="内存适中(2-4GB)，建议设置 4-8GB Swap"
    elif [ $TOTAL_MEM -le 8192 ]; then
        RECOMMENDED_SIZES="8G, 12G, 16G"
        DEFAULT_SIZE=12
        REASON="内存较大(4-8GB)，建议设置 8-16GB Swap"
    elif [ $TOTAL_MEM -le 16384 ]; then
        RECOMMENDED_SIZES="12G, 16G, 24G"
        DEFAULT_SIZE=16
        REASON="内存很大(8-16GB)，建议设置 12-24GB Swap"
    elif [ $TOTAL_MEM -le 32768 ]; then
        RECOMMENDED_SIZES="16G, 24G, 32G"
        DEFAULT_SIZE=24
        REASON="内存超大(16-32GB)，建议设置 16-32GB Swap"
    else
        RECOMMENDED_SIZES="16G, 24G, 32G, 64G, 128G"
        DEFAULT_SIZE=24
        REASON="内存极大(>32GB)，根据需求设置 16-128GB Swap"
    fi
    
    # 考虑可用磁盘空间
    MAX_ALLOWED=$((ROOT_AVAIL - 5))
    if [ $MAX_ALLOWED -lt 2 ]; then
        echo -e "${RED}错误: 磁盘空间不足 5GB，无法安全创建 Swap${NC}"
        exit 1
    fi
    
    if [ $MAX_ALLOWED -lt ${DEFAULT_SIZE} ]; then
        DEFAULT_SIZE=$MAX_ALLOWED
        RECOMMENDED_SIZES="${MAX_ALLOWED}G"
        REASON="$REASON (受磁盘空间限制，最大 ${MAX_ALLOWED}GB)"
    fi
    
    echo -e "${YELLOW}推荐方案:${NC} $REASON"
    echo -e "${YELLOW}推荐大小范围:${NC} $RECOMMENDED_SIZES"
    echo -e "${YELLOW}磁盘限制:${NC} 最大可用 ${MAX_ALLOWED}GB（预留 5GB 系统空间）\n"
}

# 选择 Swap 大小
select_swap_size() {
    while true; do
        echo -e "${BLUE}请输入新的 Swap 大小:${NC}"
        read -p "范围 2G-${MAX_ALLOWED}G [默认: ${DEFAULT_SIZE}G]: " USER_INPUT
        
        if [ -z "$USER_INPUT" ]; then
            NEW_SWAP_SIZE="${DEFAULT_SIZE}G"
            NEW_SWAP_MB=$((DEFAULT_SIZE * 1024))
            break
        fi
        
        USER_INPUT=$(echo "$USER_INPUT" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
        
        if [[ $USER_INPUT =~ ^([0-9]+)G$ ]]; then
            SIZE_NUM=${BASH_REMATCH[1]}
            if [ $SIZE_NUM -ge 2 ] && [ $SIZE_NUM -le $MAX_ALLOWED ]; then
                NEW_SWAP_SIZE="${SIZE_NUM}G"
                NEW_SWAP_MB=$((SIZE_NUM * 1024))
                break
            else
                echo -e "${RED}错误: 大小必须在 2GB 到 ${MAX_ALLOWED}GB 之间${NC}"
            fi
        else
            echo -e "${RED}错误: 格式错误，请使用如 '8G' 的格式${NC}"
        fi
    done
    
    echo -e "${GREEN}将设置 Swap 大小为: $NEW_SWAP_SIZE${NC}\n"
}

# 创建新的 Swap
create_new_swap() {
    echo -e "${BLUE}========== 创建新的 Swap ==========${NC}\n"
    
    # 创建 swapfile
    echo -e "${YELLOW}正在创建 swapfile (大小: $NEW_SWAP_SIZE)...${NC}"
    echo -e "${YELLOW}这可能需要几分钟，请耐心等待...${NC}"
    
    # 尝试使用 fallocate
    if fallocate -l $NEW_SWAP_SIZE /swapfile 2>/dev/null; then
        echo -e "${GREEN}✓ 使用 fallocate 创建成功${NC}"
    else
        echo -e "${YELLOW}fallocate 失败，使用 dd 命令...${NC}"
        dd if=/dev/zero of=/swapfile bs=1M count=$NEW_SWAP_MB status=progress
        if [ $? -ne 0 ]; then
            echo -e "${RED}✗ 创建 swapfile 失败${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ 使用 dd 创建成功${NC}"
    fi
    
    # 设置权限
    echo -e "\n${YELLOW}设置权限...${NC}"
    chmod 600 /swapfile
    echo -e "${GREEN}✓ 权限已设置 (600)${NC}"
    
    # 格式化为 swap
    echo -e "\n${YELLOW}格式化 swap...${NC}"
    mkswap /swapfile
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 格式化失败${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ 格式化成功${NC}"
    
    # 启用 swap
    echo -e "\n${YELLOW}启用 swap...${NC}"
    swapon /swapfile
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 启用失败${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Swap 已启用${NC}"
}

# 配置永久生效
configure_permanent() {
    echo -e "\n${BLUE}========== 配置永久生效 ==========${NC}\n"
    
    # 配置 fstab
    echo -e "${YELLOW}配置 /etc/fstab...${NC}"
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
    echo -e "${GREEN}✓ 已添加 swapfile 到 fstab${NC}"
    
    # 配置 swappiness
    echo -e "\n${YELLOW}配置 swappiness...${NC}"
    read -p "请输入 swappiness 值 (0-100, 推荐 10-60) [默认: 60]: " SWAP_VAL
    
    if [ -z "$SWAP_VAL" ]; then
        SWAP_VAL=60
    fi
    
    if [[ $SWAP_VAL =~ ^[0-9]+$ ]] && [ $SWAP_VAL -ge 0 ] && [ $SWAP_VAL -le 100 ]; then
        sysctl vm.swappiness=$SWAP_VAL
        echo "vm.swappiness=$SWAP_VAL" >> /etc/sysctl.conf
        echo -e "${GREEN}✓ swappiness 已设置为 $SWAP_VAL${NC}"
    else
        echo -e "${RED}输入无效，保持默认${NC}"
    fi
}

# 验证结果
verify_result() {
    echo -e "\n${GREEN}========== 扩容完成 ==========${NC}\n"
    
    sleep 2
    echo -e "${YELLOW}最终 Swap 状态:${NC}"
    free -h
    echo -e "\n${YELLOW}Swap 设备:${NC}"
    swapon --show
    
    echo -e "\n${GREEN}✓ Swap 扩容成功完成！${NC}"
    echo -e "${YELLOW}提示: 重启后配置将永久生效${NC}"
}

# 主函数
main() {
    clear
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}   Ubuntu Swap 完整清理与智能扩容脚本 v2.0   ${NC}"
    echo -e "${GREEN}============================================${NC}\n"
    
    check_root
    get_system_info
    
    # 阶段1：清理现有 Swap
    echo -e "${RED}⚠ 警告: 即将清理系统中的所有 Swap！${NC}"
    echo -e "${YELLOW}这包括所有 swap 文件和分区配置。${NC}"
    read -p "是否继续清理？[y/N]: " CLEAN_CONFIRM
    
    if [[ ! $CLEAN_CONFIRM =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}操作已取消${NC}"
        exit 0
    fi
    
    clean_all_swap
    
    # 阶段2：推荐和选择新 Swap 大小
    recommend_swap_size
    select_swap_size
    
    # 阶段3：确认创建新 Swap
    echo -e "${YELLOW}即将创建新的 Swap:${NC}"
    echo "  大小: $NEW_SWAP_SIZE"
    echo "  位置: /swapfile"
    echo -e "\n${RED}是否继续？[y/N]: ${NC}"
    read -r CREATE_CONFIRM
    
    if [[ ! $CREATE_CONFIRM =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}操作已取消${NC}"
        exit 0
    fi
    
    # 阶段4：创建和配置
    create_new_swap
    configure_permanent
    verify_result
    
    echo -e "\n${GREEN}脚本执行完毕！${NC}"
}

# 运行主函数
main
