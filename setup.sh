#!/usr/bin/env bash
#
# Ryan Skoblenick <ryan@skoblenick.com>
# 2013.10.07
#

# Prompt for sudo password upfront
sudo -v

function install () {
    local url=${1}

    # Parse package details from url
    local filename="${url##*/}"
    local extension="${filename##*.}"
    local file="${filename%.${extension}}"
    local package="${file%%-*}"
    local version="${file#*-*}"
    local version="${version%*-*}"

    # Validate the command doesn't exist
    command -v $package >/dev/null 2>&1

    # Get the installed version
    if [ $? -eq 0 ]; then
        version_present=$( $package --version )
    else
        version_present=0
    fi

    # Valifate if we need to install by version checking present to requested
    version_compare "$version_present" "$version"
    case $? in
        #0) echo "force reinstall";;
        #1) echo "downgrade?";;
        2) # Install
            http_code=$( curl -o /dev/null --silent --head --write-out '%{http_code}\n' $url )
            if [ "${http_code}" -eq '200' ]; then
                curl -L -o "/tmp/${filename}" --url "${url}"
            fi

            if [ -e "/tmp/$filename" ]; then
                case ${extension} in
                    'dmg')
                        # Mount disk image
                        hdiutil attach -nobrowse -readonly -noidme "/tmp/${filename}" -mountpoint "/Volumes/${filename}"
                        
                        # Identify the pkg installer within the mounted volume
                        pkg=$( ls "/Volumes/${filename}" | grep '.pkg' )
                        sudo installer -pkg "/Volumes/${filename}/${pkg}" -target /

                        # Unmount disk image
                        hdiutil detach "/Volumes/${filename}"
                    ;;
                    *)
                        echo "Unsupported package installer!"
                        exit 9
                    ;;
                esac

                # Clean up
                rm -f "/tmp/${filename}"
            fi
        ;;
    esac

}

function main () {
    case $( uname -s ) in
        Darwin)
            install 'http://downloads.puppetlabs.com/mac/facter-1.7.3.dmg'
            install 'http://downloads.puppetlabs.com/mac/hiera-1.2.1.dmg'
            install 'http://downloads.puppetlabs.com/mac/puppet-3.3.1.dmg'

            # Ensure puppet group is present
            sudo puppet resource group puppet ensure=present > /dev/null

            # Ensure puppet user is present
            sudo puppet resource user puppet ensure=present gid=puppet shell="/sbin/nologin" 2>&1 > /dev/null

            # Hide the puppet user; otherwise it will appear on the login screen
            defaults read /Library/Preferences/com.apple.loginwindow HiddenUsersList 2>&1 | grep --quiet "puppet"
            if [ $? -ne 0 ]; then
                sudo defaults write /Library/Preferences/com.apple.loginwindow HiddenUsersList -array-add puppet
            fi
        ;;
        Linux)
            puppet_version="3.3.1"

            mkdir -p /tmp

            # Identify the distro that I care about
            case $( lsb_release -si ) in
               
                Debian|Ubuntu)
                    # Debian bases
                    # ============
                    codename=$( lsb_release -sc )

                    # Ensure curl is installed
                    apt-get install -y curl
                    
                    # Add Puppets release repo if it doesn't exist
                    dpkg -l puppetlabs-release > /dev/null
                    if [ $? -ne 0 ]; then
                        echo "here"
                        curl --create-dirs -o "/tmp/puppetlabs-release-${codename}.deb" "http://apt.puppetlabs.com/puppetlabs-release-${codename}.deb"
                        sudo dpkg -i "/tmp/puppetlabs-release-${codename}.deb"
                        apt-get update
                    fi

                    # Find out the available versions in the repo
                    #apt-cache showpkg <package name>

                    # Install Puppet
                    apt-get install -y puppet=${puppet_version}-1puppetlabs1

                    # Clean up
                    rm -rf "/tmp/puppetlabs-release-${codename}.deb"
                    ;;

                RedHat|CentOS)
                    # RHEL6 bases
                    # ===========

                    # Ensure curl is installed
                    yum install -y curl

                    # Add Puppets PGP Key
                    rpm --import "http://yum.puppetlabs.com/RPM-GPG-KEY-puppetlabs"

                    # Add Puppets release repo
                    rpm -ivh "http://yum.puppetlabs.com/el/6/products/i386/puppetlabs-release-6-7.noarch.rpm"

                    # Find out the available versions in the repo
                    #yum --showduplicates list <package name>

                    # Install Puppet
                    yum install -y puppet-${puppet_version}-1.el6
                    ;;
            esac
        ;;
        *)
            echo "Unsupported operating system."
            exit 9
        ;;
    esac

    exit 0
}

function version_compare () {
    # http://stackoverflow.com/a/4025065/1837034
    if [[ $1 == $2 ]]; then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)

    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done

    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    return 0
}

main