#!/bin/bash

read -p "MySQL username: " MYSQL_USER
read -s -p "MySQL password: " MYSQL_PW
echo ""
read -s -p "OpenStack Admin password: " ADMIN_PW
echo ""
read -p "cinder-volumes size(GB): " CINDER_VOLUMES_SIZE
echo ""
