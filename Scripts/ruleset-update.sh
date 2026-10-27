#!/bin/bash

rulesetpath=$(grep "alias /var/www/" /etc/nginx/nginx.conf | head -n 1 | cut -d "/" -f 4)

# Обновляем rule sets (4 файла)
wget -q -O /var/www/${rulesetpath}/geoip-ru.srs.1 https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs && mv -f /var/www/${rulesetpath}/geoip-ru.srs.1 /var/www/${rulesetpath}/geoip-ru.srs
wget -q -O /var/www/${rulesetpath}/geosite-category-gov-ru.srs.1 https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-gov-ru.srs && mv -f /var/www/${rulesetpath}/geosite-category-gov-ru.srs.1 /var/www/${rulesetpath}/geosite-category-gov-ru.srs
wget -q -O /var/www/${rulesetpath}/geosite-category-ads-all.srs.1 https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs && mv -f /var/www/${rulesetpath}/geosite-category-ads-all.srs.1 /var/www/${rulesetpath}/geosite-category-ads-all.srs
wget -q -O /var/www/${rulesetpath}/geosite-ru-blocked.srs.1 https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/geosite-ru-blocked.srs && mv -f /var/www/${rulesetpath}/geosite-ru-blocked.srs.1 /var/www/${rulesetpath}/geosite-ru-blocked.srs

chmod -R 755 /var/www/${rulesetpath}

# Additional optimization:
journalctl --vacuum-time=7days &> /dev/null
[[ $(systemctl is-active warp-svc.service) == "active" ]] && systemctl restart warp-svc.service
