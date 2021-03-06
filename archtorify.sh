#!/usr/bin/env bash

# ===================================================================
# archtorify.sh
#
# version: 1.23.1
#
# Arch Linux - Transparent proxy through Tor
#
# Copyright (C) 2015-2021 Brainfuck
#
#
# GNU GENERAL PUBLIC LICENSE
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# ===================================================================


## General
#
# program information
readonly prog_name="archtorify"
readonly version="1.23.1"
readonly signature="Copyright (C) 2021 Brainfuck"
readonly git_url="https://github.com/brainfucksec/archtorify"

# set colors for stdout
export red="$(tput setaf 1)"
export green="$(tput setaf 2)"
export yellow="$(tput setaf 3)"
export blue="$(tput setaf 4)"
export magenta="$(tput setaf 5)"
export cyan="$(tput setaf 6)"
export white="$(tput setaf 7)"
export b="$(tput bold)"
export reset="$(tput sgr0)"


## Directories
#
# config files:
readonly config_dir="/usr/share/archtorify/data"
# backups:
readonly backup_dir="/usr/share/archtorify/backups"


## Show program banner
banner() {
printf "${b}${cyan}
 _____         _   _           _ ___
|  _  |___ ___| |_| |_ ___ ___|_|  _|_ _
|     |  _|  _|   |  _| . |  _| |  _| | |
|__|__|_| |___|_|_|_| |___|_| |_|_| |_  |
                                    |___| v${version}

=[ Transparent proxy through Tor
=[ brainfucksec
${reset}\\n\\n"
}


## Print a message and exit with (1) when an error occurs
die() {
    printf "${red}%s${reset}\\n" "$@" >&2
    exit 1
}

## Check if the program run as a root
check_root() {
    if [[ "${UID}" -ne 0 ]]; then
        die "[ERROR] Please run this program as a root!"
    fi
}


## Display program version
print_version() {
    printf "%s\\n" "${prog_name} ${version}"
    printf "%s\\n" "${signature}"
    printf "%s\\n" "License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>"
    printf "%s\\n" "This is free software: you are free to change and redistribute it."
    printf "%s\\n" "There is NO WARRANTY, to the extent permitted by law."
    exit 0
}


## Replace system files
#
# Backup default system files in /usr/share/archtorify/backups directory and
# replace them with files of /usr/share/archtorify/data directory.
#
# Function usage: replace_file <default_file> <new_file>
# e.g.: replace_file /etc/tor/torrc torrc
replace_file() {
    local default_file="$1"
    local new_file="$2"

    # backup
    if ! cp "$1" "${backup_dir}/$2.backup" 2>/dev/null; then
        die "[ERROR] can't backup '$1'"
    fi

    # replace
    if ! cp "${config_dir}/$2" "$1" 2>/dev/null; then
        die "[ERROR] can't set '$1'"
    fi
}


## iptables settings
#
# This function is used with args in start() & stop() for set/restore iptables.
#
# Args:
#       tor_proxy -> set rules for Tor transparent proxy
#       default   -> restore default iptables
setup_iptables() {
    case "$1" in
        tor_proxy)
            printf "${b}${green}%s${reset} %s\\n" "==>" "Set iptables rules"

            ## flush current iptables rules
            iptables -F
            iptables -X
            iptables -t nat -F
            iptables -t nat -X
            iptables -P INPUT ACCEPT
            iptables -P FORWARD ACCEPT
            iptables -P OUTPUT ACCEPT

            # copy file /usr/share/archtorify/data/iptables.rules in the
            # /etc/iptables/ directory
            if ! cp -f "${config_dir}/iptables.rules" /etc/iptables/iptables.rules 2>/dev/null; then
                die "[ERROR] can't copy file /etc/iptables/iptables.rules"
            fi

            # set new iptables rules
            if ! iptables-restore < /etc/iptables/iptables.rules 2>/dev/null; then
                die "[ERROR] can't set iptables rules"
            fi

            # start iptables service
            if ! systemctl start iptables 2>/dev/null; then
                die "[ERROR] systemd error, exit!"
            fi
        ;;

        # restore default
        default)
            printf "${b}${green}%s${reset} %s\\n" "==>" "Restore default iptables"

            # flush iptables rules
            iptables -F
            iptables -X
            iptables -t nat -F
            iptables -t nat -X
            iptables -P INPUT ACCEPT
            iptables -P FORWARD ACCEPT
            iptables -P OUTPUT ACCEPT

            # rewrite default /etc/iptables.rules file
            # ----------------------------------------
            printf "# Empty iptables rule file
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT
" > "/etc/iptables/iptables.rules"
            # ----------------------------------------

            printf "${b}${green}%s${reset} %s\\n" "==>" "Stop Tor service"
            systemctl stop tor.service iptables

        ;;
    esac

}


## Check program settings
#
# - tor package
# - program folders, see: ${backup_dir}, ${config_dir}
# - tor systemd service file: /usr/lib/systemd/system/tor.service
# - tor configuration file: /etc/tor/torrc
# - directory permissions: /var/lib/tor
check_settings() {
    printf "${b}${cyan}%s${reset} ${b}%s${reset}\\n" "::" "Check program settings"

    if ! hash tor 2>/dev/null; then
        die "[ERROR] tor isn't installed, exit"
    fi

    if [[ ! -d "${backup_dir}" ]]; then
        die "[ERROR] directory '${backup_dir}' not exist, run makefile first!"
    fi

    if [[ ! -d "${config_dir}" ]]; then
        die "[ERROR] directory '${config_dir}' not exist, run makefile first!"
    fi

    # check /usr/lib/systemd/system/tor.service
    #
    # grep required strings from existing file
    grep -q -x '\[Service\]' /usr/lib/systemd/system/tor.service
    local string1=$?

    grep -q -x 'User=root' /usr/lib/systemd/system/tor.service
    local string2=$?

    grep -q -x 'Group=root' /usr/lib/systemd/system/tor.service
    local string3=$?

    grep -q -x 'Type=simple' /usr/lib/systemd/system/tor.service
    local string4=$?

    # if required strings does not exists copy new tor.service file
    if [[ "$string1" -ne 0 ]] ||
       [[ "$string2" -ne 0 ]] ||
       [[ "$string3" -ne 0 ]] ||
       [[ "$string4" -ne 0 ]]; then

        printf "${b}${green}%s${reset} %s\\n" \
                "==>" "Set file: /usr/lib/systemd/system/tor.service"
        replace_file /usr/lib/systemd/system/tor.service tor.service
    fi

    # check /var/lib/tor permissions
    #
    # required:
    # -rwx------  tor tor
    # (700)
    if [[ "$(stat -c '%U' /var/lib/tor)" != "tor" ]] &&
        [[ "$(stat -c '%a' /var/lib/tor)" != "700" ]]; then

        printf "${b}${green}%s${reset} %s\\n" \
                "==>" "Set permissions of /var/lib/tor directory"
        chown -R tor:tor /var/lib/tor
        chmod -R 700 /var/lib/tor
    fi

    # check /etc/tor/torrc
    if [[ ! -f /etc/tor/torrc ]]; then
        die "[ERROR] /etc/tor/torrc file not exist, check Tor configuration"
    fi

    # if torrc exist grep required strings
    grep -q -x 'User tor' /etc/tor/torrc
    local string1=$?

    grep -q -x 'SocksPort 9050' /etc/tor/torrc
    local string2=$?

    grep -q -x 'DNSPort 53' /etc/tor/torrc
    local string3=$?

    grep -q -x 'TransPort 9040' /etc/tor/torrc
    local string4=$?

    # if required strings does not exists copy file
    # /usr/share/archtorify/data/torrc
    if [[ "$string1" -ne 0 ]] ||
       [[ "$string2" -ne 0 ]] ||
       [[ "$string3" -ne 0 ]] ||
       [[ "$string4" -ne 0 ]]; then

        printf "${b}${green}%s${reset} %s\\n" "==>" "Set /etc/tor/torrc"
        replace_file /etc/tor/torrc torrc
    fi

    # reload systemd daemons for save changes
    printf "${b}${green}%s${reset} %s\\n" "==>" "Reload systemd daemons"
    systemctl --system daemon-reload
}


## Check public IP address
#
# Make an HTTP request to the URL in the list, if the first request fails, try
# with the next, then print the IP address.
#
# Thanks to "NotMilitaryAI" for this function
check_ip() {
    printf "${b}${cyan}%s${reset} ${b}%s${reset}\\n" \
            "::" "Check public IP Address"

    local url_list=(
        'http://ip-api.com/'
        'https://ipleak.net/json/'
        'https://ipinfo.io/'
        'https://api.myip.com/'
    )

    for url in "${url_list[@]}"; do
        local request="$(curl -s "$url")"
        local response="$?"

        if [[ "$response" -ne 0 ]]; then
            continue
        fi

        printf "%s\\n" "${request}"
        break
    done
}

## Check status of program and services
#
# - tor.service
# - tor settings (check if Tor works correctly)
# - public IP address
check_status() {
    printf "${b}${cyan}%s${reset} ${b}%s${reset}\\n" \
            "::" "Check current status of Tor service"

    if systemctl is-active tor.service >/dev/null 2>&1; then
        printf "${b}${green}%s${reset} ${b}%s${reset}\\n\\n" \
                "[OK]" "Tor service is active"
    else
        die "[-] Tor service is not running! exit"
    fi

    # make HTTP request with curl at: https://check.torproject.org/
    # and grep the necessary strings from the html page to test connection
    # with tor
    printf "${b}${cyan}%s${reset} ${b}%s${reset}\\n" \
            "::" "Check Tor network settings"

    # curl option details:
    #   --socks5 <host[:port]> SOCKS5 proxy on given host + port
    #   --socks5-hostname <host[:port]> SOCKS5 proxy, pass host name to proxy
    #
    #   `-L` and `tac` for avoid error: "(23) Failed writing body"
    #   https://github.com/kubernetes/helm/issues/2802
    #   https://stackoverflow.com/questions/16703647/why-curl-return-and-error-23-failed-writing-body
    local hostport="localhost:9050"
    local url="https://check.torproject.org/"

    if curl -s -m 5 --socks5 "${hostport}" --socks5-hostname "${hostport}" -L "${url}" \
        | cat | tac | grep -q 'Congratulations'; then
        printf "${b}${green}%s${reset} ${b}%s${reset}\\n\\n" \
                "[OK]" "Your system is configured to use Tor"
    else
        printf "${red}%s${reset}\\n\\n" "[!] Your system is not using Tor"
        printf "%s\\n" "try another Tor circuit with '${prog_name} --restart'"
        exit 1
    fi

    check_ip
}


## Start transparent proxy through Tor
start() {
    banner
    check_root
    sleep 2
    check_settings

    # stop tor.service before changing network settings
    if systemctl is-active tor.service >/dev/null 2>&1; then
        systemctl stop tor.service
    fi

    printf "\\n${b}${cyan}%s${reset} ${b}%s${reset}\\n" \
            "::" "Starting Transparent Proxy"

    # DNS settings: /etc/resolv.conf:
    #
    # Configure system's DNS resolver to use Tor's DNSPort
    # on the loopback interface, i.e. write nameserver 127.0.0.1
    # to etc/resolv.conf file
    printf "${b}${green}%s${reset} %s\\n" "==>" "Configure DNS to use Tor's DNSPort"

    # backup current resolv.conf
    if ! cp /etc/resolv.conf "${backup_dir}/resolv.conf.backup"; then
        die "[ERROR] can't backup /etc/resolv.conf"
    fi

    # write new nameserver
    printf "%s\\n" "nameserver 127.0.0.1" > /etc/resolv.conf

    # disable IPv6 with sysctl
    printf "${b}${green}%s${reset} %s\\n" "==>" "Disable IPv6 with sysctl"
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1

    # restart tor.service
    printf "${b}${green}%s${reset} %s\\n" "==>" "Start Tor service"

    if ! systemctl start tor.service 2>/dev/null; then
        die "[ERROR] can't start tor.service, exit!"
    fi

    # iptables settings
    setup_iptables tor_proxy

    # check program status
    printf "\\n"
    check_status

    printf "\\n${b}${green}%s${reset} ${b}%s${reset}\\n" \
            "[OK]" "Transparent Proxy activated, your system is under Tor"
}


## Stop transparent proxy
#
# stop connection with Tor Network and return to clearnet navigation
stop() {
    check_root

    if systemctl is-active tor.service >/dev/null 2>&1; then
        printf "${b}${cyan}%s${reset} ${b}%s${reset}\\n" \
                "::" "Stopping Transparent Proxy"

        # restore default iptables
        setup_iptables default

        # restore /etc/resolv.conf:
        #
        # restore file with resolvconf program if exists, otherwise copy the
        # original file from backup directory
        printf "${b}${green}%s${reset} %s\\n" \
                "==>" "Restore /etc/resolv.conf file with default DNS"

        if hash resolvconf 2>/dev/null; then
            resolvconf -u
        else
            cp "${backup_dir}/resolv.conf.backup" /etc/resolv.conf
        fi

        # enable IPv6
        printf "${b}${green}%s${reset} %s\\n" "==>" "Enable IPv6"
        sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
        sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1

        # restore default /etc/tor/torrc
        printf "${b}${green}%s${reset} %s\\n" "==>" "Restore default /etc/tor/torrc"
        cp "${backup_dir}/torrc.backup" /etc/tor/torrc

        # restore default /usr/lib/systemd/system/tor.service
        printf "${b}${green}%s${reset} %s\\n" \
                "==>" "Restore default /usr/lib/systemd/system/tor.service"

        cp "${backup_dir}/tor.service.backup" /usr/lib/systemd/system/tor.service


        printf "\\n${b}${green}%s${reset} ${b}%s${reset}\\n" \
                "[-]" "Transparent Proxy stopped"
        exit 0
    else
        die "[-] Tor service is not running! exit"
    fi
}


## Restart
#
# restart tor.service (i.e. get new Tor exit node) and change public IP address
restart() {
    check_root

    if systemctl is-active tor.service >/dev/null 2>&1; then
        printf "${b}${cyan}%s${reset} ${b}%s${reset}\\n" \
                "::" "Restart Tor service and change IP"

        systemctl restart tor.service iptables
        sleep 1

        printf "${b}${green}%s${reset} ${b}%s${reset}\\n\\n" \
                "[OK]" "Tor Exit Node changed"

        check_ip
        exit 0
    else
        die "[-] Tor service is not running! exit"
    fi
}


## Show help menù
usage() {
    printf "%s\\n" "${prog_name} ${version}"
    printf "%s\\n" "Arch Linux - Transparent proxy through Tor"
    printf "%s\\n\\n" "${signature}"

    printf "%s\\n\\n" "Usage: ${prog_name} [option]"

    printf "%s\\n\\n" "Options:"

    printf "%s\\n" "-h, --help      show this help message and exit"
    printf "%s\\n" "-t, --tor       start transparent proxy through tor"
    printf "%s\\n" "-c, --clearnet  reset iptables and return to clearnet navigation"
    printf "%s\\n" "-s, --status    check status of program and services"
    printf "%s\\n" "-i, --ipinfo    show public IP"
    printf "%s\\n" "-r, --restart   restart tor service and change Tor exit node"
    printf "%s\\n\\n" "-v, --version   display program version and exit"

    printf "%s\\n" "Project URL: ${git_url}"
    printf "%s\\n" "Report bugs: ${git_url}/issues"

    exit 0
}


## Main function
#
# parse command line arguments and start program
main() {
    if [[ "$#" -eq 0 ]]; then
        printf "%s\\n" "${prog_name}: Argument required"
        printf "%s\\n" "Try '${prog_name} --help' for more information."
        exit 1
    fi

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -t | --tor)
                start
                ;;
            -c | --clearnet)
                stop
                ;;
            -r | --restart)
                restart
                ;;
            -s | --status)
                check_status
                ;;
            -i | --ipinfo)
                check_ip
                ;;
            -v | --version)
                print_version
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            -- | -* | *)
                printf "%s\\n" "${prog_name}: Invalid option '$1'"
                printf "%s\\n" "Try '${prog_name} --help' for more information."
                exit 1
                ;;
        esac
        shift
    done
}

main "$@"
