#!/bin/bash

# 用户创建脚本（交互式引导）
# 功能：创建支持 SSH/FTP/SFTP 访问的新用户
# 端口: SSH=2345, FTP/SFTP=8021

set +e
trap 'echo -e "\n${YELLOW}\n已取消${NC}"; exit 0' INT TERM

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
cat <<'EOF'
┌─────────────────────────────────────────────────────┐
│           用户创建向导 - SSH/FTP/SFTP               │
│           端口: SSH=2345, FTP/SFTP=8021              │
└─────────────────────────────────────────────────────┘

EOF

echo -e "${CYAN}按 Ctrl+C 可随时撤回，输入 b 返回上一步${NC}"
echo ""

STEP=1

step1_username() {
    echo -e "${BLUE}步骤 1/5: 设置用户名${NC}"
    echo -e "${YELLOW}────────────────────────────────────────────${NC}"
    read -p "请输入用户名: " USERNAME
    
    if [[ "$USERNAME" == "b" ]]; then
        echo -e "${YELLOW}已是第一步${NC}"
        return
    fi
    
    if [[ -z "$USERNAME" ]]; then
        echo -e "${RED}用户名不能为空${NC}"
        step1_username
        return
    fi
    
    if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
        echo -e "${RED}格式无效（仅小写字母、数字、下划线、连字符）${NC}"
        step1_username
        return
    fi
    
    if id "$USERNAME" &>/dev/null; then
        echo -e "${YELLOW}用户已存在，确认覆盖？[y/N]: ${NC}"
        read -n1 -r REPLY
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            step1_username
            return
        fi
    fi
    STEP=2
}

step2_pubkey() {
    echo -e "${BLUE}步骤 2/5: SSH 公钥（可选）${NC}"
    echo -e "${YELLOW}────────────────────────────────────────────${NC}"
    echo "留空跳过，后续可手动添加"
    read -p "请粘贴公钥: " USER_PUBKEY
    
    if [[ "$USER_PUBKEY" == "b" ]]; then
        STEP=1
        return
    fi
    
    if [[ -n "$USER_PUBKEY" ]]; then
        if [[ "$USER_PUBKEY" =~ ^(ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2) ]]; then
            echo -e "${GREEN}格式验证通过${NC}"
        else
            echo -e "${YELLOW}格式不识别，仍保存？[y/N]: ${NC}"
            read -n1 -r REPLY
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                USER_PUBKEY=""
            fi
        fi
    fi
    STEP=3
}

step3_ssh_port() {
    echo -e "${BLUE}步骤 3/5: SSH 端口配置${NC}"
    echo -e "${YELLOW}────────────────────────────────────────────${NC}"
    read -p "SSH 端口 [默认 2345]: " SSH_PORT
    SSH_PORT=${SSH_PORT:-2345}
    
    if [[ "$SSH_PORT" == "b" ]]; then
        STEP=2
        return
    fi
    
    if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [[ $SSH_PORT -lt 1 ]] || [[ $SSH_PORT -gt 65535 ]]; then
        echo -e "${RED}端口无效${NC}"
        step3_ssh_port
        return
    fi
    STEP=4
}

step4_ftp_port() {
    echo -e "${BLUE}步骤 4/5: FTP/SFTP 端口配置${NC}"
    echo -e "${YELLOW}────────────────────────────────────────────${NC}"
    read -p "FTP 端口 [默认 8021]: " SFTP_PORT
    SFTP_PORT=${SFTP_PORT:-8021}
    
    if [[ "$SFTP_PORT" == "b" ]]; then
        STEP=3
        return
    fi
    
    if ! [[ "$SFTP_PORT" =~ ^[0-9]+$ ]] || [[ $SFTP_PORT -lt 1 ]] || [[ $SFTP_PORT -gt 65535 ]]; then
        echo -e "${RED}端口无效${NC}"
        step4_ftp_port
        return
    fi
    STEP=5
}

step5_confirm() {
    echo -e "${BLUE}步骤 5/5: 确认配置${NC}"
    echo -e "${YELLOW}────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${CYAN}配置摘要:${NC}"
    echo "  用户名:    $USERNAME"
    echo "  SSH 端口:  $SSH_PORT"
    echo "  FTP 端口: $SFTP_PORT"
    echo -e "  公钥:     ${USER_PUBKEY:-(未设置)}"
    echo ""
    
    echo -e "${YELLOW}确认执行？[Y/n]: ${NC}"
    read -n1 -r REPLY
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}已取消${NC}"
        exit 0
    fi
    STEP=6
}

do_create() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 需要 root 权限${NC}" >&2
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}开始执行...${NC}"
    echo ""
    
    # 1. 创建用户
    echo -e "${BLUE}[1/5] 创建用户...${NC}"
    if id "$USERNAME" &>/dev/null; then
        echo -e "${YELLOW}  用户已存在${NC}"
    else
        useradd -m -s /sbin/nologin "$USERNAME" 2>/dev/null || useradd -m -s /usr/sbin/nologin "$USERNAME"
        echo -e "${GREEN}  用户已创建${NC}"
    fi
    
    # 2. 配置公钥
    echo -e "${BLUE}[2/5] 配置 SSH 公钥...${NC}"
    if [[ -n "$USER_PUBKEY" ]]; then
        USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
        mkdir -p "$USER_HOME/.ssh"
        chmod 700 "$USER_HOME/.ssh"
        echo "$USER_PUBKEY" > "$USER_HOME/.ssh/authorized_keys"
        chmod 600 "$USER_HOME/.ssh/authorized_keys"
        chown "$USERNAME:$USERNAME" "$USER_HOME/.ssh/authorized_keys"
        echo -e "${GREEN}  公钥已配置${NC}"
    else
        echo -e "${YELLOW}  跳过（未设置）${NC}"
    fi
    
    # 3. SSH 配置
    echo -e "${BLUE}[3/5] 配置 SSH 服务...${NC}"
    SSHD_PORT_CONF="/etc/ssh/sshd_config.d/custom.conf"
    mkdir -p /etc/ssh/sshd_config.d
    if [[ ! -f "$SSHD_PORT_CONF" ]] || ! grep -q "Port $SSH_PORT" "$SSHD_PORT_CONF"; then
        cat > "$SSHD_PORT_CONF" <<EOF
Port $SSH_PORT
ListenAddress 0.0.0.0
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
Subsystem sftp internal-sftp
EOF
    fi
    if systemctl is-active sshd &>/dev/null; then
        (systemctl reload sshd 2>/dev/null || sshd -t && systemctl reload ssh) 2>/dev/null || true
    fi
    echo -e "${GREEN}  SSH 端口 $SSH_PORT 已配置${NC}"
    
    # 4. vsftpd
    echo -e "${BLUE}[4/5] 配置 FTP 服务...${NC}"
    if ! command -v vsftpd &>/dev/null; then
        apt-get update -qq 2>/dev/null
        apt-get install -y -qq vsftpd 2>/dev/null
    fi
    
    VSFTPD_VCONF="/etc/vsftpd.custom.conf"
    cat > "$VSFTPD_VCONF" <<EOF
listen=$SFTP_PORT
listen_address=0.0.0.0
pasv_enable=YES
pasv_min_port=$((SFTP_PORT + 1000))
pasv_max_port=$((SFTP_PORT + 1010))
pasv_address=127.0.0.1
allow_writeable_chroot=YES
chroot_local_user=YES
secure_chroot_dir=/var/run/vsftpd/empty
local_enable=YES
local_umask=022
write_enable=YES
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
connect_from_port_20=NO
background=YES
listen_mode=standalone
EOF
    mkdir -p /var/run/vsftpd/empty
    pkill vsftpd 2>/dev/null || true
    sleep 0.5
    vsftpd "$VSFTPD_VCONF" &
    echo -e "${GREEN}  FTP 端口 $SFTP_PORT 已配置${NC}"
    
    # 5. 完成
    echo ""
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}        用户创建完成${NC}"
    echo -e "${GREEN}======================================${NC}"
    echo ""
    echo -e "${CYAN}连接信息:${NC}"
    echo "  SSH:   ssh -p $SSH_PORT $USERNAME@<服务器IP>"
    echo "  SFTP: sftp -P $SFTP_PORT $USERNAME@<服务器IP>"
    echo "  FTP:  ftp -p $SFTP_PORT <服务器IP>"
    echo ""
    echo -e "${YELLOW}注意: FTP 需设置密码或使用公钥认证${NC}"
}

run() {
    while [[ $STEP -lt 6 ]]; do
        case $STEP in
            1) step1_username ;;
            2) step2_pubkey ;;
            3) step3_ssh_port ;;
            4) step4_ftp_port ;;
            5) step5_confirm ;;
        esac
    done
    do_create
}

run