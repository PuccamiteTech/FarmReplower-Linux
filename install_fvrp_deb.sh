#!/bin/bash
set -euo pipefail

# variables containing directory portions of paths
FVRP_DIR=/var/www/html/fvrp
FVRP_PUBLIC_DIR=$FVRP_DIR/public
TOOLBAR_ICON_DIR=$FVRP_PUBLIC_DIR/farmville/assets/hashed/assets/decorations
LAUNCHER_DIR=/opt/fvrp
LAUNCHER_REPO_DIR=/tmp/fv-launcher

# variables containing resource links with no filename
ASSET_LINK_BASE=https://farmville.guildedsin.com/all-any/assets
SUPPLEMENTS_LINK_BASE=https://farmville.guildedsin.com/all-any/supplements
DEHASHER_LINK_BASE=https://github.com/PuccamiteTech/FVDehasher/releases/download/1.02-SNAPSHOT
SERVER_LINK_BASE=https://github.com/FV-Replowed/fv-replowed
LAUNCHER_LINK_BASE=https://github.com/FV-Replowed/fv-launcher

# variables containing filenames used with resource links
ASSET_LINK_FILE1=urls-bluepload.unstable.life-farmvilleassets.txt-shallow-20201225-045045-5762m-00000.warc.gz
ASSET_LINK_FILE2=urls-bluepload.unstable.life-farmvilleassets.txt-shallow-20201225-045045-5762m-00001.warc.gz
ASSET_LINK_FILE3=urls-bluepload.unstable.life-farmvilleassets.txt-shallow-20201225-045045-5762m-00002.warc.gz
ASSET_LINK_FILE4=urls-bluepload.unstable.life-farmvilleassets.txt-shallow-20201225-045045-5762m-00003.warc.gz
SUPPLEMENTS_LINK_FILE=supplements.zip
DEHASHER_LINK_FILE=ubuntu-build.zip

# variables containing general filenames
DEHASHER_FILE=FVDehasher-1.02-SNAPSHOT
ITEMS_SQL_FILE=farmvilledb_trimmed.sql
TOOLBAR_ICON_FILE=toolbar32x32.png

# variables containing full file paths
LAUNCHER_PATH=$LAUNCHER_DIR/fvrp.AppImage
LAUNCHER_ICON_PATH=$LAUNCHER_DIR/icon.png
LAUNCHER_SHORTCUT_PATH=/usr/share/applications/fvrp.desktop
AMFPHP_CRED_PATH=$FVRP_PUBLIC_DIR/farmville/flashservices/amfphp/Helpers/config.php
SITE_CONF_PATH=/etc/apache2/sites-available/000-default.conf

# variables containing database credentials
DB_NAME=fvdb
DB_USER=farmer
DB_PASS=examplePassword

apt-get update
apt install -y apache2 mariadb-server php php-xml php-dom npm composer php-mysql libfuse2

git clone $LAUNCHER_LINK_BASE $LAUNCHER_REPO_DIR
chown -R "$SUDO_USER" $LAUNCHER_REPO_DIR
cd $LAUNCHER_REPO_DIR
sudo -u "$SUDO_USER" npm install
sudo -u "$SUDO_USER" npm run build
mkdir -p $LAUNCHER_DIR
mv -f dist/*.AppImage $LAUNCHER_PATH
mv -f logo.png $LAUNCHER_ICON_PATH
chmod +x $LAUNCHER_PATH
ln -sf $LAUNCHER_PATH /usr/local/bin/fvrp

git clone $SERVER_LINK_BASE $FVRP_DIR
chown -R "$SUDO_USER":www-data $FVRP_DIR
cd $FVRP_DIR
rm -rf $LAUNCHER_REPO_DIR
sudo -u "$SUDO_USER" composer update
sudo -u "$SUDO_USER" npm install --include-workspace-root
sudo -u "$SUDO_USER" npm run build

# secure the MariaDB installation
mariadb -u root <<-EOF
ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('$DB_PASS');
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'%';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
EOF

wget $SUPPLEMENTS_LINK_BASE/$SUPPLEMENTS_LINK_FILE
unzip $SUPPLEMENTS_LINK_FILE $ITEMS_SQL_FILE
rm $SUPPLEMENTS_LINK_FILE
mariadb -u root "$DB_NAME" < $ITEMS_SQL_FILE

mv .env.example .env

sed -i.bak \
-e "s|^DB_DATABASE=.*|DB_DATABASE='${DB_NAME}'|" \
-e "s|^DB_USERNAME=.*|DB_USERNAME='${DB_USER}'|" \
-e "s|^DB_PASSWORD=.*|DB_PASSWORD='${DB_PASS}'|" \
.env

php artisan key:generate
php artisan migrate --seed

sed -i.bak \
-e "s|^define('DB_NAME'.*|define('DB_NAME', getenv('DB_NAME') ?: '${DB_NAME}');|" \
-e "s|^define('DB_USERNAME'.*|define('DB_USERNAME', getenv('DB_USERNAME') ?: '${DB_USER}');|" \
-e "s|^define('DB_PASSWORD'.*|define('DB_PASSWORD', getenv('DB_PASSWORD') ?: '${DB_PASS}');|" \
"$AMFPHP_CRED_PATH"

a2enmod rewrite
sed -i "s|^\s*DocumentRoot\s\+.*|DocumentRoot $FVRP_PUBLIC_DIR|" $SITE_CONF_PATH

if ! grep -q "<Directory $FVRP_PUBLIC_DIR>" $SITE_CONF_PATH; then
sed -i "/<\/VirtualHost>/i \ \n<Directory $FVRP_PUBLIC_DIR>\nAllowOverride All\nRequire all granted\n</Directory>\n" $SITE_CONF_PATH
fi

chmod -R 775 $FVRP_DIR
systemctl daemon-reload
systemctl restart apache2

cat <<-EOF > $LAUNCHER_SHORTCUT_PATH
[Desktop Entry]
Version=1.0
Name=FV Replowed
Comment=Play FV Replowed in a self-contained browser
Keywords=Internet;WWW;Browser;Web;Explorer
Exec=env GAME_URL=http://localhost fvrp
Terminal=false
X-MultipleArgs=false
Type=Application
Icon=$LAUNCHER_ICON_PATH
Categories=Network;WebBrowser;Internet
MimeType=application/x-shockwave-flash;
StartupNotify=true
EOF

wget $DEHASHER_LINK_BASE/$DEHASHER_LINK_FILE
unzip $DEHASHER_LINK_FILE
rm $DEHASHER_LINK_FILE

wget $ASSET_LINK_BASE/$ASSET_LINK_FILE1 $ASSET_LINK_BASE/$ASSET_LINK_FILE2 $ASSET_LINK_BASE/$ASSET_LINK_FILE3 $ASSET_LINK_BASE/$ASSET_LINK_FILE4
sudo -u "$SUDO_USER" ./$DEHASHER_FILE
rm $DEHASHER_FILE $ASSET_LINK_FILE1 $ASSET_LINK_FILE2 $ASSET_LINK_FILE3 $ASSET_LINK_FILE4 entries.txt

mv $TOOLBAR_ICON_DIR/$TOOLBAR_ICON_FILE .
rm -rf $FVRP_PUBLIC_DIR/farmville/assets
mv -f farmville/assets $FVRP_PUBLIC_DIR/farmville
mv $TOOLBAR_ICON_FILE $TOOLBAR_ICON_DIR
rm -rf farmville

echo All done!