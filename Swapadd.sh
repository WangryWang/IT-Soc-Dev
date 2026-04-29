#!/bin/bash
# ==================================================
# 智能Swap扩容脚本 - 支持多平台Linux
# 功能：诊断硬件 | 推荐swap大小 | 自动扩容(2-64G)
# 兼容：Ubuntu/Debian/CentOS/RHEL/AlmaLinux/Rocky
# 架构：x86_64 / aarch64 (ARM)
# GitHub: @your-repo
# ==================================================

set -e  # 遇错停止

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检测发行版
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        log_error "无法检测操作系统类型"
        exit 1
    fi
    
    case $OS in
        ubuntu|debian)
            PKT="apt-get"
            ;;
        centos|rhel|almalinux|rocky|fedora)
            PKT="yum"
            [ "$OS" = "fedora" ] && PKT="dnf"
            ;;
        *)
            log_warn "未测试的发行版: $OS，将尝试使用通用方法"
            PKT="unknown"
            ;;
    esac
}

# 检查root权限
check_root() {
    if [ $EUID -ne 0 ]; then
        log_error "请使用root权限执行 (sudo $0)"
        exit 1
    fi
}

# 硬件诊断
diagnose_hardware() {
    log_info "========== 硬件诊断 =========="
    
    # CPU信息
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
    CPU_CORES=$(nproc)
    CPU_ARCH=$(uname -m)
    log_info "CPU: $CPU_MODEL"
    log_info "核心数: $CPU_CORES"
    log_info "架构: $CPU_ARCH"
    
    # 内存信息
    MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
    MEM_USED=$(free -g | awk '/^Mem:/{print $3}')
    MEM_FREE=$(free -g | awk '/^Mem:/{print $4}')
    log_info "物理内存: ${MEM_TOTAL}GB (已用 ${MEM_USED}GB, 空闲 ${MEM_FREE}GB)"
    
    # 磁盘信息
    DISK_INFO=$(df -h / | awk 'NR==2 {print "总容量:" $2 " 已用:" $3 " 可用:" $4}')
    log_info "根分区: $DISK_INFO"
    
    # 当前swap信息
    if swapon --show | grep -q "^/"; then
        SWAP_CUR=$(free -g | awk '/^Swap:/{print $2}')
        SWAP_FILE=$(swapon --show | awk 'NR==2 {print $1}')
        log_info "当前Swap: ${SWAP_CUR}GB ($SWAP_FILE)"
    else
        log_warn "未检测到任何Swap文件/分区"
        SWAP_CUR=0
    fi
    
    echo ""
}

# 推荐swap大小 (基于物理内存)
calculate_recommended_swap() {
    local mem_gb=$1
    local recommended=0
    
    if [ $mem_gb -le 2 ]; then
        recommended=2
    elif [ $mem_gb -le 4 ]; then
        recommended=4
    elif [ $mem_gb -le 8 ]; then
        recommended=4
    elif [ $mem_gb -le 16 ]; then
        recommended=8
    elif [ $mem_gb -le 32 ]; then
        recommended=12
    else
        recommended=16
    fi
    
    # 边界限制
    if [ $recommended -lt 2 ]; then
        recommended=2
    elif [ $recommended -gt 64 ]; then
        recommended=64
    fi
    
    echo $recommended
}

# 检查磁盘空间是否足够
check_disk_space() {
    local need_gb=$1
    local avail_gb=$(df --output=avail / | tail -1)
    local avail_gb=$((avail_gb / 1024 / 1024))  # 转换为GB
    
    if [ $avail_gb -lt $((need_gb + 2)) ]; then
        log_error "磁盘空间不足! 需要 ${need_gb}GB swap + 2GB 余量, 当前可用 ${avail_gb}GB"
        exit 1
    fi
    
    log_info "磁盘空间充足 (可用 ${avail_gb}GB, 需要 ${need_gb}GB)"
}

# 创建swap文件
create_swap() {
    local size_gb=$1
    local swapfile="/swapfile"
    
    # 检查是否已有自定义swap文件
    if swapon --show | grep -q "^/"; then
        log_warn "检测到已有swap, 将停用并移除现有swap"
        swapoff -a
        # 删除以前的swapfile
        [ -f /swapfile ] && rm -f /swapfile
        # 清理fstab条目
        sed -i '/\/swapfile/d' /etc/fstab
    fi
    
    log_info "创建 ${size_gb}GB swap文件..."
    fallocate -l ${size_gb}G $swapfile || dd if=/dev/zero of=$swapfile bs=1M count=$((size_gb * 1024)) status=progress
    
    chmod 600 $swapfile
    mkswap $swapfile
    swapon $swapfile
    
    # 永久生效
    echo "$swapfile none swap sw 0 0" >> /etc/fstab
    
    log_info "Swap扩容完成! 新swap大小: ${size_gb}GB"
}

# 主流程
main() {
    check_root
    detect_os
    diagnose_hardware
    
    # 推荐swap大小
    REC_SWAP=$(calculate_recommended_swap $MEM_TOTAL)
    log_info "系统推荐swap大小: ${REC_SWAP}GB (基于 ${MEM_TOTAL}GB RAM)"
    
    # 询问用户(可选，非交互模式可自动执行)
    echo -e "\n${YELLOW}请选择操作:${NC}"
    echo "1) 使用推荐值 (${REC_SWAP}GB)"
    echo "2) 自定义大小 (2-64GB)"
    echo "3) 取消"
    read -p "输入选项 [1-3]: " choice
    
    case $choice in
        1)
            TARGET_SIZE=$REC_SWAP
            ;;
        2)
            while true; do
                read -p "请输入目标swap大小(GB, 2-64): " CUSTOM_SIZE
                if [[ $CUSTOM_SIZE =~ ^[0-9]+$ ]] && [ $CUSTOM_SIZE -ge 2 ] && [ $CUSTOM_SIZE -le 64 ]; then
                    TARGET_SIZE=$CUSTOM_SIZE
                    break
                else
                    log_error "大小无效, 请输入2-64之间的整数"
                fi
            done
            ;;
        3)
            log_info "操作已取消"
            exit 0
            ;;
        *)
            log_error "无效选项"
            exit 1
            ;;
    esac
    
    # 检查磁盘空间
    check_disk_space $TARGET_SIZE
    
    # 最终确认
    echo -e "\n${YELLOW}即将创建 ${TARGET_SIZE}GB swap文件, 继续吗? [y/N]${NC}"
    read -r confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_info "已取消"
        exit 0
    fi
    
    # 执行扩容
    create_swap $TARGET_SIZE
    
    # 显示最终状态
    echo ""
    log_info "========== 最终Swap状态 =========="
    free -h
    swapon --show
    
    log_info "脚本执行完毕!"
}

# 运行
main "$@"
