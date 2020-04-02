#!/bin/bash

# Functions

query_account_id () {
    get_account_id=`curl -X GET "https://api.cloudflare.com/client/v4/accounts?page=1&per_page=20&direction=desc" -H "X-Auth-Email: ${1}" -H "X-Auth-Key: ${2}" -H "Content-Type: application/json" | jq ".result[0].id"`
    
    echo $get_account_id | sed -e 's/^"//' -e 's/"$//'
}

query_account_name () {
    get_account_name=`curl -X GET "https://api.cloudflare.com/client/v4/accounts?page=1&per_page=20&direction=desc" -H "X-Auth-Email: ${1}" -H "X-Auth-Key: ${2}" -H "Content-Type: application/json" | jq ".result[0].name"`
    
    echo $get_account_name | sed -e 's/^"//' -e 's/"$//'
}

query_zone_id () {
    get_zone_id=`curl -X GET "https://api.cloudflare.com/client/v4/zones?name=${1}&status=active&account.id=${2}&account.name=${3}&page=1&per_page=20&order=status&direction=desc&match=all" -H "X-Auth-Email: ${4}" -H "X-Auth-Key: ${5}" -H "Content-Type: application/json" | jq ".result[0].id"`
    
    echo $get_zone_id | sed -e 's/^"//' -e 's/"$//'
}

# Enter credentials and options

read -p "Enter Cloudflare account e-mail: " cf_email
read -p "Enter Cloudflare API key: " cf_api_key
read -p "Enter the main domain (e.g. yourdomain.com): " cf_domain_name
read -p "Enter server external IP: " host_ip
read -p "Enter path to Apache config file: " apache_config
read -p "Enter list of subdomains to add (space separated): " subdomains_list_input

cf_account_id=$(query_account_id "$cf_email" "$cf_api_key")
cf_account_name=$(query_account_name "$cf_email" "$cf_api_key")

cf_zone_id=$(query_zone_id "$cf_domain_name" "$cf_account_id" "$cf_account_name" "$cf_email" "$cf_api_key")

domain_suffix=".$cf_domain_name"

subdomains_list=($subdomains_list_input)

log_file='cf_push_log'

#DEBUG
: <<'END'
echo $cf_email
echo $cf_api_key
echo $cf_domain_name
echo $host_ip
echo $apache_config
echo $subdomains_list
echo $cf_account_id
echo $cf_account_name
echo $cf_zone_id
echo $domain_suffix
END
#DEBUG END

for subdomain in "${subdomains_list[@]}"; do
    subdomain_A="$subdomain$domain_suffix"
    subdomain_CNAME="www.$subdomain"

    # echo "${subdomain_A}"
    # echo "${subdomain_CNAME}"

    push_cf_update_A=`curl -X POST "https://api.cloudflare.com/client/v4/zones/${cf_zone_id}/dns_records" -H "X-Auth-Email: ${cf_email}" -H "X-Auth-Key: ${cf_api_key}" -H "Content-Type:application/json" --data "{\"type\":\"A\",\"name\":\"${subdomain_A}\",\"content\":\"${host_ip}\",\"ttl\":1,\"priority\":10,\"proxied\":false}"`

    echo "${push_cf_update_A}\n\n" >> $log_file

    sleep 1s

    push_cf_update_CNAME=`curl -X POST "https://api.cloudflare.com/client/v4/zones/${cf_zone_id}/dns_records" -H "X-Auth-Email: ${cf_email}" -H "X-Auth-Key: ${cf_api_key}" -H "Content-Type:application/json" --data "{\"type\":\"CNAME\",\"name\":\"${subdomain_CNAME}\",\"content\":\"${subdomain_A}\",\"ttl\":1,\"priority\":10,\"proxied\":false}"`

    echo "${push_cf_update_CNAME}\n\n" >> $log_file

    sleep 1s
    
    get_serveralias_apache=`grep ServerAlias ${apache_config} | head -1`
    merge_serveralias_apache=$get_serveralias_apache' '$subdomain_A' www.'$subdomain_A

    push_apache_update=`sed -i "s/${get_serveralias_apache}/${merge_serveralias_apache}/g" $apache_config`

    echo "${merge_serveralias_apache}\n\n" >> $log_file
    
    sleep 1s
done

