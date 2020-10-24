#!/bin/bash


# FUNCTIONS
# *******************************

check_command()
{ 
  command=$1
  if ! [ -x "$(command -v $command)" ]; then
    echo -e "\e[31mCommand is missing: $command\e[0m"
    return 0
  else
    echo "Command is installed: $command" 
    return 1
  fi
}

check_server()
{ 
  server=$1
  echo "Checking server $server..."
  if ! $CMD_PING -c1 $server &>/dev/null; then
   echo -e "\e[31mUnable to reach server: $server\e[0m"
   exit 1
  fi
}

# REQUIRED COMMANDS
# *******************************
# Desc: Check to make sure we have the required commands
#       installed on the system.

CMD_CURL=curl
CMD_GEM=gem
CMD_GIT=git
CMD_PING=ping
CMD_PYTHON=python3
CMD_PYTHON_PIP=pip3
CMD_SED=sed
CMD_TAR=tar
CMD_WGET=wget

echo -e "\e[33mChecking required commands\e[0m"

if ( (check_command $CMD_CURL) || 
     (check_command $CMD_GEM) ||
     (check_command $CMD_PING) ||
     (check_command $CMD_PYTHON) ||
     (check_command $CMD_PYTHON_PIP) ||
     (check_command $CMD_SED) ||
     (check_command $CMD_TAR) ||
     (check_command $CMD_WGET) ); then
  exit 1
fi

echo "All required commands available"
echo ""

# VARIABLES 
# *******************************

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
PACKAGES="$DIR/lib/rvc/modules/vsantest/packages"

GIT_HCIB_BRANCH='rvc-hcibench'

BUILD_VERSION='UNKNOWN'
BUILD_DATE=`date`
BUILD_INFO_FILE='/etc/hcibench-build.yml'

INSTALLATION_FOLDER='install'

DISKINIT_SERVER='w3-dbc301.eng.vmware.com'
DISKINIT_PATH='charlesl/diskinit'
DISKINIT_TMP="$INSTALLATION_FOLDER/diskinit"
DISKINIT_FOLDER='/opt/output/vm-template/diskinit'
DISKINIT_FILENAME='diskinit.tar.gz'
DISKINIT_VERSIONS='diskinit-versions.txt'

FIOCONFIG_SERVER='w3-dbc301.eng.vmware.com'
FIOCONFIG_PATH='charlesl/fioconfig'
FIOCONFIG_VERSIONS='fioconfig-versions.txt'
FIOCONFIG_LOG='fioconfig.log'
FIOCONFIG_TMP="$INSTALLATION_FOLDER/fioconfig"
FIOCONFIG_SRC='src'

PYTHON_SITE_PACKAGES="$(dirname `$CMD_PYTHON -c 'import os as _; print(_.__file__)'`)/site-packages"
PERMISSION_FOLDERS=('/opt/automation' '/opt/automation/lib' '/opt/automation/lib/tests')
PERMISSION_FILES=('*.sh' '*.rb')

CLEANUP_FOLDERS=('/opt/automation' '/opt/output' '/opt/vmware/rvc/')
CLEANUP_FILES=('.git' '.gitignore' '.DS_Store')
CLEANUP_OSSLKEY='/opt/automation/conf/key.bin'


# GIT BRANCH
# ***********************************************
# Desc: If git is installed check to see if we are deploying
#       the expected GA branch and prompt whether to continue
#       with the install if it is not.
#

echo -e "\e[33mDetermining GIT Branch\e[0m"

if !([ -x "$(command -v $CMD_GIT)" ]); then
  echo 'Git not installed. Skipping.'
else
  echo 'Determining GIT Branch'

  GIT_CUR_BRANCH=`$CMD_GIT branch | grep "\*" | cut -c3-`
  echo -e "\e[32mGit Branch is: $GIT_CUR_BRANCH\e[0m"

  if ([ "$GIT_CUR_BRANCH" != "$GIT_HCIB_BRANCH" ]); then
    echo -e "\e[33mCurrent GIT branch does not match expected GA Branch:t config --global user.name "Your Name" $GIT_HCIB_BRANCH\e[0m"
    echo 'Continue with the install?'
    select yn in Yes No
    do
      case $yn in
        Yes)
          break
          ;;
        No)
          echo 'Aborting'
          exit
          ;;
      esac
    done
  fi
fi

echo ""

# SCM VERSION
# ***********************************************
# Desc: This section tries to obtain the current SCM version and
#       writes it to a file to better track what version is installed
#       on the system. There might be a wtive way to get the version
#       using the 'git' command although the python module might be
#       preferable since it provides a bit more intelligence and some
#       flexibility.
#
# It prints the values and stores them in a yaml file
#
# Ref. https://pypi.org/project/setuptools-scm/
#

echo -e "\e[33mDetermining SCM version\e[0m"

if !([ -x "$(command -v $CMD_PYTHON)" ] && [ -x "$(command -v $CMD_PYTHON_PIP)" ]); then
   echo -e "\e[31mpython and/or pip are not installed: Cannot automatically determine the SCM version\e[0m"
   echo -e "\e[31mSCM version is: $BUILD_VERSION\e[0m"
else
   echo 'Checking requirements'
   $CMD_PYTHON_PIP install --no-cache-dir --upgrade pip
   $CMD_PYTHON_PIP install --no-cache-dir --upgrade setuptools
   $CMD_PYTHON_PIP install --no-cache-dir  setuptools_scm
   BUILD_VERSION=`$CMD_PYTHON -c "from setuptools_scm import get_version;print(get_version(root='.', fallback_version='0.0'))"`
   echo -e "\e[32mSCM version is: $BUILD_VERSION\e[0m"
fi

echo "Build information file: $BUILD_INFO_FILE"
echo -e "build:\n  scm_version: '${BUILD_VERSION}'\n  date: '${BUILD_DATE}'" > $BUILD_INFO_FILE

echo ""

#
# BACKUP
# ***********************************************
echo -e "\e[33mRemoving old files and backing up config files...\e[0m"

echo 'Removing gems'
for item in 'rvc' 'rbvmomi'
do
  $CMD_GEM uninstall $item -x
done

echo 'Backing up files'
for item in '/opt/automation/conf/perf-conf.yaml' '/opt/automation/vdbench-param-files/*' '/opt/automation/fio-param-files/*'
do
  for file in $item
  do
    if [ -f $file ]; then
      FILE_NAME="$(basename $file)"
      PARENT_NAME="$(basename "$(dirname "$file")")"
      BACKUP_DIR="/tmp/$PARENT_NAME"
      mkdir -p $BACKUP_DIR && cp $item $BACKUP_DIR
      echo "Copied $file to $BACKUP_DIR"
    fi
  done
done

echo 'Stop docker'
systemctl stop docker

echo 'Removing files'
for item in '/opt/vmware/rvc' '/usr/bin/rvc' '/opt/automation' '/opt/output/vm-template/graphites' '/opt/output/vm-template/diskinit'
do
  if [ -f $item ] || [ -d $item ]; then
    rm -rf $item
  fi
done

echo ""

#
# WORKER and TVM
# ***********************************************

rm -rf /opt/output/vm-template

echo 'Copying new worker VM template'
mv -f $DIR/perf-photon-hcibench /opt/output/vm-template

echo 'Copying new tvm VM template'
mv -f $DIR/tvm /opt/output/vm-template/

echo ""

#
# FIOCONFIG
# ***********************************************
echo -e "\e[33mInstalling fioconfig\e[0m"
check_server $FIOCONFIG_SERVER

echo "Removing previous version(s)"
rm -rf "/usr/bin/fioconfig*"
rm -f "/bin/fioconfigcli"

mkdir -p "$FIOCONFIG_TMP"
pushd "$FIOCONFIG_TMP" &> /dev/null 

  echo "Checking for latest packages in http://$FIOCONFIG_SERVER/$FIOCONFIG_PATH/"
  $CMD_CURL -s "$FIOCONFIG_SERVER/$FIOCONFIG_PATH/" | $CMD_SED -n -e "s_.*a href=.\([^\"]*fioconfig-[0-9\.]*.tar.gz\).*_\1_p" > $FIOCONFIG_VERSIONS
  FIOCONFIG_LATEST=`sed  -E -e 's/fioconfig-|.tar.gz//g' "$FIOCONFIG_VERSIONS" | sort -t. -k 1,1n -k 2,2n -k 3,3n -k 4,4n | tail -1 | awk '{print("fioconfig-"$1".tar.gz")}'`
  echo "Latest fioconfig version: $FIOCONFIG_LATEST"

  echo 'Downloading fioconfig package'
  rm -f "$FIOCONFIG_LATEST"
  if `$CMD_WGET -q --show-progress "http://$FIOCONFIG_SERVER/$FIOCONFIG_PATH/$FIOCONFIG_LATEST"`; then
    echo "Fioconfig copied successully"
  else
    echo -e "\e[31mFailed to copy fioconfig\e[0m"
    exit 1
  fi

  mkdir $FIOCONFIG_SRC
  $CMD_TAR -xzf "$FIOCONFIG_LATEST" --strip 1 -C 'src'

  pushd $FIOCONFIG_SRC &> /dev/null
    $CMD_PYTHON setup.py install --record "../installed_files.txt" > "../$FIOCONFIG_LOG"
  popd &> /dev/null

  rm -rf $FIOCONFIG_SRC 
  echo -e "\e[32mFioconfig installed\e[0m"
popd &> /dev/null

echo ""

#
# DISKINIT
# ***********************************************
echo -e "\e[33mInstalling diskinit\e[0m"
check_server $DISKINIT_SERVER

echo "Removing previous version(s)"
rm -f "$DISKINIT_FOLDER/*"

mkdir -p "$DISKINIT_TMP"
pushd "$DISKINIT_TMP" &> /dev/null

  echo "Checking for latest packages in http://$DISKINIT_SERVER/$DISKINIT_PATH/"
  $CMD_CURL -s "$DISKINIT_SERVER/$DISKINIT_PATH/" | $CMD_SED -n -e "s_.*a href=.\([^\"]*diskinit-[0-9\.]*.tar.gz\).*_\1_p" > $DISKINIT_VERSIONS
  DISKINIT_LATEST=`sed  -E -e 's/diskinit-|.tar.gz//g' "$DISKINIT_VERSIONS" | sort -t. -k 1,1n -k 2,2n -k 3,3n -k 4,4n | tail -1 | awk '{print("diskinit-"$1".tar.gz")}'`
  echo "Latest diskinit version: $DISKINIT_LATEST"

  echo 'Downloading diskinit package'
  rm -f "$DISKINIT_LATEST"
  if `$CMD_WGET -q --show-progress "http://$DISKINIT_SERVER/$DISKINIT_PATH/$DISKINIT_LATEST"`; then
    echo "Diskinit copied successully"
  else
    echo -e "\e[31mFailed to copy diskinit\e[0m"
    exit 1
  fi

  if [ ! -d $DISKINIT_FOLDER ]; then
    echo "Creating target folder: $DISKINIT_FOLDER"
    mkdir -p $DISKINIT_FOLDER
  fi

  src="$DISKINIT_LATEST"
  target="$DISKINIT_FOLDER/$DISKINIT_FILENAME"
  echo "Copying $src to $target"
  if `cp -f $src $target`; then
    echo -e "\e[32mDiskinit copied\e[0m"
  else
    echo -e "\e[31mFailed to copy diskinit\e[0m"
    exit 1
  fi

popd &> /dev/null

echo ""

#
# Appliance Utility
# ***********************************************
echo -e "\e[33mMoving Utility to ~/\e[0m"
mv -f $PACKAGES/vmFacilities/glue.rb ~/
chmod +x ~/glue.rb

mv -f $PACKAGES/vmFacilities/prepare.sh ~/tmp/
chmod +x ~/tmp/prepare.sh

mv -f $PACKAGES/vmFacilities/DockerVolumeMover.sh ~/tmp/
chmod +x ~/tmp/DockerVolumeMover.sh

echo ""

#
# RVC
# ***********************************************
echo -e "\e[33mInstalling RVC\e[0m"
mv $DIR/rvc /usr/bin

echo ""

#
# TOMCAT
# ***********************************************
echo -e "\e[33mReplacing tomcat file...\e[0m"

echo 'Stopping Tomcat'
service tomcat stop

echo 'Removing old web app'
rm -rf /var/opt/apache-tomcat-8.5.4/webapps/VMtest*

echo 'Copying new web app'
mv "$PACKAGES/vmtest/VMtest.war" /var/opt/apache-tomcat-8.5.4/webapps/VMtest.war

echo 'Starting Tomcat'
# Tomcat service needs to be started then restarted...
service tomcat start
sleep 5
service tomcat restart

echo ""

#
# RESTORE
# ***********************************************
echo -e "\e[33mCreating automation part and restoring config files...\e[0m"

mkdir -p /opt/vmware
mv $DIR/lib/rvc/modules/vsantest/automation /opt
mv -f $DIR/lib/rvc/modules/vsantest/packages/graphites /opt/output/vm-template/
rm -rf /opt/automation/*-param-files/

if [ -f /tmp/conf/perf-conf.yaml ]; then
  mv -f /tmp/conf/perf-conf.yaml /opt/automation/conf/perf-conf.yaml
fi

if [ -d /tmp/vdbench-param-files ]; then
  mv -f /tmp/vdbench-param-files /opt/automation/
else
  mkdir -p /opt/automation/vdbench-param-files
fi

if [ -d /tmp/fio-param-files ]; then
  mv -f /tmp/fio-param-files /opt/automation/
else
  mkdir -p /opt/automation/fio-param-files
fi

echo ""

#
# GEMS
# ***********************************************
echo -e "\e[33mDeploying gems...\e[0m"
gem install ipaddress
unzip -q $DIR/gems.zip -d $DIR/ && mv $DIR /opt/vmware/rvc

echo ""

#
#  PERMISSIONS
# ***********************************************
echo -e "\e[33mSetting file permissions\e[0m"

for folder in "${PERMISSION_FOLDERS[@]}"
do
   if ! [ -d $folder ]; then
      echo -e "\e[31m[WARNING] Cannot set permission in non existant directory: $folder\e[0m"
   else
      echo "  Folder: $folder"
      for file in "${PERMISSION_FILES[@]}"
      do
         find $folder/* -maxdepth 0 -type f -name "$file" -exec echo "      Setting: " {} \; -exec chmod a+x {} \;
      done
   fi
done

echo ""

# CLEANUP
# ***********************************************
echo -e "\e[33mRemoving unecessary files\e[0m"

for folder in "${CLEANUP_FOLDERS[@]}"
do
   if ! [ -d $folder ]; then
      echo -e "\e[31mCannot cleanup non existant directory: $folder\e[0m"
   else
      echo "  Folder: $folder"
      for file in "${CLEANUP_FILES[@]}"
      do
         find $folder -type f -name $file -exec echo "      Deleting: " {} \; -exec rm -f {} \;
      done
   fi
done

echo "Deleting ossl key"
if ! [ -f $CLEANUP_OSSLKEY ]; then
   echo "No key to delete: $CLEANUP_OSSLKEY"
else
   echo "Removing key: $CLEANUP_OSSLKEY"
   rm -f $CLEANUP_OSSLKEY
fi

echo "Removing git repository"
rm -rf "/opt/vmware/rvc/.git"

echo ""


# START SERVICES
# **********************************************
echo -e "\e[33mStarting services...\e[0m"

echo 'Start Docker'
systemctl start docker


echo -e "\e[33mUpdating containers...\e[0m"

docker stop $(docker ps -aq)
docker rm $(docker ps -aq)
docker rmi $(docker images -q)
docker image prune -f
docker container prune -f
docker volume prune -f
docker network prune -f
docker system prune -f
docker system prune --volumes -f

docker run -d --name graphite --restart=always -p 8020:80 -p 8021:8080 -p 2003-2004:2003-2004 -p 2023-2024:2023-2024 -p 8125:8125/udp -p 8126:8126 graphiteapp/graphite-statsd:1.1.5-10
docker run -d --name grafana --restart always -p 3000:3000 -v /opt/automation/conf/grafana/provisioning:/etc/grafana/provisioning -v /opt/automation/conf/grafana/dashboards:/var/lib/grafana/dashboards -e GF_SECURITY_ADMIN_USER=admin -e GF_SECURITY_ADMIN_PASSWORD=vmware -e GF_AUTH_ANONYMOUS_ENABLED=true -u root grafana/grafana:6.7.4
docker run -d --name influxdb --restart always -p 8086:8086 influxdb:1.8.1-alpine
docker run -d --name telegraf_vsan -v /opt/automation/conf:/etc/telegraf/:ro vsananalytics/telegraf-vsan:0.0.7
docker stop telegraf_vsan
tdnf install jq -y

for i in /opt/automation/conf/grafana/data_sources/*; do \
    curl -X "POST" "http://localhost:3000/api/datasources" \
    -H "Content-Type: application/json" \
     --user admin:vmware \
     --data-binary @$i
done

echo ""

#
# Done
# ***********************************************
echo -e "\e[32m[OK] Installation Successful\e[0m"
