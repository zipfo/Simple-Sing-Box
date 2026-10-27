#!/bin/bash

version="1.6.0"

textcolor='\033[1;36m'
red='\033[1;31m'
grey='\033[1;30m'
clear='\033[0m'

check_root() {
    if [[ $EUID -ne 0 ]]
    then
        echo ""
        echo -e "${red}Error: this command should be run as root, use \"sudo -i\" command first${clear}"
        echo ""
        exit 1
    fi
}

check_config_json() {
    if [[ ! -s /etc/sing-box/config.json ]] || ! jq empty /etc/sing-box/config.json &> /dev/null
    then
        echo ""
        echo -e "${red}Error: /etc/sing-box/config.json is corrupted, corrections needed${clear}"
        echo ""
        exit 1
    fi
}

banner() {
    echo ""
    echo "╔══╗ ╔══╗ ╦══╗"
    echo "║    ║    ║  ║"
    echo "╚══╗ ╚══╗ ╠══╣"
    echo "   ║    ║ ║  ║"
    echo "╚══╝ ╚══╝ ╩══╝ by zipfo"
    echo "      (based on original SSB by A-Zuro)"
    echo -e "             ${grey}v${version}${clear}"
}

templates() {
    wget -q -O /var/www/${subspath}/template.json.1 https://raw.githubusercontent.com/zipfo/Simple-Sing-Box/main/Config-Templates/client.json

    if [[ $? -eq 0 ]]
    then
        outbound_num=$(jq '[.outbounds[].tag] | index("proxy")' /var/www/${subspath}/template.json.1)

        if [[ $(jq -r '.inbounds[] | select(.tag == "trojan-in") | .transport.type' /etc/sing-box/config.json) == "ws" ]]
        then
            mv -f /var/www/${subspath}/template.json.1 /var/www/${subspath}/template.json
        elif [[ $(jq -r '.inbounds[] | select(.tag == "trojan-in") | .transport.type' /etc/sing-box/config.json) == "httpupgrade" ]]
        then
            echo "$(jq ".outbounds[${outbound_num}].transport.type = \"httpupgrade\"" /var/www/${subspath}/template.json.1)" > /var/www/${subspath}/template.json
            rm -f /var/www/${subspath}/template.json.1
        else
            echo "$(jq "del(.outbounds[${outbound_num}].transport.type, .outbounds[${outbound_num}].transport.path)" /var/www/${subspath}/template.json.1)" > /var/www/${subspath}/template.json
            rm -f /var/www/${subspath}/template.json.1
        fi
    fi

    if [[ ! -f /var/www/${subspath}/template-loc.json ]] && [[ -s /var/www/${subspath}/template.json ]] && jq empty /var/www/${subspath}/template.json &> /dev/null
    then
        cp /var/www/${subspath}/template.json /var/www/${subspath}/template-loc.json
    fi
}

get_ip() {
    server_ip=$(curl -s https://cloudflare.com/cdn-cgi/trace | grep -E "^ip=" | cut -d "=" -f 2)
    [[ ! $server_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && server_ip=$(curl -s ipinfo.io/ip)
    [[ ! $server_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && server_ip=$(curl -s 2ip.io)
}


load_ssb_config() {
    if [[ -f /etc/secret-sing-box/config ]]
    then
        source /etc/secret-sing-box/config
    else
        server_location="ru"
        warp_option="1"
        warp_mode="1"
        chain_role="end"
        middle_mode=""
        warp_installed_by_script="true"
        next_server_link=""
    fi
}

get_data() {
    # Check sing-box version compatibility (1.12+ required for new DNS format)
    sb_version=$(sing-box version 2>/dev/null | grep "^sing-box version" | awk '{print $3}')
    if [[ -n $sb_version ]]
    then
        sb_major=$(echo "$sb_version" | cut -d '.' -f 1)
        sb_minor=$(echo "$sb_version" | cut -d '.' -f 2)
        if [[ $sb_major -lt 1 ]] || { [[ $sb_major -eq 1 ]] && [[ $sb_minor -lt 12 ]]; }
        then
            echo ""
            echo -e "${red}Error: sing-box $sb_version is not supported. Version 1.12.0+ is required.${clear}"
            echo -e "${red}Update sing-box: apt-mark unhold sing-box && apt update && apt install sing-box${clear}"
            echo ""
            exit 1
        fi
    fi

    load_ssb_config
    if [[ -f /etc/haproxy/auth.lua ]]
    then
        domain=$(grep "/etc/haproxy/certs/" /etc/haproxy/haproxy.cfg | head -n 1 | cut -d "/" -f 5)
        domain=${domain%".pem"*}
    else
        domain=$(grep "ssl_certificate" /etc/nginx/nginx.conf | head -n 1 | cut -d "/" -f 5)
        trojanpath=$(jq -r '.inbounds[] | select(.tag == "trojan-in") | .transport.path' /etc/sing-box/config.json | cut -d "/" -f 2)
        vlesspath=$(jq -r '.inbounds[] | select(.tag == "vless-in") | .transport.path' /etc/sing-box/config.json | cut -d "/" -f 2)
    fi

    subspath=$(grep "location ~ ^/" /etc/nginx/nginx.conf | head -n 1 | cut -d "/" -f 2 | cut -d " " -f 1)
    rulesetpath=$(grep "alias /var/www/" /etc/nginx/nginx.conf | head -n 1 | cut -d "/" -f 4)

    get_ip
    templates

    temprulesetpath=$(jq -r '.route.rule_set[-1].url' /var/www/${subspath}/template.json 2> /dev/null | cut -d "/" -f 4)
    tempdomain=$(jq -r '.outbounds[] | select(.tag == "proxy") | .server' /var/www/${subspath}/template.json 2> /dev/null)
    tempip=$(jq -r '.route.rules[] | select(has("ip_cidr")) | .ip_cidr[0]' /var/www/${subspath}/template.json 2> /dev/null)

    language="en"
    grep -q 'html lang="ru"' /var/www/${subspath}/sub.html &> /dev/null && language="ru"
}

check_github_template() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: не удалось загрузить данные с GitHub, попробуйте позже${clear}"
    check_message[1_en]="${red}Error: failed to download data from GitHub, try again later${clear}"

    if [[ ! -s /var/www/${subspath}/template.json ]] || ! jq empty /var/www/${subspath}/template.json &> /dev/null
    then
        echo -e "${check_message[1_$language]}"
        echo ""
        main_menu
    fi

    return 0
}

check_local_template() {
    declare -A -g general_message=()
    general_message[1_ru]="${red}Ошибка: структура template-loc.json нарушена, требуются исправления${clear}"
    general_message[2_ru]="${textcolor}[?]${clear} Введите ${textcolor}reset${clear}, чтобы сбросить шаблон до исходной версии, или введите ${textcolor}x${clear}, чтобы выйти:"
    general_message[3_ru]="Шаблон сброшен до исходной версии"
    general_message[1_en]="${red}Error: template-loc.json is corrupted, corrections needed${clear}"
    general_message[2_en]="${textcolor}[?]${clear} Enter ${textcolor}reset${clear} to reset the template to default version or enter ${textcolor}x${clear} to exit:"
    general_message[3_en]="The template has been reset to its default version"

    if [[ ! -s /var/www/${subspath}/template-loc.json ]] || ! jq empty /var/www/${subspath}/template-loc.json &> /dev/null || [[ $(jq 'any(.inbounds[]; .tag == "tun-in")' /var/www/${subspath}/template-loc.json) != "true" ]] || [[ $(jq 'any(.outbounds[]; .tag == "proxy")' /var/www/${subspath}/template-loc.json) != "true" ]]
    then
        echo -e "${general_message[1_$language]}"
        echo ""
        echo -e "${general_message[2_$language]}"
        read -r reset_temp
        [[ -n $reset_temp ]] && echo ""

        if [[ "$reset_temp" == "reset" ]]
        then
            check_github_template
            cp -f /var/www/${subspath}/template.json /var/www/${subspath}/template-loc.json
            echo "${general_message[3_$language]}"
            echo ""
        fi

        main_menu
    fi
}

### OPTION 1 - USER LIST & MANAGEMENT ###

show_users() {
    user_list_menu
}

### OPTION 2 - ADD USERS ###

exit_username() {
    if [[ ${username,,} =~ ^(x|х)$ ]]
    then
        username=""
        main_menu
    fi
}

check_username_add() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: имя пользователя должно содержать только английские буквы, цифры, символы _ и -${clear}"
    check_message[2_ru]="${red}Ошибка: пользователь с таким именем уже существует${clear}"
    check_message[3_ru]="${textcolor}[?]${clear} Введите имя нового пользователя или введите ${textcolor}x${clear}, чтобы закончить:"
    check_message[1_en]="${red}Error: the username should contain only letters, numbers, _ and - symbols${clear}"
    check_message[2_en]="${red}Error: this user already exists${clear}"
    check_message[3_en]="${textcolor}[?]${clear} Enter the name of the new user or enter ${textcolor}x${clear} to exit:"

    while ([[ ! $username =~ ^[a-zA-Z0-9_-]+$ ]] || [[ -f /var/www/${subspath}/${username}-TRJ-CLIENT.json ]] || [[ $(jq "any(.inbounds[].users[]; .name == \"${username}\")" /etc/sing-box/config.json) != "false" ]]) && [[ -n $username ]]
    do
        if [[ ! $username =~ ^[a-zA-Z0-9_-]+$ ]]
        then
            echo -e "${check_message[1_$language]}"
            echo ""
        else
            echo -e "${check_message[2_$language]}"
            echo -e "${red}https://${domain}/${subspath}/${username}-TRJ-CLIENT.json${clear}"
            [[ ! -f /etc/haproxy/auth.lua ]] && echo -e "${red}https://${domain}/${subspath}/${username}-VLESS-CLIENT.json${clear}"
            echo ""
        fi
        echo -e "${check_message[3_$language]}"
        read -r username
        [[ -n $username ]] && echo ""
        exit_username
    done
}

check_trjpass() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: пароль Trojan не должен содержать кавычки \"${clear}"
    check_message[2_ru]="${red}Ошибка: этот пароль уже закреплён за другим пользователем${clear}"
    check_message[3_ru]="${textcolor}[?]${clear} Введите пароль для Trojan или оставьте пустым для генерации случайного пароля:"
    check_message[1_en]="${red}Error: Trojan password should not contain quotes \"${clear}"
    check_message[2_en]="${red}Error: this password is already assigned to another user${clear}"
    check_message[3_en]="${textcolor}[?]${clear} Enter the password for Trojan or leave this empty to generate a random password:"

    while ([[ $trjpass =~ '"' ]] || [[ $(jq "any(.inbounds[].users[]; .password == \"${trjpass}\")" /etc/sing-box/config.json) != "false" ]]) && [[ -n $trjpass ]]
    do
        if [[ $trjpass =~ '"' ]]
        then
            echo -e "${check_message[1_$language]}"
        else
            echo -e "${check_message[2_$language]}"
        fi
        echo ""
        echo -e "${check_message[3_$language]}"
        read -r trjpass
        [[ -n $trjpass ]] && echo ""
    done
}

check_uuid() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: введённое значение не является UUID${clear}"
    check_message[2_ru]="${red}Ошибка: этот UUID уже закреплён за другим пользователем${clear}"
    check_message[3_ru]="${textcolor}[?]${clear} Введите UUID для VLESS или оставьте пустым для генерации случайного UUID:"
    check_message[1_en]="${red}Error: this is not an UUID${clear}"
    check_message[2_en]="${red}Error: this UUID is already assigned to another user${clear}"
    check_message[3_en]="${textcolor}[?]${clear} Enter the UUID for VLESS or leave this empty to generate a random UUID:"

    while ([[ ! $uuid =~ ^\{?[A-F0-9a-f]{8}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{12}\}?$ ]] || [[ $(jq "any(.inbounds[].users[]; .uuid == \"${uuid}\")" /etc/sing-box/config.json) != "false" ]]) && [[ -n $uuid ]]
    do
        if [[ ! $uuid =~ ^\{?[A-F0-9a-f]{8}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{12}\}?$ ]]
        then
            echo -e "${check_message[1_$language]}"
        else
            echo -e "${check_message[2_$language]}"
        fi
        echo ""
        echo -e "${check_message[3_$language]}"
        read -r uuid
        [[ -n $uuid ]] && echo ""
    done
}

enter_user_data_add() {
    declare -A -g input_message=()
    input_message[1_ru]="${textcolor}[?]${clear} Введите имя нового пользователя или введите ${textcolor}x${clear}, чтобы закончить:"
    input_message[2_ru]="${textcolor}[?]${clear} Введите пароль для Trojan или оставьте пустым для генерации случайного пароля:"
    input_message[3_ru]="${textcolor}[?]${clear} Введите UUID для VLESS или оставьте пустым для генерации случайного UUID:"
    input_message[1_en]="${textcolor}[?]${clear} Enter the name of the new user or enter ${textcolor}x${clear} to exit:"
    input_message[2_en]="${textcolor}[?]${clear} Enter the password for Trojan or leave this empty to generate a random password:"
    input_message[3_en]="${textcolor}[?]${clear} Enter the UUID for VLESS or leave this empty to generate a random UUID:"

    echo -e "${input_message[1_$language]}"
    read -r username
    [[ -n $username ]] && echo ""
    exit_username
    check_username_add
    echo -e "${input_message[2_$language]}"
    read -r trjpass
    [[ -n $trjpass ]] && echo ""
    check_trjpass
    if [[ ! -f /etc/haproxy/auth.lua ]]
    then
        echo -e "${input_message[3_$language]}"
        read -r uuid
        [[ -n $uuid ]] && echo ""
        check_uuid
    fi
}

generate_pass() {
    [[ -z $username ]] && username=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 10)
    [[ -z $trjpass ]] && trjpass=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 30)
    [[ -z $uuid ]] && [[ ! -f /etc/haproxy/auth.lua ]] && uuid=$(cat /proc/sys/kernel/random/uuid)
}

add_to_server_conf() {
    for inbound_tag in 'trojan-in' 'vless-in'
    do
        [[ "$inbound_tag" == "vless-in" ]] && [[ -f /etc/haproxy/auth.lua ]] && break
        inbound_num=$(jq "[.inbounds[].tag] | index(\"${inbound_tag}\")" /etc/sing-box/config.json)
        user_cred="{\"name\":\"${username}\",\"password\":\"${trjpass}\"}"
        [[ "$inbound_tag" == "vless-in" ]] && user_cred="{\"name\":\"${username}\",\"uuid\":\"${uuid}\"}"
        echo "$(jq ".inbounds[${inbound_num}].users += [${user_cred}]" /etc/sing-box/config.json)" > /etc/sing-box/config.json
    done

    mkdir -p /etc/secret-sing-box
    touch /etc/secret-sing-box/user-routes
    if ! grep -q "^${username}:" /etc/secret-sing-box/user-routes 2>/dev/null; then
        echo "${username}:direct:default" >> /etc/secret-sing-box/user-routes
    fi
    apply_user_routing
}

add_to_client_conf() {
    declare -A -g info_message=()
    info_message[1_ru]="Пользователь ${textcolor}${username}${clear} добавлен:"
    info_message[1_en]="Added user ${textcolor}${username}${clear}:"

    cp -f /var/www/${subspath}/template.json /var/www/${subspath}/${username}-TRJ-CLIENT.json
    sed -i -e "s/${tempdomain}/${domain}/g" -e "s/${temprulesetpath}/${rulesetpath}/g" /var/www/${subspath}/${username}-TRJ-CLIENT.json
    [[ -n $tempip ]] && sed -i -e "s/${tempip}/${server_ip}/g" /var/www/${subspath}/${username}-TRJ-CLIENT.json
    outbound_num=$(jq '[.outbounds[].tag] | index("proxy")' /var/www/${subspath}/${username}-TRJ-CLIENT.json)

    if [[ -f /etc/haproxy/auth.lua ]]
    then
        echo "$(jq ".outbounds[${outbound_num}].password = \"${trjpass}\"" /var/www/${subspath}/${username}-TRJ-CLIENT.json)" > /var/www/${subspath}/${username}-TRJ-CLIENT.json
    else
        echo "$(jq ".outbounds[${outbound_num}].password = \"${trjpass}\" | .outbounds[${outbound_num}].transport.path = \"/${trojanpath}\"" /var/www/${subspath}/${username}-TRJ-CLIENT.json)" > /var/www/${subspath}/${username}-TRJ-CLIENT.json
        echo "$(jq ".outbounds[${outbound_num}].type = \"vless\" | .outbounds[${outbound_num}] |= with_entries(.key |= if . == \"password\" then \"uuid\" else . end) | .outbounds[${outbound_num}].uuid = \"${uuid}\" | .outbounds[${outbound_num}].transport.path = \"/${vlesspath}\"" /var/www/${subspath}/${username}-TRJ-CLIENT.json)" > /var/www/${subspath}/${username}-VLESS-CLIENT.json
    fi

    echo -e "${info_message[1_$language]}"
    echo "https://${domain}/${subspath}/${username}-TRJ-CLIENT.json"
    [[ ! -f /etc/haproxy/auth.lua ]] && echo "https://${domain}/${subspath}/${username}-VLESS-CLIENT.json"
    echo ""
}

add_to_auth_lua() {
    if [[ -f /etc/haproxy/auth.lua ]]
    then
        pass_hash=$(echo -n "${trjpass}" | openssl dgst -sha224 | sed 's/.* //')
        sed -i "2i \ \ \ \ [\"${pass_hash}\"] = true,    -- User '${username}'" /etc/haproxy/auth.lua
        systemctl reload haproxy.service
    fi
}

add_users() {
    check_github_template

    while [[ ! ${username,,} =~ ^(x|х)$ ]]
    do
        enter_user_data_add
        generate_pass
        add_to_auth_lua
        add_to_server_conf
        add_to_client_conf
    done
}

### OPTION 3 - DELETE USERS ###

check_username_del() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: пользователь с таким именем не существует${clear}"
    check_message[2_ru]="${textcolor}[?]${clear} Введите имя пользователя или введите ${textcolor}x${clear}, чтобы закончить:"
    check_message[1_en]="${red}Error: a user with this name does not exist${clear}"
    check_message[2_en]="${textcolor}[?]${clear} Enter the name of the user or enter ${textcolor}x${clear} to exit:"

    while [[ -z $username ]] || [[ $(jq "any(.inbounds[].users[]; .name == \"${username}\")" /etc/sing-box/config.json) != "true" ]]
    do
        if [[ -n $username ]]
        then
            echo -e "${check_message[1_$language]}"
            echo ""
        fi
        echo -e "${check_message[2_$language]}"
        read -r username
        [[ -n $username ]] && echo ""
        exit_username
    done
}

enter_user_data_del() {
    declare -A -g input_message=()
    input_message[1_ru]="${textcolor}[?]${clear} Введите имя пользователя или введите ${textcolor}x${clear}, чтобы закончить:"
    input_message[1_en]="${textcolor}[?]${clear} Enter the name of the user or enter ${textcolor}x${clear} to exit:"

    echo -e "${input_message[1_$language]}"
    read -r username
    [[ -n $username ]] && echo ""
    exit_username
    check_username_del
}

del_from_conf() {
    declare -A -g info_message=()
    info_message[1_ru]="Пользователь ${textcolor}${username}${clear} удалён"
    info_message[1_en]="Deleted user ${textcolor}${username}${clear}"

    echo "$(jq --arg u "${username}" 'del(.inbounds[].users[] | select(.name == $u))' /etc/sing-box/config.json)" > /etc/sing-box/config.json
    if [[ -f /etc/secret-sing-box/user-routes ]]; then
        sed -i "/^${username}:/d" /etc/secret-sing-box/user-routes
    fi
    apply_user_routing

    rm -f /var/www/${subspath}/${username}-TRJ-CLIENT.json /var/www/${subspath}/${username}-VLESS-CLIENT.json
    echo -e "${info_message[1_$language]}"
    echo ""
}

del_from_auth_lua() {
    if [[ -f /etc/haproxy/auth.lua ]]
    then
        trjpass=$(jq -r ".inbounds[].users[] | select(.name == \"${username}\") | .password" /etc/sing-box/config.json)
        pass_hash=$(echo -n "${trjpass}" | openssl dgst -sha224 | sed 's/.* //')
        sed -i "/${pass_hash}/d" /etc/haproxy/auth.lua
        systemctl reload haproxy.service
    fi
}

delete_users() {
    user_list_menu
}

### OPTION 4 - CHANGE STACK VALUE ###

get_stack_sel() {
    declare -A -g info_message=()
    info_message[1_ru]="[Выбрано]"
    info_message[1_en]="[Selected]"

    stack_sel_1=""; stack_sel_2=""; stack_sel_3=""
    current_stack=$(jq -r '.inbounds[] | select(.tag == "tun-in") | .stack' /var/www/${subspath}/${username}-TRJ-CLIENT.json)

    case $current_stack in
        system)
        stack_sel_1="${info_message[1_$language]}"
        ;;
        gvisor)
        stack_sel_2="${info_message[1_$language]}"
        ;;
        mixed)
        stack_sel_3="${info_message[1_$language]}"
    esac
}

stack_text_ru() {
    echo -e "${textcolor}[?]${clear} Выберите \"stack\" для пользователя ${textcolor}${username}${clear}:"
    echo "0 - Назад"
    echo "1 - \"system\" (системный стек, лучшая производительность, значение по умолчанию)    ${stack_sel_1}"
    echo "2 - \"gvisor\" (запускается в userspace, рекомендуется, если не работает \"system\")   ${stack_sel_2}"
    echo "3 - \"mixed\" (смешанный вариант: \"system\" для TCP, \"gvisor\" для UDP)                ${stack_sel_3}"
    read -r stack_option
    [[ -n $stack_option ]] && echo ""
}

stack_text_en() {
    echo -e "${textcolor}[?]${clear} Select \"stack\" value for the user ${textcolor}${username}${clear}:"
    echo "0 - Back"
    echo "1 - \"system\" (system stack, the best performance, default value)             ${stack_sel_1}"
    echo "2 - \"gvisor\" (runs in userspace, is recommended if \"system\" isn't working)   ${stack_sel_2}"
    echo "3 - \"mixed\" (mixed variant: \"system\" for TCP, \"gvisor\" for UDP)              ${stack_sel_3}"
    read -r stack_option
    [[ -n $stack_option ]] && echo ""
}

edit_configs_stack() {
    declare -A -g info_message=()
    info_message[1_ru]="Изменение \"stack\" у пользователя ${textcolor}${username}${clear} завершено, для применения новых настроек обновите конфиг на клиенте"
    info_message[1_en]="The \"stack\" value for the user ${textcolor}${username}${clear} has been changed, update the config on the client app to apply new settings"

    case $stack_option in
        1)
        new_stack="system"
        ;;
        2)
        new_stack="gvisor"
        ;;
        3)
        new_stack="mixed"
        ;;
        *)
        return 1
        ;;
    esac

    for protocol in 'TRJ' 'VLESS'
    do
        [[ "$protocol" == "VLESS" ]] && [[ -f /etc/haproxy/auth.lua ]] && break
        inbound_num=$(jq '[.inbounds[].tag] | index("tun-in")' /var/www/${subspath}/${username}-${protocol}-CLIENT.json 2>/dev/null)
        [[ -n "$inbound_num" && "$inbound_num" != "null" ]] && echo "$(jq ".inbounds[${inbound_num}].stack = \"${new_stack}\"" /var/www/${subspath}/${username}-${protocol}-CLIENT.json)" > /var/www/${subspath}/${username}-${protocol}-CLIENT.json
    done

    echo -e "${info_message[1_$language]}"
    echo ""
    return 0
}

change_stack() {
    user_list_menu
}

### USER ROUTING & OUTBOUND PERSISTENCE ###

parse_proxy_link_py() {
    local link="$1"
    local tag="$2"
    python3 - "$link" "$tag" << 'PYEOF'
import urllib.parse
import json
import base64
import sys

def b64_decode(s):
    s = s.replace("-", "+").replace("_", "/")
    pad = len(s) % 4
    if pad:
        s += "=" * (4 - pad)
    return base64.b64decode(s).decode("utf-8", errors="ignore")

def parse(link, tag):
    link = link.strip()
    if link.startswith("vless://"):
        parsed = urllib.parse.urlparse(link)
        uuid = parsed.username
        server = parsed.hostname
        port = parsed.port or 443
        qs = urllib.parse.parse_qs(parsed.query)
        out = {"type": "vless", "tag": tag, "server": server, "server_port": int(port), "uuid": uuid}
        flow = qs.get("flow", [None])[0]
        if flow: out["flow"] = flow
        security = qs.get("security", ["none"])[0]
        if security in ("tls", "reality"):
            tls_conf = {"enabled": True}
            sni = qs.get("sni", [None])[0]
            if sni: tls_conf["server_name"] = sni
            fp = qs.get("fp", [None])[0]
            if fp: tls_conf["utls"] = {"enabled": True, "fingerprint": fp}
            alpn = qs.get("alpn", [None])[0]
            if alpn: tls_conf["alpn"] = [x.strip() for x in alpn.split(",") if x.strip()]
            insecure = qs.get("allowInsecure", ["0"])[0]
            if insecure == "1": tls_conf["insecure"] = True
            if security == "reality":
                reality_conf = {"enabled": True}
                pbk = qs.get("pbk", [None])[0]
                if pbk: reality_conf["public_key"] = pbk
                sid = qs.get("sid", [None])[0]
                if sid: reality_conf["short_id"] = sid
                tls_conf["reality"] = reality_conf
            out["tls"] = tls_conf
        transport_type = qs.get("type", ["tcp"])[0]
        if transport_type == "ws":
            ws_conf = {"type": "ws"}
            path = qs.get("path", [None])[0]
            if path: ws_conf["path"] = path
            host = qs.get("host", [None])[0]
            if host: ws_conf["headers"] = {"Host": host}
            out["transport"] = ws_conf
        elif transport_type == "grpc":
            service_name = qs.get("serviceName", [None])[0]
            grpc_conf = {"type": "grpc"}
            if service_name: grpc_conf["service_name"] = service_name
            out["transport"] = grpc_conf
        elif transport_type == "httpupgrade":
            httpup_conf = {"type": "httpupgrade"}
            path = qs.get("path", [None])[0]
            if path: httpup_conf["path"] = path
            host = qs.get("host", [None])[0]
            if host: httpup_conf["headers"] = {"Host": host}
            out["transport"] = httpup_conf
        packet_encoding = qs.get("packetEncoding", [None])[0]
        if packet_encoding: out["packet_encoding"] = packet_encoding
        return out
    elif link.startswith("vmess://"):
        raw = link[8:]
        data = json.loads(b64_decode(raw))
        out = {"type": "vmess", "tag": tag, "server": data.get("add"), "server_port": int(data.get("port")), "uuid": data.get("id"), "alter_id": int(data.get("aid", 0)), "security": "auto"}
        if data.get("tls") == "tls":
            tls_conf = {"enabled": True}
            sni = data.get("sni") or data.get("host")
            if sni: tls_conf["server_name"] = sni
            fp = data.get("fp")
            if fp: tls_conf["utls"] = {"enabled": True, "fingerprint": fp}
            alpn = data.get("alpn")
            if alpn: tls_conf["alpn"] = [x.strip() for x in alpn.split(",") if x.strip()]
            out["tls"] = tls_conf
        net = data.get("net", "tcp")
        if net == "ws":
            ws_conf = {"type": "ws"}
            if data.get("path"): ws_conf["path"] = data.get("path")
            if data.get("host"): ws_conf["headers"] = {"Host": data.get("host")}
            out["transport"] = ws_conf
        elif net == "grpc":
            grpc_conf = {"type": "grpc"}
            if data.get("path"): grpc_conf["service_name"] = data.get("path")
            out["transport"] = grpc_conf
        return out
    elif link.startswith("trojan://"):
        parsed = urllib.parse.urlparse(link)
        qs = urllib.parse.parse_qs(parsed.query)
        out = {"type": "trojan", "tag": tag, "server": parsed.hostname, "server_port": int(parsed.port or 443), "password": parsed.username or parsed.password or ""}
        tls_conf = {"enabled": True}
        sni = qs.get("sni", [None])[0] or qs.get("peer", [None])[0]
        if sni: tls_conf["server_name"] = sni
        fp = qs.get("fp", [None])[0]
        if fp: tls_conf["utls"] = {"enabled": True, "fingerprint": fp}
        alpn = qs.get("alpn", [None])[0]
        if alpn: tls_conf["alpn"] = [x.strip() for x in alpn.split(",") if x.strip()]
        out["tls"] = tls_conf
        transport_type = qs.get("type", ["tcp"])[0]
        if transport_type == "ws":
            ws_conf = {"type": "ws"}
            path = qs.get("path", [None])[0]
            if path: ws_conf["path"] = path
            host = qs.get("host", [None])[0]
            if host: ws_conf["headers"] = {"Host": host}
            out["transport"] = ws_conf
        return out
    elif link.startswith("ss://"):
        raw = link[5:]
        if "#" in raw: raw, _ = raw.split("#", 1)
        if "@" in raw:
            user_info, server_info = raw.split("@", 1)
            if ":" in user_info:
                method, password = user_info.split(":", 1)
            else:
                decoded = b64_decode(user_info)
                method, password = decoded.split(":", 1)
            server, port = server_info.split(":", 1)
        else:
            decoded = b64_decode(raw)
            user_info, server_info = decoded.split("@", 1)
            method, password = user_info.split(":", 1)
            server, port = server_info.split(":", 1)
        return {"type": "shadowsocks", "tag": tag, "server": server, "server_port": int(port), "method": method, "password": password}
    elif link.startswith("socks5://") or link.startswith("socks://"):
        parsed = urllib.parse.urlparse(link)
        out = {"type": "socks", "tag": tag, "server": parsed.hostname, "server_port": int(parsed.port or 1080)}
        if parsed.username: out["username"] = parsed.username
        if parsed.password: out["password"] = parsed.password
        return out
    elif link.startswith("http://") or link.startswith("https://"):
        parsed = urllib.parse.urlparse(link)
        out = {"type": "http", "tag": tag, "server": parsed.hostname, "server_port": int(parsed.port or (443 if parsed.scheme == "https" else 80))}
        if parsed.scheme == "https": out["tls"] = {"enabled": True}
        if parsed.username: out["username"] = parsed.username
        if parsed.password: out["password"] = parsed.password
        return out
    else:
        raise ValueError("Unsupported link protocol scheme")

try:
    link = sys.argv[1]
    tag = sys.argv[2]
    res = parse(link, tag)
    print(json.dumps(res))
except Exception as e:
    print(f"Parser error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

reload_sing_box() {
    # Ensure systemd service has ExecReload defined via drop-in override
    if [[ ! -f /etc/systemd/system/sing-box.service.d/override.conf ]]
    then
        mkdir -p /etc/systemd/system/sing-box.service.d 2>/dev/null || true
        cat << 'EOF' > /etc/systemd/system/sing-box.service.d/override.conf 2>/dev/null || true
[Service]
ExecReload=/bin/kill -HUP $MAINPID
EOF
        systemctl daemon-reload 2>/dev/null || true
    fi

    # 1. Try systemctl reload (standard graceful SIGHUP via systemd)
    if systemctl reload sing-box.service 2>/dev/null
    then
        return 0
    fi

    # 2. Try direct SIGHUP to running sing-box process for zero-downtime hot-reload
    local pid
    pid=$(pgrep -x sing-box 2>/dev/null || true)
    if [[ -n "$pid" ]] && kill -HUP "$pid" 2>/dev/null
    then
        return 0
    fi

    # 3. Fallback: restart service so changes are guaranteed to take effect immediately on the fly
    systemctl restart sing-box.service 2>/dev/null || true
}

get_user_node() {
    local u="$1"
    local match
    match=$(grep "^${u}:" /etc/secret-sing-box/user-routes 2>/dev/null | head -n 1)
    local u_node="direct"
    if [[ -n "$match" ]]
    then
        local f2 f3
        f2=$(echo "$match" | cut -d: -f2)
        f3=$(echo "$match" | cut -d: -f3)
        if [[ -n "$f3" ]]
        then
            u_node="$f2"
        fi
    fi
    if [[ $(jq --arg t "$u_node" '[(.outbounds // [])[].tag] | index($t) != null' /etc/sing-box/config.json 2>/dev/null) != "true" ]]
    then
        u_node="direct"
    fi
    echo "$u_node"
}

get_user_mode_val() {
    local u="$1"
    local match
    match=$(grep "^${u}:" /etc/secret-sing-box/user-routes 2>/dev/null | head -n 1)
    local u_mode="default"
    if [[ -n "$match" ]]
    then
        local f2 f3
        f2=$(echo "$match" | cut -d: -f2)
        f3=$(echo "$match" | cut -d: -f3)
        if [[ -n "$f3" ]]
        then
            u_mode="$f3"
        else
            u_mode="$f2"
        fi
    else
        local m_rule
        m_rule=$(jq -c --arg uname "$u" '[.route.rules[] | select(.auth_user and (.auth_user | index($uname) != null))] | .[0]' /etc/sing-box/config.json 2>/dev/null)
        if [[ -n "$m_rule" && "$m_rule" != "null" ]]
        then
            local m_out m_has_ru
            m_out=$(jq -r '.outbound' <<< "$m_rule" 2>/dev/null)
            m_has_ru=$(jq 'has("domain_suffix")' <<< "$m_rule" 2>/dev/null)
            if [[ "$m_has_ru" == "true" ]]
            then
                case "$m_out" in
                    warp)  u_mode="warp-ru" ;;
                    proxy) u_mode="chain-ru" ;;
                    *)     u_mode="direct-ru" ;;
                esac
            else
                case "$m_out" in
                    warp)  u_mode="full-warp" ;;
                    proxy) u_mode="full-chain" ;;
                    *)     u_mode="full-node" ;;
                esac
            fi
        fi
    fi
    echo "$u_mode"
}

save_user_route() {
    local u="$1"
    local node="$2"
    local mode="$3"
    mkdir -p /etc/secret-sing-box
    touch /etc/secret-sing-box/user-routes
    sed -i "/^${u}:/d" /etc/secret-sing-box/user-routes
    echo "${u}:${node}:${mode}" >> /etc/secret-sing-box/user-routes
    apply_user_routing
}

apply_user_routing() {
    local has_warp="" has_chain=""
    [[ $(jq '[(.outbounds // [])[].tag] | index("warp") != null' /etc/sing-box/config.json 2>/dev/null) == "true" ]] && has_warp="true"
    [[ $(jq '[(.outbounds // [])[].tag] | index("proxy") != null' /etc/sing-box/config.json 2>/dev/null) == "true" ]] && has_chain="true"

    local existing_outbounds
    existing_outbounds=$(jq -r '[(.outbounds // [])[].tag] | .[]' /etc/sing-box/config.json 2>/dev/null)

    local ru_sets=""
    for rs in geoip-ru category-gov-ru
    do
        if [[ $(jq --arg s "$rs" '[(.route.rule_set // [])[].tag] | index($s) != null' /etc/sing-box/config.json 2>/dev/null) == "true" ]]
        then
            ru_sets+="\"$rs\","
        fi
    done
    ru_sets="${ru_sets%,}"

    local valid_users
    valid_users=$(jq -r '[(.inbounds[]?.users // [])[].name] | unique[]' /etc/sing-box/config.json 2>/dev/null)

    local new_rules="[]"

    _add_rule_json() {
        local rule_obj="$1"
        new_rules=$(jq --argjson r "$rule_obj" '. + [$r]' <<< "$new_rules")
    }

    _user_arr_json() {
        local -n arr_ref=$1
        printf '%s\n' "${arr_ref[@]}" | jq -R . | jq -s .
    }

    declare -A mode_groups=()

    for u in $valid_users
    do
        local match
        match=$(grep "^${u}:" /etc/secret-sing-box/user-routes 2>/dev/null | head -n 1)
        local u_node="direct"
        local u_mode="default"

        if [[ -n "$match" ]]
        then
            local f2 f3
            f2=$(echo "$match" | cut -d: -f2)
            f3=$(echo "$match" | cut -d: -f3)
            if [[ -n "$f3" ]]
            then
                u_node="$f2"
                u_mode="$f3"
            else
                u_node="direct"
                u_mode="$f2"
            fi
        fi

        if ! grep -qw "$u_node" <<< "$existing_outbounds"
        then
            u_node="direct"
        fi

        local key="${u_node}###${u_mode}"
        mode_groups["$key"]+="${u} "
    done

    for key in "${!mode_groups[@]}"
    do
        local node="${key%%###*}"
        local mode="${key##*###}"
        local users_str="${mode_groups[$key]}"
        read -r -a users_list <<< "$users_str"
        [[ ${#users_list[@]} -eq 0 ]] && continue

        local uj
        uj=$(_user_arr_json users_list)

        case "$mode" in
            default)
                if [[ "$node" != "direct" ]]
                then
                    _add_rule_json "{\"auth_user\":$uj,\"outbound\":\"$node\"}"
                fi
                ;;
            full-node|full-direct)
                _add_rule_json "{\"auth_user\":$uj,\"outbound\":\"$node\"}"
                ;;
            full-warp)
                if [[ "$has_warp" == "true" ]]
                then
                    _add_rule_json "{\"auth_user\":$uj,\"outbound\":\"warp\"}"
                else
                    _add_rule_json "{\"auth_user\":$uj,\"outbound\":\"$node\"}"
                fi
                ;;
            warp-ru)
                if [[ "$has_warp" == "true" ]]
                then
                    local r="{\"auth_user\":$uj,\"domain_suffix\":[\".ru\",\".su\",\".ru.com\",\".ru.net\"],\"domain_keyword\":[\"xn--\"]"
                    [[ -n "$ru_sets" ]] && r+=",\"rule_set\":[$ru_sets]"
                    r+=",\"outbound\":\"warp\"}"
                    _add_rule_json "$r"
                fi
                if [[ "$node" != "direct" ]]
                then
                    _add_rule_json "{\"auth_user\":$uj,\"outbound\":\"$node\"}"
                fi
                ;;
            direct-ru)
                local r="{\"auth_user\":$uj,\"domain_suffix\":[\".ru\",\".su\",\".ru.com\",\".ru.net\"],\"domain_keyword\":[\"xn--\"]"
                [[ -n "$ru_sets" ]] && r+=",\"rule_set\":[$ru_sets]"
                r+=",\"outbound\":\"$node\"}"
                _add_rule_json "$r"

                if [[ "$has_warp" == "true" ]]
                then
                    _add_rule_json "{\"auth_user\":$uj,\"outbound\":\"warp\"}"
                fi
                ;;
            full-chain)
                if [[ "$has_chain" == "true" ]]
                then
                    _add_rule_json "{\"auth_user\":$uj,\"outbound\":\"proxy\"}"
                else
                    _add_rule_json "{\"auth_user\":$uj,\"outbound\":\"$node\"}"
                fi
                ;;
            chain-ru)
                if [[ "$has_chain" == "true" ]]
                then
                    local r="{\"auth_user\":$uj,\"domain_suffix\":[\".ru\",\".su\",\".ru.com\",\".ru.net\"],\"domain_keyword\":[\"xn--\"]"
                    [[ -n "$ru_sets" ]] && r+=",\"rule_set\":[$ru_sets]"
                    r+=",\"outbound\":\"proxy\"}"
                    _add_rule_json "$r"
                fi
                if [[ "$node" != "direct" ]]
                then
                    _add_rule_json "{\"auth_user\":$uj,\"outbound\":\"$node\"}"
                fi
                ;;
        esac
    done

    cp -f /etc/sing-box/config.json /etc/sing-box/config.json.bak-routing

    local updated_json
    updated_json=$(jq --argjson new_rules "$new_rules" '
        del(.route.rules[] | select(has("auth_user"))) |
        ([.route.rules[] | (.outbound != null and (has("auth_user") | not))] | index(true)) as $pos |
        ($pos // (.route.rules | length)) as $insert_pos |
        .route.rules |= (.[0:$insert_pos] + $new_rules + .[$insert_pos:])
    ' /etc/sing-box/config.json)

    echo "$updated_json" > /etc/sing-box/config.json

    local check_ok=""
    if command -v sing-box >/dev/null 2>&1; then
        sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1 && check_ok="true"
    else
        jq . /etc/sing-box/config.json >/dev/null 2>&1 && check_ok="true"
    fi

    if [[ "$check_ok" == "true" ]]; then
        rm -f /etc/sing-box/config.json.bak-routing
        reload_sing_box
        return 0
    else
        cp -f /etc/sing-box/config.json.bak-routing /etc/sing-box/config.json
        rm -f /etc/sing-box/config.json.bak-routing
        echo -e "${red}Error: failed sing-box config validation for user routing, changes reverted${clear}"
        return 1
    fi
}

select_user_outbound() {
    declare -A -g su_title=()
    su_title[ru]="${textcolor}[?]${clear} Выберите выходную ноду (Outbound) для пользователя ${textcolor}${username}${clear}:"
    su_title[en]="${textcolor}[?]${clear} Select an outbound node for user ${textcolor}${username}${clear}:"

    local cur_node
    cur_node=$(get_user_node "$username")
    local cur_mode
    cur_mode=$(get_user_mode_val "$username")

    local cand_nodes=("direct")
    for t in $(jq -r '.outbounds[]?.tag' /etc/sing-box/config.json 2>/dev/null); do
        if [[ "$t" != "direct" && "$t" != "warp" && "$t" != "proxy" && "$t" != "IPv4" && "$t" != "block" && -n "$t" ]]; then
            cand_nodes+=("$t")
        fi
    done

    while true
    do
        echo ""
        echo -e "${su_title[$language]}"
        echo "0 - Назад"
        for idx in "${!cand_nodes[@]}"; do
            local num=$((idx + 1))
            local tag="${cand_nodes[$idx]}"
            local sel_mark=""
            [[ "$tag" == "$cur_node" ]] && sel_mark=" ${info_message[1_$language]}"

            local desc=""
            if [[ "$tag" == "direct" ]]; then
                [[ "$language" == "ru" ]] && desc="(Локальный сервер / Прямой выход)" || desc="(Local server / Direct)"
            else
                local otype osrv oport oiface
                otype=$(jq -r --arg t "$tag" '.outbounds[] | select(.tag == $t) | .type' /etc/sing-box/config.json 2>/dev/null)
                osrv=$(jq -r --arg t "$tag" '.outbounds[] | select(.tag == $t) | .server // empty' /etc/sing-box/config.json 2>/dev/null)
                oport=$(jq -r --arg t "$tag" '.outbounds[] | select(.tag == $t) | .server_port // empty' /etc/sing-box/config.json 2>/dev/null)
                oiface=$(jq -r --arg t "$tag" '.outbounds[] | select(.tag == $t) | .bind_interface // empty' /etc/sing-box/config.json 2>/dev/null)
                if [[ -n "$osrv" ]]; then
                    desc="(${otype}, ${osrv}:${oport})"
                elif [[ -n "$oiface" ]]; then
                    desc="(${otype}, interface: ${oiface})"
                else
                    desc="(${otype})"
                fi
            fi
            echo -e "${num} - ${textcolor}${tag}${clear} ${desc}${sel_mark}"
        done

        read -r node_sel
        [[ -n $node_sel ]] && echo ""

        if [[ "$node_sel" == "0" || ${node_sel,,} =~ ^(x|х|back|q)$ ]]; then
            return 0
        fi

        if [[ "$node_sel" =~ ^[0-9]+$ ]] && [[ "$node_sel" -ge 1 && "$node_sel" -le "${#cand_nodes[@]}" ]]; then
            local chosen_node="${cand_nodes[$((node_sel - 1))]}"
            save_user_route "$username" "$chosen_node" "$cur_mode"
            declare -A -g su_success=()
            su_success[ru]="Выходная нода пользователя ${textcolor}${username}${clear} изменена на ${textcolor}${chosen_node}${clear}"
            su_success[en]="Outbound node of user ${textcolor}${username}${clear} changed to ${textcolor}${chosen_node}${clear}"
            echo -e "${su_success[$language]}"
            echo ""
            return 0
        else
            declare -A -g su_invalid=()
            su_invalid[ru]="${red}Ошибка: неверный выбор, попробуйте снова${clear}"
            su_invalid[en]="${red}Error: invalid choice, please try again${clear}"
            echo -e "${su_invalid[$language]}"
        fi
    done
}

### ROUTING MODE SELECTION FOR A USER ###

check_user_routing() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: исходящий WARP не настроен на этом сервере${clear}"
    check_message[1_en]="${red}Error: WARP outbound is not configured on this server${clear}"
    check_message[2_ru]="${red}Ошибка: цепочка из двух и более серверов не настроена на этом сервере${clear}"
    check_message[2_en]="${red}Error: a chain of two or more servers is not configured on this server${clear}"
    check_message[3_ru]="${red}Ошибка: неверный выбор, введите число от 0 до 7${clear}"
    check_message[3_en]="${red}Error: invalid choice, enter a number from 0 to 7${clear}"

    has_warp=""
    has_chain=""
    [[ $(jq '[.outbounds[].tag] | index("warp")' /etc/sing-box/config.json 2>/dev/null) != "null" ]] && has_warp="true"
    [[ $(jq '[.outbounds[].tag] | index("proxy")' /etc/sing-box/config.json 2>/dev/null) != "null" ]] && has_chain="true"
}

get_user_mode_sel() {
    declare -A -g info_message=()
    info_message[1_ru]="[Выбрано]"
    info_message[1_en]="[Selected]"

    check_user_routing

    mode_sel_1=""; mode_sel_2=""; mode_sel_3=""; mode_sel_4=""; mode_sel_5=""; mode_sel_6=""; mode_sel_7=""
    local cur_mode
    cur_mode=$(get_user_mode_val "$username")

    case "$cur_mode" in
        default)               mode_sel_1="${info_message[1_$language]}" ;;
        full-warp)             mode_sel_2="${info_message[1_$language]}" ;;
        full-node|full-direct) mode_sel_3="${info_message[1_$language]}" ;;
        full-chain)            mode_sel_4="${info_message[1_$language]}" ;;
        warp-ru)               mode_sel_5="${info_message[1_$language]}" ;;
        direct-ru)             mode_sel_6="${info_message[1_$language]}" ;;
        chain-ru)              mode_sel_7="${info_message[1_$language]}" ;;
        *)                     mode_sel_1="${info_message[1_$language]}" ;;
    esac
}

user_mode_text_ru() {
    local cur_node
    cur_node=$(get_user_node "$username")
    local node_label="Direct (сервер)"
    [[ "$cur_node" != "direct" ]] && node_label="$cur_node"

    echo -e "${textcolor}[?]${clear} Выберите режим маршрутизации для пользователя ${textcolor}${username}${clear} (нода: ${textcolor}${cur_node}${clear}):"
    echo "0 - Назад"
    echo "1 - По умолчанию (общие правила маршрутизации сервера)                          ${mode_sel_1}"
    echo "2 - Полный WARP (весь трафик пользователя через WARP)                           ${mode_sel_2}"
    echo "3 - Полный ${node_label} (весь трафик пользователя через ${cur_node})          ${mode_sel_3}"
    echo "4 - Полная цепочка (весь трафик пользователя через следующий сервер)            ${mode_sel_4}"
    echo "5 - WARP для RU/SU/РФ (RU через WARP, остальное через ${cur_node})              ${mode_sel_5}"
    echo "6 - ${node_label} для RU/SU/РФ (RU через ${cur_node}, остальное через WARP)     ${mode_sel_6}"
    echo "7 - Цепочка для RU/SU/РФ (RU через цепочку, остальное через ${cur_node})        ${mode_sel_7}"
    read -r mode_option
    [[ -n $mode_option ]] && echo ""
}

user_mode_text_en() {
    local cur_node
    cur_node=$(get_user_node "$username")
    local node_label="Direct (server)"
    [[ "$cur_node" != "direct" ]] && node_label="$cur_node"

    echo -e "${textcolor}[?]${clear} Select a routing mode for the user ${textcolor}${username}${clear} (node: ${textcolor}${cur_node}${clear}):"
    echo "0 - Back"
    echo "1 - Default (global routing rules of the server)                                ${mode_sel_1}"
    echo "2 - Full WARP (all user traffic through WARP)                                   ${mode_sel_2}"
    echo "3 - Full ${node_label} (all user traffic through ${cur_node})                   ${mode_sel_3}"
    echo "4 - Full Chain (all user traffic through the next server)                       ${mode_sel_4}"
    echo "5 - WARP for RU/SU/RF (RU through WARP, rest through ${cur_node})              ${mode_sel_5}"
    echo "6 - ${node_label} for RU/SU/RF (RU through ${cur_node}, rest through WARP)     ${mode_sel_6}"
    echo "7 - Chain for RU/SU/RF (RU through chain, rest through ${cur_node})             ${mode_sel_7}"
    read -r mode_option
    [[ -n $mode_option ]] && echo ""
}

get_user_mode() {
    get_user_mode_sel

    while true
    do
        user_mode_text_${language}

        error_option=""
        case $mode_option in
            0)
            return 1
            ;;
            2|5)
            [[ "$has_warp" != "true" ]] && error_option="1"
            ;;
            4|7)
            [[ "$has_chain" != "true" ]] && error_option="2"
            ;;
            1|3|6)
            ;;
            *)
            error_option="3"
            ;;
        esac

        if [[ -n $error_option ]]
        then
            echo -e "${check_message[${error_option}_$language]}"
            echo ""
            continue
        fi
        return 0
    done
}

edit_user_routing() {
    local cur_node
    cur_node=$(get_user_node "$username")
    local chosen_mode="default"

    case $mode_option in
        1) chosen_mode="default" ;;
        2) chosen_mode="full-warp" ;;
        3) chosen_mode="full-node" ;;
        4) chosen_mode="full-chain" ;;
        5) chosen_mode="warp-ru" ;;
        6) chosen_mode="direct-ru" ;;
        7) chosen_mode="chain-ru" ;;
    esac

    save_user_route "$username" "$cur_node" "$chosen_mode"

    declare -A -g ur_info=()
    ur_info[ru]="Режим маршрутизации пользователя ${textcolor}${username}${clear} успешно изменён и применён на сервере"
    ur_info[en]="The routing mode of the user ${textcolor}${username}${clear} has been changed and applied on the server"
    echo -e "${ur_info[$language]}"
    echo ""
}

change_user_routing() {
    user_list_menu
}

### USER MANAGEMENT: ACTIONS & SUBMENU ###

user_manage_menu() {
    declare -A -g um_title=()
    um_title[ru]="${textcolor}Управление пользователем ${clear}${textcolor_light}${username}${clear}:"
    um_title[en]="${textcolor}Managing user ${clear}${textcolor_light}${username}${clear}:"

    declare -A -g um_stack_lbl=()
    um_stack_lbl[ru]="  TUN stack:     "
    um_stack_lbl[en]="  TUN stack:     "

    declare -A -g um_node_lbl=()
    um_node_lbl[ru]="  Выходная нода: "
    um_node_lbl[en]="  Outbound node: "

    declare -A -g um_route_lbl=()
    um_route_lbl[ru]="  Маршрутизация: "
    um_route_lbl[en]="  Routing mode:  "

    declare -A -g um_links_lbl=()
    um_links_lbl[ru]="  Ссылки на конфигурации:"
    um_links_lbl[en]="  Subscription links:"

    declare -A -g um_actions_lbl=()
    um_actions_lbl[ru]="${textcolor}Выберите действие:${clear}"
    um_actions_lbl[en]="${textcolor}Select an action:${clear}"

    declare -A -g um_opt0=() um_opt1=() um_opt2=() um_opt3=() um_opt4=()
    um_opt0[ru]="0 - Назад к списку пользователей"
    um_opt0[en]="0 - Back to user list"
    um_opt1[ru]="1 - Поменять \"stack\" в tun-интерфейсе"
    um_opt1[en]="1 - Change \"stack\" in tun interface"
    um_opt2[ru]="2 - Выбрать выходную ноду (Outbound)"
    um_opt2[en]="2 - Choose outbound node"
    um_opt3[ru]="3 - Поменять режим маршрутизации"
    um_opt3[en]="3 - Change routing mode"
    um_opt4[ru]="4 - Удалить пользователя"
    um_opt4[en]="4 - Delete user"

    while true
    do
        local cur_stack="system"
        if [[ -f /var/www/${subspath}/${username}-TRJ-CLIENT.json ]]
        then
            local s
            s=$(jq -r '.inbounds[] | select(.tag == "tun-in") | .stack' /var/www/${subspath}/${username}-TRJ-CLIENT.json 2>/dev/null)
            [[ -n "$s" && "$s" != "null" ]] && cur_stack="$s"
        fi

        local cur_node
        cur_node=$(get_user_node "$username")
        local node_desc=""
        if [[ "$cur_node" == "direct" ]]; then
            [[ "$language" == "ru" ]] && node_desc="direct (Локальный сервер)" || node_desc="direct (Local server)"
        else
            local ntype nsrv nport niface
            ntype=$(jq -r --arg t "$cur_node" '.outbounds[] | select(.tag == $t) | .type' /etc/sing-box/config.json 2>/dev/null)
            nsrv=$(jq -r --arg t "$cur_node" '.outbounds[] | select(.tag == $t) | .server // empty' /etc/sing-box/config.json 2>/dev/null)
            nport=$(jq -r --arg t "$cur_node" '.outbounds[] | select(.tag == $t) | .server_port // empty' /etc/sing-box/config.json 2>/dev/null)
            niface=$(jq -r --arg t "$cur_node" '.outbounds[] | select(.tag == $t) | .bind_interface // empty' /etc/sing-box/config.json 2>/dev/null)
            if [[ -n "$nsrv" ]]; then
                node_desc="${cur_node} (${ntype}, ${nsrv}:${nport})"
            elif [[ -n "$niface" ]]; then
                node_desc="${cur_node} (${ntype}, iface: ${niface})"
            else
                node_desc="${cur_node} (${ntype})"
            fi
        fi

        local cur_mode_val
        cur_mode_val=$(get_user_mode_val "$username")
        local cur_mode_str=""
        case "$cur_mode_val" in
            default)
                [[ "$language" == "ru" ]] && cur_mode_str="По умолчанию (общие правила сервера)" || cur_mode_str="Default (global server rules)"
                ;;
            full-node|full-direct)
                [[ "$language" == "ru" ]] && cur_mode_str="Полный ${cur_node} (весь трафик)" || cur_mode_str="Full ${cur_node} (all traffic)"
                ;;
            full-warp)
                [[ "$language" == "ru" ]] && cur_mode_str="Полный WARP (весь трафик)" || cur_mode_str="Full WARP (all traffic)"
                ;;
            full-chain)
                [[ "$language" == "ru" ]] && cur_mode_str="Полная цепочка (весь трафик)" || cur_mode_str="Full Chain (all traffic)"
                ;;
            warp-ru)
                [[ "$language" == "ru" ]] && cur_mode_str="WARP (RU/SU/РФ) -> ${cur_node} (остальное)" || cur_mode_str="WARP (RU/SU/RF) -> ${cur_node} (rest)"
                ;;
            direct-ru)
                [[ "$language" == "ru" ]] && cur_mode_str="${cur_node} (RU/SU/РФ) -> WARP (остальное)" || cur_mode_str="${cur_node} (RU/SU/RF) -> WARP (rest)"
                ;;
            chain-ru)
                [[ "$language" == "ru" ]] && cur_mode_str="Цепочка (RU/SU/РФ) -> ${cur_node} (остальное)" || cur_mode_str="Chain (RU/SU/RF) -> ${cur_node} (rest)"
                ;;
            *)
                [[ "$language" == "ru" ]] && cur_mode_str="По умолчанию" || cur_mode_str="Default"
                ;;
        esac

        echo ""
        echo -e "${um_title[$language]}"
        echo -e "${um_stack_lbl[$language]}${textcolor}${cur_stack}${clear}"
        echo -e "${um_node_lbl[$language]}${textcolor}${node_desc}${clear}"
        echo -e "${um_route_lbl[$language]}${textcolor}${cur_mode_str}${clear}"
        echo -e "${um_links_lbl[$language]}"
        echo "    https://${domain}/${subspath}/${username}-TRJ-CLIENT.json"
        [[ ! -f /etc/haproxy/auth.lua ]] && echo "    https://${domain}/${subspath}/${username}-VLESS-CLIENT.json"
        echo ""
        echo -e "${um_actions_lbl[$language]}"
        echo -e "${um_opt0[$language]}"
        echo -e "${um_opt1[$language]}"
        echo -e "${um_opt2[$language]}"
        echo -e "${um_opt3[$language]}"
        echo -e "${um_opt4[$language]}"
        read -r um_action
        [[ -n $um_action ]] && echo ""

        case $um_action in
            0|x|х)
            username=""
            user_list_menu
            return
            ;;
            1)
            get_stack_sel
            stack_text_${language}
            edit_configs_stack
            ;;
            2)
            select_user_outbound
            ;;
            3)
            if get_user_mode
            then
                edit_user_routing
            fi
            ;;
            4)
            declare -A -g del_confirm_msg=()
            del_confirm_msg[ru]="${textcolor}[?]${clear} Вы уверены, что хотите удалить пользователя ${textcolor}${username}${clear}? [y/N]:"
            del_confirm_msg[en]="${textcolor}[?]${clear} Are you sure you want to delete user ${textcolor}${username}${clear}? [y/N]:"

            echo -e "${del_confirm_msg[$language]}"
            read -r confirm_del
            [[ -n $confirm_del ]] && echo ""

            if [[ ${confirm_del,,} =~ ^(y|yes|д|да)$ ]]
            then
                del_from_auth_lua
                del_from_conf
                username=""
                user_list_menu
                return
            fi
            ;;
            *)
            continue
            ;;
        esac
    done
}

user_list_menu() {
    local users_raw
    users_raw=$(ls -A1 /var/www/${subspath} 2>/dev/null | grep "\-CLIENT.json" | sed -e "s/-TRJ-CLIENT\.json//g" -e "s/-VLESS-CLIENT\.json//g" | sort -u)

    if [[ -z "$users_raw" ]]
    then
        declare -A -g no_users_msg=()
        no_users_msg[ru]="${red}Ошибка: пользователи отсутствуют${clear}"
        no_users_msg[en]="${red}Error: no users found${clear}"
        echo -e "${no_users_msg[$language]}"
        echo ""
        main_menu
        return
    fi

    local -a users_arr=()
    while IFS= read -r u
    do
        [[ -n "$u" ]] && users_arr+=("$u")
    done <<< "$users_raw"

    local total_users=${#users_arr[@]}

    declare -A -g ulist_title=()
    ulist_title[ru]="${textcolor}Список пользователей (всего: ${total_users}):${clear}"
    ulist_title[en]="${textcolor}User list (total: ${total_users}):${clear}"

    declare -A -g ulist_back=()
    ulist_back[ru]="0 - Назад в главное меню"
    ulist_back[en]="0 - Back to main menu"

    declare -A -g ulist_prompt=()
    ulist_prompt[ru]="${textcolor}[?]${clear} Выберите пользователя (номер или имя) или 0 для возврата:"
    ulist_prompt[en]="${textcolor}[?]${clear} Select a user (number or name) or 0 to go back:"

    declare -A -g ulist_invalid=()
    ulist_invalid[ru]="${red}Ошибка: пользователь не найден, попробуйте снова${clear}"
    ulist_invalid[en]="${red}Error: user not found, please try again${clear}"

    while true
    do
        echo ""
        echo -e "${ulist_title[$language]}"
        echo -e "${ulist_back[$language]}"
        echo "---------------------------------"
        for idx in "${!users_arr[@]}"
        do
            local u="${users_arr[$idx]}"
            local num=$((idx + 1))
            local u_stack="system"
            if [[ -f /var/www/${subspath}/${u}-TRJ-CLIENT.json ]]
            then
                local s
                s=$(jq -r '.inbounds[] | select(.tag == "tun-in") | .stack' /var/www/${subspath}/${u}-TRJ-CLIENT.json 2>/dev/null)
                [[ -n "$s" && "$s" != "null" ]] && u_stack="$s"
            fi

            local u_node
            u_node=$(get_user_node "$u")

            local u_mode_val
            u_mode_val=$(get_user_mode_val "$u")
            local u_mode_short=""
            case "$u_mode_val" in
                default)               u_mode_short="default" ;;
                full-warp)             u_mode_short="WARP" ;;
                full-node|full-direct) u_mode_short="${u_node}" ;;
                full-chain)            u_mode_short="chain" ;;
                warp-ru)               u_mode_short="WARP (RU)" ;;
                direct-ru)             u_mode_short="${u_node} (RU)" ;;
                chain-ru)              u_mode_short="chain (RU)" ;;
                *)                     u_mode_short="default" ;;
            esac

            echo -e "${num} - ${textcolor}${u}${clear} \t[stack: ${u_stack}, node: ${u_node}, route: ${u_mode_short}]"
        done
        echo ""
        echo -e "${ulist_prompt[$language]}"
        read -r user_sel
        [[ -n $user_sel ]] && echo ""

        if [[ "$user_sel" == "0" || ${user_sel,,} =~ ^(x|х|back|q)$ ]]
        then
            main_menu
            return
        fi

        selected_user=""
        if [[ "$user_sel" =~ ^[0-9]+$ ]] && [[ "$user_sel" -ge 1 && "$user_sel" -le "$total_users" ]]
        then
            selected_user="${users_arr[$((user_sel - 1))]}"
        else
            for u in "${users_arr[@]}"
            do
                if [[ "$user_sel" == "$u" ]]
                then
                    selected_user="$u"
                    break
                fi
            done
        fi

        if [[ -n "$selected_user" ]]
        then
            username="$selected_user"
            user_manage_menu
            return
        else
            echo -e "${ulist_invalid[$language]}"
        fi
    done
}

### OPTION 3 - OUTBOUND NODES MANAGEMENT ###

show_outbounds_table() {
    local tags
    tags=$(jq -r '.outbounds[]?.tag' /etc/sing-box/config.json 2>/dev/null)

    if [[ -z "$tags" ]]; then
        echo "  (Нет настроенных outbounds)"
        return
    fi

    declare -A user_counts=()
    declare -A user_lists=()
    local valid_users
    valid_users=$(jq -r '[(.inbounds[]?.users // [])[].name] | unique[]' /etc/sing-box/config.json 2>/dev/null)

    for u in $valid_users; do
        local n
        n=$(get_user_node "$u")
        user_counts["$n"]=$(( ${user_counts["$n"]:-0} + 1 ))
        user_lists["$n"]+="${u} "
    done

    local idx=1
    for t in $tags; do
        local otype osrv oport oiface
        otype=$(jq -r --arg t "$t" '.outbounds[] | select(.tag == $t) | .type' /etc/sing-box/config.json 2>/dev/null)
        osrv=$(jq -r --arg t "$t" '.outbounds[] | select(.tag == $t) | .server // empty' /etc/sing-box/config.json 2>/dev/null)
        oport=$(jq -r --arg t "$t" '.outbounds[] | select(.tag == $t) | .server_port // empty' /etc/sing-box/config.json 2>/dev/null)
        oiface=$(jq -r --arg t "$t" '.outbounds[] | select(.tag == $t) | .bind_interface // empty' /etc/sing-box/config.json 2>/dev/null)

        local role_label=""
        case "$t" in
            direct) role_label="[Системный / Локальный]" ;;
            warp)   role_label="[Cloudflare WARP]" ;;
            proxy)  role_label="[Цепочка серверов]" ;;
            IPv4)   role_label="[IPv4 Only]" ;;
            block)  role_label="[Блокировка]" ;;
            *)      role_label="[Пользовательский]" ;;
        esac

        local u_info=""
        local cnt=${user_counts["$t"]:-0}
        if [[ "$t" != "warp" && "$t" != "proxy" && "$t" != "IPv4" && "$t" != "block" ]]; then
            local ulist="${user_lists["$t"]:-}"
            ulist="${ulist%" "}"
            if [[ "$cnt" -gt 0 ]]; then
                u_info="— пользователей: ${cnt} (${ulist})"
            else
                u_info="— пользователей: 0"
            fi
        fi

        local target_str=""
        if [[ -n "$osrv" ]]; then
            target_str="(${osrv}:${oport})"
        elif [[ -n "$oiface" ]]; then
            target_str="(интерфейс: ${oiface})"
        fi

        printf "  %-12s %-12s %-26s %-24s %s\n" "[${idx}] ${t}" "(${otype})" "${target_str}" "${role_label}" "${u_info}"
        idx=$((idx + 1))
    done
}

add_outbound_by_link() {
    declare -A -g aol_msgs=()
    aol_msgs[tag_prompt_ru]="${textcolor}[?]${clear} Введите имя (тег) для нового outbound (например: de или de-out) или x для отмены:"
    aol_msgs[tag_prompt_en]="${textcolor}[?]${clear} Enter a name (tag) for the new outbound (e.g., de or de-out) or x to cancel:"
    aol_msgs[link_prompt_ru]="${textcolor}[?]${clear} Вставьте ссылку (vless://, vmess://, trojan://, ss://, socks5://, http://) или x для отмены:"
    aol_msgs[link_prompt_en]="${textcolor}[?]${clear} Paste proxy link (vless://, vmess://, trojan://, ss://, socks5://, http://) or x to cancel:"
    aol_msgs[err_tag_ru]="${red}Ошибка: тег может содержать только латинские буквы, цифры, дефис и подчеркивание${clear}"
    aol_msgs[err_tag_en]="${red}Error: tag may only contain alphanumeric characters, dash, and underscore${clear}"
    aol_msgs[err_exists_ru]="${red}Ошибка: outbound с таким тегом уже существует${clear}"
    aol_msgs[err_exists_en]="${red}Error: an outbound with this tag already exists${clear}"
    aol_msgs[success_ru]="Outbound ${textcolor}%s${clear} успешно добавлен на сервер!"
    aol_msgs[success_en]="Outbound ${textcolor}%s${clear} successfully added to the server!"
    aol_msgs[err_parse_ru]="${red}Ошибка: не удалось распарсить ссылку. Проверьте формат ссылки.${clear}"
    aol_msgs[err_parse_en]="${red}Error: failed to parse proxy link. Please verify link format.${clear}"
    aol_msgs[err_check_ru]="${red}Ошибка: sing-box check отклонил конфигурацию с этим outbound. Изменения отменены.${clear}"
    aol_msgs[err_check_en]="${red}Error: sing-box check rejected config with this outbound. Changes reverted.${clear}"

    local new_tag=""
    while true; do
        echo -e "${aol_msgs[tag_prompt_$language]}"
        read -r new_tag
        [[ -n $new_tag ]] && echo ""
        [[ ${new_tag,,} =~ ^(x|х|q)$ || -z "$new_tag" ]] && return 0
        new_tag=$(echo "$new_tag" | tr -d '[:space:]')
        if [[ ! $new_tag =~ ^[a-zA-Z0-9._-]+$ ]]; then
            echo -e "${aol_msgs[err_tag_$language]}"
            continue
        fi
        [[ "$new_tag" != *-out ]] && new_tag="${new_tag}-out"

        if [[ $(jq --arg t "$new_tag" '[(.outbounds // [])[].tag] | index($t) != null' /etc/sing-box/config.json 2>/dev/null) == "true" ]]; then
            echo -e "${aol_msgs[err_exists_$language]}"
            continue
        fi
        break
    done

    echo -e "${aol_msgs[link_prompt_$language]}"
    read -r proxy_link
    [[ -n $proxy_link ]] && echo ""
    [[ ${proxy_link,,} =~ ^(x|х|q)$ || -z "$proxy_link" ]] && return 0

    local parsed_json
    parsed_json=$(parse_proxy_link_py "$proxy_link" "$new_tag" 2>&1)
    if [[ $? -ne 0 || -z "$parsed_json" ]] || ! echo "$parsed_json" | jq . >/dev/null 2>&1; then
        echo -e "${aol_msgs[err_parse_$language]}"
        echo "Details: $parsed_json"
        echo ""
        return 1
    fi

    cp -f /etc/sing-box/config.json /etc/sing-box/config.json.bak-outbound
    echo "$(jq --argjson o "$parsed_json" '.outbounds += [$o]' /etc/sing-box/config.json)" > /etc/sing-box/config.json

    local check_ok=""
    if command -v sing-box >/dev/null 2>&1; then
        sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1 && check_ok="true"
    else
        jq . /etc/sing-box/config.json >/dev/null 2>&1 && check_ok="true"
    fi

    if [[ "$check_ok" == "true" ]]; then
        rm -f /etc/sing-box/config.json.bak-outbound
        reload_sing_box
        printf "${aol_msgs[success_$language]}\n" "$new_tag"
        echo ""
    else
        cp -f /etc/sing-box/config.json.bak-outbound /etc/sing-box/config.json
        rm -f /etc/sing-box/config.json.bak-outbound
        echo -e "${aol_msgs[err_check_$language]}"
        echo ""
        return 1
    fi
}

add_outbound_by_interface() {
    declare -A -g aoi_msgs=()
    aoi_msgs[iface_prompt_ru]="${textcolor}[?]${clear} Введите имя сетевого интерфейса (например: wg0, tun0, tailscale0) или x для отмены:"
    aoi_msgs[iface_prompt_en]="${textcolor}[?]${clear} Enter network interface name (e.g., wg0, tun0, tailscale0) or x to cancel:"
    aoi_msgs[tag_prompt_ru]="${textcolor}[?]${clear} Введите тег для outbound [нажмите Enter для %s]:"
    aoi_msgs[tag_prompt_en]="${textcolor}[?]${clear} Enter tag for outbound [press Enter for %s]:"
    aoi_msgs[warn_iface_ru]="${yellow}Внимание: интерфейс '%s' не обнаружен в системе (ip link). Продолжить? [y/N]:${clear}"
    aoi_msgs[warn_iface_en]="${yellow}Warning: interface '%s' not found on system (ip link). Continue anyway? [y/N]:${clear}"
    aoi_msgs[err_exists_ru]="${red}Ошибка: outbound с таким тегом уже существует${clear}"
    aoi_msgs[err_exists_en]="${red}Error: an outbound with this tag already exists${clear}"
    aoi_msgs[success_ru]="Интерфейс-outbound ${textcolor}%s${clear} успешно добавлен на сервер!"
    aoi_msgs[success_en]="Interface outbound ${textcolor}%s${clear} successfully added to the server!"

    echo -e "${aoi_msgs[iface_prompt_$language]}"
    read -r iface_name
    [[ -n $iface_name ]] && echo ""
    [[ ${iface_name,,} =~ ^(x|х|q)$ || -z "$iface_name" ]] && return 0
    iface_name=$(echo "$iface_name" | tr -d '[:space:]')

    if ! ip link show "$iface_name" >/dev/null 2>&1; then
        printf "${aoi_msgs[warn_iface_$language]}\n" "$iface_name"
        read -r iface_confirm
        [[ -n $iface_confirm ]] && echo ""
        [[ ! ${iface_confirm,,} =~ ^(y|yes|д|да)$ ]] && return 0
    fi

    local def_tag="${iface_name}-out"
    printf "${aoi_msgs[tag_prompt_$language]}\n" "$def_tag"
    read -r iface_tag
    [[ -n $iface_tag ]] && echo ""
    [[ -z "$iface_tag" ]] && iface_tag="$def_tag"
    iface_tag=$(echo "$iface_tag" | tr -d '[:space:]')
    [[ "$iface_tag" != *-out ]] && iface_tag="${iface_tag}-out"

    if [[ $(jq --arg t "$iface_tag" '[(.outbounds // [])[].tag] | index($t) != null' /etc/sing-box/config.json 2>/dev/null) == "true" ]]; then
        echo -e "${aoi_msgs[err_exists_$language]}"
        echo ""
        return 1
    fi

    local iface_json
    iface_json=$(jq -cn --arg t "$iface_tag" --arg iface "$iface_name" '{type: "direct", tag: $t, bind_interface: $iface}')

    cp -f /etc/sing-box/config.json /etc/sing-box/config.json.bak-outbound
    echo "$(jq --argjson o "$iface_json" '.outbounds += [$o]' /etc/sing-box/config.json)" > /etc/sing-box/config.json

    local check_ok=""
    if command -v sing-box >/dev/null 2>&1; then
        sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1 && check_ok="true"
    else
        jq . /etc/sing-box/config.json >/dev/null 2>&1 && check_ok="true"
    fi

    if [[ "$check_ok" == "true" ]]; then
        rm -f /etc/sing-box/config.json.bak-outbound
        reload_sing_box
        printf "${aoi_msgs[success_$language]}\n" "$iface_tag"
        echo ""
    else
        cp -f /etc/sing-box/config.json.bak-outbound /etc/sing-box/config.json
        rm -f /etc/sing-box/config.json.bak-outbound
        echo -e "${aol_msgs[err_check_$language]}"
        echo ""
        return 1
    fi
}

add_outbound_manually() {
    declare -A -g aom_msgs=()
    aom_msgs[proto_prompt_ru]="${textcolor}[?]${clear} Выберите тип прокси:\n1 - SOCKS5\n2 - HTTP\n0 - Отмена"
    aom_msgs[proto_prompt_en]="${textcolor}[?]${clear} Select proxy type:\n1 - SOCKS5\n2 - HTTP\n0 - Cancel"
    aom_msgs[host_prompt_ru]="${textcolor}[?]${clear} Введите IP или домен сервера:"
    aom_msgs[host_prompt_en]="${textcolor}[?]${clear} Enter server IP or domain:"
    aom_msgs[port_prompt_ru]="${textcolor}[?]${clear} Введите порт:"
    aom_msgs[port_prompt_en]="${textcolor}[?]${clear} Enter port:"
    aom_msgs[user_prompt_ru]="${textcolor}[?]${clear} Введите имя пользователя (или нажмите Enter, если без пароля):"
    aom_msgs[user_prompt_en]="${textcolor}[?]${clear} Enter username (or press Enter if no auth):"
    aom_msgs[pass_prompt_ru]="${textcolor}[?]${clear} Введите пароль:"
    aom_msgs[pass_prompt_en]="${textcolor}[?]${clear} Enter password:"
    aom_msgs[tag_prompt_ru]="${textcolor}[?]${clear} Введите тег (например: custom-proxy или proxy-out):"
    aom_msgs[tag_prompt_en]="${textcolor}[?]${clear} Enter tag (e.g., custom-proxy or proxy-out):"
    aom_msgs[success_ru]="Outbound ${textcolor}%s${clear} успешно добавлен на сервер!"
    aom_msgs[success_en]="Outbound ${textcolor}%s${clear} successfully added to the server!"

    echo -e "${aom_msgs[proto_prompt_$language]}"
    read -r proto_sel
    [[ -n $proto_sel ]] && echo ""
    local o_type="socks"
    case "$proto_sel" in
        1) o_type="socks" ;;
        2) o_type="http" ;;
        *) return 0 ;;
    esac

    echo -e "${aom_msgs[host_prompt_$language]}"
    read -r m_host
    [[ -n $m_host ]] && echo ""
    [[ -z "$m_host" ]] && return 0

    echo -e "${aom_msgs[port_prompt_$language]}"
    read -r m_port
    [[ -n $m_port ]] && echo ""
    [[ ! "$m_port" =~ ^[0-9]+$ ]] && return 0

    echo -e "${aom_msgs[user_prompt_$language]}"
    read -r m_user
    [[ -n $m_user ]] && echo ""

    local m_pass=""
    if [[ -n "$m_user" ]]; then
        echo -e "${aom_msgs[pass_prompt_$language]}"
        read -r m_pass
        [[ -n $m_pass ]] && echo ""
    fi

    echo -e "${aom_msgs[tag_prompt_$language]}"
    read -r m_tag
    [[ -n $m_tag ]] && echo ""
    [[ -z "$m_tag" ]] && return 0
    m_tag=$(echo "$m_tag" | tr -d '[:space:]')
    [[ "$m_tag" != *-out ]] && m_tag="${m_tag}-out"

    if [[ $(jq --arg t "$m_tag" '[(.outbounds // [])[].tag] | index($t) != null' /etc/sing-box/config.json 2>/dev/null) == "true" ]]; then
        echo -e "${aol_msgs[err_exists_$language]}"
        echo ""
        return 1
    fi

    local m_json
    m_json=$(jq -cn --arg t "$m_tag" --arg tp "$o_type" --arg s "$m_host" --argjson p "$m_port" --arg u "$m_user" --arg pw "$m_pass" '
        {type: $tp, tag: $t, server: $s, server_port: $p} +
        (if ($u | length) > 0 then {username: $u} else {} end) +
        (if ($pw | length) > 0 then {password: $pw} else {} end)
    ')

    cp -f /etc/sing-box/config.json /etc/sing-box/config.json.bak-outbound
    echo "$(jq --argjson o "$m_json" '.outbounds += [$o]' /etc/sing-box/config.json)" > /etc/sing-box/config.json

    local check_ok=""
    if command -v sing-box >/dev/null 2>&1; then
        sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1 && check_ok="true"
    else
        jq . /etc/sing-box/config.json >/dev/null 2>&1 && check_ok="true"
    fi

    if [[ "$check_ok" == "true" ]]; then
        rm -f /etc/sing-box/config.json.bak-outbound
        reload_sing_box
        printf "${aom_msgs[success_$language]}\n" "$m_tag"
        echo ""
    else
        cp -f /etc/sing-box/config.json.bak-outbound /etc/sing-box/config.json
        rm -f /etc/sing-box/config.json.bak-outbound
        echo -e "${aol_msgs[err_check_$language]}"
        echo ""
        return 1
    fi
}

delete_custom_outbound() {
    declare -A -g dco_msgs=()
    dco_msgs[no_custom_ru]="Нет добавленных пользовательских outbound для удаления"
    dco_msgs[no_custom_en]="No custom outbounds available to delete"
    dco_msgs[prompt_ru]="${textcolor}[?]${clear} Выберите outbound для удаления или 0 для отмены:"
    dco_msgs[prompt_en]="${textcolor}[?]${clear} Select an outbound to delete or 0 to cancel:"
    dco_msgs[warn_users_ru]="${yellow}Внимание: следующие пользователи используют outbound '%s':\n%s\nИх выходная нода будет переключена на 'direct'. Продолжить? [y/N]:${clear}"
    dco_msgs[warn_users_en]="${yellow}Warning: the following users are using outbound '%s':\n%s\nTheir outbound node will be reverted to 'direct'. Continue? [y/N]:${clear}"
    dco_msgs[success_ru]="Outbound ${textcolor}%s${clear} успешно удалён"
    dco_msgs[success_en]="Outbound ${textcolor}%s${clear} successfully deleted"

    local custom_tags=()
    for t in $(jq -r '.outbounds[]?.tag' /etc/sing-box/config.json 2>/dev/null); do
        if [[ "$t" != "direct" && "$t" != "warp" && "$t" != "proxy" && "$t" != "IPv4" && "$t" != "block" && -n "$t" ]]; then
            custom_tags+=("$t")
        fi
    done

    if [[ ${#custom_tags[@]} -eq 0 ]]; then
        echo -e "${dco_msgs[no_custom_$language]}"
        echo ""
        return 0
    fi

    echo -e "${dco_msgs[prompt_$language]}"
    echo "0 - Отмена"
    for idx in "${!custom_tags[@]}"; do
        local num=$((idx + 1))
        local t="${custom_tags[$idx]}"
        local otype osrv oport oiface desc=""
        otype=$(jq -r --arg t "$t" '.outbounds[] | select(.tag == $t) | .type' /etc/sing-box/config.json 2>/dev/null)
        osrv=$(jq -r --arg t "$t" '.outbounds[] | select(.tag == $t) | .server // empty' /etc/sing-box/config.json 2>/dev/null)
        oport=$(jq -r --arg t "$t" '.outbounds[] | select(.tag == $t) | .server_port // empty' /etc/sing-box/config.json 2>/dev/null)
        oiface=$(jq -r --arg t "$t" '.outbounds[] | select(.tag == $t) | .bind_interface // empty' /etc/sing-box/config.json 2>/dev/null)
        if [[ -n "$osrv" ]]; then
            desc="(${otype}, ${osrv}:${oport})"
        elif [[ -n "$oiface" ]]; then
            desc="(${otype}, iface: ${oiface})"
        else
            desc="(${otype})"
        fi
        echo "${num} - ${t} ${desc}"
    done

    read -r del_sel
    [[ -n $del_sel ]] && echo ""
    [[ "$del_sel" == "0" || ${del_sel,,} =~ ^(x|х|q)$ ]] && return 0

    if [[ "$del_sel" =~ ^[0-9]+$ ]] && [[ "$del_sel" -ge 1 && "$del_sel" -le "${#custom_tags[@]}" ]]; then
        local del_tag="${custom_tags[$((del_sel - 1))]}"

        local affected_users=""
        local valid_users
        valid_users=$(jq -r '[(.inbounds[]?.users // [])[].name] | unique[]' /etc/sing-box/config.json 2>/dev/null)
        for u in $valid_users; do
            local un
            un=$(get_user_node "$u")
            if [[ "$un" == "$del_tag" ]]; then
                affected_users+="  - ${u}\n"
            fi
        done

        if [[ -n "$affected_users" ]]; then
            printf "${dco_msgs[warn_users_$language]}\n" "$del_tag" "$affected_users"
            read -r confirm_del
            [[ -n $confirm_del ]] && echo ""
            [[ ! ${confirm_del,,} =~ ^(y|yes|д|да)$ ]] && return 0

            if [[ -f /etc/secret-sing-box/user-routes ]]; then
                sed -i "s/:${del_tag}:/:direct:/g" /etc/secret-sing-box/user-routes
            fi
        fi

        echo "$(jq --arg t "$del_tag" 'del(.outbounds[] | select(.tag == $t))' /etc/sing-box/config.json)" > /etc/sing-box/config.json
        apply_user_routing

        printf "${dco_msgs[success_$language]}\n" "$del_tag"
        echo ""
    fi
}

outbounds_menu() {
    declare -A -g ob_title=()
    ob_title[ru]="${textcolor}Управление выходными серверами (Outbound):${clear}"
    ob_title[en]="${textcolor}Outbound nodes management:${clear}"

    declare -A -g ob_actions=()
    ob_actions[ru]="${textcolor}Выберите действие:${clear}
0 - Назад в главное меню
1 - Добавить outbound по ссылке (vless://, vmess://, trojan://, ss://, socks5://, http://)
2 - Добавить outbound через интерфейс / туннель (WireGuard wg0, tun и др.)
3 - Добавить outbound вручную (SOCKS5 / HTTP прокси)
4 - Удалить добавленный outbound"

    ob_actions[en]="${textcolor}Select an action:${clear}
0 - Back to main menu
1 - Add outbound via proxy link (vless://, vmess://, trojan://, ss://, socks5://, http://)
2 - Add outbound via interface / tunnel (WireGuard wg0, tun, etc.)
3 - Add outbound manually (SOCKS5 / HTTP proxy)
4 - Delete custom outbound"

    while true
    do
        echo ""
        echo -e "${ob_title[$language]}"
        echo "--------------------------------------------------------------------------------"
        show_outbounds_table
        echo "--------------------------------------------------------------------------------"
        echo -e "${ob_actions[$language]}"
        read -r ob_choice
        [[ -n $ob_choice ]] && echo ""

        case $ob_choice in
            0|x|х)
            main_menu
            return
            ;;
            1)
            add_outbound_by_link
            ;;
            2)
            add_outbound_by_interface
            ;;
            3)
            add_outbound_manually
            ;;
            4)
            delete_custom_outbound
            ;;
            *)
            continue
            ;;
        esac
    done
}

### OPTION 5 - SYNCHRONIZE SETTINGS IN CLIENT CONFIGS ###

exit_sync() {
    if [[ ${sync,,} =~ ^(x|х)$ ]]
    then
        sync=""
        main_menu
    fi
}

check_users() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: пользователи отсутствуют${clear}"
    check_message[1_en]="${red}Error: no users found${clear}"

    if [[ $(ls -A1 /var/www/${subspath} | grep "\-CLIENT.json" | wc -l) -eq 0 ]]
    then
        echo -e "${check_message[1_$language]}"
        echo ""
        main_menu
    fi
}

get_pass() {
    if grep -q ': "trojan"' ${file}
    then
        trjpass=$(jq -r '.outbounds[] | select(.tag == "proxy") | .password' ${file})
        uuid=""
    else
        uuid=$(jq -r '.outbounds[] | select(.tag == "proxy") | .uuid' ${file})
        trjpass=""
    fi

    stack=$(jq -r '.inbounds[] | select(.tag == "tun-in") | .stack' ${file})
    [[ $(jq '.outbounds[] | select(.tag == "proxy") | .transport | has("headers")' ${file}) == "true" ]] && cf_ip=$(jq -r '.outbounds[] | select(.tag == "proxy") | .server' ${file})
}

edit_configs_loop() {
    for file in /var/www/${subspath}/*-CLIENT.json
    do
        get_pass
        cp -f /var/www/${subspath}/${sync_template_file} ${file}

        if [[ "$sync_template_file" == "template.json" ]]
        then
            sed -i -e "s/${tempdomain}/${domain}/g" -e "s/${temprulesetpath}/${rulesetpath}/g" ${file}
            [[ -n $tempip ]] && sed -i -e "s/${tempip}/${server_ip}/g" ${file}
        else
            sed -i -e "s/${loc_tempdomain}/${domain}/g" -e "s/${loc_temprulesetpath}/${rulesetpath}/g" ${file}
            [[ -n $loc_tempip ]] && sed -i -e "s/${loc_tempip}/${server_ip}/g" ${file}
        fi

        if [[ -f /etc/haproxy/auth.lua ]]
        then
            echo "$(jq ".inbounds[${inbound_num}].stack = \"${stack}\" | .outbounds[${outbound_num}].password = \"${trjpass}\"" ${file})" > ${file}
        elif [[ ! -f /etc/haproxy/auth.lua ]] && [[ -n $trjpass ]]
        then
            echo "$(jq ".inbounds[${inbound_num}].stack = \"${stack}\" | .outbounds[${outbound_num}].password = \"${trjpass}\" | .outbounds[${outbound_num}].transport.path = \"/${trojanpath}\"" ${file})" > ${file}
        else
            echo "$(jq ".inbounds[${inbound_num}].stack = \"${stack}\" | .outbounds[${outbound_num}].type = \"vless\" | .outbounds[${outbound_num}] |= with_entries(.key |= if . == \"password\" then \"uuid\" else . end) | .outbounds[${outbound_num}].uuid = \"${uuid}\" | .outbounds[${outbound_num}].transport.path = \"/${vlesspath}\"" ${file})" > ${file}
        fi

        [[ -n $cf_ip ]] && echo "$(jq ".outbounds[${outbound_num}].server = \"${cf_ip}\" | .outbounds[${outbound_num}].transport.headers |= {\"Host\":\"${domain}\"} | .route.rule_set[].download_detour = \"proxy\"" ${file})" > ${file}
        cf_ip=""
    done
}

add_rule_sets_loop() {
    for ruleset_ind in $(seq 0 $(jq '.route.rule_set | length - 1' /var/www/${subspath}/${sync_template_file}))
    do
        ruleset=$(jq -r ".route.rule_set[${ruleset_ind}].url" /var/www/${subspath}/${sync_template_file} | cut -d "/" -f 5)
        [[ -f /var/www/${rulesetpath}/${ruleset} ]] && continue
        if [[ $ruleset == geoip-* ]]
        then
            wget -q -P /var/www/${rulesetpath} https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/${ruleset}
        elif [[ $ruleset == geosite-ru-blocked* ]]
        then
            wget -q -P /var/www/${rulesetpath} https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/${ruleset}
        else
            wget -q -P /var/www/${rulesetpath} https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/${ruleset}
        fi
    done
}

sync_client_configs_main() {
    declare -A -g info_message=()
    info_message[1_ru]="Синхронизация настроек с GitHub завершена"
    info_message[1_en]="Synchronization of the settings with GitHub is completed"

    if [[ "$sync_template_file" == "template-loc.json" ]]
    then
        info_message[1_ru]="Синхронизация настроек с локальным шаблоном завершена"
        info_message[1_en]="Synchronization of the settings with local template is completed"

        loc_temprulesetpath=$(jq -r '.route.rule_set[-1].url // "missing_value"' /var/www/${subspath}/template-loc.json | cut -d "/" -f 4)
        loc_tempdomain=$(jq -r '.outbounds[] | select(.tag == "proxy") | .server' /var/www/${subspath}/template-loc.json)
        loc_tempip=$(jq -r '.route.rules[] | select(has("ip_cidr")) | .ip_cidr[0]' /var/www/${subspath}/template-loc.json)
        [[ -z $loc_tempip ]] && loc_tempip="missing_value"
    fi

    inbound_num=$(jq '[.inbounds[].tag] | index("tun-in")' /var/www/${subspath}/${sync_template_file})
    outbound_num=$(jq '[.outbounds[].tag] | index("proxy")' /var/www/${subspath}/${sync_template_file})
    edit_configs_loop

    if [[ $(jq '.route.rule_set | length' /var/www/${subspath}/${sync_template_file}) =~ ^[1-9][0-9]*$ ]]
    then
        add_rule_sets_loop
        chmod -R 755 /var/www/${rulesetpath}
    fi

    echo "${info_message[1_$language]}"
    echo ""
}

sync_github_text_ru() {
    echo -e "${red}ВНИМАНИЕ!${clear}"
    echo "Настройки в клиентских конфигах всех пользователей будут синхронизированы с последней версией на GitHub:"
    echo "https://github.com/zipfo/Simple-Sing-Box/blob/main/Config-Templates/client.json"
    echo ""
    echo -e "${textcolor}[?]${clear} Нажмите ${textcolor}Enter${clear}, чтобы синхронизировать настройки, или введите ${textcolor}x${clear}, чтобы выйти:"
    read -r sync
    [[ -n $sync ]] && echo ""
}

sync_github_text_en() {
    echo -e "${red}ATTENTION!${clear}"
    echo "The settings in client configs of all users will be synchronized with the latest version on GitHub:"
    echo "https://github.com/zipfo/Simple-Sing-Box/blob/main/Config-Templates/client.json"
    echo ""
    echo -e "${textcolor}[?]${clear} Press ${textcolor}Enter${clear} to synchronize the settings or enter ${textcolor}x${clear} to exit:"
    read -r sync
    [[ -n $sync ]] && echo ""
}

sync_local_text_ru() {
    echo -e "${red}ВНИМАНИЕ!${clear}"
    echo -e "Вы можете вручную отредактировать настройки в шаблоне ${textcolor}/var/www/${subspath}/template-loc.json${clear}"
    echo "Настройки в этом файле будут применены к клиентским конфигам всех пользователей"
    echo "При редактировании не меняйте значения \"tag\" у \"inbounds\" и \"outbounds\""
    echo ""
    echo -e "${textcolor}[?]${clear} Нажмите ${textcolor}Enter${clear}, чтобы синхронизировать настройки, или введите ${textcolor}x${clear}, чтобы выйти:"
    read -r sync
    [[ -n $sync ]] && echo ""
}

sync_local_text_en() {
    echo -e "${red}ATTENTION!${clear}"
    echo -e "You can manually edit the settings in ${textcolor}/var/www/${subspath}/template-loc.json${clear} template"
    echo "The settings in this file will be applied to client configs of all users"
    echo "Do not change \"tag\" values in \"inbounds\" and \"outbounds\" while editing"
    echo ""
    echo -e "${textcolor}[?]${clear} Press ${textcolor}Enter${clear} to synchronize the settings or enter ${textcolor}x${clear} to exit:"
    read -r sync
    [[ -n $sync ]] && echo ""
}

sync_text_ru() {
    echo -e "${textcolor}[?]${clear} Выберите вариант синхронизации:"
    echo "0 - Выйти"
    echo "1 - Синхронизировать с GitHub"
    echo "2 - Синхронизировать с локальным шаблоном (свои настройки)"
    read -r sync_option
    [[ -n $sync_option ]] && echo ""
}

sync_text_en() {
    echo -e "${textcolor}[?]${clear} Select synchronisation option:"
    echo "0 - Exit"
    echo "1 - Sync with GitHub"
    echo "2 - Sync with local template (custom settings)"
    read -r sync_option
    [[ -n $sync_option ]] && echo ""
}

sync_options() {
    case $sync_option in
        1)
        sync_variant="github"
        sync_template_file="template.json"
        ;;
        2)
        sync_variant="local"
        sync_template_file="template-loc.json"
        ;;
        *)
        main_menu
    esac
}

sync_client_configs() {
    sync_text_${language}
    sync_options
    sync_${sync_variant}_text_${language}
    exit_sync
    check_users
    check_${sync_variant}_template
    sync_client_configs_main
    main_menu
}

### OPTION 6 - SETUP CONNECTION TO CUSTOM CLOUDFLARE IP ###

check_variant() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: этот пункт только для вариантов настройки с транспортом WebSocket или HTTPUpgrade${clear}"
    check_message[1_en]="${red}Error: this option is only available for the setup variants with WebSocket or HTTPUpgrade transport${clear}"

    if [[ -f /etc/haproxy/auth.lua ]]
    then
        echo -e "${check_message[1_$language]}"
        echo ""
        main_menu
    fi
}

check_cf_option() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: IP Cloudflare итак не указан в конфиге этого пользователя${clear}"
    check_message[1_en]="${red}Error: the config file of this user does not contain Cloudflare IP anyway${clear}"

    while [[ "$cf_option" == "2" ]] && [[ $(jq '.outbounds[] | select(.tag == "proxy") | .transport | has("headers")' /var/www/${subspath}/${username}-TRJ-CLIENT.json) != "true" ]]
    do
        echo -e "${check_message[1_$language]}"
        echo ""
        cf_text_${language}
    done
}

check_cf_ip() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: введённое значение не является IP${clear}"
    check_message[2_ru]="${textcolor}[?]${clear} Введите выбранный IP Cloudflare:"
    check_message[1_en]="${red}Error: the entered value is not an IP${clear}"
    check_message[2_en]="${textcolor}[?]${clear} Enter the custom Cloudflare IP:"

    while [[ ! $cf_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
    do
        if [[ -n $cf_ip ]]
        then
            echo -e "${check_message[1_$language]}"
            echo ""
        fi
        echo -e "${check_message[2_$language]}"
        read -r cf_ip
        [[ -n $cf_ip ]] && echo ""
    done
}

enter_cf_ip() {
    declare -A -g input_message=()
    input_message[1_ru]="${textcolor}[?]${clear} Введите выбранный IP Cloudflare:"
    input_message[1_en]="${textcolor}[?]${clear} Enter the custom Cloudflare IP:"

    echo -e "${input_message[1_$language]}"
    read -r cf_ip
    [[ -n $cf_ip ]] && echo ""
    check_cf_ip
}

set_cf_ip() {
    declare -A -g info_message=()
    info_message[1_ru]="Изменение настроек для пользователя ${textcolor}${username}${clear} завершено, установлен IP ${textcolor}${cf_ip}${clear}"
    info_message[1_en]="Changed the settings for the user ${textcolor}${username}${clear}, IP ${textcolor}${cf_ip}${clear} has been set"

    for protocol in 'TRJ' 'VLESS'
    do
        [[ "$protocol" == "VLESS" ]] && [[ -f /etc/haproxy/auth.lua ]] && break
        outbound_num=$(jq '[.outbounds[].tag] | index("proxy")' /var/www/${subspath}/${username}-${protocol}-CLIENT.json)
        echo "$(jq ".outbounds[${outbound_num}].server = \"${cf_ip}\" | .outbounds[${outbound_num}].transport.headers |= {\"Host\":\"${domain}\"} | .route.rule_set[].download_detour = \"proxy\"" /var/www/${subspath}/${username}-${protocol}-CLIENT.json)" > /var/www/${subspath}/${username}-${protocol}-CLIENT.json
    done

    echo -e "${info_message[1_$language]}"
    cf_ip=""
    echo ""
}

remove_cf_ip() {
    declare -A -g info_message=()
    info_message[1_ru]="Изменение настроек для пользователя ${textcolor}${username}${clear} завершено, IP Cloudflare убран"
    info_message[1_en]="Changed the settings for the user ${textcolor}${username}${clear}, Cloudflare IP is removed"

    for protocol in 'TRJ' 'VLESS'
    do
        [[ "$protocol" == "VLESS" ]] && [[ -f /etc/haproxy/auth.lua ]] && break
        outbound_num=$(jq '[.outbounds[].tag] | index("proxy")' /var/www/${subspath}/${username}-${protocol}-CLIENT.json)
        echo "$(jq ".outbounds[${outbound_num}].server = \"${domain}\" | del(.outbounds[${outbound_num}].transport.headers, .route.rule_set[].download_detour)" /var/www/${subspath}/${username}-${protocol}-CLIENT.json)" > /var/www/${subspath}/${username}-${protocol}-CLIENT.json
    done

    echo -e "${info_message[1_$language]}"
    echo ""
}

get_cf_ip_status() {
    declare -A -g info_message=()
    info_message[1_ru]="[IP Cloudflare не выбран]"
    info_message[2_ru]="Выбрано:"
    info_message[1_en]="[Cloudflare IP is not selected]"
    info_message[2_en]="Selected:"

    sel_cf_ip=$(jq -r '.outbounds[] | select(.tag == "proxy") | .server' /var/www/${subspath}/${username}-TRJ-CLIENT.json)
    cf_ip_status="${info_message[1_$language]}"
    [[ $sel_cf_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && cf_ip_status="[${info_message[2_$language]} ${sel_cf_ip}]"
}

cf_warn_ru() {
    echo -e "${red}ВНИМАНИЕ!${clear}"
    echo "Этот пункт рекомендуется в случае недоступности IP, который Cloudflare выделил вашему домену для проксирования"
    echo "Нужно просканировать диапазоны IP Cloudflare с вашего устройства и самостоятельно выбрать оптимальный IP"
    echo "Инструкция: https://github.com/zipfo/Simple-Sing-Box/blob/main/.github/cf-scan-ip-ru.md"
    echo ""
}

cf_warn_en() {
    echo -e "${red}ATTENTION!${clear}"
    echo "This option is recommended in case of unavailability of the IP that Cloudflare allocated to your domain for proxying"
    echo "You need to scan Cloudflare IP ranges from your device and choose the optimal IP by yourself"
    echo "Instruction: https://github.com/zipfo/Simple-Sing-Box/blob/main/.github/cf-scan-ip-en.md"
    echo ""
}

cf_text_ru() {
    echo -e "${textcolor}[?]${clear} Выберите опцию для пользователя ${textcolor}${username}${clear}:"
    echo "0 - Выйти"
    echo "1 - Настроить/сменить выбранный IP Cloudflare   ${cf_ip_status}"
    echo "2 - Убрать выбранный IP Cloudflare"
    read -r cf_option
    [[ -n $cf_option ]] && echo ""
}

cf_text_en() {
    echo -e "${textcolor}[?]${clear} Select an option for the user ${textcolor}${username}${clear}:"
    echo "0 - Exit"
    echo "1 - Setup/change custom Cloudflare IP   ${cf_ip_status}"
    echo "2 - Remove custom Cloudflare IP"
    read -r cf_option
    [[ -n $cf_option ]] && echo ""
}

cf_ip_settings() {
    check_variant
    cf_warn_${language}

    while [[ ! ${username,,} =~ ^(x|х)$ ]]
    do
        enter_user_data_del
        get_cf_ip_status
        cf_text_${language}
        check_cf_option

        case $cf_option in
            1)
            enter_cf_ip
            set_cf_ip
            ;;
            2)
            remove_cf_ip
            ;;
            *)
            main_menu
        esac
    done
}

### OPTION 7 - SHOW WARP DOMAINS ###

check_warp() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: в /etc/sing-box/config.json не найдено правил маршрутизации для WARP${clear}"
    check_message[1_en]="${red}Error: no WARP routing rules found in /etc/sing-box/config.json${clear}"

    if [[ $(jq 'any(.route.rules[]; .outbound == "warp")' /etc/sing-box/config.json) != "true" ]]
    then
        echo -e "${check_message[1_$language]}"
        echo ""
        main_menu
    fi
}

show_warp_domains() {
    declare -A -g info_message=()
    info_message[1_ru]="${textcolor}Список доменов/суффиксов WARP:${clear}"
    info_message[1_en]="${textcolor}List of domains/suffixes routed through WARP:${clear}"

    check_warp
    echo -e "${info_message[1_$language]}"
    jq -r '.route.rules[] | select(.outbound == "warp" and (has("auth_user") | not)) | .domain_suffix[]' /etc/sing-box/config.json
    echo ""
    main_menu
}

### OPTION 7 - ADD WARP DOMAINS ###

exit_warp_add() {
    if [[ ${new_warp,,} =~ ^(x|х)$ ]]
    then
        new_warp=""
        main_menu
    fi
}

crop_new_warp() {
    new_warp=${new_warp#*"://"}
    new_warp=$(echo "${new_warp}" | cut -d "/" -f 1)
}

check_domain_warp_add() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: этот домен/суффикс уже добавлен в WARP${clear}"
    check_message[2_ru]="${textcolor}[?]${clear} Введите новый домен/суффикс для WARP или введите ${textcolor}x${clear}, чтобы закончить:"
    check_message[1_en]="${red}Error: this domain/suffix is already added to WARP${clear}"
    check_message[2_en]="${textcolor}[?]${clear} Enter a new domain/suffix for WARP routing or enter ${textcolor}x${clear} to exit:"

    while [[ -z $new_warp ]] || [[ $(jq "any(.route.rules[] | select(.outbound == \"warp\" and (has(\"auth_user\") | not)) | .domain_suffix[]; . == \"${new_warp}\")" /etc/sing-box/config.json) != "false" ]]
    do
        if [[ -n $new_warp ]]
        then
            echo -e "${check_message[1_$language]}"
            echo ""
        fi
        echo -e "${check_message[2_$language]}"
        read -r new_warp
        [[ -n $new_warp ]] && echo ""
        exit_warp_add
        crop_new_warp
    done
}

enter_domain_warp_add() {
    declare -A -g input_message=()
    input_message[1_ru]="${textcolor}[?]${clear} Введите новый домен/суффикс для WARP или введите ${textcolor}x${clear}, чтобы закончить:"
    input_message[1_en]="${textcolor}[?]${clear} Enter a new domain/suffix for WARP routing or enter ${textcolor}x${clear} to exit:"

    echo -e "${input_message[1_$language]}"
    read -r new_warp
    [[ -n $new_warp ]] && echo ""
    exit_warp_add
    crop_new_warp
    check_domain_warp_add
}

edit_conf_warp_add() {
    declare -A -g info_message=()
    info_message[1_ru]="Домен/суффикс ${textcolor}${new_warp}${clear} добавлен в WARP"
    info_message[1_en]="Domain/suffix ${textcolor}${new_warp}${clear} is added to WARP routing"

    warp_rule_num=$(jq '[.route.rules[] | (.outbound == "warp" and (has("auth_user") | not))] | index(true)' /etc/sing-box/config.json)
    echo "$(jq ".route.rules[${warp_rule_num}].domain_suffix += [\"${new_warp}\"]" /etc/sing-box/config.json)" > /etc/sing-box/config.json
    reload_sing_box
    echo -e "${info_message[1_$language]}"
    echo ""
}

add_warp_domains() {
    check_warp

    while [[ ! ${new_warp,,} =~ ^(x|х)$ ]]
    do
        enter_domain_warp_add
        edit_conf_warp_add
    done
}

### OPTION 8 - DELETE WARP DOMAINS ###

exit_warp_del() {
    if [[ ${del_warp,,} =~ ^(x|х)$ ]]
    then
        del_warp=""
        main_menu
    fi
}

crop_del_warp() {
    del_warp=${del_warp#*"://"}
    del_warp=$(echo "${del_warp}" | cut -d "/" -f 1)
}

check_domain_warp_del() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: этот домен/суффикс не добавлен в WARP${clear}"
    check_message[2_ru]="${textcolor}[?]${clear} Введите домен/суффикс для удаления из WARP или введите ${textcolor}x${clear}, чтобы закончить:"
    check_message[1_en]="${red}Error: this domain/suffix is not added to WARP routing${clear}"
    check_message[2_en]="${textcolor}[?]${clear} Enter a domain/suffix to delete from WARP routing or enter ${textcolor}x${clear} to exit:"

    while [[ -z $del_warp ]] || [[ $(jq "any(.route.rules[] | select(.outbound == \"warp\" and (has(\"auth_user\") | not)) | .domain_suffix[]; . == \"${del_warp}\")" /etc/sing-box/config.json) != "true" ]]
    do
        if [[ -n $del_warp ]]
        then
            echo -e "${check_message[1_$language]}"
            echo ""
        fi
        echo -e "${check_message[2_$language]}"
        read -r del_warp
        [[ -n $del_warp ]] && echo ""
        exit_warp_del
        crop_del_warp
    done
}

enter_domain_warp_del() {
    declare -A -g input_message=()
    input_message[1_ru]="${textcolor}[?]${clear} Введите домен/суффикс для удаления из WARP или введите ${textcolor}x${clear}, чтобы закончить:"
    input_message[1_en]="${textcolor}[?]${clear} Enter a domain/suffix to delete from WARP routing or enter ${textcolor}x${clear} to exit:"

    echo -e "${input_message[1_$language]}"
    read -r del_warp
    [[ -n $del_warp ]] && echo ""
    exit_warp_del
    crop_del_warp
    check_domain_warp_del
}

edit_conf_warp_del() {
    declare -A -g info_message=()
    info_message[1_ru]="Домен/суффикс ${textcolor}${del_warp}${clear} удалён из WARP"
    info_message[1_en]="Domain/suffix ${textcolor}${del_warp}${clear} is deleted from WARP routing"

    warp_rule_num=$(jq '[.route.rules[] | (.outbound == "warp" and (has("auth_user") | not))] | index(true)' /etc/sing-box/config.json)
    echo "$(jq "del(.route.rules[${warp_rule_num}].domain_suffix[] | select(. == \"${del_warp}\"))" /etc/sing-box/config.json)" > /etc/sing-box/config.json
    reload_sing_box
    echo -e "${info_message[1_$language]}"
    echo ""
}

delete_warp_domains() {
    check_warp

    while [[ ! ${del_warp,,} =~ ^(x|х)$ ]]
    do
        enter_domain_warp_del
        edit_conf_warp_del
    done
}

### OPTION 9 - WARP BACKEND MANAGEMENT ###

set_ssb_config_value() {
    local key="$1" value="$2"
    touch /etc/secret-sing-box/config
    if grep -q "^${key}=" /etc/secret-sing-box/config
    then
        sed -i "s|^${key}=.*|${key}=${value}|" /etc/secret-sing-box/config
    else
        echo "${key}=${value}" >> /etc/secret-sing-box/config
    fi
    chmod 600 /etc/secret-sing-box/config
}

warp_test_socks() {
    local trace
    trace=$(curl -s --max-time 20 --socks5-hostname 127.0.0.1:40000 https://cloudflare.com/cdn-cgi/trace 2> /dev/null)
    [[ "$trace" == *"warp=on"* ]]
}

usque_register_account() {
    mkdir -p /etc/warpscout /etc/usque
    chmod 700 /etc/warpscout /etc/usque

    if [[ ! -s /etc/warpscout/account.json ]] || ! jq -e '.masque' /etc/warpscout/account.json > /dev/null 2>&1
    then
        timeout 180 warpscout register -a /etc/warpscout/account.json > /dev/null 2>&1
    fi

    chmod 600 /etc/warpscout/account.json 2>/dev/null
    jq -e '.masque' /etc/warpscout/account.json > /dev/null 2>&1
}

usque_scan_endpoint() {
    local endpoint sni_cmd sni=""
    local -a scan_cmd

    scan_cmd=(timeout 900 warpscout scan -p masque-h2 -P -a /etc/warpscout/account.json -best -conf /etc/usque/config.json -plain)
    endpoint=$("${scan_cmd[@]}" 2> /dev/null | tail -n 1 | tr -d '[:space:]')

    if [[ -z $endpoint ]]
    then
        if [[ "$language" == "ru" ]]
        then
            echo -e "${textcolor_light}Endpoint не найден, подбираем SNI (может занять больше времени)...${clear}"
        else
            echo -e "${textcolor_light}No endpoint found, searching for a working SNI (this can take longer)...${clear}"
        fi
        sni_cmd=$(timeout 1200 warpscout find-sni -p masque-h2 -a /etc/warpscout/account.json -plain 2> /dev/null | tail -n 1)
        sni=$(sed -n 's/.*-masque-sni[ =]\([^ ]*\).*/\1/p' <<< "$sni_cmd")

        if [[ -n $sni_cmd ]]
        then
            scan_cmd=(timeout 900 warpscout scan -p masque-h2 -P -a /etc/warpscout/account.json -best -conf /etc/usque/config.json -plain)
            [[ -n $sni ]] && scan_cmd+=(-masque-sni "$sni")
            endpoint=$("${scan_cmd[@]}" 2> /dev/null | tail -n 1 | tr -d '[:space:]')
        fi
    fi

    [[ -n $endpoint && -s /etc/usque/config.json ]] || return 1
    usque_port=${endpoint##*:}
    [[ $usque_port =~ ^[0-9]+$ ]] || return 1
    usque_endpoint=$endpoint
    usque_sni=$sni
    chmod 600 /etc/usque/config.json
    return 0
}

usque_write_service() {
    local sni_arg=""
    [[ -n $usque_sni ]] && sni_arg="-s ${usque_sni} "

    cat > /etc/systemd/system/usque-warp.service <<EOF
[Unit]
Description=usque WARP (MASQUE HTTP/2 over TCP) SOCKS5 proxy
Documentation=https://github.com/Diniboy1123/usque
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/usque socks -c /etc/usque/config.json -b 127.0.0.1 -p 40000 -P ${usque_port} ${sni_arg}--http2
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
}

usque_wait_ready() {
    local i

    for i in {1..30}
    do
        ss -ltn 2> /dev/null | grep -q "127.0.0.1:40000" && break
        sleep 1
    done

    ss -ltn 2> /dev/null | grep -q "127.0.0.1:40000" || return 1

    for i in {1..3}
    do
        warp_test_socks && return 0
        sleep 3
    done

    return 1
}

warp_status() {
    if [[ "$warp_option" == "2" ]]
    then
        if [[ "$language" == "ru" ]]
        then
            echo -e "${textcolor_light}WARP отключён при установке${clear}"
        else
            echo -e "${textcolor_light}WARP is disabled on this server${clear}"
        fi
        echo ""
        return 0
    fi

    local backend="${warp_backend:-warp-cli}"
    local service_name="warp-svc.service"
    local service_state listener
    [[ "$backend" == "usque" ]] && service_name="usque-warp.service"

    service_state=$(systemctl is-active "$service_name" 2> /dev/null)
    [[ -z $service_state ]] && service_state="unknown"
    ss -ltn 2> /dev/null | grep -q "127.0.0.1:40000" && listener="up" || listener="down"

    echo ""
    if [[ "$language" == "ru" ]]
    then
        echo -e "${textcolor}Состояние WARP:${clear}"
        if [[ "$backend" == "usque" ]]
        then
            echo "  Бэкенд: usque (MASQUE HTTP/2 поверх TCP)"
        else
            echo "  Бэкенд: warp-cli (устаревший)"
        fi
        echo "  Сервис: ${service_name} — ${service_state}"
        echo "  SOCKS 127.0.0.1:40000 — ${listener}"
        echo "  Endpoint: ${usque_endpoint:-неизвестен}"
        echo "  MASQUE порт: ${usque_port:-неизвестен}"
        echo "  SNI: ${usque_sni:-по умолчанию (consumer-masque.cloudflareclient.com)}"
        [[ -f /etc/warpscout/account.json ]] && echo "  Аккаунт: /etc/warpscout/account.json" || echo "  Аккаунт: отсутствует"
        if command -v warp-cli > /dev/null 2>&1
        then
            echo "  Старый warp-cli: установлен"
        else
            echo "  Старый warp-cli: не установлен"
        fi
    else
        echo -e "${textcolor}WARP status:${clear}"
        if [[ "$backend" == "usque" ]]
        then
            echo "  Backend: usque (MASQUE HTTP/2 over TCP)"
        else
            echo "  Backend: warp-cli (legacy)"
        fi
        echo "  Service: ${service_name} — ${service_state}"
        echo "  SOCKS 127.0.0.1:40000 — ${listener}"
        echo "  Endpoint: ${usque_endpoint:-unknown}"
        echo "  MASQUE port: ${usque_port:-unknown}"
        echo "  SNI: ${usque_sni:-default (consumer-masque.cloudflareclient.com)}"
        [[ -f /etc/warpscout/account.json ]] && echo "  Account: /etc/warpscout/account.json" || echo "  Account: missing"
        if command -v warp-cli > /dev/null 2>&1
        then
            echo "  Legacy warp-cli: installed"
        else
            echo "  Legacy warp-cli: not installed"
        fi
    fi
    echo ""
}

warp_test_connection() {
    if [[ "$warp_option" == "2" ]]
    then
        [[ "$language" == "ru" ]] && echo -e "${red}WARP отключён на этом сервере${clear}" || echo -e "${red}WARP is disabled on this server${clear}"
        echo ""
        return 1
    fi

    local trace
    trace=$(curl -s --max-time 25 --socks5-hostname 127.0.0.1:40000 https://cloudflare.com/cdn-cgi/trace 2> /dev/null)

    if [[ "$trace" == *"warp=on"* ]]
    then
        if [[ "$language" == "ru" ]]
        then
            echo -e "${textcolor_light}WARP работает. Проверка через SOCKS5 127.0.0.1:40000:${clear}"
        else
            echo -e "${textcolor_light}WARP is working. Check through SOCKS5 127.0.0.1:40000:${clear}"
        fi
        echo "$trace" | grep -E "^(ip|colo|warp)="
        echo ""
        return 0
    fi

    if [[ "$language" == "ru" ]]
    then
        echo -e "${red}Проверка не пройдена: SOCKS5 127.0.0.1:40000 не вернул warp=on${clear}"
    else
        echo -e "${red}Check failed: SOCKS5 127.0.0.1:40000 did not return warp=on${clear}"
    fi
    echo ""
    return 1
}

warp_rescan() {
    if [[ "$warp_option" == "2" ]]
    then
        [[ "$language" == "ru" ]] && echo -e "${red}WARP отключён на этом сервере${clear}" || echo -e "${red}WARP is disabled on this server${clear}"
        echo ""
        return 1
    fi

    if [[ "${warp_backend:-}" != "usque" ]]
    then
        if [[ "$language" == "ru" ]]
        then
            echo -e "${red}WARP ещё не переведён на usque. Сначала выполните обновление через меню (пункт «Обновить»).${clear}"
        else
            echo -e "${red}WARP has not been migrated to usque yet. Run the update from the menu first.${clear}"
        fi
        echo ""
        return 1
    fi

    if ! command -v usque > /dev/null 2>&1 || ! command -v warpscout > /dev/null 2>&1
    then
        if [[ "$language" == "ru" ]]
        then
            echo -e "${red}usque или warpscout не установлены. Выполните обновление через меню.${clear}"
        else
            echo -e "${red}usque or warpscout is not installed. Run the update from the menu.${clear}"
        fi
        echo ""
        return 1
    fi

    if [[ "$language" == "ru" ]]
    then
        echo -e "${textcolor_light}Пересканирование MASQUE endpoint (может занять несколько минут)...${clear}"
    else
        echo -e "${textcolor_light}Re-scanning the MASQUE endpoint (this may take a few minutes)...${clear}"
    fi

    cp -f /etc/usque/config.json /etc/usque/config.json.bak 2> /dev/null
    cp -f /etc/systemd/system/usque-warp.service /etc/systemd/system/usque-warp.service.bak 2> /dev/null

    if ! usque_register_account || ! usque_scan_endpoint
    then
        if [[ "$language" == "ru" ]]
        then
            echo -e "${red}Не удалось найти рабочий endpoint, текущий конфиг не изменён${clear}"
        else
            echo -e "${red}No working endpoint found, the current config was not changed${clear}"
        fi
        echo ""
        return 1
    fi

    usque_write_service
    systemctl daemon-reload
    systemctl restart usque-warp.service > /dev/null 2>&1

    if usque_wait_ready
    then
        set_ssb_config_value usque_sni "$usque_sni"
        set_ssb_config_value usque_endpoint "$usque_endpoint"
        set_ssb_config_value usque_port "$usque_port"
        if [[ "$language" == "ru" ]]
        then
            echo -e "${textcolor_light}Endpoint обновлён: ${usque_endpoint}${usque_sni:+, SNI: ${usque_sni}}${clear}"
        else
            echo -e "${textcolor_light}Endpoint updated: ${usque_endpoint}${usque_sni:+, SNI: ${usque_sni}}${clear}"
        fi
        echo ""
        return 0
    fi

    journalctl -u usque-warp.service -n 15 --no-pager 2> /dev/null
    [[ -f /etc/usque/config.json.bak ]] && mv -f /etc/usque/config.json.bak /etc/usque/config.json
    [[ -f /etc/systemd/system/usque-warp.service.bak ]] && mv -f /etc/systemd/system/usque-warp.service.bak /etc/systemd/system/usque-warp.service
    systemctl daemon-reload
    systemctl restart usque-warp.service > /dev/null 2>&1

    if [[ "$language" == "ru" ]]
    then
        echo -e "${red}Новый endpoint не работает, восстановлен предыдущий конфиг${clear}"
    else
        echo -e "${red}The new endpoint failed, the previous config has been restored${clear}"
    fi
    echo ""
    return 1
}

warp_remove_legacy() {
    if ! command -v warp-cli > /dev/null 2>&1
    then
        if [[ "$language" == "ru" ]]
        then
            echo -e "${textcolor_light}warp-cli не установлен — удалять нечего${clear}"
        else
            echo -e "${textcolor_light}warp-cli is not installed — nothing to remove${clear}"
        fi
        echo ""
        return 0
    fi

    if [[ "${warp_backend:-}" != "usque" ]]
    then
        if [[ "$language" == "ru" ]]
        then
            echo -e "${red}Сначала переведите WARP на usque (обновление через меню)${clear}"
        else
            echo -e "${red}Migrate WARP to usque first (run the update from the menu)${clear}"
        fi
        echo ""
        return 1
    fi

    if ! warp_test_socks
    then
        if [[ "$language" == "ru" ]]
        then
            echo -e "${red}Проверка WARP не пройдена. Удаление warp-cli отменено, чтобы сохранить возможность отката${clear}"
        else
            echo -e "${red}The WARP check failed. warp-cli removal is cancelled to keep a rollback path${clear}"
        fi
        echo ""
        return 1
    fi

    if [[ "$language" == "ru" ]]
    then
        echo -e "${textcolor}[?]${clear} Удалить неиспользуемый warp-cli? (${textcolor}Enter${clear} — да, ${textcolor}x${clear} — нет):"
    else
        echo -e "${textcolor}[?]${clear} Remove the unused warp-cli? (${textcolor}Enter${clear} — yes, ${textcolor}x${clear} — no):"
    fi
    read -r remove_warp_cli
    [[ -n $remove_warp_cli ]] && echo ""
    if [[ "$remove_warp_cli" == "x" ]]
    then
        return 0
    fi

    apt-mark unhold cloudflare-warp > /dev/null 2>&1
    apt-get purge -y cloudflare-warp > /dev/null 2>&1
    rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg /etc/apt/sources.list.d/cloudflare-client.list
    rm -rf /etc/systemd/system/warp-svc.service.d
    systemctl daemon-reload

    if command -v warp-cli > /dev/null 2>&1
    then
        [[ "$language" == "ru" ]] && echo -e "${red}Не удалось удалить cloudflare-warp${clear}" || echo -e "${red}Could not remove cloudflare-warp${clear}"
    else
        [[ "$language" == "ru" ]] && echo -e "${textcolor_light}warp-cli удалён${clear}" || echo -e "${textcolor_light}warp-cli has been removed${clear}"
    fi
    echo ""
    return 0
}

warp_menu_text_ru() {
    echo ""
    echo -e "${textcolor}Управление WARP:${clear}"
    echo "0 - Назад"
    echo "1 - Показать статус WARP"
    echo "2 - Пересканировать endpoint (warpscout)"
    echo "3 - Проверить соединение"
    echo "4 - Удалить неиспользуемый warp-cli"
    read -r warp_suboption
    [[ -n $warp_suboption ]] && echo ""
}

warp_menu_text_en() {
    echo ""
    echo -e "${textcolor}WARP management:${clear}"
    echo "0 - Back"
    echo "1 - Show WARP status"
    echo "2 - Re-scan endpoint (warpscout)"
    echo "3 - Test connection"
    echo "4 - Remove the unused warp-cli"
    read -r warp_suboption
    [[ -n $warp_suboption ]] && echo ""
}

warp_menu() {
    warp_menu_text_${language}

    case $warp_suboption in
        1)
        warp_status
        warp_menu
        ;;
        2)
        warp_rescan
        warp_menu
        ;;
        3)
        warp_test_connection
        warp_menu
        ;;
        4)
        warp_remove_legacy
        warp_menu
        ;;
        *)
        main_menu
        ;;
    esac
}

### OPTION 10 - SETUP PROXY CHAINS ###

exit_enter_next_link() {
    if [[ ${next_link,,} =~ ^(x|х)$ ]]
    then
        next_link=""
        main_menu
    fi
}

check_chain_option() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: этот сервер уже настроен как конечный в цепочке или единственный${clear}"
    check_message[1_en]="${red}Error: this server is already configured as the end of the chain or the only one${clear}"

    while [[ "$chain_option" == "1" ]] && [[ $(jq 'any(.outbounds[]; .tag == "proxy")' /etc/sing-box/config.json) != "true" ]]
    do
        echo -e "${check_message[1_$language]}"
        echo ""
        chain_text_${language}
    done
}

check_config_temp() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: не удалось загрузить данные с GitHub, попробуйте позже${clear}"
    check_message[1_en]="${red}Error: failed to download data from GitHub, try again later${clear}"

    if [[ -z $config_temp ]] || ! echo "${config_temp}" | jq empty &> /dev/null
    then
        echo -e "${check_message[1_$language]}"
        echo ""
        main_menu
    fi
}

check_next_link() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: неверная ссылка на конфиг или следующий сервер не отвечает${clear}"
    check_message[2_ru]="${textcolor}[?]${clear} Введите ссылку на клиентский конфиг со следующего сервера в цепочке или введите ${textcolor}x${clear}, чтобы выйти:"
    check_message[1_en]="${red}Error: invalid link to client config or the next server does not respond${clear}"
    check_message[2_en]="${textcolor}[?]${clear} Enter the link to client config from the next server in the chain or enter ${textcolor}x${clear} to exit:"

    while [[ -z $next_link ]] || [[ -z $next_config ]] || ! echo "${next_config}" | jq empty &> /dev/null || [[ $(echo "${next_config}" | jq 'any(.outbounds[]; .tag == "proxy")') != "true" ]]
    do
        if [[ -n $next_link ]]
        then
            echo -e "${check_message[1_$language]}"
            echo ""
        fi
        echo -e "${check_message[2_$language]}"
        read -r next_link
        [[ -n $next_link ]] && echo ""
        exit_enter_next_link
        next_config=$(curl -s "${next_link}" 2> /dev/null)
    done
}

enter_chain_data() {
    declare -A -g input_message=()
    input_message[1_ru]="${textcolor}[?]${clear} Введите ссылку на клиентский конфиг со следующего сервера в цепочке или введите ${textcolor}x${clear}, чтобы выйти:"
    input_message[1_en]="${textcolor}[?]${clear} Enter the link to client config from the next server in the chain or enter ${textcolor}x${clear} to exit:"

    echo -e "${input_message[1_$language]}"
    read -r next_link
    [[ -n $next_link ]] && echo ""
    exit_enter_next_link
    next_config=$(curl -s "${next_link}" 2> /dev/null)
    check_next_link
}

manage_rule_sets() {
    for ruleset_tag in "${rule_sets_add[@]}"
    do
        if [[ $(jq "any(.route.rule_set[]; .tag == \"${ruleset_tag}\")" /etc/sing-box/config.json) == "false" ]]
        then
            if [[ $ruleset_tag == geoip-* ]]
            then
                ruleset_data="{\"tag\":\"${ruleset_tag}\",\"type\":\"local\",\"format\":\"binary\",\"path\":\"/var/www/${rulesetpath}/${ruleset_tag}.srs\"}"
            else
                ruleset_data="{\"tag\":\"${ruleset_tag}\",\"type\":\"local\",\"format\":\"binary\",\"path\":\"/var/www/${rulesetpath}/geosite-${ruleset_tag}.srs\"}"
            fi
            echo "$(jq ".route.rule_set += [${ruleset_data}]" /etc/sing-box/config.json)" > /etc/sing-box/config.json
        fi

        if [[ $ruleset_tag == geoip-* ]]
        then
            [[ ! -f /var/www/${rulesetpath}/${ruleset_tag}.srs ]] && wget -q -P /var/www/${rulesetpath} https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/${ruleset_tag}.srs
        elif [[ $ruleset_tag == ru-blocked ]]
        then
            [[ ! -f /var/www/${rulesetpath}/geosite-${ruleset_tag}.srs ]] && wget -q -P /var/www/${rulesetpath} https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/geosite-${ruleset_tag}.srs
        else
            [[ ! -f /var/www/${rulesetpath}/geosite-${ruleset_tag}.srs ]] && wget -q -P /var/www/${rulesetpath} https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-${ruleset_tag}.srs
        fi
    done

    for ruleset_tag in "${rule_sets_del[@]}"
    do
        if [[ $(jq "any(.route.rule_set[]; .tag == \"${ruleset_tag}\")" /etc/sing-box/config.json) == "true" ]]
        then
            echo "$(jq "del(.route.rule_set[] | select(.tag == \"${ruleset_tag}\"))" /etc/sing-box/config.json)" > /etc/sing-box/config.json
        fi
    done

    chmod -R 755 /var/www/${rulesetpath}
}

chain_end() {
    declare -A -g info_message=()
    info_message[1_ru]="Изменение настроек завершено, этот сервер настроен как конечный в цепочке или единственный"
    info_message[1_en]="Settings changed successfully, this server is configured as the end of the chain or the only one"

    if [[ $(jq 'any(.route.rules[]; .outbound == "warp")' /etc/sing-box/config.json) == "true" ]]
    then
        config_temp=$(curl -s https://raw.githubusercontent.com/zipfo/Simple-Sing-Box/main/Config-Templates/config.json)
        check_config_temp
        warp_rule=$(echo "${config_temp}" | jq '.route.rules[] | select(.outbound == "warp")')
        warp_rule_num=$(jq '[.route.rules[].outbound] | index("warp")' /etc/sing-box/config.json)
        echo "$(jq ".route.rules[${warp_rule_num}] |= ${warp_rule}" /etc/sing-box/config.json)" > /etc/sing-box/config.json
    fi

    echo "$(jq 'del(.outbounds[] | select(.tag == "proxy" or .tag == "IPv4")) | del(.route.rules[] | select(.outbound == "proxy" or .outbound == "IPv4")) | del(.route.rules[] | select(has("inbound") and .outbound == "direct"))' /etc/sing-box/config.json)" > /etc/sing-box/config.json

    rule_sets_add=()
    rule_sets_del=(google telegram)
    manage_rule_sets
    reload_sing_box
    echo "${info_message[1_$language]}"
    echo ""
    main_menu
}

chain_middle() {
    declare -A -g info_message=()
    info_message[1_ru]="Изменение настроек завершено, этот сервер настроен как промежуточный в цепочке"
    info_message[1_en]="Settings changed successfully, this server is configured as intermediate in the chain"

    if [[ $(jq 'any(.route.rules[]; .outbound == "warp")' /etc/sing-box/config.json) == "true" ]]
    then
        warp_rule='{"domain_suffix":["example.com"],"outbound":"warp"}'
        warp_rule_num=$(jq '[.route.rules[].outbound] | index("warp")' /etc/sing-box/config.json)
        echo "$(jq ".route.rules[${warp_rule_num}] |= ${warp_rule}" /etc/sing-box/config.json)" > /etc/sing-box/config.json
    fi

    chain_outbound=$(echo "${next_config}" | jq '.outbounds[] | select(.tag == "proxy")')
    chain_rule='{"inbound":["trojan-in","vless-in"],"outbound":"proxy"}'
    [[ -f /etc/haproxy/auth.lua ]] && chain_rule='{"inbound":["trojan-in"],"outbound":"proxy"}'

    if [[ $(jq 'any(.outbounds[]; .tag == "proxy")' /etc/sing-box/config.json) == "false" ]]
    then
        if [[ $(jq 'any(.route.rules[]; .outbound == "direct")' /etc/sing-box/config.json) == "false" ]]
        then
            proxy_rule=$(jq 'limit(1; .route.rules[] | select(.outbound == "proxy"))' /var/www/${subspath}/template.json)
            direct_rule='{"domain_suffix":[".ru",".su",".ru.com",".ru.net"],"domain_keyword":["xn--"],"rule_set":["geoip-ru","category-gov-ru"],"outbound":"direct"}'
            echo "$(jq ".route.rules |= . + [${proxy_rule}, ${direct_rule}]" /etc/sing-box/config.json)" > /etc/sing-box/config.json
        fi

        echo "$(jq ".outbounds += [${chain_outbound}] | .route.rules += [${chain_rule}]" /etc/sing-box/config.json)" > /etc/sing-box/config.json
    else
        chain_out_num=$(jq '[.outbounds[].tag] | index("proxy")' /etc/sing-box/config.json)
        chain_rule_num=$(jq '.route.rules | to_entries | map(select(.value.outbound == "proxy")) | last | .key' /etc/sing-box/config.json)
        echo "$(jq ".outbounds[${chain_out_num}] |= ${chain_outbound} | .route.rules[${chain_rule_num}] |= ${chain_rule}" /etc/sing-box/config.json)" > /etc/sing-box/config.json
    fi

    if [[ $(jq 'any(.outbounds[]; .tag == "IPv4")' /etc/sing-box/config.json) == "true" ]]
    then
        echo "$(jq 'del(.outbounds[] | select(.tag == "IPv4"))' /etc/sing-box/config.json)" > /etc/sing-box/config.json
    fi

    if [[ $(jq 'any(.route.rules[]; .outbound == "IPv4")' /etc/sing-box/config.json) == "true" ]]
    then
        echo "$(jq 'del(.route.rules[] | select(.outbound == "IPv4"))' /etc/sing-box/config.json)" > /etc/sing-box/config.json
    fi

    rule_sets_add=()
    rule_sets_del=(google telegram)
    manage_rule_sets
    reload_sing_box
    echo "${info_message[1_$language]}"
    echo ""
    main_menu
}

get_chain_sel() {
    declare -A -g info_message=()
    info_message[1_ru]="Выбрано"
    info_message[1_en]="Selected"

    chain_sel_1=""; chain_sel_2=""

    if [[ $(jq 'any(.outbounds[]; .tag == "proxy")' /etc/sing-box/config.json) != "true" ]]
    then
        chain_sel_1="[${info_message[1_$language]}]"
    else
        chain_sel_2="[${info_message[1_$language]}: $(jq -r '.outbounds[] | select(.tag == "proxy") | .server' /etc/sing-box/config.json)]"
    fi
}

chain_text_ru() {
    echo -e "${textcolor}[?]${clear} Выберите положение сервера в цепочке:"
    echo "0 - Выйти"
    echo "1 - Настроить этот сервер как конечный в цепочке или единственный                     ${chain_sel_1}"
    echo "2 - Настроить этот сервер как промежуточный в цепочке или поменять следующий сервер   ${chain_sel_2}"
    read -r chain_option
    [[ -n $chain_option ]] && echo ""
}

chain_text_en() {
    echo -e "${textcolor}[?]${clear} Select the position of the server in the chain:"
    echo "0 - Exit"
    echo "1 - Configure this server as the end of the chain or the only one                  ${chain_sel_1}"
    echo "2 - Configure this server as intermediate in the chain or change the next server   ${chain_sel_2}"
    read -r chain_option
    [[ -n $chain_option ]] && echo ""
}

chain_setup() {
    get_chain_sel
    chain_text_${language}
    check_chain_option

    case $chain_option in
        1)
        chain_end
        ;;
        2)
        check_github_template
        enter_chain_data
        chain_middle
        ;;
        *)
        main_menu
    esac
}

### OPTION 11 - RENEW CERTIFICATE MANUALLY ###

exit_renew_cert() {
    if [[ ${cert_renew,,} =~ ^(x|х)$ ]]
    then
        cert_renew=""
        main_menu
    fi
}

enter_data_reissue_cert() {
    declare -A -g input_message=()
    input_message[1_ru]="${textcolor}[?]${clear} Введите вашу почту, зарегистрированную на Cloudflare:"
    input_message[1_en]="${textcolor}[?]${clear} Enter your email registered on Cloudflare:"

    if [[ ! -f /etc/letsencrypt/cloudflare.credentials ]]
    then
        input_message[1_ru]="${textcolor}[?]${clear} Введите вашу почту для выпуска сертификата:"
        input_message[1_en]="${textcolor}[?]${clear} Enter your email to issue a certificate:"
    fi

    while [[ -z $email ]]
    do
        echo -e "${input_message[1_$language]}"
        read -r email
        [[ -n $email ]] && echo ""
        email=$(echo "${email}" | sed 's/[[:blank:]]//g')
    done
}

cert_clean_up() {
    warn_file=$(python3 -c "import os, CloudFlare; print(os.path.join(os.path.dirname(CloudFlare.__file__), 'warning_2_20.py'))")
    [[ $(dpkg -s python3-cloudflare | grep -i '^version') =~ "2.20." ]] && sed -i 's/2\.20\./2\.25\./g' ${warn_file} &> /dev/null

    domain_del="${domain}"
    [[ "$option" == "12" ]] && domain_del="${domain_old}"
    certbot delete --cert-name ${domain_del} --quiet &> /dev/null
}

cert_final_text() {
    if [[ $? -ne 0 ]]
    then
        declare -A -g info_message=()
        info_message[1_ru]="${red}Ошибка: не удалось выпустить сертификат, попробуйте позже или смените домен/поддомен с помощью пункта 12${clear}"
        info_message[1_en]="${red}Error: failed to issue the certificate, try again later or change the domain/subdomain with option 12${clear}"

        echo ""
        echo -e "${info_message[1_$language]}"
    fi
}

reissue_cert() {
    declare -A -g info_message=()
    info_message[1_ru]="${textcolor}Получение сертификата...${clear}"
    info_message[1_en]="${textcolor}Requesting a certificate...${clear}"

    cert_clean_up
    echo -e "${info_message[1_$language]}"

    if [[ -f /etc/letsencrypt/cloudflare.credentials ]]
    then
        certbot certonly --dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.credentials --dns-cloudflare-propagation-seconds 35 -d ${domain},*.${domain} --agree-tos -m ${email} --no-eff-email --non-interactive
        cert_final_text
    else
        ufw allow 80 &> /dev/null
        certbot certonly --standalone --preferred-challenges http --agree-tos --email ${email} -d ${domain} --no-eff-email --non-interactive
        cert_final_text
        ufw delete allow 80 &> /dev/null
    fi

    if [[ ! -f /etc/haproxy/auth.lua ]] && [[ -f /etc/letsencrypt/live/${domain}/fullchain.pem ]]
    then
        echo "renew_hook = systemctl reload nginx.service" >> /etc/letsencrypt/renewal/${domain}.conf
        systemctl restart nginx.service
    elif [[ -f /etc/haproxy/auth.lua ]] && [[ -f /etc/letsencrypt/live/${domain}/fullchain.pem ]]
    then
        echo "renew_hook = cat /etc/letsencrypt/live/${domain}/fullchain.pem /etc/letsencrypt/live/${domain}/privkey.pem > /etc/haproxy/certs/${domain}.pem && systemctl reload haproxy.service" >> /etc/letsencrypt/renewal/${domain}.conf
        cat /etc/letsencrypt/live/${domain}/fullchain.pem /etc/letsencrypt/live/${domain}/privkey.pem > /etc/haproxy/certs/${domain}.pem
        systemctl restart haproxy.service
    fi

    echo ""
}

cert_renewal() {
    declare -A -g info_message=()
    info_message[1_ru]="${textcolor}Обновление сертификата...${clear}"
    info_message[1_en]="${textcolor}Renewing the certificate...${clear}"

    echo -e "${info_message[1_$language]}"
    [[ ! -f /etc/letsencrypt/cloudflare.credentials ]] && ufw allow 80 &> /dev/null
    certbot renew --force-renewal
    cert_final_text
    ufw delete allow 80 &> /dev/null
    echo ""
}

renew_cert_text_ru() {
    echo -e "${red}ВНИМАНИЕ!${clear}"
    echo "В скрипт встроено автоматическое обновление сертификата раз в 2 месяца, и ручное обновление рекомендуется только в случае сбоев"
    echo "При обновлении сертификата более 5 раз в неделю можно достичь лимита Let's Encrypt, что потребует ожидания для следующего обновления"
    echo ""
    echo -e "${textcolor}[?]${clear} Нажмите ${textcolor}Enter${clear}, чтобы обновить сертификат, или введите ${textcolor}x${clear}, чтобы выйти:"
    read -r cert_renew
    [[ -n $cert_renew ]] && echo ""
}

renew_cert_text_en() {
    echo -e "${red}ATTENTION!${clear}"
    echo "The script has a built-in automatic certificate renewal every 2 months, and manual renewal is recommended only in case of failures"
    echo "Renewing a certificate more than 5 times a week can result in reaching the Let's Encrypt limit, requiring you to wait before the next renewal"
    echo ""
    echo -e "${textcolor}[?]${clear} Press ${textcolor}Enter${clear} to renew certificate or enter ${textcolor}x${clear} to exit:"
    read -r cert_renew
    [[ -n $cert_renew ]] && echo ""
}

renew_cert() {
    renew_cert_text_${language}
    exit_renew_cert

    if [[ -f /etc/letsencrypt/live/${domain}/fullchain.pem ]]
    then
        cert_renewal
    else
        email=""
        enter_data_reissue_cert
        reissue_cert
    fi

    main_menu
}

### OPTION 12 - CHANGE DOMAIN ###

exit_change_domain() {
    if [[ ${domain,,} =~ ^(x|х)$ ]]
    then
        domain="${domain_old}"
        main_menu
    fi
}

crop_domain() {
    domain=${domain#*"://"}
    domain=${domain#"www."}
    domain=$(echo "${domain}" | cut -d "/" -f 1 | sed 's/[[:blank:]]//g')
}

get_test_response() {
    test_domain=$(echo "${domain}" | rev | cut -d "." -f 1-2 | rev)

    if [[ $cf_token =~ [A-Z] ]]
    then
        test_response=$(curl -s --request GET --url https://api.cloudflare.com/client/v4/zones --header "Authorization: Bearer ${cf_token}" --header "Content-Type: application/json")
    else
        test_response=$(curl -s --request GET --url https://api.cloudflare.com/client/v4/zones --header "X-Auth-Key: ${cf_token}" --header "X-Auth-Email: ${email}" --header "Content-Type: application/json")
    fi
}

check_cf_token() {
    declare -A -g check_message=()
    check_message[1_ru]="Проверка домена, API токена/ключа и почты..."
    check_message[2_ru]="${red}Ошибка: неправильно введён домен, API токен/ключ или почта${clear}"
    check_message[3_ru]="${red}Инструкция: https://github.com/zipfo/Simple-Sing-Box/blob/main/.github/cf-settings-ru.md#получение-api-токена-cloudflare${clear}"
    check_message[4_ru]="Успешно!"
    check_message[1_en]="Checking domain name, API token/key and email..."
    check_message[2_en]="${red}Error: invalid domain name, API token/key or email${clear}"
    check_message[3_en]="${red}Instruction: https://github.com/zipfo/Simple-Sing-Box/blob/main/.github/cf-settings-en.md#getting-cloudflare-api-token${clear}"
    check_message[4_en]="Success!"

    echo "${check_message[1_$language]}"
    get_test_response

    while [[ $domain =~ ".." ]] || [[ ! $test_response =~ "\"$test_domain\"" ]] || [[ ! $test_response =~ "#dns_records:edit" ]] || [[ ! $test_response =~ "#dns_records:read" ]] || [[ ! $test_response =~ "#zone:read" ]]
    do
        echo ""
        echo -e "${check_message[2_$language]}"
        echo -e "${check_message[3_$language]}"
        enter_domain_data
        echo "${check_message[1_$language]}"
        get_test_response
    done

    echo "${check_message[4_$language]}"
    echo ""
}

enter_domain_data() {
    declare -A -g input_message=()
    input_message[1_ru]="${textcolor}[?]${clear} Введите новый домен или введите ${textcolor}x${clear}, чтобы выйти:"
    input_message[2_ru]="${textcolor}[?]${clear} Введите вашу почту, зарегистрированную на Cloudflare:"
    input_message[3_ru]="${textcolor}[?]${clear} Введите ваш API токен Cloudflare (Edit zone DNS) или Cloudflare global API key:"
    input_message[1_en]="${textcolor}[?]${clear} Enter new domain name or enter ${textcolor}x${clear} to exit:"
    input_message[2_en]="${textcolor}[?]${clear} Enter your email registered on Cloudflare:"
    input_message[3_en]="${textcolor}[?]${clear} Enter your Cloudflare API token (Edit zone DNS) or Cloudflare global API key:"

    if [[ "$validation_type" == "2" ]]
    then
        input_message[2_ru]="${textcolor}[?]${clear} Введите вашу почту для выпуска сертификата:"
        input_message[2_en]="${textcolor}[?]${clear} Enter your email to issue a certificate:"
    fi

    domain=""; email=""; cf_token=""
    echo ""
    while [[ -z $domain ]]
    do
        echo -e "${input_message[1_$language]}"
        read -r domain
        [[ -n $domain ]] && echo ""
    done
    exit_change_domain
    crop_domain
    while [[ -z $email ]]
    do
        echo -e "${input_message[2_$language]}"
        read -r email
        [[ -n $email ]] && echo ""
        email=$(echo "${email}" | sed 's/[[:blank:]]//g')
    done
    if [[ "$validation_type" == "1" ]]
    then
        while [[ -z $cf_token ]]
        do
            echo -e "${input_message[3_$language]}"
            read -r cf_token
            [[ -n $cf_token ]] && echo ""
        done
    fi
}

issue_cert_dns_cf() {
    if [[ $cf_token =~ [A-Z] ]]
    then
        echo "dns_cloudflare_api_token = ${cf_token}" > /etc/letsencrypt/cloudflare.credentials
    else
        echo "dns_cloudflare_email = ${email}" > /etc/letsencrypt/cloudflare.credentials
        echo "dns_cloudflare_api_key = ${cf_token}" >> /etc/letsencrypt/cloudflare.credentials
    fi

    chown root:root /etc/letsencrypt/cloudflare.credentials
    chmod 600 /etc/letsencrypt/cloudflare.credentials

    echo -e "${info_message[3_$language]}"
    certbot certonly --dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.credentials --dns-cloudflare-propagation-seconds 35 -d ${domain},*.${domain} --agree-tos -m ${email} --no-eff-email --non-interactive

    if [[ $? -ne 0 ]]
    then
        sleep 3
        echo ""
        echo -e "${info_message[4_$language]}"
        certbot delete --cert-name ${domain} --quiet &> /dev/null
        certbot certonly --dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.credentials --dns-cloudflare-propagation-seconds 35 -d ${domain},*.${domain} --agree-tos -m ${email} --no-eff-email --non-interactive
    fi

    crontab -l | sed 's/.*certbot -q renew.*/0 2 * * * certbot -q renew/' | crontab -
}

issue_cert_standalone() {
    rm -f /etc/letsencrypt/cloudflare.credentials
    ufw allow 80 &> /dev/null

    echo -e "${info_message[3_$language]}"
    certbot certonly --standalone --preferred-challenges http --agree-tos --email ${email} -d ${domain} --no-eff-email --non-interactive

    if [[ $? -ne 0 ]]
    then
        sleep 3
        echo ""
        echo -e "${info_message[4_$language]}"
        certbot delete --cert-name ${domain} --quiet &> /dev/null
        certbot certonly --standalone --preferred-challenges http --agree-tos --email ${email} -d ${domain} --no-eff-email --non-interactive
    fi

    ufw delete allow 80 &> /dev/null
    crontab -l | sed 's/.*certbot -q renew.*/0 2 * * * ufw allow 80 \&\& certbot -q renew; ufw delete allow 80/' | crontab -
}

manage_frontend() {
    if [[ ! -f /etc/haproxy/auth.lua ]]
    then
        echo "renew_hook = systemctl reload nginx.service" >> /etc/letsencrypt/renewal/${domain}.conf
        sed -i "s/${domain_old}/${domain}/g" /etc/nginx/nginx.conf
        systemctl reload nginx.service || systemctl start nginx.service
    else
        rm -f /etc/haproxy/certs/${domain_old}.pem
        echo "renew_hook = cat /etc/letsencrypt/live/${domain}/fullchain.pem /etc/letsencrypt/live/${domain}/privkey.pem > /etc/haproxy/certs/${domain}.pem && systemctl reload haproxy.service" >> /etc/letsencrypt/renewal/${domain}.conf
        cat /etc/letsencrypt/live/${domain}/fullchain.pem /etc/letsencrypt/live/${domain}/privkey.pem > /etc/haproxy/certs/${domain}.pem
        sed -i "s/${domain_old}/${domain}/g" /etc/haproxy/haproxy.cfg
        systemctl reload haproxy.service || systemctl start haproxy.service
    fi
}

edit_subs_files() {
    declare -A -g info_message=()
    info_message[1_ru]="Домен ${textcolor}${domain_old}${clear} заменён на ${textcolor}${domain}${clear}"
    info_message[1_en]="Domain ${textcolor}${domain_old}${clear} changed to ${textcolor}${domain}${clear}"

    for file in /var/www/${subspath}/*-CLIENT.json
    do
        sed -i "s/${domain_old}/${domain}/g" ${file}
    done

    [[ -f /var/www/${subspath}/sub.html ]] && sed -i "s/${domain_old}/${domain}/g" /var/www/${subspath}/sub.html
    echo ""
    echo -e "${info_message[1_$language]}"
    echo ""
}

get_old_values() {
    domain_old="${domain}"
    validation_old="DNS Cloudflare"
    [[ ! -f /etc/letsencrypt/cloudflare.credentials ]] && validation_old="Standalone"
}

change_domain_text_ru() {
    echo -e "${red}ВНИМАНИЕ!${clear}"
    echo "Не забудьте создать А запись для нового домена и заменить домен в ссылках для клиентов"
    echo ""
    echo -e "Текущий домен: ${textcolor}${domain_old}${clear}"
    echo -e "Метод валидации сертификатов: ${textcolor}${validation_old}${clear}"
    echo ""
    echo -e "${textcolor}[?]${clear} Выберите метод валидации сертификатов для нового домена:"
    echo "0 - Выйти"
    echo "1 - DNS Cloudflare (если ваш домен прикреплён к Cloudflare)"
    echo "2 - Standalone (если ваш домен прикреплён к другому сервису)"
    read -r validation_type
}

change_domain_text_en() {
    echo -e "${red}ATTENTION!${clear}"
    echo "Don't forget to create an A record for the new domain and change the domain in client config links"
    echo ""
    echo -e "Current domain: ${textcolor}${domain_old}${clear}"
    echo -e "Certificate validation method: ${textcolor}${validation_old}${clear}"
    echo ""
    echo -e "${textcolor}[?]${clear} Select a certificate validation method for the new domain:"
    echo "0 - Exit"
    echo "1 - DNS Cloudflare (if your domain is linked to Cloudflare)"
    echo "2 - Standalone (if your domain is linked to another service)"
    read -r validation_type
}

cert_validation_options() {
    declare -A -g info_message=()
    info_message[1_ru]="${red}ВНИМАНИЕ!${clear}"
    info_message[2_ru]="Обязательно проверьте правильность написания домена"
    info_message[3_ru]="${textcolor}Получение сертификата...${clear}"
    info_message[4_ru]="${textcolor}Получение сертификата: 2-я попытка...${clear}"
    info_message[1_en]="${red}ATTENTION!${clear}"
    info_message[2_en]="Be sure to check the spelling of the domain name"
    info_message[3_en]="${textcolor}Requesting a certificate...${clear}"
    info_message[4_en]="${textcolor}Requesting a certificate: 2nd attempt...${clear}"

    case $validation_type in
        1)
        enter_domain_data
        check_cf_token
        cert_clean_up
        issue_cert_dns_cf
        ;;
        2)
        echo ""
        echo -e "${info_message[1_$language]}"
        echo "${info_message[2_$language]}"
        enter_domain_data
        cert_clean_up
        issue_cert_standalone
        ;;
        *)
        [[ -n $validation_type ]] && echo ""
        main_menu
    esac
}

change_domain() {
    get_old_values
    change_domain_text_${language}
    cert_validation_options
    manage_frontend
    edit_subs_files
    main_menu
}

### OPTION 13 - CHANGE PATHS ###

exit_change_paths() {
    if [[ ${paths_change,,} =~ ^(x|х)$ ]]
    then
        paths_change=""
        main_menu
    fi
}

change_paths_text_ru() {
    echo -e "${red}ВНИМАНИЕ!${clear}"
    echo "Здесь вы можете поменять пути, если они были скомпрометированы"
    echo "Не забудьте после этого заново добавить конфиги на клиентах"
    echo ""
    echo -e "${textcolor}[?]${clear} Нажмите ${textcolor}Enter${clear}, чтобы продолжить, или введите ${textcolor}x${clear}, чтобы выйти:"
    read -r paths_change
    [[ -n $paths_change ]] && echo ""
}

change_paths_text_en() {
    echo -e "${red}ATTENTION!${clear}"
    echo "Here you can change the paths if they were compromised"
    echo "After this, don't forget to re-add configs to client apps"
    echo ""
    echo -e "${textcolor}[?]${clear} Press ${textcolor}Enter${clear} to continue or enter ${textcolor}x${clear} to exit:"
    read -r paths_change
    [[ -n $paths_change ]] && echo ""
}

old_paths() {
    trojanpath_old="${trojanpath}"
    vlesspath_old="${vlesspath}"
    subspath_old="${subspath}"
    rulesetpath_old="${rulesetpath}"
    old_paths_list=("$trojanpath_old" "$vlesspath_old" "$subspath_old" "$rulesetpath_old")
}

check_trojan_path() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: путь должен содержать только английские буквы, цифры, символы _ и -${clear}"
    check_message[2_ru]="${red}Ошибка: новый путь не должен совпадать ни с одним из старых путей${clear}"
    check_message[3_ru]="${textcolor}[?]${clear} Введите путь для Trojan или оставьте пустым для генерации случайного пути:"
    check_message[1_en]="${red}Error: the path should contain only letters, numbers, _ and - symbols${clear}"
    check_message[2_en]="${red}Error: the new path should not match with any of the old paths${clear}"
    check_message[3_en]="${textcolor}[?]${clear} Enter your path for Trojan or leave this empty to generate a random path:"

    while ([[ ! $trojanpath =~ ^[a-zA-Z0-9_-]+$ ]] || printf '%s\n' "${old_paths_list[@]}" | grep -xFq "${trojanpath}") && [[ -n $trojanpath ]]
    do
        if [[ ! $trojanpath =~ ^[a-zA-Z0-9_-]+$ ]]
        then
            echo -e "${check_message[1_$language]}"
        else
            echo -e "${check_message[2_$language]}"
        fi
        echo ""
        echo -e "${check_message[3_$language]}"
        read -r trojanpath
        [[ -n $trojanpath ]] && echo ""
        trojanpath=${trojanpath#"/"}
    done
}

check_vless_path() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: путь должен содержать только английские буквы, цифры, символы _ и -${clear}"
    check_message[2_ru]="${red}Ошибка: пути для Trojan и VLESS должны быть разными${clear}"
    check_message[3_ru]="${red}Ошибка: новый путь не должен совпадать ни с одним из старых путей${clear}"
    check_message[4_ru]="${textcolor}[?]${clear} Введите путь для VLESS или оставьте пустым для генерации случайного пути:"
    check_message[1_en]="${red}Error: the path should contain only letters, numbers, _ and - symbols${clear}"
    check_message[2_en]="${red}Error: paths for Trojan and VLESS must be different${clear}"
    check_message[3_en]="${red}Error: the new path should not match with any of the old paths${clear}"
    check_message[4_en]="${textcolor}[?]${clear} Enter your path for VLESS or leave this empty to generate a random path:"

    while ([[ ! $vlesspath =~ ^[a-zA-Z0-9_-]+$ ]] || [[ "$vlesspath" == "$trojanpath" ]] || printf '%s\n' "${old_paths_list[@]}" | grep -xFq "${vlesspath}") && [[ -n $vlesspath ]]
    do
        if [[ ! $vlesspath =~ ^[a-zA-Z0-9_-]+$ ]]
        then
            echo -e "${check_message[1_$language]}"
        elif [[ "$vlesspath" == "$trojanpath" ]]
        then
            echo -e "${check_message[2_$language]}"
        else
            echo -e "${check_message[3_$language]}"
        fi
        echo ""
        echo -e "${check_message[4_$language]}"
        read -r vlesspath
        [[ -n $vlesspath ]] && echo ""
        vlesspath=${vlesspath#"/"}
    done
}

check_subscription_path() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: путь должен содержать только английские буквы, цифры, символы _ и -${clear}"
    check_message[2_ru]="${red}Ошибка: пути для Trojan, VLESS и подписки должны быть разными${clear}"
    check_message[3_ru]="${red}Ошибка: новый путь не должен совпадать ни с одним из старых путей${clear}"
    check_message[4_ru]="${textcolor}[?]${clear} Введите путь для подписки или оставьте пустым для генерации случайного пути:"
    check_message[1_en]="${red}Error: the path should contain only letters, numbers, _ and - symbols${clear}"
    check_message[2_en]="${red}Error: paths for Trojan, VLESS and subscription must be different${clear}"
    check_message[3_en]="${red}Error: the new path should not match with any of the old paths${clear}"
    check_message[4_en]="${textcolor}[?]${clear} Enter your subscription path or leave this empty to generate a random path:"

    while ([[ ! $subspath =~ ^[a-zA-Z0-9_-]+$ ]] || [[ "$subspath" == "$trojanpath" ]] || [[ "$subspath" == "$vlesspath" ]] || printf '%s\n' "${old_paths_list[@]}" | grep -xFq "${subspath}") && [[ -n $subspath ]]
    do
        if [[ ! $subspath =~ ^[a-zA-Z0-9_-]+$ ]]
        then
            echo -e "${check_message[1_$language]}"
        elif [[ "$subspath" == "$trojanpath" ]] || [[ "$subspath" == "$vlesspath" ]]
        then
            echo -e "${check_message[2_$language]}"
        else
            echo -e "${check_message[3_$language]}"
        fi
        echo ""
        echo -e "${check_message[4_$language]}"
        read -r subspath
        [[ -n $subspath ]] && echo ""
        subspath=${subspath#"/"}
    done
}

check_rulesetpath() {
    declare -A -g check_message=()
    check_message[1_ru]="${red}Ошибка: путь должен содержать только английские буквы, цифры, символы _ и -${clear}"
    check_message[2_ru]="${red}Ошибка: пути для Trojan, VLESS, подписки и наборов правил должны быть разными${clear}"
    check_message[3_ru]="${red}Ошибка: новый путь не должен совпадать ни с одним из старых путей${clear}"
    check_message[4_ru]="${textcolor}[?]${clear} Введите путь для наборов правил (rule sets) или оставьте пустым для генерации случайного пути:"
    check_message[1_en]="${red}Error: the path should contain only letters, numbers, _ and - symbols${clear}"
    check_message[2_en]="${red}Error: paths for Trojan, VLESS, subscription and rule sets must be different${clear}"
    check_message[3_en]="${red}Error: the new path should not match with any of the old paths${clear}"
    check_message[4_en]="${textcolor}[?]${clear} Enter your path for rule sets or leave this empty to generate a random path:"

    while ([[ ! $rulesetpath =~ ^[a-zA-Z0-9_-]+$ ]] || [[ "$rulesetpath" == "$trojanpath" ]] || [[ "$rulesetpath" == "$vlesspath" ]] || [[ "$rulesetpath" == "$subspath" ]] || printf '%s\n' "${old_paths_list[@]}" | grep -xFq "${rulesetpath}") && [[ -n $rulesetpath ]]
    do
        if [[ ! $rulesetpath =~ ^[a-zA-Z0-9_-]+$ ]]
        then
            echo -e "${check_message[1_$language]}"
        elif [[ "$rulesetpath" == "$trojanpath" ]] || [[ "$rulesetpath" == "$vlesspath" ]] || [[ "$rulesetpath" == "$subspath" ]]
        then
            echo -e "${check_message[2_$language]}"
        else
            echo -e "${check_message[3_$language]}"
        fi
        echo ""
        echo -e "${check_message[4_$language]}"
        read -r rulesetpath
        [[ -n $rulesetpath ]] && echo ""
        rulesetpath=${rulesetpath#"/"}
    done
}

enter_new_paths() {
    declare -A -g input_message=()
    input_message[1_ru]="${textcolor}[?]${clear} Введите путь для Trojan или оставьте пустым для генерации случайного пути:"
    input_message[2_ru]="${textcolor}[?]${clear} Введите путь для VLESS или оставьте пустым для генерации случайного пути:"
    input_message[3_ru]="${textcolor}[?]${clear} Введите путь для подписки или оставьте пустым для генерации случайного пути:"
    input_message[4_ru]="${textcolor}[?]${clear} Введите путь для наборов правил (rule sets) или оставьте пустым для генерации случайного пути:"
    input_message[1_en]="${textcolor}[?]${clear} Enter your path for Trojan or leave this empty to generate a random path:"
    input_message[2_en]="${textcolor}[?]${clear} Enter your path for VLESS or leave this empty to generate a random path:"
    input_message[3_en]="${textcolor}[?]${clear} Enter your subscription path or leave this empty to generate a random path:"
    input_message[4_en]="${textcolor}[?]${clear} Enter your path for rule sets or leave this empty to generate a random path:"

    if [[ ! -f /etc/haproxy/auth.lua ]]
    then
        echo -e "${input_message[1_$language]}"
        read -r trojanpath
        [[ -n $trojanpath ]] && echo ""
        trojanpath=${trojanpath#"/"}
        check_trojan_path
        echo -e "${input_message[2_$language]}"
        read -r vlesspath
        [[ -n $vlesspath ]] && echo ""
        vlesspath=${vlesspath#"/"}
        check_vless_path
    fi
    echo -e "${input_message[3_$language]}"
    read -r subspath
    [[ -n $subspath ]] && echo ""
    subspath=${subspath#"/"}
    check_subscription_path
    echo -e "${input_message[4_$language]}"
    read -r rulesetpath
    [[ -n $rulesetpath ]] && echo ""
    rulesetpath=${rulesetpath#"/"}
    check_rulesetpath
}

generate_paths() {
    [[ -z $trojanpath ]] && [[ ! -f /etc/haproxy/auth.lua ]] && trojanpath=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 30)
    [[ -z $vlesspath ]] && [[ ! -f /etc/haproxy/auth.lua ]] && vlesspath=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 30)
    [[ -z $subspath ]] && subspath=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 30)
    [[ -z $rulesetpath ]] && rulesetpath=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 30)
}

edit_configs_with_paths() {
    declare -A -g info_message=()
    info_message[1_ru]="Старые пути для ${paths_to_change}подписки и наборов правил заменены на новые"
    info_message[1_en]="Old paths for ${paths_to_change}subscription and rule sets were changed to new ones"

    sed -i "s/${rulesetpath_old}/${rulesetpath}/g" /etc/sing-box/config.json
    sed -i -e "s/${subspath_old}/${subspath}/g" -e "s/${rulesetpath_old}/${rulesetpath}/g" /etc/nginx/nginx.conf

    if [[ -f /etc/haproxy/haproxy.cfg ]]
    then
        sed -i -e "s/${subspath_old}/${subspath}/g" -e "s/${rulesetpath_old}/${rulesetpath}/g" /etc/haproxy/haproxy.cfg
    else
        inbound_num_tr=$(jq '[.inbounds[].tag] | index("trojan-in")' /etc/sing-box/config.json)
        inbound_num_vl=$(jq '[.inbounds[].tag] | index("vless-in")' /etc/sing-box/config.json)
        echo "$(jq ".inbounds[${inbound_num_tr}].transport.path = \"/${trojanpath}\" | .inbounds[${inbound_num_vl}].transport.path = \"/${vlesspath}\"" /etc/sing-box/config.json)" > /etc/sing-box/config.json
        sed -i -e "s/${trojanpath_old}/${trojanpath}/g" -e "s/${vlesspath_old}/${vlesspath}/g" /etc/nginx/nginx.conf
    fi

    for file in /var/www/${subspath_old}/*-CLIENT.json
    do
        sed -i "s/${rulesetpath_old}/${rulesetpath}/g" ${file}
        [[ -f /etc/haproxy/auth.lua ]] && continue
        outbound_num=$(jq '[.outbounds[].tag] | index("proxy")' ${file})
        new_path="/${trojanpath}"
        [[ $(jq -r ".outbounds[${outbound_num}].type" ${file}) == "vless" ]] && new_path="/${vlesspath}"
        echo "$(jq ".outbounds[${outbound_num}].transport.path = \"${new_path}\"" ${file})" > ${file}
    done

    sed -i "s/${subspath_old}/${subspath}/g" /var/www/${subspath_old}/sub.html
    mv -f /var/www/${subspath_old} /var/www/${subspath}
    mv -f /var/www/${rulesetpath_old} /var/www/${rulesetpath}
    reload_sing_box
    systemctl reload nginx.service 2>/dev/null || systemctl restart nginx.service 2>/dev/null || true
    [[ -f /etc/haproxy/auth.lua ]] && systemctl reload haproxy.service

    echo "${info_message[1_$language]}"
    echo "https://${domain}/${subspath}/sub.html"
    echo ""
}

change_paths() {
    change_paths_text_${language}
    exit_change_paths
    old_paths
    enter_new_paths
    generate_paths
    edit_configs_with_paths
    main_menu
}

### OPTION 14 - DISABLE IPv6 ###

disable_ipv6() {
    declare -A -g info_message=()
    info_message[1_ru]="${textcolor}IPv6 отключён:${clear}"
    info_message[1_en]="${textcolor}IPv6 is disabled:${clear}"

    for sysctl_entry in 'net.ipv6.conf.all.disable_ipv6 = 1' 'net.ipv6.conf.default.disable_ipv6 = 1' 'net.ipv6.conf.lo.disable_ipv6 = 1'
    do
        grep -q "${sysctl_entry}" /etc/sysctl.d/99-ssb.conf &> /dev/null || echo "${sysctl_entry}" >> /etc/sysctl.d/99-ssb.conf
    done

    echo -e "${info_message[1_$language]}"
    sysctl --system &> /dev/null
    sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 net.ipv6.conf.lo.disable_ipv6
    echo ""
    main_menu
}

### OPTION 15 - ENABLE IPv6 ###

enable_ipv6() {
    declare -A -g info_message=()
    info_message[1_ru]="${textcolor}IPv6 включён:${clear}"
    info_message[2_ru]="${red}ВНИМАНИЕ!${clear}"
    info_message[3_ru]="Для применения новых настроек рекомендуется перезагрузить сервер командой ${textcolor}reboot${clear}"
    info_message[1_en]="${textcolor}IPv6 is enabled:${clear}"
    info_message[2_en]="${red}ATTENTION!${clear}"
    info_message[3_en]="To apply the new settings, it is recommended to reboot the server with ${textcolor}reboot${clear} command"

    for sysctl_file in '/etc/sysctl.d/99-ssb.conf' '/etc/sysctl.conf'
    do
        sed -i -e "/net.ipv6.conf.all.disable_ipv6 = 1/d" -e "/net.ipv6.conf.default.disable_ipv6 = 1/d" -e "/net.ipv6.conf.lo.disable_ipv6 = 1/d" ${sysctl_file} &> /dev/null
    done

    echo -e "${info_message[1_$language]}"
    sysctl --system &> /dev/null
    sysctl -w net.ipv6.conf.all.disable_ipv6=0 -w net.ipv6.conf.default.disable_ipv6=0 -w net.ipv6.conf.lo.disable_ipv6=0
    echo ""
    echo -e "${info_message[2_$language]}"
    echo -e "${info_message[3_$language]}"
    echo ""
    main_menu
}

### OPTION 16 - SHOW PATHS TO IMPORTANT FILES ###

show_paths_ru() {
    echo -e "${textcolor}Страница выдачи подписок пользователей:${clear}"
    echo -e "https://${domain}/${subspath}/sub.html${grey}?name=$(ls -A1 /var/www/${subspath} | grep "\-CLIENT.json" | sed -e "s/-TRJ-CLIENT\.json//g" -e "s/-VLESS-CLIENT\.json//g" | uniq | tail -n 1)${clear}"
    echo "Серым текстом показан пример автозаполнения поля с именем пользователя"
    echo ""

    echo -e "${textcolor}Конфигурация сервисов:${clear}"
    echo "Конфиг Sing-Box                        /etc/sing-box/config.json"
    [[ -f /etc/usque/config.json ]] && echo "Конфиг usque (WARP MASQUE-H2)          /etc/usque/config.json"
    echo "Конфиг NGINX                           /etc/nginx/nginx.conf"
    if [[ -f /etc/haproxy/haproxy.cfg ]]
    then
        echo "Конфиг HAProxy                         /etc/haproxy/haproxy.cfg"
        echo "Скрипт, считывающий пароли Trojan      /etc/haproxy/auth.lua"
    fi
    echo ""

    echo -e "${textcolor}Контент, доставляемый с помощью NGINX:${clear}"
    echo "Директория подписки                    /var/www/${subspath}/"
    echo "Директория c наборами правил           /var/www/${rulesetpath}/"
    site_dir=$(grep "/var/www/" /etc/nginx/nginx.conf | head -n 1 | cut -d "/" -f 4 | cut -d ";" -f 1)
    [[ -d /var/www/${site_dir} ]] && echo "Директория cайта                       /var/www/${site_dir}/"
    echo ""

    echo -e "${textcolor}Сертификаты и вспомогательные файлы:${clear}"
    echo "Директория с сертификатами             /etc/letsencrypt/live/${domain}/"
    [[ -f /etc/haproxy/certs/${domain}.pem ]] && echo "Объединённый файл с сертификатами      /etc/haproxy/certs/${domain}.pem"
    echo "Конфиг обновления сертификатов         /etc/letsencrypt/renewal/${domain}.conf"
    [[ -f /etc/letsencrypt/cloudflare.credentials ]] && echo "Файл с API токеном/ключом Cloudflare   /etc/letsencrypt/cloudflare.credentials"
    echo ""

    echo -e "${textcolor}Скрипты:${clear}"
    echo "Этот скрипт (меню настроек)            /usr/local/bin/sbmanager"
    echo "Скрипт, обновляющий наборы правил      /usr/local/bin/rsupdate"
    echo ""
    echo ""
    exit 0
}

show_paths_en() {
    echo -e "${textcolor}Subscription page:${clear}"
    echo -e "https://${domain}/${subspath}/sub.html${grey}?name=$(ls -A1 /var/www/${subspath} | grep "\-CLIENT.json" | sed -e "s/-TRJ-CLIENT\.json//g" -e "s/-VLESS-CLIENT\.json//g" | uniq | tail -n 1)${clear}"
    echo "Grey text shows an example of autofilling the username field"
    echo ""

    echo -e "${textcolor}Configuration of the services:${clear}"
    echo "Sing-Box config                      /etc/sing-box/config.json"
    [[ -f /etc/usque/config.json ]] && echo "usque config (WARP MASQUE-H2)        /etc/usque/config.json"
    echo "NGINX config                         /etc/nginx/nginx.conf"
    if [[ -f /etc/haproxy/haproxy.cfg ]]
    then
        echo "HAProxy config                       /etc/haproxy/haproxy.cfg"
        echo "Trojan password reading script       /etc/haproxy/auth.lua"
    fi
    echo ""

    echo -e "${textcolor}Content delivered by NGINX:${clear}"
    echo "Subscription directory               /var/www/${subspath}/"
    echo "Rule set directory                   /var/www/${rulesetpath}/"
    site_dir=$(grep "/var/www/" /etc/nginx/nginx.conf | head -n 1 | cut -d "/" -f 4 | cut -d ";" -f 1)
    [[ -d /var/www/${site_dir} ]] && echo "Site directory                       /var/www/${site_dir}/"
    echo ""

    echo -e "${textcolor}Certificates and accessory files:${clear}"
    echo "Certificate directory                /etc/letsencrypt/live/${domain}/"
    [[ -f /etc/haproxy/certs/${domain}.pem ]] && echo "Combined file with certificates      /etc/haproxy/certs/${domain}.pem"
    echo "Certificate renewal config           /etc/letsencrypt/renewal/${domain}.conf"
    [[ -f /etc/letsencrypt/cloudflare.credentials ]] && echo "File with Cloudflare API token/key   /etc/letsencrypt/cloudflare.credentials"
    echo ""

    echo -e "${textcolor}Scripts:${clear}"
    echo "This script (settings menu)          /usr/local/bin/sbmanager"
    echo "Rule set renewal script              /usr/local/bin/rsupdate"
    echo ""
    echo ""
    exit 0
}

### OPTION 18 - BLACKLIST MANAGEMENT ###

manage_blacklist() {
    declare -A -g info_message=()
    info_message[1_ru]="Blacklist не настроен (nftables sets не найдены)"
    info_message[1_en]="Blacklist not configured (nftables sets not found)"
    info_message[2_ru]="Обновление blacklist..."
    info_message[2_en]="Updating blacklist..."
    info_message[3_ru]="Blacklist обновлён"
    info_message[3_en]="Blacklist updated"
    info_message[4_ru]="Выберите действие:"
    info_message[4_en]="Select an action:"
    info_message[5_ru]="1 - Показать статус"
    info_message[5_en]="1 - Show status"
    info_message[6_ru]="2 - Обновить списки"
    info_message[6_en]="2 - Update lists"
    info_message[7_ru]="3 - Установить blacklist (если не был установлен при настройке)"
    info_message[7_en]="3 - Install blacklist (if not installed during setup)"

    # Check if blacklist sets exist
    if ! nft list set inet filter blacklist_v4 &>/dev/null
    then
        echo ""
        echo -e "${red}${info_message[1_$language]}${clear}"
        echo ""
        echo -e "${info_message[7_$language]}"
        read -r bl_action
        [[ -n $bl_action ]] && echo ""

        if [[ "$bl_action" == "3" ]]
        then
            # Install blacklist: add sets to nftables and download
            if ! nft list table inet filter &>/dev/null; then
                echo -e "${red}Error: nftables not configured${clear}"
                echo ""
                main_menu
            fi
            nft add set inet filter blacklist_v4 '{ type ipv4_addr; flags interval; }'
            nft add set inet filter blacklist_v6 '{ type ipv6_addr; flags interval; }'
            # Add rules to input chain (before accept rules)
            local input_handle
            input_handle=$(nft -a list chain inet filter input 2>/dev/null | grep "ct state" | awk '{print $NF}')
            if [[ -n $input_handle ]]; then
                nft insert rule inet filter input position "$input_handle" ip saddr @blacklist_v4 counter drop
                nft insert rule inet filter input position "$input_handle" ip6 saddr @blacklist_v6 counter drop
            fi
            # Install update script
            wget -q -O /usr/local/bin/blacklist-update https://raw.githubusercontent.com/zipfo/Simple-Sing-Box/main/Scripts/blacklist-update.sh
            chmod +x /usr/local/bin/blacklist-update
            # Add to crontab
            (crontab -l 2>/dev/null; echo "30 4 * * * blacklist-update") | crontab -
            # Initial download
            echo -e "${info_message[2_$language]}"
            /usr/local/bin/blacklist-update
            echo -e "${info_message[3_$language]}"
        fi
        echo ""
        main_menu
    fi

    # Show blacklist submenu
    echo ""
    echo -e "${info_message[4_$language]}"
    echo -e "${info_message[5_$language]}"
    echo -e "${info_message[6_$language]}"
    echo "0 - Выход / Exit"
    read -r bl_action
    [[ -n $bl_action ]] && echo ""

    case $bl_action in
        1)
        # Show status
        local v4_count=0 v6_count=0 last_update=""
        v4_count=$(nft list set inet filter blacklist_v4 2>/dev/null | grep -c 'elements' || echo 0)
        if [[ $v4_count -gt 0 ]]; then
            v4_count=$(nft -j list set inet filter blacklist_v4 2>/dev/null | jq '.nftables[1].set.elem | length' 2>/dev/null || echo "?")
        else
            v4_count=0
        fi
        v6_count=$(nft -j list set inet filter blacklist_v6 2>/dev/null | jq '.nftables[1].set.elem | length' 2>/dev/null || echo "0")
        last_update=$(tail -1 /var/log/blacklist-update.log 2>/dev/null | cut -d' ' -f1-2 || echo "N/A")

        if [[ "$language" == "ru" ]]
        then
            echo ""
            echo -e "${textcolor}Статус blacklist:${clear}"
            echo "  IPv4 подсетей: ${v4_count}"
            echo "  IPv6 подсетей: ${v6_count}"
            echo "  Последнее обновление: ${last_update}"
        else
            echo ""
            echo -e "${textcolor}Blacklist status:${clear}"
            echo "  IPv4 subnets: ${v4_count}"
            echo "  IPv6 subnets: ${v6_count}"
            echo "  Last update: ${last_update}"
        fi
        echo ""
        manage_blacklist
        ;;
        2)
        # Update lists
        echo -e "${info_message[2_$language]}"
        /usr/local/bin/blacklist-update
        echo -e "${info_message[3_$language]}"
        echo ""
        manage_blacklist
        ;;
        *)
        main_menu
        ;;
    esac
}

### OPTION 17 - UPDATE SSB ###

update_ssb() {
    declare -A -g info_message=()
    info_message[1_ru]="${red}Ошибка: не удалось загрузить данные с GitHub, попробуйте позже${clear}"
    info_message[1_en]="${red}Error: failed to download data from GitHub, try again later${clear}"

    update_script=$(curl -Ls https://raw.githubusercontent.com/zipfo/Simple-Sing-Box/main/Scripts/update-server.sh)

    if [[ $update_script =~ '#!/bin/bash' ]]
    then
        export version language INSTALLED_VERSION
        export -f get_ip templates load_ssb_config get_data check_users check_github_template get_pass edit_configs_loop add_rule_sets_loop sync_client_configs_main
        bash <(echo "${update_script}")
        exit 0
    else
        echo -e "${info_message[1_$language]}"
        echo ""
        main_menu
    fi
}

# Функция удаления Secret Sing-Box

### UNINSTALL FUNCTIONS ###

uninstall_menu_text_ru() {
    echo -e "${textcolor}[?]${clear} Выберите вариант удаления:"
    echo "0 - Выйти"
    echo "1 - Удалить полностью (все пакеты, файлы, настройки)"
    echo "2 - Удалить с сохранением конфигов (сохранить /etc/letsencrypt, /var/www)"
    read -r uninstall_option
    [[ -n $uninstall_option ]] && echo ""
}

uninstall_menu_text_en() {
    echo -e "${textcolor}[?]${clear} Select uninstall option:"
    echo "0 - Exit"
    echo "1 - Full uninstall (all packages, files, settings)"
    echo "2 - Uninstall keeping configs (keep /etc/letsencrypt, /var/www)"
    read -r uninstall_option
    [[ -n $uninstall_option ]] && echo ""
}

uninstall_full() {
    declare -A -g info_message=()
    info_message[1_ru]="Полное удаление Secret Sing-Box..."
    info_message[2_ru]="Удаление завершено. Рекомендуется перезагрузить сервер."
    info_message[1_en]="Full uninstall of Secret Sing-Box..."
    info_message[2_en]="Uninstall complete. Server reboot is recommended."

    echo -e "${info_message[1_$language]}"
    echo ""

    # Stop and disable services
    echo "Stopping services..."
    systemctl stop sing-box.service 2>/dev/null
    systemctl disable sing-box.service 2>/dev/null
    systemctl stop nginx.service 2>/dev/null
    systemctl disable nginx.service 2>/dev/null
    systemctl stop haproxy.service 2>/dev/null
    systemctl disable haproxy.service 2>/dev/null
    systemctl stop warp-svc.service 2>/dev/null
    systemctl disable warp-svc.service 2>/dev/null
    systemctl stop usque-warp.service 2>/dev/null
    systemctl disable usque-warp.service 2>/dev/null
    systemctl stop certbot.timer 2>/dev/null
    systemctl disable certbot.timer 2>/dev/null

    # Remove crontab entries
    echo "Removing crontab entries..."
    crontab -l 2>/dev/null | grep -v "certbot\|rsupdate\|sysctl --system\|blacklist-update\|PATH=" | crontab - 2>/dev/null

    # Remove packages
    echo "Removing packages..."
    apt-mark unhold sing-box 2>/dev/null
    apt-mark unhold cloudflare-warp 2>/dev/null
    apt-get purge -y sing-box cloudflare-warp 2>/dev/null
    apt-get purge -y nginx 2>/dev/null
    apt-get purge -y haproxy 2>/dev/null
    apt-get purge -y certbot python3-certbot-dns-cloudflare python3-cloudflare 2>/dev/null
    apt-get autoremove -y 2>/dev/null
    apt-get autoclean -y 2>/dev/null

    # Remove apt sources and GPG keys
    echo "Removing apt sources and GPG keys..."
    rm -f /etc/apt/sources.list.d/sagernet.list
    rm -f /etc/apt/sources.list.d/cloudflare-client.list
    rm -f /etc/apt/sources.list.d/nginx.list
    rm -f /etc/apt/keyrings/sagernet.asc
    rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    rm -f /usr/share/keyrings/nginx-archive-keyring.gpg

    # Remove config files
    echo "Removing config files..."
    rm -rf /etc/sing-box
    rm -rf /etc/nginx
    rm -rf /etc/haproxy
    rm -rf /etc/letsencrypt
    rm -rf /var/www
    rm -f /etc/sysctl.d/99-ssb.conf
    rm -f /etc/nftables.conf
    sysctl --system &> /dev/null

    # Remove nftables rules
    nft flush ruleset 2>/dev/null
    systemctl disable nftables 2>/dev/null

    # Remove Secret Sing-Box config
    rm -rf /etc/secret-sing-box

    # Remove usque WARP backend and legacy drop-ins
    rm -f /etc/systemd/system/usque-warp.service
    rm -rf /etc/systemd/system/warp-svc.service.d /etc/usque /etc/warpscout
    rm -f /usr/local/bin/usque /usr/local/bin/usque.prev /usr/local/bin/warpscout
    systemctl daemon-reload 2>/dev/null

    # Remove scripts
    rm -f /usr/local/bin/sbmanager
    rm -f /usr/local/bin/rsupdate
    rm -f /usr/local/bin/blacklist-update
    rm -f /var/log/blacklist-update.log

    # Remove alias
    sed -i "/alias ssb=/d" /etc/bash.bashrc
    sed -i "/alias sudo=/d" /etc/bash.bashrc

    # Reset SSH if it was modified (optional)
    if [[ -f /etc/ssh/sshd_config ]]
    then
        if [[ "$language" == "ru" ]]
        then
            echo -e "${textcolor}[?]${clear} Сбросить настройки SSH к исходным? (PermitRootLogin yes)"
            echo "1 - Да (рекомендуется, если вы настраивали SSH через скрипт)"
            echo "2 - Нет (оставить текущие настройки)"
        else
            echo -e "${textcolor}[?]${clear} Reset SSH settings to defaults? (PermitRootLogin yes)"
            echo "1 - Yes (recommended if you configured SSH via script)"
            echo "2 - No (keep current settings)"
        fi
        read -r reset_ssh
        [[ -n $reset_ssh ]] && echo ""

        if [[ "$reset_ssh" == "1" ]]
        then
            echo "Resetting SSH settings..."
            sed -i "s/.*PermitRootLogin no.*/PermitRootLogin yes/g" /etc/ssh/sshd_config 2>/dev/null
            sed -i "s/.*#PermitRootLogin .*/PermitRootLogin yes/g" /etc/ssh/sshd_config 2>/dev/null
            systemctl restart ssh.service 2>/dev/null
        fi
    fi

    # Reset nftables (optional)
    if command -v nft &>/dev/null && nft list table inet filter &>/dev/null
    then
        if [[ "$language" == "ru" ]]
        then
            echo -e "${textcolor}[?]${clear} Сбросить nftables? (это откроет все порты)"
            echo "1 - Да"
            echo "2 - Нет (оставить текущие правила)"
        else
            echo -e "${textcolor}[?]${clear} Reset nftables? (this will open all ports)"
            echo "1 - Yes"
            echo "2 - No (keep current rules)"
        fi
        read -r reset_nft
        [[ -n $reset_nft ]] && echo ""

        if [[ "$reset_nft" == "1" ]]
        then
            echo "Resetting nftables..."
            nft flush ruleset 2>/dev/null
            systemctl disable nftables 2>/dev/null
            rm -f /etc/nftables.conf
        fi
    fi

    echo ""
    echo -e "${info_message[2_$language]}"
    echo ""
    exit 0
}

uninstall_keep_configs() {
    declare -A -g info_message=()
    info_message[1_ru]="Удаление с сохранением конфигов..."
    info_message[2_ru]="Удаление завершено. Конфиги сохранены в /etc/letsencrypt и /var/www."
    info_message[1_en]="Uninstall keeping configs..."
    info_message[2_en]="Uninstall complete. Configs saved in /etc/letsencrypt and /var/www."

    echo -e "${info_message[1_$language]}"
    echo ""

    # Stop and disable services
    echo "Stopping services..."
    systemctl stop sing-box.service 2>/dev/null
    systemctl disable sing-box.service 2>/dev/null
    systemctl stop nginx.service 2>/dev/null
    systemctl disable nginx.service 2>/dev/null
    systemctl stop haproxy.service 2>/dev/null
    systemctl disable haproxy.service 2>/dev/null
    systemctl stop warp-svc.service 2>/dev/null
    systemctl disable warp-svc.service 2>/dev/null
    systemctl stop usque-warp.service 2>/dev/null
    systemctl disable usque-warp.service 2>/dev/null
    systemctl stop certbot.timer 2>/dev/null
    systemctl disable certbot.timer 2>/dev/null

    # Remove crontab entries
    echo "Removing crontab entries..."
    crontab -l 2>/dev/null | grep -v "certbot\|rsupdate\|sysctl --system\|blacklist-update\|PATH=" | crontab - 2>/dev/null

    # Remove packages
    echo "Removing packages..."
    apt-mark unhold sing-box 2>/dev/null
    apt-mark unhold cloudflare-warp 2>/dev/null
    apt-get purge -y sing-box cloudflare-warp 2>/dev/null
    apt-get purge -y nginx 2>/dev/null
    apt-get purge -y haproxy 2>/dev/null
    apt-get purge -y certbot python3-certbot-dns-cloudflare python3-cloudflare 2>/dev/null
    apt-get autoremove -y 2>/dev/null
    apt-get autoclean -y 2>/dev/null

    # Remove apt sources and GPG keys
    echo "Removing apt sources and GPG keys..."
    rm -f /etc/apt/sources.list.d/sagernet.list
    rm -f /etc/apt/sources.list.d/cloudflare-client.list
    rm -f /etc/apt/sources.list.d/nginx.list
    rm -f /etc/apt/keyrings/sagernet.asc
    rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    rm -f /usr/share/keyrings/nginx-archive-keyring.gpg

    # Remove config files (except letsencrypt and www)
    echo "Removing config files..."
    rm -rf /etc/sing-box
    rm -rf /etc/nginx
    rm -rf /etc/haproxy
    rm -f /etc/sysctl.d/99-ssb.conf
    sysctl --system &> /dev/null

    # Remove Cloudflare credentials (security: contains API token/key)
    rm -f /etc/letsencrypt/cloudflare.credentials

    # Remove Secret Sing-Box config
    rm -rf /etc/secret-sing-box

    # Remove usque WARP backend and legacy drop-ins
    rm -f /etc/systemd/system/usque-warp.service
    rm -rf /etc/systemd/system/warp-svc.service.d /etc/usque /etc/warpscout
    rm -f /usr/local/bin/usque /usr/local/bin/usque.prev /usr/local/bin/warpscout
    systemctl daemon-reload 2>/dev/null

    # Remove scripts
    rm -f /usr/local/bin/sbmanager
    rm -f /usr/local/bin/rsupdate
    rm -f /usr/local/bin/blacklist-update
    rm -f /var/log/blacklist-update.log

    # Remove alias
    sed -i "/alias ssb=/d" /etc/bash.bashrc
    sed -i "/alias sudo=/d" /etc/bash.bashrc

    # Reset SSH if it was modified (optional)
    if [[ -f /etc/ssh/sshd_config ]]
    then
        if [[ "$language" == "ru" ]]
        then
            echo -e "${textcolor}[?]${clear} Сбросить настройки SSH к исходным? (PermitRootLogin yes)"
            echo "1 - Да (рекомендуется, если вы настраивали SSH через скрипт)"
            echo "2 - Нет (оставить текущие настройки)"
        else
            echo -e "${textcolor}[?]${clear} Reset SSH settings to defaults? (PermitRootLogin yes)"
            echo "1 - Yes (recommended if you configured SSH via script)"
            echo "2 - No (keep current settings)"
        fi
        read -r reset_ssh
        [[ -n $reset_ssh ]] && echo ""

        if [[ "$reset_ssh" == "1" ]]
        then
            echo "Resetting SSH settings..."
            sed -i "s/.*PermitRootLogin no.*/PermitRootLogin yes/g" /etc/ssh/sshd_config 2>/dev/null
            sed -i "s/.*#PermitRootLogin .*/PermitRootLogin yes/g" /etc/ssh/sshd_config 2>/dev/null
            systemctl restart ssh.service 2>/dev/null
        fi
    fi

    # Reset nftables (optional)
    if command -v nft &>/dev/null && nft list table inet filter &>/dev/null
    then
        if [[ "$language" == "ru" ]]
        then
            echo -e "${textcolor}[?]${clear} Сбросить nftables? (это откроет все порты)"
            echo "1 - Да"
            echo "2 - Нет (оставить текущие правила)"
        else
            echo -e "${textcolor}[?]${clear} Reset nftables? (this will open all ports)"
            echo "1 - Yes"
            echo "2 - No (keep current rules)"
        fi
        read -r reset_nft
        [[ -n $reset_nft ]] && echo ""

        if [[ "$reset_nft" == "1" ]]
        then
            echo "Resetting nftables..."
            nft flush ruleset 2>/dev/null
            systemctl disable nftables 2>/dev/null
            rm -f /etc/nftables.conf
        fi
    fi

    echo ""
    echo -e "${info_message[2_$language]}"
    echo ""
    exit 0
}

uninstall_menu() {
    uninstall_menu_text_${language}

    case $uninstall_option in
        1)
        uninstall_full
        ;;
        2)
        uninstall_keep_configs
        ;;
        *)
        main_menu
    esac
}

### MAIN MENU ###

main_menu_text_ru() {
    echo ""
    echo -e "${textcolor}Выберите действие:${clear}"
    echo "0 - Выйти"
    echo "1 - Список пользователей"
    echo "2 - Добавить нового пользователя"
    echo "3 - Управление выходными серверами (Outbound)"
    echo "---------------------------------"
    echo "4 - Синхронизировать настройки во всех клиентских конфигах"
    echo "5 - Настроить на клиенте подключение к выбранному IP Cloudflare"
    echo "---------------------------------"
    echo "6 - Вывести список доменов/суффиксов WARP"
    echo "7 - Добавить домен/суффикс в WARP"
    echo "8 - Удалить домен/суффикс из WARP"
    echo "9 - Управление WARP (статус, endpoint, тест)"
    echo "---------------------------------"
    echo "10 - Настроить/убрать цепочку из двух и более серверов"
    echo "---------------------------------"
    echo "11 - Обновить сертификат вручную"
    echo "12 - Сменить домен"
    echo "13 - Поменять пути для ${paths_to_change}подписки и наборов правил"
    echo "---------------------------------"
    echo "14 - Отключить IPv6 на сервере"
    echo "15 - Включить IPv6 на сервере"
    echo "---------------------------------"
    echo "16 - Показать пути до конфигов и других значимых файлов"
    echo "17 - Обновить"
    echo "---------------------------------"
    echo "18 - Управление blacklist (сети обнаружения)"
    echo "19 - Удалить Secret Sing-Box"
    read -r option
    [[ -n $option ]] && echo ""
}

main_menu_text_en() {
    echo ""
    echo -e "${textcolor}Select an option:${clear}"
    echo "0 - Exit"
    echo "1 - User list"
    echo "2 - Add a new user"
    echo "3 - Outbound nodes management"
    echo "---------------------------------"
    echo "4 - Sync settings in all client configs"
    echo "5 - Setup connection to custom Cloudflare IP on the client"
    echo "---------------------------------"
    echo "6 - Show the list of domains/suffixes routed through WARP"
    echo "7 - Add a new domain/suffix to WARP routing"
    echo "8 - Delete a domain/suffix from WARP routing"
    echo "9 - WARP management (status, endpoint, test)"
    echo "---------------------------------"
    echo "10 - Setup/remove a chain of two or more servers"
    echo "---------------------------------"
    echo "11 - Renew certificate manually"
    echo "12 - Change domain"
    echo "13 - Change paths for ${paths_to_change}subscription and rule sets"
    echo "---------------------------------"
    echo "14 - Disable IPv6 on the server"
    echo "15 - Enable IPv6 on the server"
    echo "---------------------------------"
    echo "16 - Show paths to configs and other important files"
    echo "17 - Update"
    echo "---------------------------------"
    echo "18 - Blacklist management (detection networks)"
    echo "19 - Uninstall Secret Sing-Box"
    read -r option
    [[ -n $option ]] && echo ""
}


show_config() {
    # Server location
    if [[ "$server_location" == "ru" ]]
    then
        loc_text_ru="Россия"
        loc_text_en="Russia"
    else
        loc_text_ru="Другая страна"
        loc_text_en="Other country"
    fi

    # WARP mode
    if [[ "$warp_option" == "2" ]]
    then
        warp_text_ru="Без WARP"
        warp_text_en="Without WARP"
    elif [[ "${warp_backend:-}" == "usque" ]]
    then
        warp_text_ru="WARP (режим ${warp_mode}, usque MASQUE-H2)"
        warp_text_en="WARP (mode ${warp_mode}, usque MASQUE-H2)"
    else
        warp_text_ru="WARP (режим ${warp_mode}, warp-cli)"
        warp_text_en="WARP (mode ${warp_mode}, warp-cli)"
    fi

    # Chain role
    if [[ "$chain_role" == "middle" ]]
    then
        role_text_ru="Промежуточный (режим ${middle_mode})"
        role_text_en="Intermediate (mode ${middle_mode})"
    else
        role_text_ru="Конечный"
        role_text_en="End server"
    fi

    echo ""
    echo -e "${textcolor}Текущая конфигурация:${clear}"
    if [[ "$language" == "ru" ]]
    then
        echo "  Расположение: ${loc_text_ru}"
        echo "  Маршрутизация: ${warp_text_ru}"
        echo "  Роль сервера: ${role_text_ru}"
    else
        echo "  Location: ${loc_text_en}"
        echo "  Routing: ${warp_text_en}"
        echo "  Server role: ${role_text_en}"
    fi
}

main_menu() {
    [[ ! -f /etc/haproxy/auth.lua ]] && paths_to_change="Trojan, VLESS, "
    show_config
    main_menu_text_${language}

    case $option in
        1)
        user_list_menu
        ;;
        2)
        add_users
        ;;
        3)
        outbounds_menu
        ;;
        4)
        sync_client_configs
        ;;
        5)
        cf_ip_settings
        ;;
        6)
        show_warp_domains
        ;;
        7)
        add_warp_domains
        ;;
        8)
        delete_warp_domains
        ;;
        9)
        warp_menu
        ;;
        10)
        chain_setup
        ;;
        11)
        renew_cert
        ;;
        12)
        change_domain
        ;;
        13)
        change_paths
        ;;
        14)
        disable_ipv6
        ;;
        15)
        enable_ipv6
        ;;
        16)
        show_paths_${language}
        ;;
        17)
        update_ssb
        ;;
        18)
        manage_blacklist
        ;;
        19)
        uninstall_menu
        ;;
        *)
        exit 0
    esac
}

if [[ "$1" == "--apply-routes" ]]; then
    check_config_json
    apply_user_routing
    exit 0
fi

if [[ "$1" == "--update" ]]; then
    check_root
    check_config_json
    get_data
    update_ssb
    exit 0
fi

check_root
check_config_json
banner
get_data
main_menu
