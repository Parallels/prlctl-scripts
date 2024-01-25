#!/bin/bash

Check if Guacamole is already installed
GUACD_SERVICE=$(sudo systemctl list-unit-files --type=service | grep "guacd.service")
if [ -n "$GUACD_SERVICE" ]; then
  echo "Guacamole Service already installed. checking if it is running..."
  STATE=$(sudo systemctl is-active guacd.service)
  if [ "$STATE" = "active" ]; then
    echo "Guacamole Service is already running."
    exit 0
  else
    echo "Guacamole Service is not running."
    if sudo systemctl start guacd.service; then
      echo "Guacamole Service started successfully."
      exit 0
    else
      echo "Guacamole Service failed to start."
    fi
  fi
fi

echo "Installing Guacamole Service..."
echo "Installing dependencies..."
sudo apt update
sudo apt install -y build-essential libcairo2-dev libjpeg-turbo8-dev \
  libpng-dev libtool-bin libossp-uuid-dev libvncserver-dev \
  freerdp2-dev libssh2-1-dev libtelnet-dev libwebsockets-dev \
  libpulse-dev libvorbis-dev libwebp-dev libssl-dev \
  libpango1.0-dev libswscale-dev libavcodec-dev libavutil-dev \
  libavformat-dev jq

# Get the latest version of Apache Guacamole using GitHub tags
LATEST_VERSION=$(curl -s "https://api.github.com/repos/apache/guacamole-server/tags" | jq -r '.[0].name')

Check if the latest version is retrieved successfully
if [ -z "$LATEST_VERSION" ]; then
  echo "Failed to retrieve the latest version of Apache Guacamole."
  exit 1
fi

if [ -d "guacamole-server-$LATEST_VERSION" ]; then
  echo "Removing existing guacamole-server-$LATEST_VERSION folder..."
  rm -rf "guacamole-server-$LATEST_VERSION"
fi

echo "Getting the source code for $LATEST_VERSION of Apache Guacamole Server..."
wget https://downloads.apache.org/guacamole/"$LATEST_VERSION"/source/guacamole-server-"$LATEST_VERSION".tar.gz
tar -xzf guacamole-server-"$LATEST_VERSION".tar.gz
cd guacamole-server-"$LATEST_VERSION" || exit 1

echo "Configuring Apache Guacamole Server..."
sudo ./configure --with-init-dir=/etc/init.d --disable-guacenc

echo "Building Apache Guacamole Server..."
sudo make
sudo make install

echo "Updating installed library cache..."
sudo ldconfig
sudo systemctl daemon-reload

echo "Starting Guacamole Service..."
sudo systemctl start guacd.service
sudo systemctl enable guacd.service

echo "Creating reuired folders..."
sudo mkdir -p /etc/guacamole/{extensions,lib}

echo "Installing Tomcat..."
sudo apt install -y tomcat9 tomcat9-admin tomcat9-common tomcat9-user
echo "Installing Guacamole Client..."
wget https://downloads.apache.org/guacamole/"$LATEST_VERSION"/binary/guacamole-"$LATEST_VERSION".war
sudo mv guacamole-"$LATEST_VERSION".war /var/lib/tomcat9/webapps/guacamole.war
echo "Restarting Tomcat..."
sudo systemctl restart tomcat9 guacd

echo "Setting up database authentication..."
sudo apt install -y mariadb-server-10.6

echo "Getting the version 8.3.0 of MySQL Connector/J..."
wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-j-8.3.0.tar.gz
echo "Extracting MySQL Connector/J..."
tar -xzf mysql-connector-j-8.3.0.tar.gz
sudo cp mysql-connector-j-8.3.0/mysql-connector-j-8.3.0.jar /etc/guacamole/lib/

echo "Getting the latest version of Apache Guacamole Auth..."
wget https://downloads.apache.org/guacamole/"$LATEST_VERSION"/binary/guacamole-auth-jdbc-"$LATEST_VERSION".tar.gz

echo "Extracting Apache Guacamole Auth..."
tar -xzf guacamole-auth-jdbc-"$LATEST_VERSION".tar.gz
sudo cp guacamole-auth-jdbc-"$LATEST_VERSION"/mysql/guacamole-auth-jdbc-mysql-"$LATEST_VERSION".jar /etc/guacamole/extensions/

ROOT_PASSWORD="password"
PASSWORD="password"
{
  echo "UPDATE mysql.user SET Password=PASSWORD('$ROOT_PASSWORD') WHERE User='root';"
  echo "DELETE FROM mysql.user WHERE User='';"
  echo "DROP DATABASE test;"
  echo "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';"
  echo "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  echo "FLUSH PRIVILEGES;"
  echo "CREATE DATABASE guacamole_db;"
  echo "CREATE USER 'admin'@'localhost' IDENTIFIED BY '$PASSWORD';"
  echo "GRANT SELECT,INSERT,UPDATE,DELETE ON guacamole_db.* TO 'admin'@'localhost';"
  echo "FLUSH PRIVILEGES;"
} >>mysql-init.sql

echo "Setting up the database..."
sudo mysql <<_EOF_
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$ROOT_PASSWORD');
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
CREATE DATABASE IF NOT EXISTS guacamole_db;
CREATE USER  IF NOT EXISTS 'admin'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT SELECT,INSERT,UPDATE,DELETE ON guacamole_db.* TO 'admin'@'localhost';
FLUSH PRIVILEGES;
_EOF_
if [ $? -ne 0 ]; then
  echo "Failed to set up the database."
  exit 1
fi

cat ./guacamole-auth-jdbc-"$LATEST_VERSION"/mysql/schema/*.sql | mysql -u root guacamole_db -p"$PASSWORD"

echo "Creating the MySQL properties file..."
sudo touch /etc/guacamole/guacamole.properties
sudo chown tomcat:tomcat /etc/guacamole/guacamole.properties
sudo chmod 600 /etc/guacamole/guacamole.properties

{
  echo "# MySQL properties"
  echo "mysql-hostname: 127.0.0.1"
  echo "mysql-port: 3306"
  echo "mysql-database: guacamole_db"
  echo "mysql-username: admin"
  echo "mysql-password: $PASSWORD"
} >guacamole.properties
sudo mv guacamole.properties /etc/guacamole/

echo "Restarting Tomcat..."
sudo systemctl restart tomcat9 guacd mysql
