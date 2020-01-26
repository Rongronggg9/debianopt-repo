#!/usr/bin/env bash


## Step 1: Enter directory
HERE="$(dirname "$(readlink -f "${0}")")"
cd $1


## Step 2: Read the recipe YAML file
parse_yaml() {
    local prefix=$2
    local s
    local w
    local fs
    s='[[:blank:]]*'
    w='[a-zA-Z0-9_]*'
    fs="$(echo @|tr @ '\034')"
    sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" "$1" |
    awk -F"$fs" '{
    indent = length($1)/2;
    vname[indent] = $2;
    for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            printf("%s%s%s=(\"%s\")\n", "'"$prefix"'",vn, $2, $3);
        }
    }' | sed 's/_=/+=/g'
}
eval $(parse_yaml recipe.yml "_")


## Step 3: Get latest version and source url
get_latest_version_github() {
    export PYTHONIOENCODING=utf8
    curl -s "https://api.github.com/repos/$1/releases/latest" | \
    python -c "import sys, json; sys.stdout.write(json.load(sys.stdin)['tag_name'])"
}

guess_package_url_github() {
    curl -s "https://api.github.com/repos/$1/releases/latest" | grep "browser_download_url" | grep "amd64.deb\"" | sed 's/.*\"\(.*amd64\.deb\)\".*/\1/g'
}

if [ "$_source_host" = "github" ]; then
    LATEST_VERSION=$(get_latest_version_github "$_source_repo")
    LATEST_VERSION="${LATEST_VERSION#v}"
    if [ "$_source_method" = "build" ]; then
        if [ -n "${_source_url}" ]; then
            SOURCE_URL="${_source_url}"
            SOURCE_URL=`echo "$SOURCE_URL" | sed "s|##VERSION|$LATEST_VERSION|g"`
        else
            SOURCE_URL="https://github.com/$_source_repo/archive/v$LATEST_VERSION.tar.gz"
        fi
    else
        if [ -n "${_source_package_url}" ]; then
            PACKAGE_URL="${_source_package_url}"
            PACKAGE_URL=`echo "$PACKAGE_URL" | sed "s|##VERSION|$LATEST_VERSION|g"`
        else
            PACKAGE_URL=$(guess_package_url_github "$_source_repo")
        fi
    fi

elif [ "$_source_host" = "other" ]; then
    LATEST_VERSION=`bash -c "${_source_get_version}"`
    if [ "$_source_method" = "build" ]; then
        SOURCE_URL="${_source_url}"
        SOURCE_URL=`echo "$SOURCE_URL" | sed "s|##VERSION|$LATEST_VERSION|g"`
    else
        PACKAGE_URL="${_source_package_url}"
        PACKAGE_URL=`echo "$PACKAGE_URL" | sed "s|##VERSION|$LATEST_VERSION|g"`
    fi
else
    echo "Error: unsupported host: $_source_host" > /dev/stderr
    exit 1
fi


## Step 4: Check if the package of latest version exists
REMOTE_URL="https://dl.bintray.com/coslyk/debianzh/pool/main/${_name:0:1}/${_name}/${_name}_${LATEST_VERSION}-1~${DEBIAN_RELEASE}_amd64.deb"
if curl --output /dev/null --silent --head --fail "$REMOTE_URL"; then
    exit 0
else
    echo -e "\e[32m *** Detect update for $_name: $LATEST_VERSION *** \e[0m"
fi


## Step 5: Download source code or package
if [ "$_source_method" = "build" ]; then
    echo "Downloading source code from $SOURCE_URL"
    curl -L -o source.tar.gz "$SOURCE_URL"
    tar xzf source.tar.gz
else
    echo "Downloading $PACKAGE_URL"
    curl -L -o package.deb "$PACKAGE_URL"
fi


## Step 6: Build package if needed
if [ "$_source_method" = "build" ]; then

    SOURCE_DIR=`ls --ignore=debian-template --ignore=recipe.yml`

    # Copy debian folder
    cp -rf debian-template $SOURCE_DIR/debian
    find $SOURCE_DIR/debian -type f -exec sed -i -e "s|##VERSION|$LATEST_VERSION|g" {} \;
    find $SOURCE_DIR/debian -type f -exec sed -i -e "s|##RELEASE|$DEBIAN_RELEASE|g" {} \;
    
    # Build package
    printf "Building "
    $HERE/travis/build -i docker-deb-builder:$DEBIAN_RELEASE -o . $SOURCE_DIR | while read LINE; do
        printf "."
    done
    printf "\n"
    rm -f *-dbgsym_*.deb
    printf "Built: "
    ls *.deb

elif [ -d "debian-template" ]; then
    # Repack deb
    dpkg-deb -x package.deb temp
    dpkg-deb -e package.deb temp/debian
    cp -rf debian-template temp/debian
    dpkg-deb -b temp repack.deb
    rm -f package.deb
fi

# Step 9: Upload
echo "Uploading ..."
if [ "$TRAVIS_PULL_REQUEST" = "false" ]; then
    curl -X PUT -T *.deb -ucoslyk:$BINTRAY_APIKEY "https://api.bintray.com/content/coslyk/debianzh/${_name}/${LATEST_VERSION}/pool/main/${_name:0:1}/${_name}/${_name}_${LATEST_VERSION}-1~${DEBIAN_RELEASE}_amd64.deb;deb_distribution=${DEBIAN_RELEASE};deb_component=main;deb_architecture=amd64;publish=1"
fi
printf "\n\n"
