#!/bin/bash
#本脚本适用于Linux环境下增加swap内存。
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

# 获取系统信息
get_system_info() {
    echo -e "${BLUE}正在检测系统信息...${NC}\n"
    
    # 获取内存信息 (单位: MB)
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    AVAIL_MEM=$(free -m | awk '/^Mem:/{print $7}')
    
    # 获取 Swap 信息
    if swapon --show 2>/dev/null | grep -q "swap"; then
        CURRENT_SWAP=$(free -m | awk '/^Swap:/{print $2}')
        SWAP_TYPE=$(swapon --show | awk 'NR>1 {print $1}' | head -1)
        if [[ "$SWAP_TYPE" == "/swapfile" ]]; then
            SWAP_TYPE_NAME="文件"
        else
            SWAP_TYPE_NAME="分区"
        fi
    else
        CURRENT_SWAP=0
        SWAP_TYPE_NAME="无"
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
    echo -e "${YELLOW}根目录可用空间:${NC} ${ROOT_AVAIL}GB"
    echo -e "${GREEN}================================${NC}\n"
}

# 推荐 Swap 大小
recommend_swap_size() {
    echo -e "${BLUE}正在分析并推荐 Swap 大小...${NC}\n"
    
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
    if [ $ROOT_AVAIL -lt 20 ]; then
        echo -e "${YELLOW}警告: 根目录剩余空间仅 ${ROOT_AVAIL}GB，建议慎重考虑 Swap 大小${NC}"
        MAX_SWAP=$((ROOT_AVAIL - 2))
        if [ $MAX_SWAP -lt 2 ]; then
            echo -e "${RED}错误: 磁盘空间不足 2GB，无法创建 Swap${NC}"
            exit 1
        fi
        RECOMMENDED_SIZES="${MAX_SWAP}G"
        REASON="$REASON (受磁盘空间限制)"
        DEFAULT_SIZE=$MAX_SWAP
    fi
    
    echo -e "${YELLOW}推荐方案:${NC} $REASON"
    echo -e "${YELLOW}推荐大小:${NC} $RECOMMENDED_SIZES\n"
}

# 选择 Swap 大小
select_swap_size() {
    while true; do
        echo -e "${BLUE}请输入新的 Swap 大小 (范围: 2G 到 128G):${NC}"
        read -p "例如: 8G, 16G, 32G [默认: ${DEFAULT_SIZE}G]: " USER_INPUT
        
        if [ -z "$USER_INPUT" ]; then
            NEW_SWAP_SIZE="${DEFAULT_SIZE}G"
            NEW_SWAP_MB=$((DEFAULT_SIZE * 1024))
            break
        fi
        
        # 去除空格并转换为大写
        USER_INPUT=$(echo "$USER_INPUT" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
        
        # 提取数字和单位
        if [[ $USER_INPUT =~ ^([0-9]+)G$ ]]; then
            SIZE_NUM=${BASH_REMATCH[1]}
            if [ $SIZE_NUM -ge 2 ] && [ $SIZE_NUM -le 128 ]; then
                NEW_SWAP_SIZE="${SIZE_NUM}G"
                NEW_SWAP_MB=$((SIZE_NUM * 1024))
                break
            else
                echo -e "${RED}错误: 大小必须在 2GB 到 128GB 之间${NC}"
            fi
        else
            echo -e "${RED}错误: 格式错误，请使用如 '8G' 或 '16G' 的格式${NC}"
        fi
    done
    
    # 检查磁盘空间
    if [ $NEW_SWAP_MB -gt $((ROOT_AVAIL_MB - 1024)) ]; then
        echo -e "${RED}错误: 磁盘空间不足！需要 ${NEW_SWAP_SIZE}，但仅剩 ${ROOT_AVAIL}GB 可用空间${NC}"
        echo -e "${YELLOW}请在释放一些空间后重试${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}将设置 Swap 大小为: $NEW_SWAP_SIZE${NC}\n"
}

# 执行 Swap 扩容
execute_swap_expand() {
    echo -e "${BLUE}开始执行 Swap 扩容...${NC}\n"
    
    # 关闭现有 Swap
    if [ $CURRENT_SWAP -gt 0 ]; then
        echo -e "${YELLOW}正在关闭现有 Swap...${NC}"
        swapoff -a 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 已关闭现有 Swap${NC}"
        else
            echo -e "${RED}✗ 关闭 Swap 失败${NC}"
            exit 1
        fi
    fi
    
    # 删除旧的 swapfile（如果存在）
    if [ -f /swapfile ]; then
        echo -e "${YELLOW}正在删除旧的 swapfile...${NC}"
        rm -f /swapfile
        echo -e "${GREEN}✓ 已删除旧的 swapfile${NC}"
    fi
    
    # 创建新的 swapfile
    echo -e "${YELLOW}正在创建新的 swapfile (大小: $NEW_SWAP_SIZE)...${NC}"
    echo -e "${YELLOW}这可能需要一些时间，请耐心等待...${NC}"
    
    # 尝试使用 fallocate
    if fallocate -l $NEW_SWAP_SIZE /swapfile 2>/dev/null; then
        echo -e "${GREEN}✓ 使用 fallocate 创建成功${NC}"
    else
        echo -e "${YELLOW}fallocate 失败，尝试使用 dd 命令...${NC}"
        if dd if=/dev/zero of=/swapfile bs=1M count=$NEW_SWAP_MB status=progress 2>/dev/null; then
            echo -e "${GREEN}✓ 使用 dd 创建成功${NC}"
        else
            echo -e "${RED}✗ 创建 swapfile 失败${NC}"
            exit 1
        fi
    fi
    
    # 设置权限
    echo -e "${YELLOW}正在设置权限...${NC}"
    chmod 600 /swapfile
    echo -e "${GREEN}✓ 权限设置完成${NC}"
    
    # 格式化为 swap
    echo -e "${YELLOW}正在格式化 swap...${NC}"
    mkswap /swapfile
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 格式化成功${NC}"
    else
        echo -e "${RED}✗ 格式化失败${NC}"
        exit 1
    fi
    
    # 启用 swap
    echo -e "${YELLOW}正在启用 swap...${NC}"
    swapon /swapfile
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Swap 启用成功${NC}"
    else
        echo -e "${RED}✗ Swap 启用失败${NC}"
        exit 1
    fi
}

# 配置 fstab
configure_fstab() {
    echo -e "\n${BLUE}正在配置永久挂载...${NC}"
    
    # 备份 fstab
    if [ ! -f /etc/fstab.backup ]; then
        cp /etc/fstab /etc/fstab.backup
        echo -e "${GREEN}✓ 已备份 /etc/fstab 到 /etc/fstab.backup${NC}"
    fi
    
    # 移除旧的 swap 条目
    sed -i '/swapfile/d' /etc/fstab
    sed -i '/swap.*swap/d' /etc/fstab
    
    # 添加新的条目
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
    echo -e "${GREEN}✓ 已添加 swapfile 到 /etc/fstab${NC}"
}

# 配置 swappiness
configure_swappiness() {
    echo -e "\n${BLUE}正在配置 swappiness 参数...${NC}"
    
    CURRENT_SWAPPINESS=$(cat /proc/sys/vm/swappiness)
    echo -e "${YELLOW}当前 swappiness 值: $CURRENT_SWAPPINESS${NC}"
    echo -e "${YELLOW}建议值: ${NC}"
    echo "  10 - 20: 服务器/高性能场景"
    echo "  60:      桌面系统默认值"
    echo "  100:     会频繁使用 swap"
    
    read -p "请输入新的 swappiness 值 [默认: 60]: " NEW_SWAPPINESS
    
    if [ -z "$NEW_SWAPPINESS" ]; then
        NEW_SWAPPINESS=60
    fi
    
    if [[ $NEW_SWAPPINESS =~ ^[0-9]+$ ]] && [ $NEW_SWAPPINESS -ge 0 ] && [ $NEW_SWAPPINESS -le 100 ]; then
        sysctl vm.swappiness=$NEW_SWAPPINESS
        echo "vm.swappiness=$NEW_SWAPPINESS" >> /etc/sysctl.conf
        echo -e "${GREEN}✓ swappiness 已设置为 $NEW_SWAPPINESS${NC}"
    else
        echo -e "${RED}输入无效，保持默认值 $CURRENT_SWAPPINESS${NC}"
    fi
}

# 验证结果
verify_result() {
    echo -e "\n${GREEN}========== 扩容完成 ==========${NC}"
    
    sleep 2
    free -h
    
    echo -e "\n${BLUE}Swap 状态:${NC}"
    swapon --show
    
    echo -e "\n${GREEN}✓ Swap 扩容成功完成！${NC}"
    echo -e "${YELLOW}注意: 请检查上述输出确认 Swap 大小是否正确${NC}"
}

# 主函数
main() {
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}     Ubuntu Swap 智能扩容脚本 v1.0     ${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    
    check_root
    get_system_info
    recommend_swap_size
    select_swap_size
    
    echo -e "${YELLOW}即将执行以下操作:${NC}"
    echo "  1. 关闭现有 Swap"
    echo "  2. 删除旧的 swapfile"
    echo "  3. 创建 ${NEW_SWAP_SIZE} 的 swapfile"
    echo "  4. 配置权限并启用"
    echo "  5. 配置永久挂载"
    echo "  6. 配置 swappiness"
    
    echo -e "\n${RED}是否继续？[y/N]: ${NC}"
    read -r CONFIRM
    
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}操作已取消${NC}"
        exit 0
    fi
    
    execute_swap_expand
    configure_fstab
    configure_swappiness
    verify_result
}

# 运行主函数
main
