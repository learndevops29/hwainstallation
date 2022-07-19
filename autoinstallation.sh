#/bin/bash
# This script spin-up of HWA instance for Testing and Demo 
# need to have directory structure /opt/HWA/images/hwa
# MDM extract in /opt/HWA/images/hwa/MDM and DWC under /opt/HWA/images/hwa/DWC
# DB2 extract installation file in v11.5.4_linuxx64_server_dec.tar.gz under /opt/HWA/images/hwa/
# wlp installation file is in wlp-base-all-20.0.0.11.jar /opt/HWA/images/hwa/
# wlp liberty installation would be /opt/liberty/wlp
# V12 19/7/22 Mani

startime=`date`
yum install java -y # instaling Java as pre-requisite on newly build server
echo "starting @ `date`"
tar -xzvf v11.5.4_linuxx64_server_dec.tar.gz
#random server ID generator
serverid=`cat /dev/urandom | tr -dc '[:alpha:]' | fold -w ${1:-12} | head -n 1 | tr [:lower:] [:upper:]`
sh -xv /opt/HWA/images/hwa/usercreate.sh
/opt/HWA/images/hwa/server_dec/db2setup -r db2server.rsp
sleep 10
su - db2inst1 -c db2start
sleep 10
su - db2inst1 -c 'db2 -tvf /opt/HWA/images/hwa/create_database_MDM.sql'
sleep 10
su - db2inst1 -c 'db2 -tvf /opt/HWA/images/hwa/create_database_DWC.sql'
sleep 10
java -jar /opt/HWA/images/hwa/wlp-base-all-20.0.0.11.jar --acceptlicense /opt/liberty
/opt/HWA/images/hwa/MDM/TWS/LINUX_X86_64/configureDb.sh -f /opt/HWA/images/hwa/configureDb_MDM.properties
sleep 10
/opt/HWA/images/hwa/DWC/configureDb.sh -f /opt/HWA/images/hwa/configureDb_DWC.properties
sleep 10
sed -i 's/testing/'$serverid'/g' /opt/HWA/images/hwa/serverinst_MDM.properties
sleep 5
/opt/HWA/images/hwa/MDM/TWS/LINUX_X86_64/serverinst.sh -f /opt/HWA/images/hwa/serverinst_MDM.properties
sleep 15
/opt/HWA/images/hwa/DWC/dwcinst.sh -f /opt/HWA/images/hwa/dwcinst_DWC.properties
sleep 20

/opt/HWA/dwc/appservertools/stopAppServer.sh
cp /opt/HWA/images/hwa/engine_connection.xml /opt/HWA/dwc/usr/servers/dwcServer/configDropins/overrides/
sleep 10
/opt/HWA/dwc/appservertools/startAppServer.sh -direct
rm -rf /opt/HWA/dwc/usr/servers/dwcServer/configDropins/overrides/engine_connection.xml /opt/HWA/images/hwa/engine_connection.xml

echo "MAESTROLINES=0" >> ~wauser/.bash.bash_profile
echo "export MAESTROLINES" >> ~wauser/.bash_profile
echo "MAESTRO_OUTPUT_STYLE=LONG" >> ~wauser/.bash_profile
echo "export MAESTRO_OUTPUT_STYLE" >> ~wauser/.bash_profile
echo "cd /opt/HWA/hwa" >> ~wauser/.bash_profile
echo ". ./twa_env.sh" >> ~wauser/.bash_profile

. /opt/HWA/hwa/twa_env.sh
JnextPlan
sleep 20
conman lc '@!@' 10 noask

echo "hurray installation completed "

echo "started @ $startime , Completed @ `date`"

#alias startdwc='/opt/HWA/dwc/appservertools/startAppServer.sh'
#alias startmdm='/opt/HWA/hwa/appservertools/startAppServer.sh'
#alias stopdwc='/opt/HWA/dwc/appservertools/stopAppServer.sh'
#alias stopmdm='/opt/HWA/hwa/appservertools/stopAppServer.sh'


