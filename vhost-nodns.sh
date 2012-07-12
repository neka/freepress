#!/bin/bash

# freebsd wordpress setup script v1.0
#
# requirements: freebsd, apache 2.2, php 5.x, and mysql 5.x, and root access
#
# you will need to add the following to your httpd.conf
#
# Include etc/apache22/vhosts/*.conf
#
# vhosts being the sub directory to store your apache domain .conf files
#
# script process
#
# a. checks if a valid ip address and valid domain
# b. checks if domain matches ip address, and if ip is on this system
# c. creates virtual host
# d. creates proper folders and permissions for domain
# e. reloads apache with your domain added
# f. creates mysql database, if none specified takes domain minus extension, also checks if it exists already
# g. downloads latest wordpress version or whatever version you select
# h. creates proper secure salts for your wp-config
# i. adds database info to your wp-config

#### edit the following to fit your freebsd server

# user login
username="username"

# directory to create the htdocs folders for domains
htdocs="domains"

# mysql username
db_user="mysql_username"

# mysql password
db_password="mysql_password"

# directory to store the apache domain .conf files
#
# this should match your httpd.conf include as mentioned at the top
#

configsubdir="vhosts"

#### end of configuration

function validate_domain {
   if [[ $1 =~ (([A-Za-z0-9]+)\.)+ ]]; then
      return 0;
   else
      return 1;
   fi
}

function validate_ip {
   case "$*" in
      ""|*[!0-9.]*|*[!0-9]) return 1 ;;
   esac
   local IFS=.
   set -- $*
   [ $# -eq 4 ] && [ ${1:-666} -le 255 ] && [ ${2:-666} -le 255 ] && [ ${3:-666} -le 255 ] && [ ${4:-666} -le 254 ]
}

function create_vhost {
cat <<- _EOF_
	<VirtualHost $host>
		ServerName $domain
		ServerAlias www.$domain
		DocumentRoot $webdir/$domain
		<Directory "">
			Options ALL -Indexes
			AllowOverride ALL
		</Directory>

		LogLevel warn
		LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined
		LogFormat "%h %l %u %t \"%r\" %>s %b" common
		LogFormat "%{Referer}i -> %U" referer
		LogFormat "%{User-agent}i" agent
		ErrorLog $webdir/$domain/logs/error.log
		CustomLog $webdir/$domain/logs/access.log common
		CustomLog $webdir/$domain/logs/referer.log referer

	</VirtualHost>
_EOF_
}

if [[ $EUID -ne 0 ]]; then
   echo "You must be root to do this." 1>&2
   exit 0
   
else if [ $# -ne 2 ]; then
      cmd=`basename $0`
      echo "$cmd <domain> <host-ip> <database-name> <wordpress-version>"
      echo "old version: google.com 192.168.0.1 googledb 2.9"
      echo "latest version: bing.com 192.168.1.1 bingdb"
      echo "latest version: yahoo.com 192.168.1.1"
      exit 0
      
   else if validate_domain $1 && validate_ip $2
      then
         reloadscript="/usr/local/etc/rc.d/apache22 reload"
         configdir="/usr/local/etc/apache22/$configsubdir"
         domain=$1
         host=$2
	 homedir="/usr/home/$username"
         webdir="$homedir/$htdocs"
         ip=`dig +short $domain`
         checkip=`/sbin/ifconfig -a | grep netmask | awk '{print $2}' | grep $host`
         
         if [ ! "$ip" = "$host" ];
         then
            echo "domain doesnt match ipaddress"
            exit
         fi
         if [ ! "$host" = "$checkip" ];
         then
            echo "ip matches, but non on this system"
            exit
         else
	    auto_db_name="${domain%%.*}"
            db_name=${3-$auto_db_name}
            #wp_current_version=`curl -s http://api.wordpress.org/core/version-check/1.6/ | awk -F\" '{print $34}'`
            wp_current_version=`curl -s http://api.wordpress.org/core/version-check/1.6/ | sed -e 's/.*s:7:"current";s:5:"//;s/".*//'`
            wpversion=${4-$wp_current_version}
            wpconfig="$webdir/$domain/wp-config.php"
            echo "checking if mysql database exists..."
            checkdb=`mysql -u$db_user -p$db_password --skip-column-names -e "SHOW DATABASES LIKE '$db_name'"`
            if [ "$checkdb" == "$db_name" ];
            then
               echo "mysql database $db_name already exists, try again."
               exit
            else if [ -f $configdir/$domain.conf ];
               then
                  echo "vhost already exists, try again."
                  exit
               else
                  echo "creating database $db_name..."
                  mysqladmin -u $db_user -p$db_password create $db_name
                  echo "creating web and log directories for $domain..."
                  mkdir -p $webdir/$domain
                  chown -R $username:$username $webdir/$domain
                  mkdir -p $webdir/$domain/logs
                  chown -R $username:$username $webdir/$domain/logs
                  echo "creating apache entry for $domain binding to ip address $host..."
                  create_vhost > $configdir/$domain.conf
                  echo "reloading apache..."
                  $reloadscript > /dev/null 2>&1
                  echo "downloading wordpress..."
                  svn co http://core.svn.wordpress.org/tags/$wpversion $webdir/$domain/ -q
                  echo "configuring Salts..."
                  curl --silent -o salt.txt https://api.wordpress.org/secret-key/1.1/salt/
                  sed '45,52d' $webdir/$domain/wp-config-sample.php > $webdir/$domain/wp-config-stripped.php
                  sed '44 r salt.txt' $webdir/$domain/wp-config-stripped.php > $webdir/$domain/wp-config.php
                  rm salt.txt
                  rm $webdir/$domain/wp-config-sample.php
                  rm $webdir/$domain/wp-config-stripped.php
                  echo "Adding database details to wp-config.php..."
                  sed "s/database_name_here/$db_name/g" "$wpconfig" > "$wpconfig.new" && mv "$wpconfig.new" "$wpconfig"
                  sed "s/username_here/$db_user/g" "$wpconfig" > "$wpconfig.new" && mv "$wpconfig.new" "$wpconfig"
                  sed "s/password_here/$db_password/g" "$wpconfig" > "$wpconfig.new" && mv "$wpconfig.new" "$wpconfig"
                  chown -R $username:$username $webdir/$domain
                  echo "Done..."
                  echo "visit http://www.$domain to complete the installation"
               fi
            fi
         fi
      else
         echo "Bad ip address or domain name, try again."
         exit
      fi
   fi
fi
