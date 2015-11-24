# ------------------------------------------------------------------------------
# Based on a work at https://github.com/docker/docker.
# ------------------------------------------------------------------------------
# Pull base image.
FROM ubuntu
MAINTAINER Kevin Delfour <kevin@delfour.eu>

# Install Supervisor.
RUN \
  apt-get update && \
  apt-get install -y supervisor && \
  rm -rf /var/lib/apt/lists/* && \
  sed -i 's/^\(\[supervisord\]\)$/\1\nnodaemon=true/' /etc/supervisor/supervisord.conf

# ------------------------------------------------------------------------------
# Security changes
# - Determine runlevel and services at startup [BOOT-5180]
RUN update-rc.d supervisor defaults

# - Check the output of apt-cache policy manually to determine why output is empty [KRNL-5788]
RUN apt-get update | apt-get upgrade -y

# - Install a PAM module for password strength testing like pam_cracklib or pam_passwdqc [AUTH-9262]
RUN apt-get install libpam-cracklib -y
RUN ln -s /lib/x86_64-linux-gnu/security/pam_cracklib.so /lib/security

# ------------------------------------------------------------------------------
# Install Base
RUN apt-get update && apt-get install -yq wget unzip nginx fontconfig-config fonts-dejavu-core \
    php5-fpm php5-common php5-json php5-cli php5-common php5-mysql\
    php5-gd php5-json php5-mcrypt php5-readline psmisc ssl-cert \
    ufw php-pear libgd-tools libmcrypt-dev mcrypt mysql-server mysql-client

# ------------------------------------------------------------------------------
# Configure mysql
RUN sed -i -e"s/^bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/" /etc/mysql/my.cnf
RUN service mysql start && \
    mysql -uroot -e "CREATE DATABASE IF NOT EXISTS pydio;" && \
    mysql -uroot -e "CREATE USER 'pydio'@'localhost' IDENTIFIED BY 'pydio';" && \
    mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO 'pydio'@'localhost' WITH GRANT OPTION;" && \
    mysql -uroot -e "FLUSH PRIVILEGES;"
    
# ------------------------------------------------------------------------------
# Configure php-fpm
RUN sed -i -e "s/output_buffering\s*=\s*4096/output_buffering = Off/g" /etc/php5/fpm/php.ini && \
    sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php5/fpm/php.ini && \
    sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 1G/g" /etc/php5/fpm/php.ini && \
    sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 1G/g" /etc/php5/fpm/php.ini && \
    sed -i -e 's/;daemonize = yes/daemonize = no/g' /etc/php5/fpm/php-fpm.conf && \
    php5enmod mcrypt

# ------------------------------------------------------------------------------
# Configure nginx
RUN mkdir /var/www && \
    chown www-data:www-data /var/www && \
    rm /etc/nginx/sites-enabled/* && \
    rm /etc/nginx/sites-available/* && \
    sed -i -e"s/keepalive_timeout\s*65/keepalive_timeout 2/" /etc/nginx/nginx.conf && \
    sed -i -e"s/keepalive_timeout 2/keepalive_timeout 2;\n\tclient_max_body_size 100m/" /etc/nginx/nginx.conf && \
    echo "daemon off;" >> /etc/nginx/nginx.conf

ADD conf/pydio /etc/nginx/sites-enabled/
RUN mkdir /etc/nginx/ssl
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt -subj '/CN=localhost/O=My Company Name LTD./C=US'

# ------------------------------------------------------------------------------
# Configure services
RUN update-rc.d nginx defaults
RUN update-rc.d php5-fpm defaults
RUN update-rc.d mysql defaults

# ------------------------------------------------------------------------------
# Install Pydio
ENV PYDIO_VERSION 6.2.0
WORKDIR /var/www
#RUN wget http://downloads.sourceforge.net/project/ajaxplorer/pydio/stable-channel/${PYDIO_VERSION}/pydio-core-${PYDIO_VERSION}.zip && \
#    unzip pydio-core-${PYDIO_VERSION}.zip && \
#    mv pydio-core-${PYDIO_VERSION} pydio-core && \
#    chown -R www-data:www-data /var/www/pydio-core && \
#    chmod -R 770 /var/www/pydio-core && \
#    chmod 777  /var/www/pydio-core/data/files/ && \
#    chmod 777  /var/www/pydio-core/data/personal/

RUN mkdir -p /var/www/pydio-core/data/files && \
    mkdir -p /var/www/pydio-core/data/personal && \
    chown -R www-data:www-data /var/www/pydio-core && \
    chmod -R 770 /var/www/pydio-core && \
    chmod 777  /var/www/pydio-core/data/files/ && \
    chmod 777  /var/www/pydio-core/data/personal/


WORKDIR /
RUN ln -s /var/www/pydio-core/data pydio-data 
# ------------------------------------------------------------------------------
# Expose ports.
EXPOSE 80
EXPOSE 443

# ------------------------------------------------------------------------------
# Expose volumes
VOLUME /var/www/pydio-core
VOLUME /pydio-data/files
VOLUME /pydio-data/personal
VOLUME /etc/supervisor/conf.d

# ------------------------------------------------------------------------------
# Add supervisord conf
ADD conf/startup.conf /etc/supervisor/conf.d/

# Start supervisor, define default command.
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]