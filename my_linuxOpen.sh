#!/bin/bash
# ============================================
# 本地端口全面检测脚本
#一键运行命令
#curl -sL https://raw.githubusercontent.com/WangryWang/IT-Soc-Dev/main/my_linuxOpen.sh | sudo bash
# 功能：检测 1-65535 端口开放情况，显示详细信息和进程占用
# ============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 检查是否为 root 用户（某些端口信息需要 root 权限）
check_privilege() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}⚠ 提示: 未使用 root 权限运行，部分进程信息可能无法显示${NC}"
        echo -e "${YELLOW}建议使用: sudo $0${NC}\n"
    fi
}

# 检查依赖工具
check_dependencies() {
    local missing_tools=()
    
    for tool in netstat lsof ss; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${YELLOW}提示: 缺少以下工具，将使用备选方案: ${missing_tools[*]}${NC}"
        echo -e "${YELLOW}建议安装: sudo apt update && sudo apt install net-tools lsof -y${NC}\n"
    fi
}

# 获取端口协议类型
get_protocol() {
    local port=$1
    # 常见端口协议映射
    declare -A common_ports=(
        [20]="FTP-data" [21]="FTP" [22]="SSH" [23]="Telnet" [25]="SMTP"
        [53]="DNS" [67]="DHCP" [68]="DHCP" [69]="TFTP" [80]="HTTP"
        [110]="POP3" [123]="NTP" [135]="RPC" [137]="NetBIOS" [138]="NetBIOS"
        [139]="NetBIOS" [143]="IMAP" [161]="SNMP" [162]="SNMP" [179]="BGP"
        [389]="LDAP" [443]="HTTPS" [445]="SMB" [465]="SMTPS" [514]="Syslog"
        [587]="SMTP" [993]="IMAPS" [995]="POP3S" [1080]="SOCKS"
        [1433]="MSSQL" [1521]="Oracle" [1723]="PPTP" [3306]="MySQL"
        [3389]="RDP" [5432]="PostgreSQL" [5900]="VNC" [6379]="Redis"
        [8080]="HTTP-Alt" [8443]="HTTPS-Alt" [27017]="MongoDB"
    )
    
    if [[ -n "${common_ports[$port]}" ]]; then
        echo -e "${CYAN}${common_ports[$port]}${NC}"
    else
        echo -e "${YELLOW}未知${NC}"
    fi
}

# 获取监听状态的进程信息
get_process_info() {
    local port=$1
    local protocol=$2
    local pid=""
    local process_name=""
    local user=""
    
    # 使用 lsof 获取进程信息
    if command -v lsof &> /dev/null; then
        if [ "$protocol" == "tcp" ]; then
            info=$(lsof -i tcp:$port -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $2, $1, $3}')
        else
            info=$(lsof -i udp:$port 2>/dev/null | awk 'NR==2 {print $2, $1, $3}')
        fi
        
        if [ -n "$info" ]; then
            pid=$(echo $info | cut -d' ' -f1)
            process_name=$(echo $info | cut -d' ' -f2)
            user=$(echo $info | cut -d' ' -f3)
        fi
    fi
    
    # 如果 lsof 失败，尝试使用 netstat
    if [ -z "$pid" ] && command -v netstat &> /dev/null; then
        if [ "$protocol" == "tcp" ]; then
            info=$(netstat -tnlp 2>/dev/null | grep ":$port " | awk '{print $7}')
        else
            info=$(netstat -unlp 2>/dev/null | grep ":$port " | awk '{print $7}')
        fi
        
        if [ -n "$info" ]; then
            pid=$(echo $info | cut -d'/' -f1)
            process_name=$(echo $info | cut -d'/' -f2)
            # user 信息需要额外获取
            if [ -n "$pid" ]; then
                user=$(ps -o user= -p $pid 2>/dev/null | xargs)
            fi
        fi
    fi
    
    # 使用 ss 命令作为备选
    if [ -z "$pid" ] && command -v ss &> /dev/null; then
        if [ "$protocol" == "tcp" ]; then
            info=$(ss -tnlp 2>/dev/null | grep ":$port " | grep -v "127.0.0.1" | awk '{print $6}')
            if [ -n "$info" ]; then
                pid=$(echo $info | grep -oP 'pid=\K\d+' | head -1)
                process_name=$(echo $info | grep -oP 'name=\K[^,]+' | head -1)
            fi
        else
            info=$(ss -unlp 2>/dev/null | grep ":$port " | awk '{print $6}')
            if [ -n "$info" ]; then
                pid=$(echo $info | grep -oP 'pid=\K\d+' | head -1)
                process_name=$(echo $info | grep -oP 'name=\K[^,]+' | head -1)
            fi
        fi
    fi
    
    if [ -n "$pid" ] && [ "$pid" != "-" ]; then
        echo -e "${GREEN}PID: $pid${NC} | ${CYAN}进程: $process_name${NC} | ${PURPLE}用户: ${user:-未知}${NC}"
    else
        echo -e "${YELLOW}无进程信息（可能为内核占用）${NC}"
    fi
}

# 检测单个端口
check_single_port() {
    local port=$1
    local tcp_status=""
    local udp_status=""
    local tcp_process=""
    local udp_process=""
    
    # 检测 TCP
    if command -v ss &> /dev/null; then
        tcp_status=$(ss -tln 2>/dev/null | grep -c ":$port ")
    elif command -v netstat &> /dev/null; then
        tcp_status=$(netstat -tln 2>/dev/null | grep -c ":$port ")
    else
        tcp_status=$(timeout 1 nc -zv 127.0.0.1 $port 2>&1 | grep -c "succeeded")
    fi
    
    # 检测 UDP
    if command -v ss &> /dev/null; then
        udp_status=$(ss -uln 2>/dev/null | grep -c ":$port ")
    elif command -v netstat &> /dev/null; then
        udp_status=$(netstat -uln 2>/dev/null | grep -c ":$port ")
    else
        udp_status=0
    fi
    
    # 输出结果
    if [ $tcp_status -gt 0 ] || [ $udp_status -gt 0 ]; then
        echo -e "${GREEN}✓ 端口 $port 开放${NC}"
        
        if [ $tcp_status -gt 0 ]; then
            echo -e "  ├─ ${CYAN}TCP${NC} | 服务: $(get_protocol $port)"
            echo -e "  │  └─ 进程: $(get_process_info $port tcp)"
        fi
        
        if [ $udp_status -gt 0 ]; then
            echo -e "  └─ ${CYAN}UDP${NC} | 服务: $(get_protocol $port)"
            echo -e "     └─ 进程: $(get_process_info $port udp)"
        fi
        echo ""
    fi
}

# 快速扫描（仅显示开放端口）
quick_scan() {
    echo -e "${BLUE}========== 快速扫描模式 ==========${NC}\n"
    echo -e "${YELLOW}正在扫描所有开放端口，请稍候...${NC}\n"
    
    local open_ports=0
    
    if command -v ss &> /dev/null; then
        echo -e "${CYAN}使用 ss 命令快速检测...${NC}\n"
        
        # TCP 监听端口
        echo -e "${GREEN}TCP 监听端口:${NC}"
        ss -tln 2>/dev/null | awk 'NR>1 {print $4}' | grep -oP ':\K\d+' | sort -n | uniq | while read port; do
            service=$(get_protocol $port)
            echo -e "  ${GREEN}✓${NC} 端口 $port - ${service}"
            open_ports=$((open_ports + 1))
        done
        
        # UDP 监听端口
        echo -e "\n${GREEN}UDP 监听端口:${NC}"
        ss -uln 2>/dev/null | awk 'NR>1 {print $5}' | grep -oP ':\K\d+' | sort -n | uniq | while read port; do
            service=$(get_protocol $port)
            echo -e "  ${GREEN}✓${NC} 端口 $port - ${service}"
            open_ports=$((open_ports + 1))
        done
    elif command -v netstat &> /dev/null; then
        echo -e "${CYAN}使用 netstat 命令快速检测...${NC}\n"
        
        echo -e "${GREEN}监听端口列表:${NC}"
        netstat -tuln 2>/dev/null | awk 'NR>2 {print $1, $4}' | while read proto address; do
            port=$(echo $address | grep -oP ':\K\d+')
            if [ -n "$port" ]; then
                service=$(get_protocol $port)
                echo -e "  ${GREEN}✓${NC} $proto 端口 $port - ${service}"
                open_ports=$((open_ports + 1))
            fi
        done
    else
        echo -e "${RED}错误: 未找到 ss 或 netstat 命令${NC}"
        echo -e "${YELLOW}安装方法: sudo apt update && sudo apt install iproute2 net-tools -y${NC}"
        exit 1
    fi
}

# 详细扫描（逐个端口检测）
detailed_scan() {
    local start_port=${1:-1}
    local end_port=${2:-65535}
    
    echo -e "${BLUE}========== 详细扫描模式 ==========${NC}"
    echo -e "${YELLOW}扫描范围: $start_port - $end_port${NC}"
    echo -e "${YELLOW}预计耗时: 较长，请耐心等待...${NC}\n"
    
    local open_ports=0
    local current=0
    local total=$((end_port - start_port + 1))
    
    for port in $(seq $start_port $end_port); do
        current=$((current + 1))
        
        # 显示进度（每100个端口显示一次）
        if [ $((current % 100)) -eq 0 ]; then
            echo -e "${CYAN}进度: $current/$total ($((current * 100 / total))%)${NC}\r"
        fi
        
        check_single_port $port
    done
    
    echo -e "\n${GREEN}扫描完成！${NC}"
}

# 显示端口服务映射表
show_common_ports() {
    echo -e "${BLUE}========== 常用端口服务映射表 ==========${NC}\n"
    
    echo -e "${GREEN}系统端口 (1-1023):${NC}"
    echo -e "  20/tcp  FTP-data      21/tcp  FTP           22/tcp  SSH"
    echo -e "  23/tcp  Telnet        25/tcp  SMTP          53/tcp  DNS"
    echo -e "  67/udp  DHCP          68/udp  DHCP          80/tcp  HTTP"
    echo -e "  110/tcp POP3          123/udp NTP           143/tcp IMAP"
    echo -e "  161/udp SNMP          162/udp SNMP          179/tcp BGP"
    echo -e "  389/tcp LDAP          443/tcp HTTPS         445/tcp SMB"
    echo -e "  465/tcp SMTPS         514/udp Syslog        587/tcp SMTP"
    echo -e "  993/tcp IMAPS         995/tcp POP3S\n"
    
    echo -e "${GREEN}注册端口 (1024-49151):${NC}"
    echo -e "  1080/tcp SOCKS        1433/tcp MSSQL        1521/tcp Oracle"
    echo -e "  1723/tcp PPTP         3306/tcp MySQL        3389/tcp RDP"
    echo -e "  5432/tcp PostgreSQL   5900/tcp VNC          6379/tcp Redis"
    echo -e "  8080/tcp HTTP-Alt     8443/tcp HTTPS-Alt    27017/tcp MongoDB\n"
    
    echo -e "${YELLOW}提示: 完整列表请查看 /etc/services${NC}"
}

# 显示当前所有连接的进程
show_connections() {
    echo -e "${BLUE}========== 当前网络连接进程 ==========${NC}\n"
    
    echo -e "${GREEN}监听端口进程:${NC}"
    if command -v lsof &> /dev/null; then
        lsof -i -sTCP:LISTEN 2>/dev/null | awk 'NR==1 || $9~/LISTEN/'
    elif command -v netstat &> /dev/null; then
        netstat -tulnp 2>/dev/null | grep LISTEN
    else
        echo -e "${RED}无法获取进程信息${NC}"
    fi
}

# 主菜单
main_menu() {
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      本地端口全面检测脚本 v1.0       ${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    
    echo -e "${CYAN}请选择扫描模式:${NC}"
    echo -e "  ${GREEN}1)${NC} 快速扫描 - 仅显示开放端口"
    echo -e "  ${GREEN}2)${NC} 详细扫描 - 检测 1-65535 端口（耗时较长）"
    echo -e "  ${GREEN}3)${NC} 自定义范围扫描"
    echo -e "  ${GREEN}4)${NC} 显示常用端口服务映射表"
    echo -e "  ${GREEN}5)${NC} 显示当前网络连接进程"
    echo -e "  ${GREEN}6)${NC} 检测特定端口"
    echo -e "  ${RED}0)${NC} 退出"
    echo ""
    
    read -p "请输入选项 [0-6]: " choice
    
    case $choice in
        1)
            quick_scan
            ;;
        2)
            detailed_scan 1 65535
            ;;
        3)
            read -p "起始端口 [1]: " start
            read -p "结束端口 [65535]: " end
            start=${start:-1}
            end=${end:-65535}
            if [ $start -lt 1 ] || [ $end -gt 65535 ] || [ $start -gt $end ]; then
                echo -e "${RED}端口范围无效！${NC}"
            else
                detailed_scan $start $end
            fi
            ;;
        4)
            show_common_ports
            ;;
        5)
            show_connections
            ;;
        6)
            read -p "请输入端口号: " single_port
            if [[ $single_port =~ ^[0-9]+$ ]] && [ $single_port -ge 1 ] && [ $single_port -le 65535 ]; then
                check_single_port $single_port
            else
                echo -e "${RED}端口号无效！${NC}"
            fi
            ;;
        0)
            echo -e "${GREEN}再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项！${NC}"
            ;;
    esac
    
    echo -e "\n${YELLOW}按 Enter 键返回主菜单...${NC}"
    read
    main_menu
}

# 命令行参数模式
if [ $# -gt 0 ]; then
    case $1 in
        -q|--quick)
            check_privilege
            check_dependencies
            quick_scan
            ;;
        -d|--detailed)
            check_privilege
            check_dependencies
            detailed_scan ${2:-1} ${3:-65535}
            ;;
        -p|--port)
            if [ -n "$2" ]; then
                check_privilege
                check_dependencies
                check_single_port $2
            else
                echo "用法: $0 --port <端口号>"
            fi
            ;;
        -l|--list)
            show_common_ports
            ;;
        -c|--connections)
            show_connections
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  -q, --quick              快速扫描模式"
            echo "  -d, --detailed [起始] [结束]  详细扫描模式"
            echo "  -p, --port <端口号>      检测特定端口"
            echo "  -l, --list               显示常用端口服务映射表"
            echo "  -c, --connections        显示当前网络连接进程"
            echo "  -h, --help               显示此帮助信息"
            ;;
        *)
            echo "未知选项: $1"
            echo "使用 $0 -h 查看帮助"
            exit 1
            ;;
    esac
else
    # 交互式模式
    check_privilege
    check_dependencies
    main_menu
fi
