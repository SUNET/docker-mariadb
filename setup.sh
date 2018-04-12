#!/bin/bash

set -e
set -x

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
groupadd -r mysql && useradd -r -g mysql mysql

export DEBIAN_FRONTEND noninteractive
echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
{ \
		echo "mariadb-server-$MARIADB_MAJOR" mysql-server/root_password password 'unused'; \
		echo "mariadb-server-$MARIADB_MAJOR" mysql-server/root_password_again password 'unused'; \
	} | debconf-set-selections 

# Use the mirror hosted within SUNET in Sweden
/bin/sed -i s/deb.debian.org/ftp.se.debian.org/g /etc/apt/sources.list

# Update the image and install the needed tools
apt-get update && \
    apt-get -y dist-upgrade && \
    apt-get install -y \
        mariadb-server \
        gosu \
        gpg \
        dirmngr \
        socat \
    && apt-get -y autoremove \
    && apt-get autoclean 
# comment out any "user" entires in the MySQL config ("docker-entrypoint.sh" or "--user" will handle user switching)
sed -ri 's/^user\s/#&/' /etc/mysql/my.cnf /etc/mysql/conf.d/* 
# purge and re-create /var/lib/mysql with appropriate ownership
rm -rf /var/lib/mysql && mkdir -p /var/lib/mysql /var/run/mysqld \
    && chown -R mysql:mysql /var/lib/mysql /var/run/mysqld \
# ensure that /var/run/mysqld (used for socket and lock files) is writable regardless of the UID our mysqld instance ends up having at runtime
chmod 777 /var/run/mysqld \
# comment out a few problematic configuration values
find /etc/mysql/ -name '*.cnf' -print0 \
	| xargs -0 grep -lZE '^(bind-address|log)' \
	| xargs -rt -0 sed -Ei 's/^(bind-address|log)/#&/' \
# don't reverse lookup hostnames, they are usually another container
echo '[mysqld]\nskip-host-cache\nskip-name-resolve' > /etc/mysql/conf.d/docker.cnf

mkdir /docker-entrypoint-initdb.d

# Do some more cleanup to save space
rm -rf /var/lib/apt/lists/*
