#!/bin/bash
sudo apt update -y
sudo apt install apache2 php libapache2-mod-php -y
sudo systemctl start apache2
sudo systemctl enable apache2
