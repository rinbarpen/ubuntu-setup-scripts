#!/bin/bash

# SSH密钥生成与配置脚本
# 功能：自动生成SSH密钥并配置服务器和客户端
# 支持交互式操作，可随时撤回

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 临时文件
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# 状态变量
STEP=1
TOTAL_STEPS=5
CANCELLED=0

# 默认配置
KEY_TYPE="ed25519"
KEY_BITS=""
PASSPHRASE=""
REMOTE_HOST=""
REMOTE_PORT="22"
REMOTE_USER=""
HOST_ALIAS=""
SKIP_SERVER=0
SKIP_CLIENT=0

# 收集系统信息
collect_info() {
    HOSTNAME=$(hostname)
    OS_PRETTY=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)
    OS_NAME=$(echo "$OS_PRETTY" | awk '{print $1}')
    OS_VERSION=$(grep VERSION_ID /etc/os-release 2>/dev/null | cut -d'"' -f2)
    USERNAME=$(whoami)

    # 生成默认密钥名
    KEY_NAME="${HOSTNAME}-${OS_NAME}${OS_VERSION}-${USERNAME}"
    KEY_PATH="$HOME/.ssh/${KEY_NAME}"
}

# 显示信息
show_info() {
    echo -e "${BLUE}=== SSH密钥生成脚本 ===${NC}"
    echo ""
    echo -e "系统信息："
    echo -e "  主机名: ${GREEN}${HOSTNAME}${NC}"
    echo -e "  系统: ${GREEN}${OS_PRETTY}${NC}"
    echo -e "  用户: ${GREEN}${USERNAME}${NC}"
    echo ""
    echo -e "密钥信息："
    echo -e "  名称: ${GREEN}${KEY_NAME}${NC}"
    echo -e "  路径: ${GREEN}${KEY_PATH}${NC}"
    echo -e "  类型: ${GREEN}${KEY_TYPE}${NC}"
    echo ""
}

# whiptail 检查
check_whiptail() {
    if ! command -v whiptail &> /dev/null; then
        echo -e "${YELLOW}警告: whiptail未安装，将使用命令行交互模式${NC}"
        USE_WHIPTAIL=0
    else
        USE_WHIPTAIL=1
    fi
}

# whiptail 信息确认
whiptail_confirm() {
    local title="步骤 $STEP/$TOTAL_STEPS - 确认密钥信息"
    local message="即将生成SSH密钥：\n\n"
    message+="主机名: $HOSTNAME\n"
    message+="系统: $OS_PRETTY\n"
    message+="用户: $USERNAME\n"
    message+="密钥名: $KEY_NAME\n"
    message+="密钥类型: $KEY_TYPE\n"
    message+="密钥路径: $KEY_PATH\n\n"
    message+="请选择操作："

    whiptail --title "$title" --menu "$message" 20 70 5 \
        "confirm" "确认并继续生成密钥" \
        "modify" "修改密钥名称" \
        "type" "修改密钥类型 (当前: $KEY_TYPE)" \
        "cancel" "取消操作" \
        2>$TEMP_FILE || return 1

    choice=$(cat $TEMP_FILE)
    case $choice in
        confirm) return 0 ;;
        modify) modify_key_name; return 1 ;;
        type) modify_key_type; return 1 ;;
        cancel) return 2 ;;
        *) return 1 ;;
    esac
}

# 命令行信息确认
cli_confirm() {
    show_info
    echo "请选择操作："
    echo "  1) 确认并继续生成密钥"
    echo "  2) 修改密钥名称"
    echo "  3) 修改密钥类型 (当前: $KEY_TYPE)"
    echo "  4) 取消操作"
    echo ""
    read -p "请输入选项 [1-4]: " choice

    case $choice in
        1) return 0 ;;
        2) modify_key_name; return 1 ;;
        3) modify_key_type; return 1 ;;
        4) return 2 ;;
        *) echo -e "${RED}无效选项${NC}"; return 1 ;;
    esac
}

# 修改密钥名称
modify_key_name() {
    if [ $USE_WHIPTAIL -eq 1 ]; then
        whiptail --title "修改密钥名称" --inputbox "请输入新的密钥名称：" 10 60 "$KEY_NAME" 2>$TEMP_FILE || return
        NEW_NAME=$(cat $TEMP_FILE)
    else
        read -p "请输入新的密钥名称 [当前: $KEY_NAME]: " NEW_NAME
    fi

    if [ -n "$NEW_NAME" ]; then
        KEY_NAME="$NEW_NAME"
        KEY_PATH="$HOME/.ssh/${KEY_NAME}"
        echo -e "${GREEN}密钥名称已更新为: $KEY_NAME${NC}"
    fi
}

# 修改密钥类型
modify_key_type() {
    if [ $USE_WHIPTAIL -eq 1 ]; then
        whiptail --title "选择密钥类型" --menu "请选择密钥类型：" 15 50 4 \
            "ed25519" "ED25519 (推荐，更安全)" \
            "rsa" "RSA 4096 (兼容性好)" \
            2>$TEMP_FILE || return
        KEY_TYPE=$(cat $TEMP_FILE)
    else
        echo "请选择密钥类型："
        echo "  1) ED25519 (推荐，更安全)"
        echo "  2) RSA 4096 (兼容性好)"
        read -p "请输入选项 [1-2]: " choice
        case $choice in
            1) KEY_TYPE="ed25519" ;;
            2) KEY_TYPE="rsa" ;;
            *) echo -e "${RED}无效选项，保持当前类型: $KEY_TYPE${NC}" ;;
        esac
    fi

    if [ "$KEY_TYPE" = "rsa" ]; then
        KEY_BITS="-b 4096"
    else
        KEY_BITS=""
    fi
    echo -e "${GREEN}密钥类型已设置为: $KEY_TYPE${NC}"
}

# 生成密钥
generate_key() {
    echo -e "${BLUE}正在生成 $KEY_TYPE 密钥...${NC}"

    # 检查是否已存在
    if [ -f "$KEY_PATH" ]; then
        echo -e "${YELLOW}警告: 密钥文件已存在: $KEY_PATH${NC}"
        if [ $USE_WHIPTAIL -eq 1 ]; then
            whiptail --title "密钥已存在" --yesno "密钥文件已存在，是否覆盖？" 10 60 || return 1
        else
            read -p "是否覆盖现有密钥? [y/N]: " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || return 1
        fi
    fi

    # 设置密码
    if [ $USE_WHIPTAIL -eq 1 ]; then
        if whiptail --title "设置密码" --yesno "是否为密钥设置密码保护？(推荐)" 10 60; then
            whiptail --title "输入密码" --passwordbox "请输入密钥密码：" 10 60 2>$TEMP_FILE || return 1
            PASSPHRASE=$(cat $TEMP_FILE)
            whiptail --title "确认密码" --passwordbox "请再次输入密钥密码：" 10 60 2>$TEMP_FILE || return 1
            PASSPHRASE2=$(cat $TEMP_FILE)
            if [ "$PASSPHRASE" != "$PASSPHRASE2" ]; then
                echo -e "${RED}密码不匹配${NC}"
                return 1
            fi
        else
            PASSPHRASE=""
        fi
    else
        read -p "是否为密钥设置密码? [y/N]: " set_pass
        if [[ "$set_pass" =~ ^[Yy]$ ]]; then
            read -sp "请输入密钥密码: " PASSPHRASE
            echo ""
            read -sp "请再次输入密钥密码: " PASSPHRASE2
            echo ""
            if [ "$PASSPHRASE" != "$PASSPHRASE2" ]; then
                echo -e "${RED}密码不匹配${NC}"
                return 1
            fi
        else
            PASSPHRASE=""
        fi
    fi

    # 生成密钥
    if [ -n "$PASSPHRASE" ]; then
        ssh-keygen -t "$KEY_TYPE" $KEY_BITS -f "$KEY_PATH" -C "$KEY_NAME" -N "$PASSPHRASE" -q
    else
        ssh-keygen -t "$KEY_TYPE" $KEY_BITS -f "$KEY_PATH" -C "$KEY_NAME" -N "" -q
    fi

    # 设置权限
    chmod 600 "$KEY_PATH"
    chmod 644 "$KEY_PATH.pub"

    echo -e "${GREEN}密钥生成成功！${NC}"
    echo -e "  私钥: $KEY_PATH"
    echo -e "  公钥: $KEY_PATH.pub"
    STEP=2
}

# 配置服务器
setup_server() {
    echo -e "${BLUE}=== 配置服务器 ===${NC}"
    echo ""

    if [ $USE_WHIPTAIL -eq 1 ]; then
        if ! whiptail --title "配置服务器" --yesno "是否配置远程服务器？\n(将使用ssh-copy-id复制公钥)" 10 60; then
            SKIP_SERVER=1
            return 0
        fi

        whiptail --title "远程服务器信息" --inputbox "请输入远程服务器地址 (IP或域名)：" 10 60 "$REMOTE_HOST" 2>$TEMP_FILE || return 1
        REMOTE_HOST=$(cat $TEMP_FILE)

        whiptail --title "远程服务器端口" --inputbox "请输入SSH端口 (默认22)：" 10 60 "$REMOTE_PORT" 2>$TEMP_FILE || return 1
        REMOTE_PORT=$(cat $TEMP_FILE)

        whiptail --title "远程服务器用户" --inputbox "请输入远程服务器用户名：" 10 60 "$REMOTE_USER" 2>$TEMP_FILE || return 1
        REMOTE_USER=$(cat $TEMP_FILE)
    else
        read -p "是否配置远程服务器? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            SKIP_SERVER=1
            return 0
        fi

        read -p "远程服务器地址: " REMOTE_HOST
        read -p "SSH端口 [22]: " REMOTE_PORT
        REMOTE_PORT=${REMOTE_PORT:-22}
        read -p "远程用户名: " REMOTE_USER
    fi

    # 复制公钥
    echo -e "${BLUE}正在复制公钥到远程服务器...${NC}"
    if ssh-copy-id -i "$KEY_PATH.pub" -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST"; then
        echo -e "${GREEN}公钥复制成功！${NC}"
    else
        echo -e "${RED}公钥复制失败，请检查连接信息${NC}"
        return 1
    fi

    STEP=3
}

# 配置客户端
setup_client() {
    echo -e "${BLUE}=== 配置客户端 ===${NC}"
    echo ""

    if [ $USE_WHIPTAIL -eq 1 ]; then
        if ! whiptail --title "配置客户端" --yesno "是否配置SSH客户端 (~/.ssh/config)？\n(将添加Host配置)" 10 60; then
            SKIP_CLIENT=1
            return 0
        fi

        whiptail --title "Host别名" --inputbox "请输入Host别名 (用于连接)：" 10 60 "$HOST_ALIAS" 2>$TEMP_FILE || return 1
        HOST_ALIAS=$(cat $TEMP_FILE)

        if [ -z "$HOST_ALIAS" ]; then
            HOST_ALIAS="$REMOTE_HOST"
        fi
    else
        read -p "是否配置SSH客户端 (~/.ssh/config)? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            SKIP_CLIENT=1
            return 0
        fi

        read -p "Host别名 [默认: $REMOTE_HOST]: " HOST_ALIAS
        HOST_ALIAS=${HOST_ALIAS:-$REMOTE_HOST}
    fi

    # 备份现有配置
    if [ -f "$HOME/.ssh/config" ]; then
        cp "$HOME/.ssh/config" "$HOME/.ssh/config.backup.$(date +%Y%m%d%H%M%S)"
        echo -e "${GREEN}已备份现有配置到 ~/.ssh/config.backup.*${NC}"
    fi

    # 检查是否已存在相同Host
    if grep -q "^Host $HOST_ALIAS" "$HOME/.ssh/config" 2>/dev/null; then
        echo -e "${YELLOW}警告: Host '$HOST_ALIAS' 已存在于配置中${NC}"
        if [ $USE_WHIPTAIL -eq 1 ]; then
            whiptail --title "Host已存在" --yesno "Host '$HOST_ALIAS' 已存在，是否覆盖？" 10 60 || return 1
        else
            read -p "是否覆盖现有配置? [y/N]: " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || return 1
        fi
        # 删除现有配置（简单实现，实际应该更精确）
        sed -i "/^Host $HOST_ALIAS$/,/^$/d" "$HOME/.ssh/config" 2>/dev/null || true
    fi

    # 写入配置
    cat >> "$HOME/.ssh/config" << EOF

# Added by ssh-key-setup on $(date '+%Y-%m-%d %H:%M:%S')
Host $HOST_ALIAS
    HostName ${REMOTE_HOST:-localhost}
    User ${REMOTE_USER:-$USERNAME}
    Port ${REMOTE_PORT:-22}
    IdentityFile $KEY_PATH
EOF

    chmod 600 "$HOME/.ssh/config"
    echo -e "${GREEN}客户端配置已添加！${NC}"
    echo -e "  可以使用: ssh $HOST_ALIAS 连接"

    STEP=4
}

# 显示摘要
show_summary() {
    echo ""
    echo -e "${GREEN}=== 操作完成 ===${NC}"
    echo ""
    echo -e "密钥信息："
    echo -e "  名称: $KEY_NAME"
    echo -e "  路径: $KEY_PATH"
    echo -e "  类型: $KEY_TYPE"
    echo ""

    if [ $SKIP_SERVER -eq 0 ] && [ -n "$REMOTE_HOST" ]; then
        echo -e "服务器配置："
        echo -e "  地址: $REMOTE_HOST:$REMOTE_PORT"
        echo -e "  用户: $REMOTE_USER"
        echo ""
    fi

    if [ $SKIP_CLIENT -eq 0 ] && [ -n "$HOST_ALIAS" ]; then
        echo -e "客户端配置："
        echo -e "  别名: $HOST_ALIAS"
        echo -e "  连接: ssh $HOST_ALIAS"
        echo ""
    fi

    echo -e "公钥内容："
    cat "$KEY_PATH.pub"
    echo ""
}

# 清理函数
cleanup() {
    if [ $CANCELLED -eq 1 ]; then
        echo -e "${YELLOW}操作已取消${NC}"
        # 如果密钥已生成但后续步骤取消，询问是否保留密钥
        if [ -f "$KEY_PATH" ] && [ $STEP -le 2 ]; then
            if [ $USE_WHIPTAIL -eq 1 ]; then
                if whiptail --title "清理" --yesno "是否删除已生成的密钥？" 10 60; then
                    rm -f "$KEY_PATH" "$KEY_PATH.pub"
                    echo -e "${GREEN}已删除密钥文件${NC}"
                fi
            else
                read -p "是否删除已生成的密钥? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    rm -f "$KEY_PATH" "$KEY_PATH.pub"
                    echo -e "${GREEN}已删除密钥文件${NC}"
                fi
            fi
        fi
    fi
}

# 主流程
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}   SSH密钥生成与配置脚本${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""

    # 检查环境
    check_whiptail
    collect_info

    # 步骤1: 确认信息
    while true; do
        if [ $USE_WHIPTAIL -eq 1 ]; then
            whiptail_confirm
            result=$?
        else
            cli_confirm
            result=$?
        fi

        case $result in
            0) break ;;  # 确认
            1) continue ;;  # 继续循环（修改后）
            2) CANCELLED=1; cleanup; exit 0 ;;  # 取消
        esac
    done

    # 步骤2: 生成密钥
    while true; do
        if generate_key; then
            break
        else
            echo -e "${RED}密钥生成失败，请重试${NC}"
            if [ $USE_WHIPTAIL -eq 1 ]; then
                whiptail --title "重试" --yesno "是否重试生成密钥？" 10 60 || { CANCELLED=1; cleanup; exit 1; }
            else
                read -p "是否重试? [y/N]: " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] || { CANCELLED=1; cleanup; exit 1; }
            fi
        fi
    done

    # 步骤3: 配置服务器
    if setup_server; then
        :
    else
        echo -e "${YELLOW}跳过服务器配置${NC}"
        SKIP_SERVER=1
    fi

    # 步骤4: 配置客户端
    if [ $SKIP_SERVER -eq 0 ] || [ -n "$HOST_ALIAS" ]; then
        if setup_client; then
            :
        else
            echo -e "${YELLOW}跳过客户端配置${NC}"
            SKIP_CLIENT=1
        fi
    fi

    # 步骤5: 显示摘要
    show_summary

    echo -e "${GREEN}所有操作已完成！${NC}"
}

# 运行主函数
main "$@"
