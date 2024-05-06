#!/bin/bash

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    echo "Usage: $0 [-d <domain> | -f <domain_list_file>] [-r]"
    exit 1
fi

mkdir -p .temp

domain=""
file=""
resolve_flag="false"

while getopts ":d:f:r" option; do
    case "${option}" in
        d)
            domain="${OPTARG}"
            ;;
        f)
            file="${OPTARG}"
            ;;
        r)
            resolve_flag="true"
            ;;
        *)
            echo "Invalid option: ${OPTARG}"
            exit 1
            ;;
    esac
done

wayback() {
    local domain="$1"
    local output_path="$2"
    curl -sk "http://web.archive.org/cdx/search/cdx?url=*.$domain&output=txt&fl=original&collapse=urlkey&page=" | awk -F/ '{gsub(/:.*/, "", $3); print $3}' | sort -u | anew "$output_path/wayback.txt"
}

crt() {
    local domain="$1"
    local output_path="$2"
    curl -sk "https://crt.sh/?q=%.$domain&output=json" | tr ',' '\n' | awk -F'"' '/name_value/ {gsub(/\*\./, "", $4); gsub(/\\n/,"\n",$4);print $4}' | anew "$output_path/crt.txt"
}

abuseipdb() {
    local domain="$1"
    local output_path="$2"
    curl -s "https://www.abuseipdb.com/whois/$domain" -H "user-agent: firefox" -b "abuseipdb_session=" | grep -E '<li>\w.*</li>' | sed -E 's/<\/?li>//g' | sed -e "s/$/.$domain/" | anew "$output_path/abuseipdb.txt"
}

bufferover() {
    local domain="$1"
    local output_path="$2"
    curl -s "https://dns.bufferover.run/dns?q=.$domain" | grep $domain | awk -F, '{gsub("\"", "", $2); print $2}' | anew "$output_path/bufferover.txt"
}

enumerate_domain() {
    local domain="$1"
    local output_path=".temp/"
    echo "Enumerating subdomains for $domain..."
    amass enum -active -d "$domain" -o ".temp/amass-active.txt" || echo "Amass active enumeration failed for $domain"
    amass enum -active -d "$domain" -o ".temp/amass-active.txt" || echo "Amass active enumeration failed for $domain"
    assetfinder --subs-only "$domain" | tee ".temp/assetfinder.txt" || echo "Assetfinder enumeration failed for $domain"
    subfinder -d "$domain" -o ".temp/subfinder.txt" || echo "Subfinder enumeration failed for $domain"
    findomain -t "$domain" -u ".temp/findomain.txt"  || echo "Findomain enumeration failed for $domain"
    wayback "$domain" "$output_path"
    crt "$domain" "$output_path"
    abuseipdb "$domain" "$output_path"
    bufferover "$domain" "$output_path"
    echo "Subdomain enumeration completed for $domain."
    cat .temp/* | sort -u > domains.txt
}

enumerate_file() {
    local file="$1"
    
    echo "Enumerating subdomains from file $file..."
    amass enum -active -df "$file" -o ".temp/amass-active.txt" || echo "Amass active enumeration failed for $domain"
    amass enum -active -df "$file" -o ".temp/amass-active.txt" || echo "Amass active enumeration failed for $domain"
    subfinder -dL "$file" -o ".temp/subfinder.txt" || echo "Subfinder enumeration failed for $domain"
    findomain -f "$file" -u ".temp/findomain.txt" || echo "Findomain enumeration failed for $domain"
    while IFS= read -r domain; do
        mkdir -p .temp/roots/$domain
        local output_path=".temp/roots/$domain"
        assetfinder --subs-only "$domain" | tee ".temp/roots/$domain/assetfinder.txt" || echo "Assetfinder enumeration failed for $domain"
        wayback "$domain" "$output_path"
        crt "$domain" "$output_path"
        abuseipdb "$domain" "$output_path"
        bufferover "$domain" "$output_path"
        cat .temp/roots/$domain/* > .temp/$domain.txt
    done < "$file"
    
    cat .temp/*.txt > domains.txt
    echo "Subdomain enumeration from file $file completed."
}

resolve_domains() {
    echo "Resolving domains using httpx..."
    httpx -l domains.txt -o hosts.txt || echo "Error: httpx failed to resolve domains"
    echo "Domain resolution completed."
}

if [ ! -z "$domain" ]; then
    enumerate_domain "$domain"
    echo "All subdomain enumerations completed."

elif [ ! -z "$file" ]; then
    enumerate_file "$file"
    echo "All subdomain enumerations completed."

else
    echo "Error: No domain or file specified."
    exit 1
fi

if [ "$resolve_flag" == "true" ]; then
    resolve_domains
fi