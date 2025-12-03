#!/usr/bin/env bash
set -uo pipefail

# Multi 3x-ui Manager
# Author: ParsDigital
# Tested on: Ubuntu/Debian (root required)

########################
#  Script metadata     #
########################

SCRIPT_NAME="Multi 3x-ui Manager"
SCRIPT_VERSION="1.1"
YOUTUBE_URL="https://www.youtube.com/@ParsDigital/"
TELEGRAM_URL="https://t.me/+2S96GjBZJ1cxYzVk"

########################
#  Global variables    #
########################

BASE_DIR=""
COMPOSE_FILE=""
DOCKER_COMPOSE_CMD=""
SERVER_IP=""

########################
#  Helper functions    #
########################

color_green()  { printf "\e[32m%s\e[0m\n" "$*"; }
color_red()    { printf "\e[31m%s\e[0m\n" "$*"; }
color_yellow() { printf "\e[33m%s\e[0m\n" "$*"; }
color_cyan()   { printf "\e[36m%s\e[0m\n" "$*"; }
pause()        { read -rp "Press Enter to continue..." _; }

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    color_red "Please run this script as root (sudo -i && bash install.sh)"
    exit 1
  fi
}

detect_base_dir() {
  # If docker is installed via snap, we must use its confined data path
  if command -v snap >/dev/null 2>&1 && snap list docker >/dev/null 2>&1; then
    BASE_DIR="/var/snap/docker/common/3xui-multi"
  else
    BASE_DIR="/opt/3xui-multi"
  fi
  COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
}

detect_docker_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
  elif docker-compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
  else
    color_yellow "Docker Compose not found, attempting to install plugin (Debian/Ubuntu)..."
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update
      apt-get install -y docker-compose-plugin
      if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
      else
        color_red "Failed to install docker-compose plugin automatically."
        exit 1
      fi
    else
      color_red "Unsupported OS for automatic docker-compose installation."
      exit 1
    fi
  fi
}

install_docker_if_needed() {
  if command -v docker >/dev/null 2>&1; then
    color_green "Docker is already installed."
    return
  fi

  color_yellow "Docker not found. Installing Docker using get.docker.com..."
  if ! command -v curl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update
      apt-get install -y curl
    else
      color_red "curl is required to install Docker automatically."
      exit 1
    fi
  fi

  curl -fsSL https://get.docker.com | sh

  systemctl enable docker || true
  systemctl start docker || true

  if ! command -v docker >/dev/null 2>&1; then
    color_red "Docker installation failed."
    exit 1
  fi
  color_green "Docker installed successfully."
}

detect_server_ip() {
  # Try public IPv4 first
  local ip=""
  if command -v curl >/dev/null 2>&1; then
    ip=$(curl -4s https://ifconfig.me || curl -4s https://ipv4.icanhazip.com || true)
  fi
  if [[ -z "${ip}" ]]; then
    # Fallback: first IP from hostname -I
    if command -v hostname >/dev/null 2>&1; then
      ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
  fi
  if [[ -z "${ip}" ]]; then
    ip="YOUR_SERVER_IP"
  fi
  SERVER_IP="${ip}"
}

ensure_dirs() {
  mkdir -p "${BASE_DIR}"
  cd "${BASE_DIR}"
}

print_logo() {
  # Compact multi-color ASCII logo (better on small screens)
  local colors=(
    "\e[38;5;196m"
    "\e[38;5;202m"
    "\e[38;5;208m"
    "\e[38;5;214m"
    "\e[38;5;220m"
    "\e[38;5;46m"
    "\e[38;5;51m"
    "\e[38;5;27m"
  )
  local reset="\e[0m"
  local i=0

  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      printf "\n"
      continue
    fi
    local color="${colors[i % ${#colors[@]}]}"
    printf "%b%s%b\n" "$color" "$line" "$reset"
    ((i++))
  done << 'EOF'
   ___  ___                _ _   _   _____                _ 
  / _ \/   \   /\/\  _   _| | |_(_) |___ /_  __     _   _(_)
 / /_)/ /\ /  /    \| | | | | __| |   |_ \ \/ /____| | | | |
/ ___/ /_//  / /\/\ \ |_| | | |_| |  ___) >  <_____| |_| | |
\/  /___,'   \/    \/\__,_|_|\__|_| |____/_/\_\     \__,_|_|
                                                            
                                          
EOF
}

print_title_box() {
  local text="$1"
  local padding=2   # spaces left/right
  local inner_len=$(( ${#text} + padding * 2 ))
  local box_color="\e[38;5;51m"
  local reset="\e[0m"

  local top="╔"
  local bottom="╚"
  local i
  for (( i=0; i<inner_len; i++ )); do
    top+="═"
    bottom+="═"
  done
  top+="╗"
  bottom+="╝"

  local spaces
  spaces=$(printf '%*s' "$padding" "")
  local middle="║${spaces}${text}${spaces}║"

  echo -e "${box_color}${top}${reset}"
  echo -e "${box_color}${middle}${reset}"
  echo -e "${box_color}${bottom}${reset}"
}

print_header() {
  clear
  print_logo
  echo
  print_title_box "${SCRIPT_NAME}"
  echo
  echo -e " 🧩 Version   : \e[35m${SCRIPT_VERSION}\e[0m"
  echo -e " 🌐 Server IP : \e[36m${SERVER_IP}\e[0m"
  echo -e " ▶️ YouTube   : \e[34m${YOUTUBE_URL}\e[0m"
  echo -e " 💬 Telegram  : \e[34m${TELEGRAM_URL}\e[0m"
  echo "----------------------------------------"
  echo
}

########################
#  Core logic          #
########################

ask_int() {
  local prompt default value
  prompt="$1"
  default="$2"
  while true; do
    read -rp "${prompt} [default: ${default}]: " value
    value="${value:-$default}"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      echo "$value"
      return
    else
      color_red "Please enter a valid integer."
    fi
  done
}

port_range_overlap() {
  local s1="$1" e1="$2" s2="$3" e2="$4"
  # overlap if s1<=e2 AND s2<=e1
  if (( s1 <= e2 && s2 <= e1 )); then
    return 0
  else
    return 1
  fi
}

generate_compose_initial() {
  print_header
  color_green "=== Initial multi-3x-ui setup ==="
  echo

  local num_panels
  num_panels=$(ask_int "How many panels do you want to create?" "2")

  # Arrays to keep track for overlap checking
  declare -a PANEL_PORTS
  declare -a RANGE_STARTS
  declare -a RANGE_ENDS

  # Build compose file
  cat > "${COMPOSE_FILE}" <<EOF
version: "3.8"

services:
EOF

  for (( i=1; i<=num_panels; i++ )); do
    echo
    color_yellow "--- Panel #${i} configuration ---"

    # Default panel port: 2020 + (i-1)
    local default_panel_port=$((2020 + i - 1))
    local panel_port
    while true; do
      panel_port=$(ask_int "Panel #${i} web port (host)?" "${default_panel_port}")
      # check unique
      local conflict=0
      for p in "${PANEL_PORTS[@]:-}"; do
        if [[ "$panel_port" -eq "$p" ]]; then
          conflict=1
          break
        fi
      done
      if (( conflict == 1 )); then
        color_red "Port ${panel_port} already used by another panel. Choose another."
      else
        PANEL_PORTS+=("$panel_port")
        break
      fi
    done

    # Default range: 10000 + (i-1)*100 .. start+99
    local default_start=$((10000 + (i-1)*100))
    local default_end=$((default_start + 99))
    local range_start range_end

    while true; do
      range_start=$(ask_int "Inbound port range START for panel #${i}?" "${default_start}")
      range_end=$(ask_int "Inbound port range END for panel #${i}?" "${default_end}")
      if (( range_start >= range_end )); then
        color_red "Start must be less than end."
        continue
      fi

      # Check overlap with previous ranges
      local overlap=0
      local idx
      for idx in "${!RANGE_STARTS[@]}"; do
        if port_range_overlap "$range_start" "$range_end" "${RANGE_STARTS[$idx]}" "${RANGE_ENDS[$idx]}"; then
          overlap=1
          break
        fi
      done

      if (( overlap == 1 )); then
        color_red "Port range ${range_start}-${range_end} overlaps with an existing panel range."
      else
        RANGE_STARTS+=("$range_start")
        RANGE_ENDS+=("$range_end")
        break
      fi
    done

    # Create directories for this panel
    mkdir -p "xui${i}/db" "xui${i}/cert"

    # Append service to compose file
    cat >> "${COMPOSE_FILE}" <<EOF

  xui${i}:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: xui_panel_${i}
    restart: unless-stopped
    tty: true
    environment:
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "true"
    volumes:
      - ./xui${i}/db:/etc/x-ui
      - ./xui${i}/cert:/root/cert
    ports:
      - "${panel_port}:2053"
      - "${range_start}-${range_end}:${range_start}-${range_end}"
EOF

  done

  color_green
  color_green "docker-compose.yml generated at: ${COMPOSE_FILE}"
  echo
  color_green "Bringing up all panels with Docker..."
  ${DOCKER_COMPOSE_CMD} -f "${COMPOSE_FILE}" up -d
  color_green "Done. Use the following URLs:"
  for idx in "${!PANEL_PORTS[@]}"; do
    local n=$((idx+1))
    echo "  Panel #${n} => http://${SERVER_IP}:${PANEL_PORTS[$idx]}"
  done
  echo
  pause
}

get_existing_panels_count() {
  # Count services named xuiN in compose file
  if [[ ! -f "${COMPOSE_FILE}" ]]; then
    echo 0
    return
  fi
  local count
  count=$(grep -E '^[[:space:]]+xui[0-9]+:' "${COMPOSE_FILE}" | wc -l || true)
  echo "$count"
}

add_new_panel() {
  if [[ ! -f "${COMPOSE_FILE}" ]]; then
    color_red "docker-compose.yml not found. Run initial installation first."
    pause
    return
  fi

  local existing
  existing=$(get_existing_panels_count)
  local new_index=$((existing + 1))

  print_header
  color_green "=== Add new panel (Panel #${new_index}) ==="
  echo

  # Collect existing ports and ranges for validation
  declare -a PANEL_PORTS
  declare -a RANGE_STARTS
  declare -a RANGE_ENDS

  # ports
  while IFS= read -r line; do
    local host_port
    host_port=$(echo "$line" | sed -E 's/.*"([0-9]+):2053".*/\1/' || true)
    if [[ -n "$host_port" ]]; then
      PANEL_PORTS+=("$host_port")
    fi
  done < <(grep -E '"[0-9]+:2053"' "${COMPOSE_FILE}" || true)

  # ranges
  while IFS= read -r line; do
    local left
    left=$(echo "$line" | sed -E 's/.*"([0-9]+-[0-9]+):.*/\1/' || true)
    if [[ -n "$left" ]]; then
      local s e
      s=$(echo "$left" | cut -d- -f1)
      e=$(echo "$left" | cut -d- -f2)
      RANGE_STARTS+=("$s")
      RANGE_ENDS+=("$e")
    fi
  done < <(grep -E '"[0-9]+-[0-9]+:[0-9]+-[0-9]+"' "${COMPOSE_FILE}" || true)

  # Ask new panel port
  local default_panel_port=$((2020 + new_index - 1))
  local panel_port
  while true; do
    panel_port=$(ask_int "Panel #${new_index} web port (host)?" "${default_panel_port}")
    local conflict=0
    for p in "${PANEL_PORTS[@]:-}"; do
      if [[ "$panel_port" -eq "$p" ]]; then
        conflict=1
        break
      fi
    done
    if (( conflict == 1 )); then
      color_red "Port ${panel_port} already used by another panel. Choose another."
    else
      break
    fi
  done

  # Ask new range
  local default_start=$((10000 + (new_index-1)*100))
  local default_end=$((default_start + 99))
  local range_start range_end
  while true; do
    range_start=$(ask_int "Inbound port range START for panel #${new_index}?" "${default_start}")
    range_end=$(ask_int "Inbound port range END for panel #${new_index}?" "${default_end}")
    if (( range_start >= range_end )); then
      color_red "Start must be less than end."
      continue
    fi
    local overlap=0
    local idx
    for idx in "${!RANGE_STARTS[@]}"; do
      if port_range_overlap "$range_start" "$range_end" "${RANGE_STARTS[$idx]}" "${RANGE_ENDS[$idx]}"; then
        overlap=1
        break
      fi
    done
    if (( overlap == 1 )); then
      color_red "Port range ${range_start}-${range_end} overlaps with an existing panel range."
    else
      break
    fi
  done

  mkdir -p "xui${new_index}/db" "xui${new_index}/cert"

  cat >> "${COMPOSE_FILE}" <<EOF

  xui${new_index}:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: xui_panel_${new_index}
    restart: unless-stopped
    tty: true
    environment:
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "true"
    volumes:
      - ./xui${new_index}/db:/etc/x-ui
      - ./xui${new_index}/cert:/root/cert
    ports:
      - "${panel_port}:2053"
      - "${range_start}-${range_end}:${range_start}-${range_end}"
EOF

  color_green "New panel #${new_index} appended to docker-compose.yml"
  ${DOCKER_COMPOSE_CMD} -f "${COMPOSE_FILE}" up -d
  color_green "Panel #${new_index} is starting..."
  echo "URL: http://${SERVER_IP}:${panel_port}"
  pause
}

reset_panel() {
  if [[ ! -f "${COMPOSE_FILE}" ]]; then
    color_red "docker-compose.yml not found. Nothing to reset."
    pause
    return
  fi

  local existing
  existing=$(get_existing_panels_count)
  if (( existing == 0 )); then
    color_red "No panels found."
    pause
    return
  fi

  print_header
  color_green "=== Reset a panel (clear its DB and restart) ==="
  echo "Existing panels: ${existing}"
  local idx
  idx=$(ask_int "Which panel number do you want to reset? (1-${existing})" "1")
  if (( idx < 1 || idx > existing )); then
    color_red "Invalid panel number."
    pause
    return
  fi

  read -rp "Are you sure you want to RESET panel #${idx}? This will wipe its DB. [y/N]: " yn
  yn=${yn:-N}
  if [[ ! "$yn" =~ ^[Yy]$ ]]; then
    color_yellow "Aborted."
    pause
    return
  fi

  docker stop "xui_panel_${idx}" >/dev/null 2>&1 || true

  rm -rf "xui${idx}/db"/*
  color_green "DB for panel #${idx} wiped."

  ${DOCKER_COMPOSE_CMD} -f "${COMPOSE_FILE}" up -d
  color_green "Panel #${idx} restarted with fresh DB (default admin/admin)."
  pause
}

uninstall_all() {
  if [[ ! -d "${BASE_DIR}" ]]; then
    color_red "Base directory ${BASE_DIR} not found. Nothing to uninstall."
    pause
    return
  fi

  print_header
  color_red "=== WARNING: Full uninstall ==="
  echo "This will:"
  echo "  - Stop and remove all multi 3x-ui containers"
  echo "  - Remove docker-compose.yml and all xuiN data directories"
  echo

  read -rp "Are you sure you want to continue? [y/N]: " yn
  yn=${yn:-N}
  if [[ ! "$yn" =~ ^[Yy]$ ]]; then
    color_yellow "Aborted."
    pause
    return
  fi

  if [[ -f "${COMPOSE_FILE}" ]]; then
    ${DOCKER_COMPOSE_CMD} -f "${COMPOSE_FILE}" down || true
  fi

  rm -rf "${BASE_DIR}"

  color_green "All multi 3x-ui data and containers removed."
  pause
}

show_status() {
  print_header
  color_green "=== Docker containers ==="
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | sed '1!{/xui_panel_/!d}'
  echo
  if [[ -f "${COMPOSE_FILE}" ]]; then
    color_green "docker-compose.yml present at: ${COMPOSE_FILE}"
  else
    color_yellow "docker-compose.yml not found."
  fi
  echo
  pause
}

main_menu() {
  while true; do
    print_header

    local menu_color="\e[38;5;45m"
    local reset="\e[0m"
    echo -e "${menu_color}┌───────────────────── Menu ─────────────────────┐${reset}"
    echo -e "${menu_color}│  Use numbers to select an option              │${reset}"
    echo -e "${menu_color}└────────────────────────────────────────────────┘${reset}"
    echo

    echo -e " \e[38;5;45m1)\e[0m 🚀 \e[38;5;45mInitial install / Rebuild multi 3x-ui\e[0m"
    echo -e " \e[38;5;82m2)\e[0m ➕ \e[38;5;82mAdd new panel\e[0m"
    echo -e " \e[38;5;220m3)\e[0m ♻️ \e[38;5;220mReset a panel (wipe DB and restart)\e[0m"
    echo -e " \e[38;5;196m4)\e[0m 🗑️ \e[38;5;196mUninstall all panels (FULL REMOVE)\e[0m"
    echo -e " \e[38;5;39m5)\e[0m 📊 \e[38;5;39mShow status\e[0m"
    echo -e " \e[38;5;244m0)\e[0m ❌ \e[38;5;244mExit\e[0m"
    echo

    read -rp "Select an option: " choice
    case "$choice" in
      1) generate_compose_initial ;;
      2) add_new_panel ;;
      3) reset_panel ;;
      4) uninstall_all ;;
      5) show_status ;;
      0) exit 0 ;;
      *) color_red "Invalid choice."; sleep 1 ;;
    esac
  done
}

########################
#  Entry point         #
########################

require_root
install_docker_if_needed
detect_base_dir
ensure_dirs
detect_docker_compose_cmd
detect_server_ip
main_menu
