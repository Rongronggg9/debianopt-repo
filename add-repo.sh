#!/bin/sh

# Get release codename
RELEASE=`lsb_release -sc`
if [ "$RELEASE" != "buster" ]; then
    echo "Sorry! Currently only Debian 10 buster is supported."
    exit 1
fi


MIRROR="https://coslyk.github.io/debianopt"


# Write source list
echo "deb $MIRROR $RELEASE main" > /etc/apt/sources.list.d/debianopt.list


# Add key
which curl > /dev/null || apt-get install -y curl
curl -L $MIRROR/PUBLIC.KEY | apt-key add -

# Update
apt-get update

# Finish
echo ""
echo "Congratulations! DebianOpt is set up successfully."
