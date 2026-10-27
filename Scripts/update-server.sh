#!/bin/bash

textcolor='\033[1;36m'
textcolor_light='\033[1;37m'
red='\033[1;31m'
clear='\033[0m'

# The exported get_data() calls load_ssb_config(). Older sb-manager versions do
# not export that helper, so define a local fallback before get_data runs.
load_ssb_config() {
    if [[ -f /etc/secret-sing-box/config ]]
    then
        source /etc/secret-sing-box/config
    fi
}

check_parent() {
    if [[ -z $version ]]
    then
        echo ""
        echo -e "${red}Error: this script should be run from the settings menu, not manually${clear}"
        echo ""
        exit 1
    fi
}

check_update() {
    declare -A -g info_message=()
    info_message[1_ru]="Установлена последняя версия:"
    info_message[2_ru]="Текущая версия:"
    info_message[3_ru]="Доступна новая версия:"
    info_message[4_ru]="${textcolor}[?]${clear} Принудительно обновить скрипты и конфиги? (${textcolor}Enter${clear} — да, ${textcolor}x${clear} — нет):"
    info_message[5_ru]="${red}Отмена обновления${clear}"
    info_message[1_en]="The latest version is already installed:"
    info_message[2_en]="Current version:"
    info_message[3_en]="New version is available:"
    info_message[4_en]="${textcolor}[?]${clear} Force update scripts and configs? (${textcolor}Enter${clear} — yes, ${textcolor}x${clear} — no):"
    info_message[5_en]="${red}Update cancelled${clear}"

    [[ ! $language =~ ^[a-z]+$ ]] && language="ru"   # Legacy
    new_version="1.6.0"
    [[ -n $INSTALLED_VERSION ]] && version="$INSTALLED_VERSION"

    if [[ "$version" == "$new_version" ]]
    then
        echo -e "${info_message[1_$language]} ${textcolor}v${version}${clear}"
        echo ""
        echo -e "${info_message[4_$language]}"
        read -r force_update
        [[ -n $force_update ]] && echo ""
        [[ "$force_update" == "x" ]] && { echo -e "${info_message[5_$language]}"; echo ""; exit 0; }
    else
        echo -e "${info_message[2_$language]} ${textcolor}v${version}${clear}"
        echo -e "${info_message[3_$language]} ${textcolor}v${new_version}${clear}"
    fi
}

extract_values() {
    inbound_num_tr=$(jq '[.inbounds[].tag] | index("trojan-in")' /etc/sing-box/config.json)
    users_tr=$(jq ".inbounds[${inbound_num_tr}].users" /etc/sing-box/config.json)

    if [[ ! -f /etc/haproxy/auth.lua ]]
    then
        inbound_num_vl=$(jq '[.inbounds[].tag] | index("vless-in")' /etc/sing-box/config.json)
        users_vl=$(jq ".inbounds[${inbound_num_vl}].users" /etc/sing-box/config.json)
        transport=$(jq -r '.inbounds[] | select(.tag == "trojan-in") | .transport.type' /etc/sing-box/config.json)
    fi

    if [[ $(jq 'any(.route.rules[]; .outbound == "warp" and (has("auth_user") | not))' /etc/sing-box/config.json) == "true" ]]
    then
        warp_domain_suffix=$(jq '.route.rules[] | select(.outbound == "warp" and (has("auth_user") | not)) | .domain_suffix' /etc/sing-box/config.json)
        warp_rule_set=$(jq '.route.rules[] | select(.outbound == "warp" and (has("auth_user") | not)) | .rule_set' /etc/sing-box/config.json)
    fi

    if [[ $(jq 'any(.outbounds[]; .tag == "proxy")' /etc/sing-box/config.json) == "true" ]]
    then
        chain_outbound=$(jq '.outbounds[] | select(.tag == "proxy")' /etc/sing-box/config.json)
    fi

    # Capture custom outbounds added by user
    custom_outbounds=$(jq -c '[.outbounds[] | select(.tag != "direct" and .tag != "warp" and .tag != "proxy" and .tag != "IPv4" and .tag != "block")]' /etc/sing-box/config.json 2>/dev/null)

    # Capture old rule_set tags for preservation during update
    old_rule_sets=()
    for tag in $(jq -r '.route.rule_set[].tag' /etc/sing-box/config.json)
    do
        old_rule_sets+=("$tag")
    done
}

insert_values() {
    inbound_num_tr=$(jq '[.inbounds[].tag] | index("trojan-in")' /etc/sing-box/config.json)
    inbound_num_vl=$(jq '[.inbounds[].tag] | index("vless-in")' /etc/sing-box/config.json)
    echo "$(jq ".inbounds[${inbound_num_tr}].users |= ${users_tr} | .inbounds[${inbound_num_tr}].transport.path = \"/${trojanpath}\"" /etc/sing-box/config.json)" > /etc/sing-box/config.json

    if [[ ! -f /etc/haproxy/auth.lua ]]
    then
        echo "$(jq ".inbounds[${inbound_num_vl}].users |= ${users_vl} | .inbounds[${inbound_num_vl}].transport.path = \"/${vlesspath}\"" /etc/sing-box/config.json)" > /etc/sing-box/config.json
        [[ "$transport" == "httpupgrade" ]] && echo "$(jq '.inbounds[].transport.type = "httpupgrade"' /etc/sing-box/config.json)" > /etc/sing-box/config.json
    else
        echo "$(jq "del(.inbounds[${inbound_num_tr}].transport.type, .inbounds[${inbound_num_tr}].transport.path, .inbounds[${inbound_num_vl}])" /etc/sing-box/config.json)" > /etc/sing-box/config.json
    fi

    if [[ -n $warp_domain_suffix ]]
    then
        warp_rule_num=$(jq '[.route.rules[] | (.outbound == "warp" and (has("auth_user") | not))] | index(true)' /etc/sing-box/config.json)
        echo "$(jq ".route.rules[${warp_rule_num}].domain_suffix |= ${warp_domain_suffix}" /etc/sing-box/config.json)" > /etc/sing-box/config.json
        [[ -n $warp_rule_set ]] && echo "$(jq ".route.rules[${warp_rule_num}].rule_set |= ${warp_rule_set}" /etc/sing-box/config.json)" > /etc/sing-box/config.json
    fi

    # Restore custom outbounds
    if [[ -n "$custom_outbounds" && "$custom_outbounds" != "[]" && "$custom_outbounds" != "null" ]]
    then
        echo "$(jq --argjson co "$custom_outbounds" '.outbounds += $co' /etc/sing-box/config.json)" > /etc/sing-box/config.json
    fi

    if [[ -n $chain_outbound ]]
    then
        insert_chain
    fi

    sed -i -e "s/RULESETPATH/${rulesetpath}/g" -e "s/${temprulesetpath}/${rulesetpath}/g" /etc/sing-box/config.json
    chmod -R 755 /var/www/${rulesetpath}
}

insert_chain() {
    # Remove old IPv4 and direct rules that conflict with chain
    if [[ $(jq 'any(.outbounds[]; .tag == "IPv4")' /etc/sing-box/config.json) == "true" ]]
    then
        echo "$(jq 'del(.outbounds[] | select(.tag == "IPv4"))' /etc/sing-box/config.json)" > /etc/sing-box/config.json
    fi

    if [[ $(jq 'any(.route.rules[]; .outbound == "IPv4")' /etc/sing-box/config.json) == "true" ]]
    then
        echo "$(jq 'del(.route.rules[] | select(.outbound == "IPv4"))' /etc/sing-box/config.json)" > /etc/sing-box/config.json
    fi

    # Add chain rule: all inbound traffic -> proxy (next server)
    chain_rule='{"inbound":["trojan-in","vless-in"],"outbound":"proxy"}'
    [[ -f /etc/haproxy/auth.lua ]] && chain_rule='{"inbound":["trojan-in"],"outbound":"proxy"}'
    echo "$(jq ".outbounds += [${chain_outbound}] | .route.rules += [${chain_rule}]" /etc/sing-box/config.json)" > /etc/sing-box/config.json
}

manage_rule_sets() {
    for ruleset_tag in "${old_rule_sets[@]}"
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

    chmod -R 755 /var/www/${rulesetpath}
}

update_services() {
    declare -A -g info_message=()
    info_message[1_ru]="${textcolor_light}Обновление пакетов...${clear}"
    info_message[1_en]="${textcolor_light}Updating packages...${clear}"

    echo ""
    echo -e "${info_message[1_$language]}"
    systemctl stop sing-box.service
    [[ "${warp_backend:-}" != "usque" ]] && systemctl stop warp-svc.service
    systemctl stop nginx.service
    [[ -f /etc/haproxy/auth.lua ]] && systemctl stop haproxy.service
    [[ -f /etc/apt/apt.conf.d/50unattended-upgrades ]] && systemctl stop unattended-upgrades.service

    extract_values
    cp -f /etc/sing-box/config.json /etc/sing-box/config.json.0
    [[ -f /etc/secret-sing-box/config ]] && cp -f /etc/secret-sing-box/config /etc/secret-sing-box/config.bak
    wget -O /etc/sing-box/config.json.1 https://raw.githubusercontent.com/zipfo/Simple-Sing-Box/main/Config-Templates/config.json

    if [[ $? -eq 0 && -s /etc/sing-box/config.json.1 ]] && jq empty /etc/sing-box/config.json.1 >/dev/null 2>&1
    then
        mv -f /etc/sing-box/config.json.1 /etc/sing-box/config.json
        insert_values
        manage_rule_sets
    else
        rm -f /etc/sing-box/config.json.1
    fi

    keyring_files=(/etc/apt/keyrings/sagernet.asc /usr/share/keyrings/nginx-archive-keyring.gpg)
    if command -v warp-cli > /dev/null 2>&1 || [[ "${warp_backend:-}" != "usque" ]]
    then
        curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
        keyring_files=(/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg "${keyring_files[@]}")
    fi
    curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc && chmod a+r /etc/apt/keyrings/sagernet.asc
    curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg > /dev/null
    gpg --dry-run --quiet --no-keyring --import --import-options import-show "${keyring_files[@]}"

    apt-mark unhold sing-box
    apt update -y && apt -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" full-upgrade -y
    apt-mark hold sing-box
    apt autoremove -y; apt autoclean -y
    mkdir -p /etc/systemd/system/sing-box.service.d
    echo -e "[Service]\nExecReload=/bin/kill -HUP \$MAINPID" > /etc/systemd/system/sing-box.service.d/override.conf
    systemctl daemon-reload

    # Verify sing-box config before starting service; rollback to config.json.0 if invalid
    if command -v sing-box >/dev/null 2>&1; then
        if ! sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1; then
            cp -f /etc/sing-box/config.json.0 /etc/sing-box/config.json
        fi
    fi

    systemctl start sing-box.service
    [[ "${warp_backend:-}" != "usque" ]] && systemctl start warp-svc.service
    systemctl start nginx.service
    [[ -f /etc/haproxy/auth.lua ]] && systemctl start haproxy.service
    [[ -f /etc/apt/apt.conf.d/50unattended-upgrades ]] && systemctl start unattended-upgrades.service
    echo ""
}

print_msg() {
    local ru="$1" en="$2"
    if [[ "$language" == "ru" ]]
    then
        echo -e "$ru"
    else
        echo -e "$en"
    fi
}

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

usque_release_arch() {
    case $(uname -m) in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l|armv7)
            echo "armv7"
            ;;
        armv6l|armv6)
            echo "armv6"
            ;;
        armv5l|armv5)
            echo "armv5"
            ;;
        *)
            return 1
            ;;
    esac
}

warpscout_release_arch() {
    case $(uname -m) in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            return 1
            ;;
    esac
}

install_usque_binaries() {
    local usque_arch warpscout_arch usque_tag usque_version warpscout_tag warpscout_version
    local tmp_dir expected_sum actual_sum

    usque_arch=$(usque_release_arch)
    warpscout_arch=$(warpscout_release_arch)
    if [[ -z $usque_arch || -z $warpscout_arch ]]
    then
        print_msg "${red}Архитектура $(uname -m) не поддерживается usque/warpscout${clear}" \
                  "${red}Architecture $(uname -m) is not supported by usque/warpscout${clear}"
        return 1
    fi

    tmp_dir=$(mktemp -d)
    [[ -z $tmp_dir ]] && return 1

    usque_tag=$(curl -fsSL --retry 3 https://api.github.com/repos/Diniboy1123/usque/releases/latest | jq -r '.tag_name // empty')
    if [[ -z $usque_tag ]]
    then
        rm -rf "$tmp_dir"
        return 1
    fi
    usque_version=${usque_tag#v}

    if ! curl -fsSL --retry 3 -o "$tmp_dir/usque.zip" "https://github.com/Diniboy1123/usque/releases/download/${usque_tag}/usque_${usque_version}_linux_${usque_arch}.zip" ||
       ! curl -fsSL --retry 3 -o "$tmp_dir/checksums.txt" "https://github.com/Diniboy1123/usque/releases/download/${usque_tag}/checksums.txt"
    then
        print_msg "${red}Не удалось скачать usque ${usque_version}${clear}" \
                  "${red}Failed to download usque ${usque_version}${clear}"
        rm -rf "$tmp_dir"
        return 1
    fi

    expected_sum=$(grep " usque_${usque_version}_linux_${usque_arch}.zip$" "$tmp_dir/checksums.txt" | awk '{print $1}')
    actual_sum=$(sha256sum "$tmp_dir/usque.zip" | awk '{print $1}')
    if [[ -z $expected_sum || "$expected_sum" != "$actual_sum" ]]
    then
        print_msg "${red}Проверка контрольной суммы usque не пройдена${clear}" \
                  "${red}usque checksum verification failed${clear}"
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! unzip -o -q "$tmp_dir/usque.zip" -d "$tmp_dir"
    then
        rm -rf "$tmp_dir"
        return 1
    fi

    warpscout_tag=$(curl -fsSL --retry 3 https://api.github.com/repos/vernette/warpscout/releases/latest | jq -r '.tag_name // empty')
    if [[ -z $warpscout_tag ]]
    then
        rm -rf "$tmp_dir"
        return 1
    fi
    warpscout_version=${warpscout_tag#v}

    if ! curl -fsSL --retry 3 -o "$tmp_dir/warpscout.tar.gz" "https://github.com/vernette/warpscout/releases/download/${warpscout_tag}/warpscout_${warpscout_version}_linux_${warpscout_arch}.tar.gz" ||
       ! tar -xzf "$tmp_dir/warpscout.tar.gz" -C "$tmp_dir" warpscout ||
       ! install -m 755 "$tmp_dir/warpscout" /usr/local/bin/warpscout
    then
        print_msg "${red}Не удалось установить warpscout ${warpscout_version}${clear}" \
                  "${red}Failed to install warpscout ${warpscout_version}${clear}"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Install usque last: a failed warpscout download above must not leave a new,
    # untested usque binary that would only start on the next reboot.
    [[ -x /usr/local/bin/usque ]] && cp -f /usr/local/bin/usque /usr/local/bin/usque.prev
    if ! install -m 755 "$tmp_dir/usque" /usr/local/bin/usque
    then
        rm -rf "$tmp_dir"
        return 1
    fi

    rm -rf "$tmp_dir"
    print_msg "  usque ${usque_version}, warpscout ${warpscout_version}" \
              "  usque ${usque_version}, warpscout ${warpscout_version}"
    return 0
}

usque_register_account() {
    mkdir -p /etc/warpscout /etc/usque
    chmod 700 /etc/warpscout /etc/usque

    if [[ ! -s /etc/warpscout/account.json ]] || ! jq -e '.masque' /etc/warpscout/account.json > /dev/null 2>&1
    then
        timeout 180 warpscout register -a /etc/warpscout/account.json > /dev/null 2>&1
    fi

    chmod 600 /etc/warpscout/account.json 2>/dev/null

    if ! jq -e '.masque' /etc/warpscout/account.json > /dev/null 2>&1
    then
        print_msg "${red}Не удалось зарегистрировать MASQUE-устройство Cloudflare${clear}" \
                  "${red}Could not register a MASQUE device with Cloudflare${clear}"
        return 1
    fi

    return 0
}

usque_scan_endpoint() {
    local endpoint sni_cmd sni=""
    local -a scan_cmd

    scan_cmd=(timeout 900 warpscout scan -p masque-h2 -P -a /etc/warpscout/account.json -best -conf /etc/usque/config.json -plain)
    endpoint=$("${scan_cmd[@]}" 2> /dev/null | tail -n 1 | tr -d '[:space:]')

    if [[ -z $endpoint ]]
    then
        print_msg "${textcolor_light}Endpoint не найден, подбираем SNI (может занять больше времени)...${clear}" \
                  "${textcolor_light}No endpoint found, searching for a working SNI (this can take longer)...${clear}"
        sni_cmd=$(timeout 1200 warpscout find-sni -p masque-h2 -a /etc/warpscout/account.json -plain 2> /dev/null | tail -n 1)
        sni=$(sed -n 's/.*-masque-sni[ =]\([^ ]*\).*/\1/p' <<< "$sni_cmd")

        if [[ -n $sni_cmd ]]
        then
            scan_cmd=(timeout 900 warpscout scan -p masque-h2 -P -a /etc/warpscout/account.json -best -conf /etc/usque/config.json -plain)
            [[ -n $sni ]] && scan_cmd+=(-masque-sni "$sni")
            endpoint=$("${scan_cmd[@]}" 2> /dev/null | tail -n 1 | tr -d '[:space:]')
        fi
    fi

    if [[ -z $endpoint || ! -s /etc/usque/config.json ]]
    then
        print_msg "${red}Рабочий MASQUE endpoint не найден${clear}" \
                  "${red}No working MASQUE endpoint found${clear}"
        return 1
    fi

    usque_port=${endpoint##*:}
    if [[ ! $usque_port =~ ^[0-9]+$ ]]
    then
        return 1
    fi

    usque_endpoint=$endpoint
    usque_sni=$sni
    chmod 600 /etc/usque/config.json

    print_msg "  endpoint: ${usque_endpoint}, MASQUE port: ${usque_port}${usque_sni:+, SNI: ${usque_sni}}" \
              "  endpoint: ${usque_endpoint}, MASQUE port: ${usque_port}${usque_sni:+, SNI: ${usque_sni}}"
    return 0
}

usque_write_service() {
    local sni_arg=""
    [[ -n $usque_sni ]] && sni_arg="-s ${usque_sni} "

    mkdir -p /etc/systemd/system
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
    local i trace

    for i in {1..30}
    do
        ss -ltn 2> /dev/null | grep -q "127.0.0.1:40000" && break
        sleep 1
    done

    ss -ltn 2> /dev/null | grep -q "127.0.0.1:40000" || return 1

    for i in {1..3}
    do
        trace=$(curl -s --max-time 20 --socks5-hostname 127.0.0.1:40000 https://cloudflare.com/cdn-cgi/trace 2> /dev/null)
        [[ "$trace" == *"warp=on"* ]] && return 0
        sleep 3
    done

    return 1
}

warp_cli_installed() {
    command -v warp-cli > /dev/null 2>&1
}

rollback_to_warp_cli() {
    if ! warp_cli_installed
    then
        print_msg "${red}usque не работает, а резервный warp-cli не установлен. Сервис оставлен включённым для повторной попытки.${clear}" \
                  "${red}usque is not working and the legacy warp-cli is not installed. The service is left running for another attempt.${clear}"
        return 1
    fi

    systemctl stop usque-warp.service > /dev/null 2>&1
    systemctl disable usque-warp.service > /dev/null 2>&1
    systemctl enable warp-svc.service > /dev/null 2>&1
    systemctl start warp-svc.service > /dev/null 2>&1
    set_ssb_config_value warp_backend warp-cli

    print_msg "${red}Выполнен откат на warp-cli: WARP продолжает работать по-старому${clear}" \
              "${red}Rolled back to warp-cli: WARP keeps working the old way${clear}"
    return 0
}

offer_warp_cli_removal() {
    warp_cli_installed || return 0

    print_msg "${textcolor}[?]${clear} WARP работает через usque (MASQUE HTTP/2), старый warp-cli больше не используется." \
              "${textcolor}[?]${clear} WARP now runs through usque (MASQUE HTTP/2), the legacy warp-cli is no longer used."
    print_msg "${textcolor}[?]${clear} Удалить warp-cli? (${textcolor}Enter${clear} — да, ${textcolor}x${clear} — оставить):" \
              "${textcolor}[?]${clear} Remove warp-cli? (${textcolor}Enter${clear} — yes, ${textcolor}x${clear} — keep):"
    read -r remove_warp_cli
    [[ -n $remove_warp_cli ]] && echo ""

    if [[ "$remove_warp_cli" == "x" ]]
    then
        print_msg "warp-cli оставлен установленным" \
                  "warp-cli has been kept installed"
        return 0
    fi

    apt-mark unhold cloudflare-warp > /dev/null 2>&1
    apt-get purge -y cloudflare-warp > /dev/null 2>&1
    rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg /etc/apt/sources.list.d/cloudflare-client.list
    rm -rf /etc/systemd/system/warp-svc.service.d
    systemctl daemon-reload

    if warp_cli_installed
    then
        print_msg "${red}Не удалось удалить cloudflare-warp, попробуйте позже${clear}" \
                  "${red}Could not remove cloudflare-warp, try again later${clear}"
    else
        print_msg "warp-cli удалён" \
                  "warp-cli has been removed"
    fi
    return 0
}

migrate_legacy_to_usque() {
    print_msg "${textcolor_light}Перевод WARP на usque (MASQUE HTTP/2 поверх TCP)...${clear}" \
              "${textcolor_light}Migrating WARP to usque (MASQUE HTTP/2 over TCP)...${clear}"
    print_msg "${textcolor_light}Поиск оптимального endpoint может занять несколько минут...${clear}" \
              "${textcolor_light}Scanning for the best endpoint may take a few minutes...${clear}"

    apt-get install -y curl unzip > /dev/null 2>&1

    if ! install_usque_binaries || ! usque_register_account || ! usque_scan_endpoint
    then
        print_msg "${red}Не удалось подготовить usque — WARP остаётся на warp-cli${clear}" \
                  "${red}Could not prepare usque — WARP stays on warp-cli${clear}"
        set_ssb_config_value warp_backend warp-cli
        return 1
    fi

    usque_write_service
    systemctl stop warp-svc.service > /dev/null 2>&1
    systemctl disable warp-svc.service > /dev/null 2>&1
    systemctl daemon-reload
    systemctl enable usque-warp.service > /dev/null 2>&1
    systemctl restart usque-warp.service > /dev/null 2>&1

    if ! usque_wait_ready
    then
        echo ""
        journalctl -u usque-warp.service -n 15 --no-pager 2> /dev/null
        rollback_to_warp_cli
        return 1
    fi

    set_ssb_config_value warp_backend usque
    set_ssb_config_value usque_sni "$usque_sni"
    set_ssb_config_value usque_endpoint "$usque_endpoint"
    set_ssb_config_value usque_port "$usque_port"
    set_ssb_config_value warp_installed_by_script true

    print_msg "${textcolor_light}WARP переведён на usque. Endpoint: ${usque_endpoint}${clear}" \
              "${textcolor_light}WARP has been migrated to usque. Endpoint: ${usque_endpoint}${clear}"
    offer_warp_cli_removal
    return 0
}

maintain_usque_backend() {
    local config_regenerated=0

    apt-get install -y curl unzip > /dev/null 2>&1

    if ! install_usque_binaries
    then
        print_msg "${red}Не удалось обновить usque — оставлена текущая версия${clear}" \
                  "${red}Could not update usque — keeping the current version${clear}"
        return 1
    fi

    if [[ ! -s /etc/usque/config.json ]]
    then
        if ! usque_register_account || ! usque_scan_endpoint
        then
            rollback_to_warp_cli
            return 1
        fi
        config_regenerated=1
        set_ssb_config_value usque_sni "$usque_sni"
        set_ssb_config_value usque_endpoint "$usque_endpoint"
        set_ssb_config_value usque_port "$usque_port"
    fi

    [[ -z ${usque_port:-} && -n ${usque_endpoint:-} ]] && usque_port=${usque_endpoint##*:}
    if [[ -z ${usque_port:-} ]]
    then
        usque_port=443
    fi

    if [[ $config_regenerated -eq 1 || ! -f /etc/systemd/system/usque-warp.service ]]
    then
        usque_write_service
    fi

    systemctl daemon-reload
    systemctl enable usque-warp.service > /dev/null 2>&1
    systemctl restart usque-warp.service > /dev/null 2>&1

    if usque_wait_ready
    then
        print_msg "${textcolor_light}WARP работает через usque (MASQUE HTTP/2)${clear}" \
                  "${textcolor_light}WARP is running through usque (MASQUE HTTP/2)${clear}"
        offer_warp_cli_removal
        return 0
    fi

    echo ""
    journalctl -u usque-warp.service -n 15 --no-pager 2> /dev/null

    if [[ -x /usr/local/bin/usque.prev ]]
    then
        install -m 755 /usr/local/bin/usque.prev /usr/local/bin/usque
        systemctl restart usque-warp.service > /dev/null 2>&1
        if usque_wait_ready
        then
            print_msg "${red}Новая версия usque не работает, восстановлена предыдущая${clear}" \
                      "${red}The new usque build failed, the previous one has been restored${clear}"
            return 0
        fi
    fi

    rollback_to_warp_cli
    return 1
}

migrate_warp_backend() {
    [[ "${warp_option:-}" == "1" ]] || return 0

    if ! jq -e 'any(.outbounds[]; .tag == "warp")' /etc/sing-box/config.json > /dev/null 2>&1
    then
        return 0
    fi

    if [[ "${warp_backend:-}" == "usque" ]]
    then
        maintain_usque_backend
        return $?
    fi

    if ! warp_cli_installed
    then
        return 0
    fi

    migrate_legacy_to_usque
    return $?
}

check_sync_client() {
    declare -A -g info_message=()
    info_message[1_ru]="${textcolor_light}Синхронизация настроек в клиентских конфигах с GitHub...${clear}"
    info_message[1_en]="${textcolor_light}Syncing settings in client configs with GitHub...${clear}"

    echo -e "${info_message[1_$language]}"
    check_users
    declare -f check_github_template &> /dev/null && check_github_template || validate_template   # Legacy

    if [[ "$stop_sync" != "1" ]]
    then
        sync_template_file="template.json"
        declare -f sync_client_configs_main &> /dev/null && sync_client_configs_main || sync_client_configs_github   # Legacy
    fi
}

update_sub_page() {
    declare -A -g info_message=()
    info_message[1_ru]="${textcolor_light}Обновление страницы выдачи подписок...${clear}"
    info_message[1_en]="${textcolor_light}Updating subscription page...${clear}"

    echo -e "${info_message[1_$language]}"
    data_vrnt="both"
    [[ -f /etc/haproxy/auth.lua ]] && data_vrnt="novless"
    wget -O /var/www/${subspath}/sub.html https://raw.githubusercontent.com/zipfo/Simple-Sing-Box/main/Subscription-Page/sub.html
    sed -i -e "s/DOMAIN/${domain}/g" -e "s/SUBSCRIPTION-PATH/${subspath}/g" -e "s/html lang=\"en\" data-vrnt=\"both\"/html lang=\"${language}\" data-vrnt=\"${data_vrnt}\"/g" /var/www/${subspath}/sub.html
}

update_scripts() {
    declare -A -g info_message=()
    info_message[1_ru]="${textcolor_light}Обновление скриптов...${clear}"
    info_message[1_en]="${textcolor_light}Updating scripts...${clear}"

    echo -e "${info_message[1_$language]}"
    wget -O /usr/local/bin/sbmanager https://raw.githubusercontent.com/zipfo/Simple-Sing-Box/main/Scripts/sb-manager.sh
    wget -O /usr/local/bin/rsupdate https://raw.githubusercontent.com/zipfo/Simple-Sing-Box/main/Scripts/ruleset-update.sh
    chmod +x /usr/local/bin/sbmanager /usr/local/bin/rsupdate
    grep -q "alias ssb=" /etc/bash.bashrc || echo "alias ssb='/usr/local/bin/sbmanager'" >> /etc/bash.bashrc   # Legacy
    grep -q "alias sudo=" /etc/bash.bashrc || echo "alias sudo='sudo '" >> /etc/bash.bashrc   # Legacy
    [[ ! $(crontab -l) =~ "PATH=" ]] && crontab -l | sed '1i PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin' | crontab -   # Legacy
    mkdir -p /etc/secret-sing-box
    if [[ ! -f /etc/secret-sing-box/user-routes ]]; then
        touch /etc/secret-sing-box/user-routes
        for u in $(jq -r '[(.inbounds[]?.users // [])[].name] | unique[]' /etc/sing-box/config.json 2>/dev/null); do
            echo "${u}:direct:default" >> /etc/secret-sing-box/user-routes
        done
    fi
    /usr/local/bin/sbmanager --apply-routes >/dev/null 2>&1 || true
    echo ""
}

final_text() {
    final_text_ru() {
        echo -e "${textcolor}Установка обновления v${new_version} завершена!${clear}"
        echo "Перезагружать сервер не обязательно"
        echo ""
        echo "При проблемах с Sing-Box запустите команду:"
        echo "cp -f /etc/sing-box/config.json.0 /etc/sing-box/config.json && systemctl restart sing-box.service"
    }

    final_text_en() {
        echo -e "${textcolor}The update v${new_version} has been installed!${clear}"
        echo "It is not necessary to reboot the server"
        echo ""
        echo "If you are having problems with Sing-Box, run this command:"
        echo "cp -f /etc/sing-box/config.json.0 /etc/sing-box/config.json && systemctl restart sing-box.service"
    }

    final_text_${language}
    echo ""
    echo ""
    sleep 1
    exit 0
}

main_menu() {
    stop_sync="1"
}

update_menu() {
    menu_text_ru() {
        echo ""
        echo -e "${textcolor}[?]${clear} Выберите вариант обновления:"
        echo "0 - Выйти"
        echo "1 - Обновить всё"
        echo "2 - Обновить без синхронизации клиентских конфигов с GitHub"
        read -r update_option
        [[ -n $update_option ]] && echo ""
    }

    menu_text_en() {
        echo ""
        echo -e "${textcolor}[?]${clear} Select an update option:"
        echo "0 - Exit"
        echo "1 - Update everything"
        echo "2 - Update without syncing client configs with GitHub"
        read -r update_option
        [[ -n $update_option ]] && echo ""
    }

    menu_text_${language}

    case $update_option in
        1)
        update_services
        migrate_warp_backend
        check_sync_client
        update_sub_page
        update_scripts
        final_text
        ;;
        2)
        update_services
        migrate_warp_backend
        update_sub_page
        update_scripts
        final_text
        ;;
        *)
        exit 0
    esac
}

check_parent
check_update
get_data
update_menu
