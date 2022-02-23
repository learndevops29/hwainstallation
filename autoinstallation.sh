#/bin/bash
# need to have directory structure /opt/HWA/images/hwa
# MDM extract in /opt/HWA/images/hwa/MDM and DWC under /opt/HWA/images/hwa/DWC
# DB2 extract under /opt/HWA/images/hwa/server_dec
# wlp liberty in /opt/liberty/wlp
startime=`date`
echo "starting @ `date`"


yum install git -y
sleep 10
git pull https://github.com/learndevops29/hwainstallation.git
sleep 10
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
sleep 20
/opt/HWA/images/hwa/DWC/dwcinst.sh -f /opt/HWA/images/hwa/dwcinst_DWC.properties
sleep 20


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


