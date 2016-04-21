#!/bin/bash
# This script helps switching among different version of curl and PHP.
#
# From what I tried, since php-build builds PHP with the --with-curl option, it's not possible to provide the curl.so
# module in php.ini file: Module already loaded error. Any workaround failed.
# The only solution I found was to build PHP from source without the --with-curl option and link the curl extension
# afterwards.
# Therefore, here are the exact steps this script follows:
#
# - Check that PHP binaries, libcurl and PHP curl extension (for this version of PHP and curl) are not cached already.
#   If so, we have nothing to do.
# - Download curl (from curl official website) and PHP sources (from php/php-src repo).
# - Build curl into /tmp/PHP_VERSION/CURL_VERSION/curl/
# - Build php-curl shared object (curl.so) into /tmp/PHP_VERSION/CURL_VERSION/phpcurl/
# - Download php-build and patch it to drop the --with-curl option.
# - Build PHP into /tmp/PHP_VERSION/php/
# - Update php.ini in /tmp/PHP_VERISON/php/etc/php.ini to load curl module (that we previously build).

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

# Build curl
if ! [ -f "$PHP_CURL_LIBS_DIRECTORY/curl/lib/libcurl.so" ]; then
    curl -L "https://curl.haxx.se/download/curl-$CURL_VERSION.tar.gz" --output curl.tar.gz
    tar -xzf curl.tar.gz
    cd "curl-$CURL_VERSION"

    ./configure --prefix="$PHP_CURL_LIBS_DIRECTORY/curl/"
    make
    make install

    cd ..
fi
# End build curl

# Build PHP
if ! [ -d "$PHP_DIRECTORY/php/bin/" ]; then
    git clone https://github.com/php-build/php-build.git
    grep -v "with-curl" "php-build/share/php-build/default_configure_options" \
         > "php-build/share/php-build/default_configure_options_"
    mv "php-build/share/php-build/default_configure_options_" "php-build/share/php-build/default_configure_options"
    travis_wait 30 php-build/bin/php-build "$PHP_VERSION" "$PHP_DIRECTORY/php"
fi
# End build PHP

# Build PHP Curl
if ! [ -f "$PHP_CURL_LIBS_DIRECTORY/phpcurl/curl.so" ]; then
    curl -L "https://github.com/php/php-src/archive/php-$PHP_VERSION.tar.gz" --output php.tar.gz
    tar -xzf php.tar.gz

    cd "php-src-php-$PHP_VERSION/ext/curl/"
    chmod +x "$PHP_DIRECTORY/php/bin/phpize"
    "$PHP_DIRECTORY/php/bin/phpize"
    ./configure --with-curl="$PHP_CURL_LIBS_DIRECTORY/curl/" --with-php-config="$PHP_DIRECTORY/php/bin/php-config"
    make
    cp modules/* "$PHP_CURL_LIBS_DIRECTORY/phpcurl/"

    # Add PHP Curl module to php.ini if it's not already present
    EXTENSION_LINE="extension=/tmp/curl/$PHP_VERSION/$CURL_VERSION/phpcurl/curl.so"
    ESCAPED_EXTENSION_LINE=$(sed -e 's/[]\/$*.^|[]/\\&/g' <<< "$EXTENSION_LINE")
    PHP_INI_FILE="$PHP_DIRECTORY/php/etc/php.ini"
    sed 's/extension=.*curl.so.*/'"$ESCAPED_EXTENSION_LINE"'/g' "$PHP_INI_FILE" >> "$PHP_INI_FILE"_
    mv "$PHP_INI_FILE"_ "$PHP_INI_FILE"

    cd ..
fi
# End build PHP Curl
