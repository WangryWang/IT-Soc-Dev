# 删除旧脚本
sudo rm -f /tmp/swap_cleanup.sh

# 使用 cat 重新创建（会自动使用正确格式）
sudo cat > /tmp/swap_cleanup.sh << 'EOF'
#!/bin/bash
# ============================================
# Ubuntu Swap 完全清理与智能扩容脚本
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 请使用 root 权限运行此脚本${NC}"
        exit 1
    fi
}

get_system_info() {
    echo -e "${BLUE}正在检测系统信息...${NC}\n"
    
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    AVAIL_MEM=$(free -m | awk '/^Mem:/{print $7}')
    
    # 获取 Swap 信息
    if swapon --show 2>/dev/null | grep -q "swap"; then
        CURRENT_SWAP=$(free -m | awk '/^Swap:/{print $2}')
        CURRENT_SWAP=${CURRENT_SWAP:-0}
    else
        CURRENT_SWAP=0
    fi
    
    ROOT_AVAIL=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    echo -e "${GREEN}========== 系统信息 ==========${NC}"
    echo -e "${YELLOW}物理内存总量:${NC} ${TOTAL_MEM}MB"
    echo -e "${YELLOW}可用物理内存:${NC} ${AVAIL_MEM}MB"
    echo -e "${YELLOW}当前 Swap 大小:${NC} ${CURRENT_SWAP}MB"
    echo -e "${YELLOW}根目录可用空间:${NC} ${ROOT_AVAIL}GB"
    echo -e "${GREEN}================================${NC}\n"
}

clean_all_swap() {
    echo -e "${BLUE}========== 清理现有 Swap ==========${NC}\n"
    
    echo -e "${YELLOW}关闭所有 Swap...${NC}"
    swapoff -a 2>/dev/null
    
    echo -e "${YELLOW}删除 swapfile...${NC}"
    rm -f /swapfile /swap.img
    
    if [ -f /etc/fstab ]; then
        cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
        sed -i '/swap/d' /etc/fstab
        echo -e "${GREEN}✓ 已清理 /etc/fstab${NC}"
    fi
    
    echo -e "${GREEN}✓ 清理完成${NC}\n"
}

main() {
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   Ubuntu Swap 智能扩容脚本 v2.0${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    
    check_root
    get_system_info
    clean_all_swap
    
    echo -e "${GREEN}✓ 脚本执行完毕！${NC}"
}

main
EOF

# 运行脚本
sudo bash /tmp/swap_cleanup.sh
