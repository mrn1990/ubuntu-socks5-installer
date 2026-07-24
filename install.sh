#!/usr/bin/env bash
set -Eeuo pipefail

CREDENTIALS_FILE="/root/socks5-credentials.txt"
INSTALL_MARKER="/etc/socks5-installer.user"
SOCKS_GROUP="socks5users"
DANTE_CONFIG="/etc/danted.conf"
TTY="/dev/tty"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { printf "${CYAN}%s${NC}\n" "$*"; }
success() { printf "${GREEN}%s${NC}\n" "$*"; }
warn()    { printf "${YELLOW}%s${NC}\n" "$*"; }
die()     { printf "${RED}ERROR: %s${NC}\n" "$*" >&2; exit 1; }

trap 'printf "\n${RED}Installation failed at line %s.${NC}\n" "$LINENO" >&2' ERR

[[ -r "$TTY" && -w "$TTY" ]] || die "An interactive terminal is required."
[[ "${EUID}" -eq 0 ]] || die "Run with sudo, for example: curl -fsSL <RAW_URL> | sudo bash"
[[ -r /etc/os-release ]] || die "Cannot detect the operating system."

# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "This installer supports Ubuntu only. Detected: ${PRETTY_NAME:-unknown}"

printf '\n'
printf '============================================================\n'
printf '        Interactive SOCKS5 Installer for Ubuntu\n'
printf '============================================================\n\n'

if [[ -f "$INSTALL_MARKER" || -f "$CREDENTIALS_FILE" ]]; then
    warn "A previous installation created by this installer was detected."
    read -r -p "Replace it? [y/N]: " replace_answer < "$TTY"
    if [[ ! "$replace_answer" =~ ^[Yy]$ ]]; then
        die "Installation cancelled."
    fi
fi

select_port() {
    local choice candidate

    while true; do
        printf '\nPort selection:\n'
        printf '  1) Choose a random free port\n'
        printf '  2) Enter a port manually\n'
        read -r -p "Select [1/2]: " choice < "$TTY"

        case "$choice" in
            1)
                for _ in {1..200}; do
                    candidate="$(shuf -i 20000-60000 -n 1)"
                    if ! ss -lntH 2>/dev/null |
                        awk '{print $4}' |
                        grep -Eq "[:.]${candidate}$"; then
                        SOCKS_PORT="$candidate"
                        return
                    fi
                done
                die "Could not find a free random TCP port."
                ;;
            2)
                while true; do
                    read -r -p "Enter TCP port (1024-65535): " candidate < "$TTY"

                    if [[ ! "$candidate" =~ ^[0-9]+$ ]] ||
                        (( candidate < 1024 || candidate > 65535 )); then
                        warn "Enter a number between 1024 and 65535."
                        continue
                    fi

                    if ss -lntH 2>/dev/null |
                        awk '{print $4}' |
                        grep -Eq "[:.]${candidate}$"; then
                        warn "Port ${candidate} is already in use."
                        continue
                    fi

                    SOCKS_PORT="$candidate"
                    return
                done
                ;;
            *)
                warn "Please select 1 or 2."
                ;;
        esac
    done
}

select_username() {
    local candidate

    while true; do
        read -r -p "Enter SOCKS5 username: " candidate < "$TTY"

        if [[ ! "$candidate" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
            warn "Use 1-32 lowercase characters: letters, numbers, underscore or hyphen; start with a letter/underscore."
            continue
        fi

        if id "$candidate" >/dev/null 2>&1; then
            warn "Linux user '${candidate}' already exists. Choose another username."
            continue
        fi

        SOCKS_USER="$candidate"
        return
    done
}

select_password() {
    local first second

    while true; do
        read -r -s -p "Enter SOCKS5 password: " first < "$TTY"
        printf '\n' > "$TTY"

        read -r -s -p "Confirm password: " second < "$TTY"
        printf '\n' > "$TTY"

        if [[ "$first" != "$second" ]]; then
            warn "Passwords do not match."
            continue
        fi

        SOCKS_PASSWORD="$first"
        return
    done
}

url_encode() {
    local LC_ALL=C
    local value="$1" encoded="" character index

    for (( index = 0; index < ${#value}; index++ )); do
        character="${value:index:1}"
        case "$character" in
            [A-Za-z0-9.~_-])
                encoded+="$character"
                ;;
            *)
                printf -v character '%%%02X' "'$character"
                encoded+="$character"
                ;;
        esac
    done

    printf '%s' "$encoded"
}

select_port
printf '\n'
select_username
select_password

info "[1/7] Installing required packages..."
export DEBIAN_FRONTEND=noninteractive

apt-get update -y

if ! apt-cache show dante-server >/dev/null 2>&1; then
    apt-get install -y software-properties-common
    add-apt-repository -y universe
    apt-get update -y
fi

apt-get install -y dante-server curl ca-certificates openssl

EXTERNAL_INTERFACE="$(ip -4 route show default | awk 'NR==1 {print $5}')"
[[ -n "$EXTERNAL_INTERFACE" ]] ||
    die "Could not detect the default network interface."

info "[2/7] Preparing the restricted SOCKS5 account..."

if ! getent group "$SOCKS_GROUP" >/dev/null; then
    groupadd --system "$SOCKS_GROUP"
fi

if [[ -f "$INSTALL_MARKER" ]]; then
    OLD_USER="$(cat "$INSTALL_MARKER" 2>/dev/null || true)"

    if [[ -n "$OLD_USER" ]] && id "$OLD_USER" >/dev/null 2>&1; then
        if id -nG "$OLD_USER" 2>/dev/null |
            tr ' ' '\n' |
            grep -qx "$SOCKS_GROUP"; then
            userdel "$OLD_USER" || true
        fi
    fi
fi

useradd \
    --no-create-home \
    --shell /usr/sbin/nologin \
    --gid "$SOCKS_GROUP" \
    "$SOCKS_USER"

printf '%s:%s\n' "$SOCKS_USER" "$SOCKS_PASSWORD" | chpasswd
printf '%s\n' "$SOCKS_USER" > "$INSTALL_MARKER"
chmod 600 "$INSTALL_MARKER"

info "[3/7] Writing Dante configuration..."

if [[ -f "$DANTE_CONFIG" ]]; then
    cp -a \
        "$DANTE_CONFIG" \
        "${DANTE_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"
fi

cat > "$DANTE_CONFIG" <<EOF_DANTE
logoutput: syslog

user.privileged: root
user.unprivileged: nobody

internal: 0.0.0.0 port = ${SOCKS_PORT}
external: ${EXTERNAL_INTERFACE}

clientmethod: none
socksmethod: username

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

# Prevent proxy access to loopback, private networks and metadata services.
socks block {
    from: 0.0.0.0/0 to: 127.0.0.0/8
    command: connect
    log: error
}

socks block {
    from: 0.0.0.0/0 to: 10.0.0.0/8
    command: connect
    log: error
}

socks block {
    from: 0.0.0.0/0 to: 172.16.0.0/12
    command: connect
    log: error
}

socks block {
    from: 0.0.0.0/0 to: 192.168.0.0/16
    command: connect
    log: error
}

socks block {
    from: 0.0.0.0/0 to: 169.254.0.0/16
    command: connect
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: connect
    socksmethod: username
    group: ${SOCKS_GROUP}
    log: connect disconnect error
}
EOF_DANTE

chmod 600 "$DANTE_CONFIG"

info "[4/7] Enabling and starting Dante..."

systemctl enable danted >/dev/null
systemctl restart danted
sleep 2

if ! systemctl is-active --quiet danted; then
    journalctl -u danted -n 80 --no-pager >&2 || true
    die "Dante did not start."
fi

if ! ss -lntH "sport = :${SOCKS_PORT}" 2>/dev/null | grep -q LISTEN; then
    journalctl -u danted -n 80 --no-pager >&2 || true
    die "Dante is running but port ${SOCKS_PORT} is not listening."
fi

info "[5/7] Configuring the local firewall..."

FIREWALL_MESSAGE="UFW is inactive or unavailable; no UFW rule was changed."

if command -v ufw >/dev/null 2>&1 &&
    ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow "${SOCKS_PORT}/tcp" comment 'SOCKS5 Dante' >/dev/null
    FIREWALL_MESSAGE="UFW allowed incoming TCP port ${SOCKS_PORT}."
fi

info "[6/7] Detecting the server public IP..."

PUBLIC_IP="$(
    curl -4fsS \
        --max-time 10 \
        https://api.ipify.org 2>/dev/null || true
)"

if [[ ! "$PUBLIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi

if [[ -z "$PUBLIC_IP" ]]; then
    read -r \
        -p "Public IP could not be detected. Enter server public IP/domain: " \
        PUBLIC_IP < "$TTY"
fi

ENCODED_SOCKS_USER="$(url_encode "$SOCKS_USER")"
ENCODED_SOCKS_PASSWORD="$(url_encode "$SOCKS_PASSWORD")"
SOCKS5_URL="socks5://${ENCODED_SOCKS_USER}:${ENCODED_SOCKS_PASSWORD}@${PUBLIC_IP}:${SOCKS_PORT}"
SOCKS5H_URL="socks5h://${ENCODED_SOCKS_USER}:${ENCODED_SOCKS_PASSWORD}@${PUBLIC_IP}:${SOCKS_PORT}"

cat > "$CREDENTIALS_FILE" <<EOF_CREDS
SOCKS_HOST=${PUBLIC_IP}
SOCKS_PORT=${SOCKS_PORT}
SOCKS_USER=${SOCKS_USER}
SOCKS_PASSWORD=${SOCKS_PASSWORD}
SOCKS5_URL=${SOCKS5_URL}
SOCKS5H_URL=${SOCKS5H_URL}
EOF_CREDS

chmod 600 "$CREDENTIALS_FILE"

info "[7/7] Installation completed."

printf '\n'
printf '============================================================\n'
printf '             SOCKS5 CONNECTION INFORMATION\n'
printf '============================================================\n'
printf 'Server   : %s\n' "$PUBLIC_IP"
printf 'Port     : %s\n' "$SOCKS_PORT"
printf 'Username : %s\n' "$SOCKS_USER"
printf 'Password : %s\n' "$SOCKS_PASSWORD"
printf '\nSOCKS5 URL:\n%s\n' "$SOCKS5_URL"
printf '\nSOCKS5 URL with remote DNS:\n%s\n' "$SOCKS5H_URL"
printf '\nTest from another computer:\n'

printf "curl --proxy '%s' https://api.ipify.org\n" "$SOCKS5H_URL"

printf '\n%s\n' "$FIREWALL_MESSAGE"
printf 'Credentials file: %s\n' "$CREDENTIALS_FILE"
printf 'Service status  : systemctl status danted --no-pager\n'
printf 'View credentials: sudo cat %s\n' "$CREDENTIALS_FILE"
printf '============================================================\n'

warn "SOCKS5 username/password authentication is not encrypted. Use only on networks you trust, or place it behind an encrypted tunnel/VPN."
warn "If your VPS provider has a cloud firewall, open TCP port ${SOCKS_PORT} there as well."
