FROM ubuntu:16.04

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r mysql && useradd -r -g mysql mysql

ENV DEBIAN_FRONTEND noninteractive


#RUN echo "deb http://mirrors.aliyun.com/ubuntu/ xenial main restricted" >/etc/apt/sources.list \
#&& echo "deb-src http://mirrors.aliyun.com/ubuntu/ xenial main restricted multiverse universe #Added by software-properties" >>/etc/apt/sources.list \
#&& echo "deb http://mirrors.aliyun.com/ubuntu/ xenial-updates main restricted" >>/etc/apt/sources.list \
#&& echo "deb-src http://mirrors.aliyun.com/ubuntu/ xenial-updates main restricted multiverse universe #Added by software-properties" >>/etc/apt/sources.list \
#&& echo "deb http://mirrors.aliyun.com/ubuntu/ xenial universe" >>/etc/apt/sources.list \
#&& echo "deb http://mirrors.aliyun.com/ubuntu/ xenial-updates universe" >>/etc/apt/sources.list \
#&& echo "deb http://mirrors.aliyun.com/ubuntu/ xenial multiverse" >>/etc/apt/sources.list \
#&& echo "deb http://mirrors.aliyun.com/ubuntu/ xenial-updates multiverse" >>/etc/apt/sources.list \
#&& echo "deb http://mirrors.aliyun.com/ubuntu/ xenial-backports main restricted universe multiverse" >>/etc/apt/sources.list \
#&& echo "deb-src http://mirrors.aliyun.com/ubuntu/ xenial-backports main restricted universe multiverse #Added by software-properties" >>/etc/apt/sources.list \
#&& echo "deb http://mirrors.aliyun.com/ubuntu/ xenial-security main restricted" >>/etc/apt/sources.list \
#&& echo "deb-src http://mirrors.aliyun.com/ubuntu/ xenial-security main restricted multiverse universe #Added by software-properties" >>/etc/apt/sources.list \
#&& echo "deb http://mirrors.aliyun.com/ubuntu/ xenial-security universe" >>/etc/apt/sources.list \
#&& echo "deb http://mirrors.aliyun.com/ubuntu/ xenial-security multiverse" >>/etc/apt/sources.list

RUN apt-get update  && apt-get install -y --no-install-recommends --fix-missing nodejs nodejs-legacy npm curl && rm -rf /var/lib/apt/lists/*

#RUN npm config set registry https://registry.npm.taobao.org

RUN npm install n -g && n stable

RUN apt-get update  && apt-get install -y --no-install-recommends gnupg dirmngr gnupg2 apt-utils && rm -rf /var/lib/apt/lists/*


# add gosu for easy step-down from root
ENV GOSU_VERSION 1.7
RUN set -x \
	&& apt-get update && apt-get install -y --no-install-recommends ca-certificates wget && rm -rf /var/lib/apt/lists/* \
	&& wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
	&& wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
	&& gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
	#&& gpgconf --kill all \
	&& rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc \
	&& chmod +x /usr/local/bin/gosu \
	&& gosu nobody true \
	&& apt-get purge -y --auto-remove ca-certificates wget

RUN mkdir /docker-entrypoint-initdb.d

RUN apt-get update && apt-get install -y --no-install-recommends \
# for MYSQL_RANDOM_ROOT_PASSWORD
		pwgen \
# for mysql_ssl_rsa_setup
		openssl \
# FATAL ERROR: please install the following Perl modules before executing /usr/local/mysql/scripts/mysql_install_db:
# File::Basename
# File::Copy
# Sys::Hostname
# Data::Dumper
		perl \
	&& rm -rf /var/lib/apt/lists/*

RUN set -ex; \
# gpg: key 5072E1F5: public key "MySQL Release Engineering <mysql-build@oss.oracle.com>" imported
	key='A4A9406876FCBD3C456770C88C718D3B5072E1F5'; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
	gpg --batch --export "$key" > /etc/apt/trusted.gpg.d/mysql.gpg; \
	rm -rf "$GNUPGHOME"; \
	apt-key list > /dev/null

ENV MYSQL_MAJOR 5.7
ENV MYSQL_VERSION 5.7


#RUN echo "deb http://repo.mysql.com/apt/debian/ stretch mysql-${MYSQL_MAJOR}" >> /etc/apt/sources.list.d/mysql.list

# the "/var/lib/mysql" stuff here is because the mysql-server postinst doesn't have an explicit way to disable the mysql_install_db codepath besides having a database already "configured" (ie, stuff in /var/lib/mysql/mysql)
# also, we set debconf keys to make APT a little quieter
RUN echo "mysql-server mysql-server/data-dir select /var/lib/mysql" | debconf-set-selections
RUN echo "mysql-server mysql-server/root-pass password root" | debconf-set-selections
RUN echo "mysql-server mysql-server/re-root-pass password root" | debconf-set-selections
RUN echo "mysql-server mysql-server/remove-test-db select false" | debconf-set-selections
RUN apt-get update && apt-get install -y mysql-server-5.7 && rm -rf /var/lib/apt/lists/* \
	&& rm -rf /var/lib/mysql && mkdir -p /var/lib/mysql /var/run/mysqld \
	&& chown -R mysql:mysql /var/lib/mysql /var/run/mysqld \
# ensure that /var/run/mysqld (used for socket and lock files) is writable regardless of the UID our mysqld instance ends up having at runtime
	&& chmod 777 /var/run/mysqld \
# comment out a few problematic configuration values
	&& find /etc/mysql/ -name '*.cnf' -print0 \
		| xargs -0 grep -lZE '^(bind-address|log)' \
		| xargs -rt -0 sed -Ei 's/^(bind-address|log)/#&/' \
# don't reverse lookup hostnames, they are usually another container
	&& echo '[mysqld]\nskip-host-cache\nskip-name-resolve' > /etc/mysql/conf.d/docker.cnf \
	&& echo "[client]\ndefault-character-set = utf8mb4\n[mysql]\ndefault-character-set = utf8mb4\n[mysqld]\ncharacter-set-client-handshake = FALSE\ncharacter-set-server = utf8mb4\ncollation-server = utf8mb4_unicode_ci\ninit_connect='SET NAMES utf8mb4'\n" >> /etc/mysql/my.cnf

RUN apt-get update && apt-get install -y --no-install-recommends \
		nginx \
	&& rm -rf /var/lib/apt/lists/*

# TODO USER www-data

COPY qx.conf /etc/nginx/conf.d/

EXPOSE 80


VOLUME /var/lib/mysql

#deploy web

RUN mkdir /home/iportal

COPY package.json /home/

WORKDIR /home

RUN npm install --production

#RUN unzip /home/iportal.zip -d /home/ && rm -f /home/iportal.zip

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /entrypoint.sh # backwards compat
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 3306 33060
CMD ["mysqld"]
