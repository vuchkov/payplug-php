#!/bin/bash

set -x
set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 curl_version php_version"
    exit 1
fi

CURL_VERSION="$1"
PHP_VERSION="$2"
PHP_DIRECTORY="/tmp/curl/$PHP_VERSION"
PHP_CURL_LIBS_DIRECTORY="$PHP_DIRECTORY/$CURL_VERSION"

if [ -f "$PHP_CURL_LIBS_DIRECTORY/phpcurl/curl.so" ] \
   && [ -f "$PHP_CURL_LIBS_DIRECTORY/curl/lib/libcurl.so" ] \
   && [ -d "$PHP_DIRECTORY/php" ]; then
    echo "Curl shared objects were cached. Skipping."
    exit 0
fi

SCRIPT_PATH="$(readlink --canonicalize-existing "$0")"
DIR_PATH="$(dirname "$SCRIPT_PATH")"
source "$DIR_PATH/travis_wait.sh"

mkdir -p "$PHP_CURL_LIBS_DIRECTORY/phpcurl" "$PHP_DIRECTORY/php" "$PHP_CURL_LIBS_DIRECTORY/curl"

TEMP_DIRECTORY="$(mktemp -d)"

cd "$TEMP_DIRECTORY"

# Get and extract curl and PHP
curl -L "https://curl.haxx.se/download/curl-$CURL_VERSION.tar.gz" --output curl.tar.gz
curl -L "https://github.com/php/php-src/archive/php-$PHP_VERSION.tar.gz" --output php.tar.gz
tar -xzf curl.tar.gz
tar -xzf php.tar.gz

# Compile curl
cd "curl-$CURL_VERSION"
./configure --prefix="$PHP_CURL_LIBS_DIRECTORY/curl/"
make
make install

# Compile PHP
cd ..
git clone https://github.com/php-build/php-build.git
grep -v "with-curl" "php-build/share/php-build/default_configure_options" \
     > "php-build/share/php-build/default_configure_options_"
mv "php-build/share/php-build/default_configure_options_" "php-build/share/php-build/default_configure_options"
travis_wait 30 php-build/bin/php-build "$PHP_VERSION" "$PHP_DIRECTORY/php"

# Compile PHP Curl
cd "php-src-php-$PHP_VERSION/ext/curl/"
chmod +x "$PHP_DIRECTORY/php/bin/phpize"
"$PHP_DIRECTORY/php/bin/phpize"
./configure --with-curl="$PHP_CURL_LIBS_DIRECTORY/curl/" --with-php-config="$PHP_DIRECTORY/php/bin/php-config"
make
cp modules/* "$PHP_CURL_LIBS_DIRECTORY/phpcurl/"

# Add PHP Curl module to php.ini
echo "extension=/tmp/curl/$PHP_VERSION/$CURL_VERSION/phpcurl/curl.so" \
     >> "$PHP_DIRECTORY/php/etc/php.ini"