#!/bin/bash

echo "CentOS7安装部署DCRM自动脚本V1.0(By imPone In feng.COM)正在全力安装部署...";
yum -y install zlib-devel bzip2-devel openssl-devel ncurses-devel sqlite-devel readline-devel tk-devel gdbm-devel db4-devel libpcap-devel xz-devel
wget https://www.python.org/ftp/python/3.6.1/Python-3.6.1.tgz
mkdir -p /usr/local/python3
tar -zxvf Python-3.6.1.tgz
cd Python-3.6.1
./configure --prefix=/usr/local/python3
make && make install
ln -s /usr/local/python3/bin/python3 /usr/bin/python3
echo "# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
. ~/.bashrc
fi

# User specific environment and startup programs

PATH=$PATH:$HOME/bin:/usr/local/python3/bin

export PATH" > ~/.bash_profile
source ~/.bash_profile
python3 -V python
yum -y groupinstall "Development Tools"
yum -y install epel-release MySQL-python mysql-devel python-devel python-setuptools libjpeg-devel

easy_install pip
pip install rq==0.13.0 python-memcached Pillow exifread
yum -y install mariadb-server redis memcached nginx supervisor curl

systemctl start nginx 
systemctl enable nginx 
systemctl start supervisord 
systemctl enable supervisord
systemctl start redis 
systemctl enable redis 
systemctl start memcached 
systemctl enable memcached 
systemctl start mariadb 
systemctl enable mariadb

sed -i 's/OPTIONS=""/OPTIONS="-l 127.0.0.1"/g' /etc/sysconfig/memcached
systemctl restart memcached

read -p "请输入您需要设置的数据库密码:" DB_password
echo -e "\ny\n$DB_password\n$DB_password\ny\nn\ny\ny" | mysql_secure_installation
echo "正在配置数据库,请等待...";
systemctl restart mariadb
echo -e "CREATE DATABASE DCRM DEFAULT CHARSET UTF8;\nGRANT ALL PRIVILEGES ON DCRM.* TO 'root'@'localhost';\nFLUSH PRIVILEGES;\nquit" | mysql -u root -p$DB_password

mkdir -p /opt/wwwroot && cd /opt/wwwroot 
git clone https://github.com/82Flex/DCRM.git 
cd DCRM
pip3 install setuptools==33.1.1
pip3 install -r requirements.txt

cp DCRM/settings.default.py DCRM/settings.py
read -p "请输入您的域名(不加http://):" Domain
read -p "请输入您需要设置的安全密钥:" SECRET_KEY
sed -i 's/False/True/g' DCRM/settings.py 
sed -i "49c SECRET_KEY = '$SECRET_KEY'" DCRM/settings.py 
sed -i "s/'apt.82flex.com'/'$Domain'/g" DCRM/settings.py 
sed -i "s/LANGUAGE_CODE = 'en'/LANGUAGE_CODE = 'zh-Hans'/g" DCRM/settings.py 
sed -i "s/'USER': 'dcrm'/'USER': 'root'/g" DCRM/settings.py 
sed -i "s/'thisisthepassword'/'$DB_password'/g" DCRM/settings.py 

./manage.py collectstatic 
./manage.py migrate 
./manage.py createsuperuser

echo "[uwsgi] 

chdir = /opt/wwwroot/DCRM 
module = DCRM.wsgi 

master = true 
processes = 4 
socket = :8001 
buffer-size = 32768 
vaccum = true 
uid = root 
gid = root" > uwsgi.ini

sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config 
setenforce 0

echo "upstream django {
    server 127.0.0.1:8001;
}

server {
    listen 80;
    listen 443 ssl http2;
    server_name $Domain;
    root /opt/wwwroot/DCRM;
    index index.html index.htm;
    client_max_body_size 128g;
    if (server_port !~ 443){
        rewrite ^(/.*)$ https://host1 permanent;
    }

    ssl_certificate /etc/nginx/certs/$Domain/fullchain.cer;
    ssl_certificate_key /etc/nginx/certs/$Domain/$Domain.key;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    error_page 497  https://hostrequest_uri;

    location = / {
        rewrite ^ /index/ last;
    }
    
    location / {
        try_files uri uri/ @djangosite;
    }        
    
    location ~^/static/(.*)$ {
        alias /opt/wwwroot/DCRM/WEIPDCRM/static/11;  # make an alias for static files
    }

    location ~^/resources/(.*)$ {
        alias /opt/wwwroot/DCRM/resources/11;  # make an alias for resources
    }
    
    location ~^/((CydiaIcon.png)|(Release(.gpg)?)|(Packages(.gz|.bz2)?))$ {
        alias /opt/wwwroot/DCRM/resources/releases/1/11;  # make an alias for Cydia meta resources
    }
    
    location @djangosite {
        uwsgi_pass django;
        include /etc/nginx/uwsgi_params;
    }
    
    location ~* .(ico|gif|bmp|jpg|jpeg|png|swf|js|css|mp3|m4a|m4v|mp4|ogg|aac)$ {
        expires 7d;
    }
    
    location ~* .(gz|bz2)$ {
        expires 12h;
    }
}" > /etc/nginx/conf.d/dcrm.conf
sed -i 's/server_port/$server_port/g' /etc/nginx/conf.d/dcrm.conf 
sed -i 's/host1/$host$1/g' /etc/nginx/conf.d/dcrm.conf 
sed -i 's/hostrequest_uri/$host$request_uri/g' /etc/nginx/conf.d/dcrm.conf 
sed -i 's/uri uri/$uri $uri/g' /etc/nginx/conf.d/dcrm.conf 
sed -i 's/11/$1/g' /etc/nginx/conf.d/dcrm.conf 

curl https://get.acme.sh | sh
cd && cd .acme.sh
read -p "阿里云域名请输入1,dnspod域名请输入2:" Domaindns
case $Domaindns in
	1) echo "您已选择阿里云域名";
	read -p "请输入阿里云的AccessKeyId:" AccessKeyId
	read -p "请输入阿里云的AccessKeySecret:" AccessKeySecret
	export Ali_Key="$AccessKeyId"
    export Ali_Secret="$AccessKeySecret"
    ./acme.sh --issue --dns dns_ali -d $Domain
	;;
	2) echo "您已选择dnspod域名";
	read -p "请输入dnspod的ID:" dnspodID
	read -p "请输入dnspod的Token:" dnspodToken
	export DP_Id="$dnspodID"
    export DP_Key="$dnspodToken"
    ./acme.sh --issue --dns dns_dp -d $Domain	
	;;
esac
mkdir -p /etc/nginx/certs/$Domain
./acme.sh --install-cert -d $Domain \
 --key-file /etc/nginx/certs/$Domain/$Domain.key \
 --fullchain-file /etc/nginx/certs/$Domain/fullchain.cer \
 --reloadcmd "systemctl force-reload nginx.service" 

echo "[supervisord] 
nodaemon=false 

[program:uwsgi] 
priority=1 
directory=/opt/wwwroot/DCRM 
command=/usr/bin/uwsgi --ini uwsgi.ini 

[program:high] 
priority=2 
directory=/opt/wwwroot/DCRM 
command=/usr/bin/python ./manage.py rqworker high 

[program:default] 
priority=3 
directory=/opt/wwwroot/DCRM 
command=/usr/bin/python ./manage.py rqworker default" > /etc/supervisord.d/dcrm.ini

echo "# encoding=utf8 
import sys

reload(sys) 
sys.setdefaultencoding('utf8')" > /usr/lib/python2.7/site-packages/sitecustomize.py

cd /opt/wwwroot/
git clone https://github.com/gregmuellegger/django-sortedm2m.git
cd /opt/wwwroot/DCRM/
mkdir sortedm2m
cd /opt/wwwroot/django-sortedm2m
\cp -rf /opt/wwwroot/django-sortedm2m/sortedm2m/* /opt/wwwroot/DCRM/sortedm2m/
\rm -r /opt/wwwroot/django-sortedm2m/

systemctl restart supervisord
echo "恭喜您成功安装，请继续按照帖子步骤登录后台$Domain/admin进行相关设置,感谢使用本脚本(By imPone In feng.COM)";
