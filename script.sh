#!/bin/bash

Check if the script is running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Check if the required commands are installed
for cmd in nginx composer git tee; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "$cmd command not found"
        exit 1
    fi
done

# Set the project name
project_name=${1:-"laravel"}

# Find a unique project name
iteration=1
while [ -d "/var/www/$project_name.loc" ]; do
    project_name="laravel$((iteration++))"
done

nginx_conf="/etc/nginx/sites-enabled/$project_name.conf"
project_dir="/var/www/$project_name.loc"

# Create nginx configuration file
tee $nginx_conf > /dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $project_name.loc;
    root $project_dir/public;
 
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    access_log /var/log/nginx/$project_name-access.log;
    error_log /var/log/nginx/$project_name-error.log;

    index index.php;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
 
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
 
    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9083;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

# Reload nginx configuration
nginx -s reload

# Create Laravel project
composer create-project --prefer-dist --no-interaction laravel/laravel $project_dir
git init $project_dir
chown -fR www-data:www-data $project_dir

if [[ " $* " == *" --github "* ]] && command -v gh >/dev/null 2>&1; then
    # Check if the project already exists in github by gh command
    if gh repo view $project_name > /dev/null 2>&1; then
        echo "Repository $project_name already exists on your github"
    else
        # Create new repo on github
        gh repo create $project_name --private

        # Check if the project already exists in github by gh command
        if gh repo view $project_name > /dev/null 2>&1; then

            # Get the remote origin
            origin=$(gh repo view $project_name --json sshUrl -q .sshUrl)

            # Go to the project directory
            cd $project_dir

            # Add the remote origin
            git remote add origin $origin
            git branch -M master
            git add . && git commit -m "Initial commit"
            git push -u origin master

            # Go back
            cd -

        else
            echo "Failed to create repository $project_name on your github"
        fi

    fi
fi

# Echo the success message
echo "Laravel project created successfully, visit http://$project_name.loc"

exit 0