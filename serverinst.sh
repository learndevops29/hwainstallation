#!/bin/sh


main()
{
    logentry "main"

    umask 022
    initFromImageDirVar
    initCommonVariables $FROM_IMAGE_DIR
    WLP_SERVER=$WLP_ENGINE_SERVER
    initHiddenDefault

    initCommonMessages

    log " -----------------------------------"
    log " command: $0"
    # cannot log parameters here because of clear password
    SERVERINST_INPUT_PARAMS="$*"
    log " -----------------------------------"

    chooseInput $*


    # load Defaults From template file
    checkExistingFile ${TEMPLATE_PROPS_FILE}
    parseInputFromFile ${TEMPLATE_PROPS_FILE}

    DB_DRIVER_PATH_PROVIDED_BY_USER="false"

    #The following  will be calculated in initLocalVariablesPostInput if not entered by the user
    WA_USER=""
    INST_DIR=""

    # echoVars "echo vars after parse template file"

    if [ "$INPUT_FROM_FILE" = "true" ]
    then
        checkExistingFile ${PROPS_FILE}
        parseInputFromFile ${PROPS_FILE}
        # echoVars "echo vars after parse properties file"
    fi

    # read --lang parameter and set INST_LANG before reading other parameters
    # i.e. before parseInput
    # since it is needed to display usage or other messages
    readLangParameter $*
    #again .. in case user change language
    initCommonMessages
    SEELOGFILEMSG="`${MSG_CMD} MessageSeeLogFile $LOG_FILE`"

    parseInput $*

    PASSWORDS="$DB_PASSWORD $WA_PASSWORD $KEY_STORE_PASSWORD $TRUST_STORE_PASSWORD $SSL_PASSWORD"
    checkSomePasswordIsEncrypted $PASSWORDS       
    handlePw $0
    
    logInputParameters $SERVERINST_INPUT_PARAMS

    #--------------------------------------
    # Checks - For DOCKER pre installation it's needed that all checks must be done in this section.
    #--------------------------------------
    if [ "$CHECK" = "true" ]
    then
        checkLicense ${ACCEPTLICENSE}

        #check in twa registry if operation is new or update and set OPERATION
        #if update initalize from registry the following: WA_USER, VERSION, COMPONENT_TYPE, WLP_INSTALL_DIR, DB_DRIVER_PATH
        if [ -z "${INST_DIR}" ]; then
            initWaUserAndInstDirForNew
        fi
                
        initNewOrUpdate "TWS" "${THIS_SCRIPT_ABSOLUTE_DIR}/ACTIONTOOLS/twaregistry.sh" "${INST_DIR}"
    fi

    initWaUserAndInstDirForNew
    if [ "$CHECK" = "true" ]
    then
        checkForNew
        #-------------------------------------------------------------------------------------
        # checkRequiredForUpdate is not needed
        # the only parameters required for update are 
        # --acceptlicense      already checked in checkLicense above
        # --inst_dir           initialized with default in initWaUserAndInstDirForNew above 
        #-------------------------------------------------------------------------------------
        checkIgnoredForUpdate
    fi

    initLocalVariablesPostInput
    echoVars "echo vars after initLocalVariablesPostInput"

    handleLog ${DATA_DIR}
    SIMUL_PROPS_FILE=${DATA_DIR}/installation/${SIMUL_PROPS_FILE_NAME}
    execute_command_and_exit_if_fail cp ${TEMPLATE_PROPS_FILE} ${SIMUL_PROPS_FILE}
    updateSimul ${SIMUL_PROPS_FILE}
    

    #--------------------------------------
    # Checks - For DOCKER pre installation it's needed that all checks must be done in this section.
    #--------------------------------------
    if [ "$CHECK" = "true" ]
    then
        MSG_CHECKING_INPUT=`${MSG_CMD} Message_CheckingInput`
        echolog  ${MSG_CHECKING_INPUT}

        checkCalledFromImageDir

        if [ "$SKIPCHECKPREREQ_UC" = "FALSE" ]
        then
            checkPrereqMdm "${INST_DIR}" "${WORK_DIR}" "${DATA_DIR}"
        fi
        
        if [ "${OPERATION}" = "${OP_UPDATE}" ]
        then
            #WLP_INSTALL_DIR is read from registry in initNewOrUpdate
            if [ "$SKIPCHECKPREREQ_UC" = "FALSE" ]
            then
                checkWlpVersion ${WLP_INSTALL_DIR}
            fi
            WA_USER=${USER_READ_FROM_TWAREGISTRY}
            MSG_STOP_SERVER=`${MSG_CMD} Message_StopServer $WLP_ENGINE_SERVER`
            echolog  ${MSG_STOP_SERVER}
            #both stop needed to cover all possible cases
            stopWlpServer "${INST_DIR}/appservertools"
            stopWlpServer "${INST_DIR}/appservertools" "-direct" 
            checkWlpNotStarted ${INST_DIR}/appservertools
            clearWlpAppsDir
        fi

        #perform additional check only for fresh
        if [ "${OPERATION}" = "${OP_NEW}" ]
        then
            #check if wa user given in input exist
            checkWauser

            #check for fresh install in twa registry if product is already installed, in this case exit with error
            checkTwaRegistry
            checkJdbcDriver
            
            if [ "$SKIPCHECKPREREQ_UC" = "FALSE" ]
            then
                checkWlp "${WLP_INSTALL_DIR}"  "${WA_USER}"
            fi
            checkLengths
            checkPorts

        fi
    fi
    #end if check = true

    #--------------------------------------
    # Simul stuff
    #-------------------------------------- 
    generateSimulFilesWithoutPassword
      
    if [ "$EXECINST" = "false" ]
    then
        simulation
        POSTCONFIGURE="false"
        POPULATE="false"
    else
        FINAL_SUCC_MSG=$INST_SUCC_MSG
    fi

    #--------------------------------------
    # install binaries - For DOCKER pre installation it's needed that all files must be created and copied only in this section. Do NOT copy/add files outside this section.
    #--------------------------------------
    if [ "$INSTALL_BINARY" = "true" ]
    then
       initTwsinstParms
       MSG_INSTALLING_BINARIES=`${MSG_CMD} Message_InstallingBinaries`
       echolog  ${MSG_INSTALLING_BINARIES}

       installPluginsEngine ${THIS_SCRIPT_ABSOLUTE_DIR}/Tivoli_MDM_${INST_INTERP}/TWS/applicationJobPlugIn  ${INST_DIR}/TWS/applicationJobPlugIn            
 
       execute_command_and_exit_if_fail ${THIS_SCRIPT_DIR}/twsinst ${TWSINST_PARMS}
       extractFromEars "${WLP_USER_DIR}/servers/${WLP_ENGINE_SERVER}/apps"  "${WA_USER}"
       #N.B.modifyOwnership  must be done before start wlp server
       modifyOwnership
       removeFileNotNeededByBroker
    fi
    
    #---------------------------------------------------------------------------------------
    # modify DATADIR in update - For DOCKER to fix jobmacrc moved to DATADIR after 9.5 GA  
    # insert in this section other code needed when modifing datadir in update
    # this code is duplicated in agent script twsConfigAction.sh called by twsinst
    # which is not called because INSTALL_BINARY is false
    #---------------------------------------------------------------------------------------
    if [ "$INSTALL_BINARY" = "false" ]
    then
        log "=== This serverinst.sh section is executed only in docker installation ==="
        log "Manipulating ${DATA_DIR}/jobmanrc and ${INST_DIR}/TWS/jobmanrc"
        
        if [ -f "${DATA_DIR}/jobmanrc" ]
        then
            log "${DATA_DIR}/jobmanrc exists"
        else
            log "${DATA_DIR}/jobmanrc  does notexist, copy from config"
            execute_command_and_exit_if_fail cp ${INST_DIR}/TWS/config/jobmanrc ${DATA_DIR}/jobmanrc
            execute_command_and_exit_if_fail chmod 555 ${DATA_DIR}/jobmanrc
        fi
        
        
        if [ -h "${INST_DIR}/TWS/jobmanrc" ]
        then
            log "link to ${INST_DIR}/TWS/jobmanrc  exist"
        else
            log "Creating symlink between ${DATA_DIR}/jobmanrc and ${INST_DIR}/TWS/jobmanrc"
            execute_command_and_exit_if_fail ln -f -s ${DATA_DIR}/jobmanrc ${INST_DIR}/TWS/jobmanrc
        fi
        log "=== End of serverinst.sh section  executed only in docker installation ==="

    fi

    #--------------------------------------
    # configuration - For DOCKER post configuration it's needed that all files must be configured/untagged only in this section. Do NOT configure/untag files outside this section.
    # This section must run also with not-root user
    #--------------------------------------
    if [ "$CONFIGURE" = "true" ]
    then
        if [ "$COMPONENT_TYPE" = "MDM"  -o "$COMPONENT_TYPE" = "BKM" ]
        then
            # WA_PLUGINS_DIR is an environment variable defined in Dockerfile
            if [ ! -z ${WA_PLUGINS_DIR} ]
            then
                installPluginsEngine ${WA_PLUGINS_DIR}  ${INST_DIR}/TWS/applicationJobPlugIn            
            fi           
        fi

        WLP_USR_RES_SEC_DIR=${DATA_DIR}/usr/servers/${WLP_ENGINE_SERVER}/resources/security
        if [ ! -d "$WLP_USR_RES_SEC_DIR"  ]
        then
            WLP_USR_RES_SEC_DIR=${WLP_USER_DIR}/servers/${WLP_ENGINE_SERVER}/resources/security
        fi
    
        copySSL ${WLP_USR_RES_SEC_DIR}
       # perform configuration both for fresh and for update installation
        configForNewAndUpdate

        # perform configuration only for fresh installation
        configForNew

    fi

    #--------------------------------------
    # postConfigure - For DOCKER post configuration, it's needed that all operations done to populate data must be done only in this section. Do NOT create data files outside this section.
    # This section must run also with not-root user
    #--------------------------------------
    if [ "$POSTCONFIGURE" = "true" ]
    then
        # perform post-configuration only for fresh installation
        if [ "${OPERATION}" = "${OP_NEW}" ]
        then
            # call importServerCert.sh
            DEST_LOCATION=$DATA_DIR/usr/servers/engineServer/resources/security
            runSecurityScripts  "$SEC_SCRIPT_ABSOLUTE_PATH" "$DEST_LOCATION" "$SSL_KEY_FOLDER" "$SSL_PASSWORD" "MDM" "$WA_USER"
            # call waPostConfigure.sh
            initWaPostConfigureParms
            MSG_POST_CONF=`${MSG_CMD} Message_ExecutingPostConf`
            echolog  ${MSG_POST_CONF}
            execute_command_and_exit_if_fail ${TWSTOOLS_DIR}/waPostConfigure.sh ${WA_POST_CONFIGURE_PARMS}
        else
            # Fix 9.5GA BUG for GenericEventPlugin
            fixGenericEvents
            # perform start product only for update installation (in fresh it is performed during waPostConfigure)

            HTTPS_PORT=`propFromFreshParameters "HTTPS_PORT"`
            log "main: HTTPS_PORT from configuration file = $HTTPS_PORT needed for TestServerConnection"
            
            log "main: calling startProduct clean"
            startProduct "clean"
        fi
    fi

    #--------------------------------------
    # commit files - For DOCKER pre installation it's needed that the latest registry modification is done only in this section.
    #--------------------------------------
    if [ "$COMMIT" = "true" ]
    then
        # commit files
        commit
    fi
    
    #clean work_dir
    rm -rf ${OLD_PLUGIN_DIR}
    
    echoInfo ${SEELOGFILEMSG}
    echolog ${FINAL_SUCC_MSG}
    logexit "main"

    exit  0

}
#end of main


# *************************************************************************************************
# Common Subroutines
# *************************************************************************************************

THIS_SCRIPT_DIR=`dirname $0`
. ${THIS_SCRIPT_DIR}/commonFunctions.sh

# *************************************************************************************************
# Local Subroutines
# *************************************************************************************************
removeOldPlugin(){
    logentry "removeOldPlugin"
    if [ "${OPERATION}" = "${OP_UPDATE}" ]
    then
        if [ "$COMPONENT_TYPE" = "MDM" -o "$COMPONENT_TYPE" = "BKM" ]
        then
            OLD_PLUGIN_DIR=${WORK_DIR}/oldplugin
            rm -rf ${OLD_PLUGIN_DIR}
            mkdir ${OLD_PLUGIN_DIR}
            mv ${INST_DIR}/TWS/applicationJobPlugIn/com.ibm.scheduling.agent.*9.5.0.0* ${OLD_PLUGIN_DIR}
        fi
    fi
    logexit "removeOldPlugin"
}


removeFileNotNeededByBroker(){
    logentry "removeFileNotNeededByBroker COMPONENT_TYPE=$COMPONENT_TYPE"
    if [ "$COMPONENT_TYPE" = "DDM" -o "$COMPONENT_TYPE" = "BDM" ]
    then
        #remove MDM ear
        rm -rf ${INST_DIR}/usr/servers/engineServer/apps/TWSEngineModel.ear
        #remove MDM binaries
        rm -rf ${INST_DIR}/TWS/config/*
        rm -rf ${INST_DIR}/TWS/cpudef_unix
        rm -rf ${INST_DIR}/TWS/CreatePostReports
        rm -rf ${INST_DIR}/TWS/eventPlugIn/*
        rm -rf ${INST_DIR}/TWS/eventrulesdef.conf
        rm -rf ${INST_DIR}/TWS/JnextPlan
        rm -rf ${INST_DIR}/TWS/MakePlan
        rm -rf ${INST_DIR}/TWS/PostSwitchPlan
        rm -rf ${INST_DIR}/TWS/PreSwitchPlan
        rm -rf ${INST_DIR}/TWS/ResetPlan
        rm -rf ${INST_DIR}/TWS/schemas/*
        rm -rf ${INST_DIR}/TWS/selfPatchingRuleDef.xml
        rm -rf ${INST_DIR}/TWS/Sfinal
        rm -rf ${INST_DIR}/TWS/SwitchPlan
        rm -rf ${INST_DIR}/TWS/templates/*
        rm -rf ${INST_DIR}/TWS/UpdateStats
        rm -rf ${INST_DIR}/TWS/applicationJobPlugIn/*
        rm -rf ${INST_DIR}/TWS/depot/*       
        rm -rf ${INST_DIR}/usr/servers/engineServer/resources/properties/TWSConfig.properties
        rm -rf ${INST_DIR}/usr/servers/engineServer/resources/properties/WA.properties
        
    fi
    logexit "removeFileNotNeededByBroker"
}

checkRequiredForNew()
{
    logentry "checkRequiredForNew"
    if [ "${OPERATION}" = "${OP_NEW}" ]
    then
        #INFORMIX_SERVER
        if [  -z "$INFORMIX_SERVER"  -a "$RDBMS_TYPE_UC" = "IDS" ]
        then
            MSG_REQUIRED_OPTION=`${MSG_CMD} Message_RequiredOption --informixserver`
            echoErrorAndUsageAndExit $MSG_REQUIRED_OPTION
        fi
        #DB_HOST_NAME
        if [  -z "$DB_HOST_NAME" ]
        then
            MSG_REQUIRED_OPTION=`${MSG_CMD} Message_RequiredOption --dbhostname`
            echoErrorAndUsageAndExit $MSG_REQUIRED_OPTION
        fi

        #DB_PASSWORD
        if [  -z "$DB_PASSWORD" ]
        then
            MSG_REQUIRED_OPTION=`${MSG_CMD} Message_RequiredOption --dbpassword`
            echoErrorAndUsageAndExit $MSG_REQUIRED_OPTION
        fi

        #WA_PASSWORD
        if [  -z "$WA_PASSWORD" ]
        then
            MSG_REQUIRED_OPTION=`${MSG_CMD} Message_RequiredOption --wapassword`
            echoErrorAndUsageAndExit $MSG_REQUIRED_OPTION
        fi

        #WLP_INSTALL_DIR
        if [  -z "$WLP_INSTALL_DIR" ]
        then
            MSG_REQUIRED_OPTION=`${MSG_CMD} Message_RequiredOption --wlpdir`
            echoErrorAndUsageAndExit $MSG_REQUIRED_OPTION
        fi

        #LICENSE_SERVER_ID
        if [  -z "$LICENSE_SERVER_ID" -a "$IBM_OR_HCL" = "IBM" -a ${COMPONENT_TYPE} = "MDM" ]
        then
            MSG_REQUIRED_OPTION=`${MSG_CMD} Message_RequiredOption --licenseserverid`
            echoErrorAndUsageAndExit $MSG_REQUIRED_OPTION
        fi

        #end check required parameters
    fi
    logexit "checkRequiredForNew"
}

checkIgnoredForUpdate()
{
    logentry "checkIgnoredForUpdate"
    if [ "${OPERATION}" = "${OP_UPDATE}" ]
    then
            
        #general warning
        # do not  insert blank in the string below
        GENERAL_OPTIONS_FOR_MSG="--acceptlicense,--inst_dir,--lang,--work_dir,--skipcheckprereq"  
        MSG_UPGRADE_IGNORE=`${MSG_CMD} Message_UpgradeIgnore ${GENERAL_OPTIONS_FOR_MSG}`
        echolog $MSG_UPGRADE_IGNORE        
        
        #uncomment the following code if you want to give a message for each option passed that it is not necessary in update

        #TWSINST_OPTIONS="--data_dir --jmport --displayname --netmanport --hostname --thiscpu"
        #WAPOSTC_OPTIONS="--wapassword --componenttype --eifport --company"
        #WLP_OPTIONS="--wlpdir|-w --httpport --httpsport --bootstrapport|-b --bootsecport|-s --wauser"
        #DB_OPTIONS="--rdbmstype|-r --dbname --dbuser --dbpassword  --dbport --dbhostname --dbdriverpath --brwksname"
        #SSL_OPTIONS="--dbsslconnection --sslkeysfolder --keystorepassword --truststorepassword"
        
        #OPTIONS=${TWSINST_OPTIONS}" "${WAPOSTC_OPTIONS}" "${WLP_OPTIONS}" "${DB_OPTIONS}" "${SSL_OPTIONS}    
              
        #for option in $OPTIONS ; do
        #    getValueFromOption $option 
        #    if [ ! "${VALUE_FROM_OPTION}x" = "x" ]
        #    then
        #       MSG_IGNORED_OPTION=`${MSG_CMD} Message_IgnoredOption $option`
        #        echolog $MSG_IGNORED_OPTION
        #    fi
        # done           
    fi
    logexit "checkIgnoredForUpdate"
}

getValueFromOption()
{
    logentry "getValueFromOption"
    if [ "$1" = "--data_dir" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--jmport" ]
    then
        VALUE_FROM_OPTION=$JM_PORT
    fi
    if [ "$1" = "--displayname" ]
    then
        VALUE_FROM_OPTION=$DISPLAYNAME
    fi
    if [ "$1" = "--xaname" ]
    then
        VALUE_FROM_OPTION=$XANAME
    fi
    if [ "$1" = "--netmanport" ]
    then
        VALUE_FROM_OPTION=$NETMAN_PORT
    fi
    if [ "$1" = "--hostname" ]
    then
        VALUE_FROM_OPTION=$THIS_HOSTNAME
    fi
    if [ "$1" = "--thiscpu" ]
    then
        VALUE_FROM_OPTION=$THISCPU
    fi
    if [ "$1" = "--wapassword" ]
    then
        VALUE_FROM_OPTION=$WA_PASSWORD
    fi
    if [ "$1" = "--componenttype" ]
    then
        VALUE_FROM_OPTION=$COMPONENT_TYPE
    fi
    if [ "$1" = "--eifport" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
     if [ "$1" = "--company" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--wlpdir" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--httpport" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--httpsport" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--bootstrapport" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--bootsecport" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--wauser" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--rdbmstype" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--dbname" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--dbuser" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--dbpassword" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--dbport" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--dbhostname" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--dbdriverpath" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--brwksname" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--dbsslconnection" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--sslkeysfolder" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "--$KEY_STORE_PASSWORD_OPTION" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi
    if [ "$1" = "$TRUST_STORE_PASSWORD_OPTION" ]
    then
        VALUE_FROM_OPTION=$DATA_DIR
    fi

    logexit "getValueFromOption"
}

fixGenericEvents()
{
    logentry "fixGenericEvents"
    if [ ! -d "$DATA_DIR/eventPlugIn/config/GenericEventPlugIn" -a -d "$INST_DIR/TWS/eventPlugIn/config/GenericEventPlugIn" ]
    then
        mkdir -p $DATA_DIR/eventPlugIn
        mv $INST_DIR/TWS/eventPlugIn/config $DATA_DIR/eventPlugIn/
    fi
    
    logexit "fixGenericEvents"
}

startProduct()
{
    logentry " cleanOption = $1"
    cleanOption=$1
    if [ "$COMPONENT_TYPE" = "MDM" -o "$COMPONENT_TYPE" = "BKM" ]
    then
        contextToUse="twsd"
    else
        contextToUse="JobManagerRESTWeb/JobManagerServlet"
    fi
    
    if [ "$COMPONENT_TYPE" = "BDM" ]
    then
        WAIT_FOR_START="FALSE"
    else
        WAIT_FOR_START="TRUE"
    fi

    if [ "$cleanOption" = "clean" ]
    then
       options="-directclean"
    else
       options="-direct"
    fi
    log "startProduct: calling startWlpServer with options = $options"
    startWlpServer $START_SERVER ${INST_DIR}/appservertools $HTTPS_PORT $contextToUse $WAIT_FOR_START $options

    log "Configuring TWS environment ..."
    TWS_DIR=$INST_DIR/TWS
    cd ${TWS_DIR}
    LIBPATH=${TWS_DIR}/bin:$LIBPATH
    export LIBPATH
    . ./tws_env.sh
    cd - > /dev/null

    if [ "$COMPONENT_TYPE" = "MDM" -o "$COMPONENT_TYPE" = "BKM" ]
    then
        # ************************************
        # Start LWA
        # ************************************
        execute_command $TWS_DIR/StartUpLwa

        # ************************************
        # Start FTA
        # ************************************
        execute_command $TWS_DIR/StartUp
    else
        # ************************************
        # Start LWA
        # ************************************
        execute_command $TWS_DIR/StartUpLwa
    fi
    logexit "startProduct"
}

configForNewAndUpdate()
{
    logentry "configForNewAndUpdate"
    MSG_CONF_TWS=`${MSG_CMD} Message_Configuring $COMPONENT_TYPE`
    echolog  ${MSG_CONF_TWS}
    configureTwsFiles

    MSG_CONF_BROKER=`${MSG_CMD} Message_ConfiguringBroker`
    echolog  ${MSG_CONF_BROKER}
    configureTdwbFiles
    # call configureWlp.sh
    initConfigureWlpParms
    echolog  ${MSG_CONF_WLP}
    execute_command_and_exit_if_fail ${TWSTOOLS_DIR}/configureWlp.sh ${CONFIGURE_WLP_PARMS}
    logexit "configForNewAndUpdate"
}

configurePoolsProperties()
{
    logentry "configurePoolsProperties"
    
    if [ "$COMPONENT_TYPE" = "MDM" -o  "$COMPONENT_TYPE" = "BKM" ]
    then
        log "configurePoolsProperties() updating pools.properties"
        parmRow="FileUpdateListFullPath=$ACTIONTOOLS_DIR/FileUpdatePoolsList.txt data_dir=$DATA_DIR"
        execute_command_and_exit_if_fail_quiet  $INST_DIR/TWS/JavaExt/jre/jre/bin/java -cp  $ACTIONTOOLS_DIR/FileUpdate.jar com.hcl.wa.install.FileUpdate $parmRow
    else
        log "configurePoolsProperties() pools.properties is updated only if component type is MDM or BKM"
    fi
    logexit "configurePoolsProperties"
}

configForNew()
{
    logentry "configForNew"
    if [ "${OPERATION}" = "${OP_NEW}" ]
    then
        if [ "$COMPONENT_TYPE" = "BKM" -o "$COMPONENT_TYPE" = "BDM" ]
        then
            bkmSwichBrokerWorkstationProperties
        else
            if [ "$COMPONENT_TYPE" = "MDM" -o "$COMPONENT_TYPE" = "DDM" ]
            then
                mdmCleanUpBrokerWorkstationProperties
            fi
        fi
        
		WLP_USR_RES_SEC_DIR=${DATA_DIR}/usr/servers/${WLP_ENGINE_SERVER}/resources/security
        if [ ! -d "$WLP_USR_RES_SEC_DIR"  ]
        then
            WLP_USR_RES_SEC_DIR=${WLP_USER_DIR}/servers/${WLP_ENGINE_SERVER}/resources/security
        fi
        
		copySSL ${WLP_USR_RES_SEC_DIR}

        # call configureDatasource.sh
        initConfigureDatasourceParms
        echolog  ${MSG_CONF_DATASOURCE}
        execute_command_and_exit_if_fail ${TWSTOOLS_DIR}/configureDatasource.sh ${CONFIGURE_DATASOURCE_PARMS}
        
        #add line with $MASTERAGENTS if MDM to the file @(data_dir)/ITA/cpa/config/pools.properties
        configurePoolsProperties

        #configure Sfinal
        MSG_CONF_SFINAL=`${MSG_CMD} Message_ConfiguringSFinal`
        echolog  ${MSG_CONF_SFINAL}
        configureSfinal
    fi
    logexit "configForNew"
}

mdmCleanUpBrokerWorkstationProperties()
{
    logentry "mdmCleanUpBrokerWorkstationProperties"
    BROKER_WKS_BKM_PROPERTIES_FILE="${DATA_DIR}/broker/config/BrokerWorkstation_backup.properties"

    if [ -f "${BROKER_WKS_BKM_PROPERTIES_FILE}" ]
    then
        rm -f ${BROKER_WKS_BKM_PROPERTIES_FILE}
    fi
    logexit "mdmCleanUpBrokerWorkstationProperties"
}

initHiddenDefault(){
    logentry "initHiddenDefault"
    INSTALL_BINARY="true"
    CONFIGURE="true"
    POSTCONFIGURE="true"
    POPULATE="true"
    OPTMANFORDOCKER="false"
    COMMIT="true"
    CHECK="true"
    CHECKDB="true"
    EXECINST="true"
    logexit "initHiddenDefault"
}
# **************************
# Check values
# **************************
checkCalledFromImageDir(){
    logentry "checkCalledFromImageDir"
    debug "checkCalledFromImageDir ${THIS_SCRIPT_ABSOLUTE_DIR}/Tivoli_MDM_$INST_INTERP "
    checkImageDir ${THIS_SCRIPT_ABSOLUTE_DIR}/Tivoli_MDM_$INST_INTERP
    logexit "checkCalledFromImageDir"
}


checkWauser(){
    logentry "checkWauser"
    MSG_USER_NOT_EXIST=""
    checkExistingUser $WA_USER
    if [ $result -ne 0 ]
    then
        MSG_USER_NOT_EXIST="`${MSG_CMD} Message_UserDoesNotExist $WA_USER '--wauser' `\n"
        printf "${MSG_USER_NOT_EXIST}1}${OUT_USAGE}"
        exit 1
    fi
    logexit "checkWauser"
}

checkDDMParam()
{
    logentry "checkDDMParam"
    if [  -z "$2"  ]
    then
        if [ "$COMPONENT_TYPE" = "DDM" -o  "$COMPONENT_TYPE" = "BDM" ]
        then
           MSG=`${MSG_CMD} Message_RequiredOption $1`
           echoErrorAndUsageAndExit $MSG
        fi
    else
        if [ "$COMPONENT_TYPE" = "MDM" -o  "$COMPONENT_TYPE" = "BKM" ]
        then
           MSG=`${MSG_CMD} Message_WrongOptionForComponent $1 DDM`
           echoErrorAndUsageAndExit $MSG
        fi
    fi
    logexit "checkDDMParam"
}

checkBDDMParam()
{
    logentry "checkBDDMParam"
    if [  ! -z "$2"  ]
    then
           #value provided with option $1 will be ignored since there is already a broker in the database
           MSG=`${MSG_CMD} Message_IgnoredBDDMOption $1`
           echolog  $MSG
     fi
    logexit "checkBDDMParam"
}

checkBDDM()
{
    logentry "checkBDDM"
    if [ "${COMPONENT_TYPE}" = "BDM" ]
    then
        #"mdm_host_name=$MDM_BROKER_HOSTNAME"
        #MasterDomainManager.HostName=$(mdm_host_name)
        checkBDDMParam "--mdmbrokerhostname" $MDM_BROKER_HOSTNAME_BY_USER

        #"mdm_https_port=$MDM_HTTPS_PORT"
        #MasterDomainManager.HttpsPort=$(mdm_https_port)
        checkBDDMParam "--mdmhttpsport" $MDM_HTTPS_PORT_BY_USER

        #"master_cpu=$MASTER"
        #MasterDomainManager.Name=$(master_cpu)
        checkBDDMParam "--master" $MASTER_BY_USER
        
        #"dm_tcp_port=$NETMAN_PORT"
        #DomainManager.Workstation.Port=$(dm_tcp_port)
        checkBDDMParam "--netmanport" $NETMAN_PORT_BY_USER

        #"dm_domain_name=$DOMAIN"
        #DomainManager.Workstation.Domain=$(dm_domain_name)
        checkBDDMParam "--domain" $DOMAIN_BY_USER

        #"dm_this_cpu=$THISCPU"
        #DomainManager.Workstation.Name=$(dm_this_cpu)
        checkBDDMParam "--thiscpu" $THISCPU_BY_USER

        #"this_cpu=$BROKER_WORKSTATION_NAME"
        #Broker.Workstation.Name=$(this_cpu)
        checkBDDMParam "--brwksname" $BROKER_WORKSTATION_NAME_BY_USER
 
        #"tcp_port=$BROKER_NETMAN_PORT"
        #Broker.Workstation.Port=$(tcp_port)
        checkBDDMParam "--brnetmanport" $BROKER_NETMAN_PORT_BY_USER
   
    fi
    logexit "checkBDDM"
}

checkDDM()
{
    logentry "checkDDM"
    checkIsForZos ${ISFORZOS}

    if [  "${ISFORZOS_LC}" = "no" ]
    then
        checkDDMParam "--mdmbrokerhostname" $MDM_BROKER_HOSTNAME
        checkDDMParam "--mdmhttpsport" $MDM_HTTPS_PORT
        checkDDMParam "--master" $MASTER

        if [  ! -z "$MDM_HTTPS_PORT"  ]
        then
            isValidPort $MDM_HTTPS_PORT
            if [ $result -ne 1 ]
            then
                MSG="`${MSG_CMD} Message_WrongRangePort $BROKER_PORT --brokerport`\n"
                echoErrorAndUsageAndExit $MSG
            fi
        fi

        if [  ! -z "$MASTER"  ]
        then
            MSG_MASTER=""
            isValidLength "$MASTER" "16"
            if [ $result -ne 1 ]
            then
                #Message_TooLongValue=WAINST021E The value {0} provided after option {1} is too long. The limit is {2} bytes
                MSG_MASTER="`${MSG_CMD} Message_TooLongValue $MASTER '--master' '16'`\n"
                echoErrorAndUsageAndExit $MSG_MASTER
            fi
        fi
    else
        if [  "${ISFORZOS_LC}" = "yes" ]
        then
            checkDDMForZos
        else
             echo "ERROR should never pass from here"
             exit 1
        fi
    fi
    logexit "checkDDM"
}
###################################################################
# checkIsForZos
#  Input:
#     $1 ISFORZOS
#
#  exit with correct nls message if $1 not yes or no
#       or if component not DDM or BDM
#
###################################################################
checkIsForZos()
{
    logentry "checkIsForZos"
    ISFORZOS=$1
    EXIT_CODE=0
    ISFORZOS_LC=`echo $ISFORZOS |$TR "[:upper:]" "[:lower:]"`
    if [ ! -z "${ISFORZOS_LC}" ]
    then
        if [ "${COMPONENT_TYPE}" != "DDM" -a "${COMPONENT_TYPE}" != "BDM" ]
        then
            if [ "${ISFORZOS_LC}" = "yes" ]
            then
                EXIT_CODE=1
                ERROR_MSG="`${MSG_CMD} Message_IsForZosDDMOnly --isforzos `"
            fi
        else
            if [ "${ISFORZOS_LC}" != "yes" -a "${ISFORZOS_LC}" != "no" ]
            then
                EXIT_CODE=1
                ERROR_MSG="`${MSG_CMD} Message_WrongValue $ISFORZOS --isforzos '< yes | no >' `"
            fi
        fi
    fi
    if [ ${EXIT_CODE} -ne 0 ]
    then
        echolog ${ERROR_MSG}
        echoInfo ${USAGE_MSG}
        exit $EXIT_CODE
    fi
    logexit "checkIsForZos"
}
###################################################################
# checkDDMForZos
#  if isforzos = yes some variables (see below) are set by the script and cannot be entered by the user
#  in case some variables are set by the user send message
#       "option invalid if isforzos = yes"
#  and exit
#
#  Input: all variable set with method setDefaultIsForZos
#        THISCPU
#        DOMAIN
#        MASTER
#        BROKER_NETMAN_PORT
#        MDM_BROKER_HOSTNAME
#        MDM_HTTPS_PORT
#
#  exit with correct nls message if error
#
###################################################################
checkDDMForZos()
{
    logentry "checkDDMForZos"
    # "option invalid if isforzos = yes"
    checkDDMForZosParam "--thiscpu" $THISCPU_BY_USER
    checkDDMForZosParam "--brnetmanport" $BROKER_NETMAN_PORT_BY_USER
    checkDDMForZosParam "--domain" $DOMAIN_BY_USER
    checkDDMForZosParam "--mdmbrokerhostname" $MDM_BROKER_HOSTNAME_BY_USER
    checkDDMForZosParam "--mdmhttpsport" $MDM_HTTPS_PORT_BY_USER
    checkDDMForZosParam "--master" $MASTER_BY_USER
    logexit "checkDDMForZos"
}

checkDDMForZosParam()
{
    logentry "checkDDMForZosParam"
    if [ !  -z "$2"  ]
    then
        MSG=`${MSG_CMD} Message_WrongDDMOptionForZos $1`
        echoErrorAndUsageAndExit $MSG
    fi
    logexit "checkDDMForZosParam"
}

checkValuesForNew()
{
    logentry "checkValuesForNew"
    RET_COD=0

    OUT_USAGE="${USAGE_MSG}\n"

    checkDDM
    
    checkBDDM

    checkInvalidChars

    checkBooleanOptions

    #N.B. DO NOT CHECK HERE DB_USER since it must exist in the DB host, not in the host where serverinst.sh is running

    MSG_WRONG_USER=""
    checkUser ${WA_USER}
    if [ $RET_CODE -ne 0 ]
    then
        MSG_WRONG_USER="${RET_STDOUT}\n"
        RET_COD=1
    fi

    RDBMS_TYPE_UC=`echo $RDBMS_TYPE |$TR "[:lower:]" "[:upper:]"`
    MSG_WRONG_RDBMS_TYPE=""
    if [ "DB2" != "$RDBMS_TYPE_UC" -a  "ORACLE" != "$RDBMS_TYPE_UC" -a  "MSSQL" != "$RDBMS_TYPE_UC" -a  "IDS" != "$RDBMS_TYPE_UC" ]
    then
        #Message_WrongValue=WAINST033E Wrong value {0} for the option {1}. Expected values are {2}
        MSG_WRONG_RDBMS_TYPE="`${MSG_CMD} Message_WrongValue $RDBMS_TYPE_UC --rdbmstype '< DB2 | ORACLE | MSSQL | IDS >' `\n"
        RET_COD=1
    fi

    #INFORMIX_SERVER
    MSG_WRONG_INFORMIX_SERVER=""
    if [ ! -z "$INFORMIX_SERVER" -a "$RDBMS_TYPE_UC" != "IDS" ]
    then
        #Message_WrongInformixOption=WAINST0240E Option --informixserver is supported only if rdbmstype is IDS.
        MSG_WRONG_INFORMIX_SERVER=`${MSG_CMD} Message_WrongInformixOption`
        RET_COD=1
    fi

    MSG_WRONG_COMPONENT_TYPE=""
    if [ "MDM" != "$COMPONENT_TYPE" -a  "DDM" != "$COMPONENT_TYPE" ]
    then
        #Message_WrongValue=WAINST033E Wrong value {0} for the option {1}. Expected values are {2}
        MSG_WRONG_COMPONENT_TYPE="`${MSG_CMD} Message_WrongValue $COMPONENT_TYPE --componenttype '< MDM | DDM >' `\n"
        RET_COD=1
    fi

    if [ $RET_COD -eq 1 ]
    then
        #use printf nd not echo to avoid \n problems
        printf "${MSG_WRONG_USER}${MSG_WRONG_RDBMS_TYPE}${MSG_WRONG_INFORMIX_SERVER}${MSG_WRONG_COMPONENT_TYPE}${OUT_USAGE}"
        exit 1
    fi

    logexit "checkValuesForNew"
}
###################################################################
# setDefaultIsForZos
#  Input:
#     $1 ISFORZOS
#
#  Output:
#      THISCPU This workstation name => Always generated from the hostname, cannot be specified
#      MASTER Master domain manager workstation name ==> DDM1 hardcoded
#      DOMAIN ==> MYDOMAIN hardcoded
#      BROKER_NETMAN_PORT Dynamic domain manager port (used by Netman) ==> 41114 hardcoded
#      MDM_BROKER_HOSTNAME Master domain manager host name ==> NOT_CONFIGURED hardcoded
#      MDM_HTTPS_PORT Master domain manager HTTPS port ==> 31116 hardcoded
#
###################################################################
setDefaultDDMForZos()
{
    logentry "setDefaultDDMForZos"
    ISFORZOS_LC=`echo $ISFORZOS |$TR "[:upper:]" "[:lower:]"`
    if [ "${ISFORZOS_LC}" = "yes" ]
    then
        THISCPU="$DEFAULT_THISCPU"
        MASTER="DDM1"
        DOMAIN="MYDOMAIN"
        BROKER_NETMAN_PORT="41114"
        MDM_BROKER_HOSTNAME="NOT_CONFIGURED"
        MDM_HTTPS_PORT="31116"
    fi
    logexit "setDefaultDDMForZos"
}



checkBooleanOptions()
{
    logentry "checkBooleanOptions"
    checkBooleanOption --skipcheckprereq ${SKIPCHECKPREREQ}
    checkBooleanOption --skipcheckemptydir ${SKIPCHECKEMPTYDIR}
    checkBooleanOption --startserver ${START_SERVER}
    checkBooleanOption --override ${OVERRIDE}

    logexit "checkBooleanOptions"
}

checkInvalidChars()
{
    logentry "checkInvalidChars"
    OUT1=""
    if [ ! -z "$THISCPU" ]
    then
        checkValidChar ${THISCPU} "--thiscpu"
        if [ $result -ne 0 ]
        then
            OUT1="`${MSG_CMD} Message_InvalidCharacter $THISCPU --thiscpu`\n"
            RET_COD=1
        fi
    fi

    OUT2=""
    if [ ! -z "$DISPLAYNAME" ]
    then
        checkValidChar ${DISPLAYNAME} "--displayname"
        if [ $result -ne 0 ]
        then
            OUT2="`${MSG_CMD} Message_InvalidCharacter $DISPLAYNAME --displayname`\n"
            RET_COD=1
        fi
    fi

    OUT3=""
    if [ ! -z "$BROKER_WORKSTATION_NAME" ]
    then
        checkValidChar ${BROKER_WORKSTATION_NAME} "--brwksname"
        if [ $result -ne 0 ]
        then
            OUT3="`${MSG_CMD} Message_InvalidCharacter $BROKER_WORKSTATION_NAME --brwksname`\n"
            RET_COD=1
        fi
    fi

    OUT4=""
    if [ ! -z "$DOMAIN" ]
    then
        checkValidChar ${DOMAIN} "--domain"
        if [ $result -ne 0 ]
        then
            OUT4="`${MSG_CMD} Message_InvalidCharacter $DOMAIN --domain`\n"
            RET_COD=1
        fi
    fi

    OUT5=""
    if [ ! -z "$WA_PASSWORD" ]
    then
        checkValidCharForEngineDwcPw ${WA_PASSWORD}
        if [ $result -ne 0 ]
        then
            OUT5="`${MSG_CMD} Message_InvalidPasswordCharacter $WA_PASSWORD --wapassword $VALID_PW_CHARS`\n"
            RET_COD=1
        fi
    fi
    
    OUT6=""
    if [ ! -z "${INST_DIR}" ]
    then
        checkValidCharForPath ${INST_DIR}
        if [ $result -ne 0 ]
        then
            OUT6="`${MSG_CMD} Message_InvalidPathCharacter ${INST_DIR} --inst_dir `\n"
            RET_COD=1
        fi
    fi
    
    OUT7=""
    if [ ! -z "${WORK_DIR}" ]
    then
        checkValidCharForPath ${WORK_DIR}
        if [ $result -ne 0 ]
        then
            OUT7="`${MSG_CMD} Message_InvalidPathCharacter ${WORK_DIR} --work_dir `\n"
            RET_COD=1
        fi
    fi

    OUT8=""
    if [ ! -z "${DATA_DIR}" ]
    then
        checkValidCharForPath ${DATA_DIR}
        if [ $result -ne 0 ]
        then
            OUT8="`${MSG_CMD} Message_InvalidPathCharacter ${DATA_DIR} --data_dir `\n"
            RET_COD=1
        fi
    fi

    OUT9=""
    if [ ! -z "$XANAME" ]
    then
        checkValidChar ${XANAME} "--xaname"
        if [ $result -ne 0 ]
        then
            OUT9="`${MSG_CMD} Message_InvalidCharacter $XANAME --xaname`\n"
            RET_COD=1
        fi
    fi

    if [ $RET_COD -eq 1 ]
    then
        #use printf nd not echo to avoid \n problems
        printf "${OUT1}${OUT2}${OUT3}${OUT4}${OUT5}${OUT6}${OUT7}${OUT8}${OUT9}${OUT_USAGE}"
        exit 1
    fi
    logexit "checkInvalidChars"
}


#
#    company  40
#    thiscpu 16
#    brwksname 16
#    displayname  16
#    domain 16
#    db2 dbname 8


checkLengths()
{
    logentry "checkLengths"
    RET_COD=0

    MSG_COMPANY=""
    isValidLength "$COMPANY_NAME" "40"
    if [ $result -ne 1 ]
    then
        #Message_TooLongValue=WAINST021E The value {0} provided after option {1} is too long. The limit is {2} bytes
        MSG_COMPANY="`${MSG_CMD} Message_TooLongValue $COMPANY_NAME '--company' '40'`\n"
        RET_COD=1
    fi

    MSG_THISCPU=""
    isValidLength "$THISCPU" "16"
    if [ $result -ne 1 ]
    then
        #Message_TooLongValue=WAINST021E The value {0} provided after option {1} is too long. The limit is {2} bytes
        MSG_THISCPU="`${MSG_CMD} Message_TooLongValue $THISCPU '--thiscpu' '16'`\n"
        RET_COD=1
    fi

    MSG_BROKER_WORKSTATION_NAME=""
    isValidLength "$BROKER_WORKSTATION_NAME" "16"
    if [ $result -ne 1 ]
    then
        #Message_TooLongValue=WAINST021E The value {0} provided after option {1} is too long. The limit is {2} bytes
        MSG_BROKER_WORKSTATION_NAME="`${MSG_CMD} Message_TooLongValue $BROKER_WORKSTATION_NAME '--brwksname' '16'`\n"
        RET_COD=1
    fi

    MSG_DISPLAYNAME=""
    isValidLength "$DISPLAYNAME" "16"
    if [ $result -ne 1 ]
    then
        #Message_TooLongValue=WAINST021E The value {0} provided after option {1} is too long. The limit is {2} bytes
        MSG_DISPLAYNAME="`${MSG_CMD} Message_TooLongValue $DISPLAYNAME '--displayname' '16'`\n"
        RET_COD=1
    fi

    MSG_XANAME=""
    isValidLength "$XANAME" "16"
    if [ $result -ne 1 ]
    then
        #Message_TooLongValue=WAINST021E The value {0} provided after option {1} is too long. The limit is {2} bytes
        MSG_XANAME="`${MSG_CMD} Message_TooLongValue $XANAME '--xaname' '16'`\n"
        RET_COD=1
    fi
 
    MSG_DOMAIN=""
    isValidLength "$DOMAIN" "16"
    if [ $result -ne 1 ]
    then
        #Message_TooLongValue=WAINST021E The value {0} provided after option {1} is too long. The limit is {2} bytes
        MSG_DOMAIN="`${MSG_CMD} Message_TooLongValue $DOMAIN '--domain' '16'`\n"
        RET_COD=1
    fi

    RDBMS_TYPE_UC=`echo $RDBMS_TYPE |$TR "[:lower:]" "[:upper:]"`
    if [ "DB2" = "$RDBMS_TYPE_UC"  ]
    then
        MSG_DBNAME=""
        isValidLength "$DB_NAME" "8"
        if [ $result -ne 1 ]
        then
            #Message_TooLongValue=WAINST021E The value {0} provided after option {1} is too long. The limit is {2} bytes
            MSG_DBNAME="`${MSG_CMD} Message_TooLongValue $DB_NAME '--dbname' '8'`\n"
            RET_COD=1
        fi
    fi

    if [ $RET_COD -eq 1 ]
    then
        #use printf nd not echo to avoid \n problems
        printf "${MSG_COMPANY}${MSG_THISCPU}${MSG_BROKER_WORKSTATION_NAME}${MSG_DISPLAYNAME}${MSG_XANAME}${MSG_DOMAIN}${MSG_DBNAME}${OUT_USAGE}"
        exit 1
    fi
    logexit "checkLengths"

}

checkPorts()
{
    logentry "checkPorts"
    RET_COD=0

    OUT1a=""
    isValidPort $JM_PORT
    if [ $result -ne 1 ]
    then
        OUT1a="`${MSG_CMD} Message_WrongRangePort $JM_PORT --jmport`\n"
        RET_COD=1
    fi

    OUT1b=""
    check_listening_port ${JM_PORT}
    if [ $? -eq 1 ]
    then
        #OUT1=" The port ${JM_PORT} is already used by another process."
        OUT1b="`${MSG_CMD} Message_AlreadyUsedPort $JM_PORT --jmport`\n"
        RET_COD=1
    fi

    OUT2a=""
    isValidPort $NETMAN_PORT
    if [ $result -ne 1 ]
    then
        OUT2a="`${MSG_CMD} Message_WrongRangePort $NETMAN_PORT --netmanport`\n"
        RET_COD=1
    fi

    OUT2b=""
    check_listening_port ${NETMAN_PORT}
    if [ $? -eq 1 ]
    then
        #OUT2=" The port ${NETMAN_PORT} is already used by another process."
        OUT2b="`${MSG_CMD} Message_AlreadyUsedPort $NETMAN_PORT --netmanport`\n"
        RET_COD=1
    fi

    OUT3a=""
    isValidPort $HTTP_PORT
    if [ $result -ne 1 ]
    then
        OUT3a="`${MSG_CMD} Message_WrongRangePort $HTTP_PORT --httpport`\n"
        RET_COD=1
    fi

    OUT3b=""
    check_listening_port ${HTTP_PORT}
    if [ $? -eq 1 ]
    then
        #OUT3=" The httpport ${HTTP_PORT} is already used by another process."
        OUT3b="`${MSG_CMD} Message_AlreadyUsedPort $HTTP_PORT --httpport`\n"
        RET_COD=1
    fi

    OUT4a=""
    isValidPort $HTTPS_PORT
    if [ $result -ne 1 ]
    then
        OUT4a="`${MSG_CMD} Message_WrongRangePort $HTTPS_PORT --httpsport`\n"
        RET_COD=1
    fi


    OUT4b=""
    check_listening_port ${HTTPS_PORT}
    if [ $? -eq 1 ]
    then
        #OUT4=" The httpsport ${HTTPS_PORT} is already used by another process."
        OUT4b="`${MSG_CMD} Message_AlreadyUsedPort $HTTPS_PORT --httpsport`\n"
        RET_COD=1
    fi

    OUT5a=""
    isValidPort $EIF_PORT
    if [ $result -ne 1 ]
    then
        OUT5a="`${MSG_CMD} Message_WrongRangePort $EIF_PORT --eifport`\n"
        RET_COD=1
    fi

    OUT5b=""
    check_listening_port ${EIF_PORT}
    if [ $? -eq 1 ]
    then
        #OUT5=" The eifport ${EIF_PORT} is already used by another process."
        OUT5b="`${MSG_CMD} Message_AlreadyUsedPort $EIF_PORT --eifport`\n"
        RET_COD=1
    fi

    OUT6a=""
    isValidPort $BOOTSTRAP_PORT
    if [ $result -ne 1 ]
    then
        OUT6a="`${MSG_CMD} Message_WrongRangePort $BOOTSTRAP_PORT --bootstrapport`\n"
        RET_COD=1
    fi

    OUT6b=""
    check_listening_port ${BOOTSTRAP_PORT}
    if [ $? -eq 1 ]
    then
        #OUT6=" The eifport ${BOOTSTRAP_PORT} is already used by another process."
        OUT6b="`${MSG_CMD} Message_AlreadyUsedPort $BOOTSTRAP_PORT --bootstrapport`\n"
        RET_COD=1
    fi

    OUT7a=""
    isValidPort $BOOTSTRAP_SEC_PORT
    if [ $result -ne 1 ]
    then
        OUT7a="`${MSG_CMD} Message_WrongRangePort $BOOTSTRAP_SED_PORT --bootsecport`\n"
        RET_COD=1
    fi

    OUT7b=""
    check_listening_port ${BOOTSTRAP_SEC_PORT}
    if [ $? -eq 1 ]
    then
        #OUT7=" The eifport ${BOOTSTRAP_SEC_PORT} is already used by another process."
        OUT7b="`${MSG_CMD} Message_AlreadyUsedPort $BOOTSTRAP_SEC_PORT --bootsecport`\n"
        RET_COD=1
    fi

    if [ $RET_COD -eq 1 ]
    then
        printf "${OUT1a}${OUT2a}${OUT3a}${OUT4a}${OUT5a}${OUT6a}${OUT7a}${OUT1b}${OUT2b}${OUT3b}${OUT4b}${OUT5b}${OUT6b}${OUT7b}${OUT_USAGE}"
        exit 1
    fi
    logexit "checkPorts"
}

# ********************
# usage
# ********************

usage()
{
    logentry "usage"
    
    USAGE_CMD="${JAVA_BIN_DIR}/java -cp  ${TOOLS_DIR}/FileUpdate.jar com.hcl.wa.install.Usage -lang $INST_LANG  -usage ${TEMPLATE_PROPS_FILE}"
    USAGE_TXT=`${USAGE_CMD}`
    printf "${USAGE_TXT}"
    echo ""
    
    exit 0
    logexit "usage"
}

initLocalVariablesPostInput()
{
    logentry "initLocalVariablesPostInput"

    if [ -z "$WORK_DIR" ]
    then
        WORK_DIR="${SERVER_TMP_DIR}"
    fi
    
    initLocalVariablesPostInputForNew
    
    #init wlp user dir
    WLP_USER_DIR=$INST_DIR/usr

    #needed first time in modifyOwnership after twsinst call
    TWSTOOLS_DIR=${INST_DIR}/TWS/tws_tools
    
    WLP_APPS_DIR="${WLP_USER_DIR}/servers/${WLP_ENGINE_SERVER}/apps"

    logexit "initLocalVariablesPostInput"
}

initLocalVariablesPostInputForNew()
{
    logentry "initLocalVariablesPostInputForNew"

    if [ "${OPERATION}" = "${OP_NEW}" ]
    then
        #init this hostname
        # TT I'm calling the procedure calculateHostName also if the THIS_HOSTNAME is not null
        # TT in order to set the value of the QUALIFIED_HOSTNAME variable, used in FileUpdateTdwb step

        calculateHostName

        if [ -z "$THIS_HOSTNAME" ]
        then
            # TT calculateHostName
            THIS_HOSTNAME=$QUALIFIED_HOSTNAME
        fi

        DEFAULT_BROKER_HOSTNAME=$THIS_HOSTNAME

        #init defaults that depends on CPUTYE
        if [ "$COMPONENT_TYPE" = "MDM" -o "$COMPONENT_TYPE" = "BKM" ]
        then
            DEFAULT_DOMAIN="MASTERDM"
            DEFAULT_THISCPU=`uname -n | $AWK -F'[ |.]' '{print $1}' | cut -c1-16`
            DEFAULT_AGENT_DISPLAY_NAME=`echo $DEFAULT_THISCPU | cut -c1-14`_1
            DEFAULT_BROKER_WORKSTATION_NAME=`echo $DEFAULT_THISCPU | cut -c1-12`_DWB
            DEFAULT_XA_NAME=`echo $DEFAULT_THISCPU | cut -c1-13`_XA
        fi

        if [ "$COMPONENT_TYPE" = "DDM"  -o "$COMPONENT_TYPE"  = "BDM"  ]
        then
            DEFAULT_DOMAIN="DYNAMICDM"
            DEFAULT_THISCPU=`uname -n | $AWK -F'[ |.]' '{print $1}' | cut -c1-12`_DDM
            DEFAULT_AGENT_DISPLAY_NAME=`uname -n | awk -F'[ |.]' '{print $1}' | cut -c1-13`_D1
            DEFAULT_BROKER_WORKSTATION_NAME=`uname -n | awk -F'[ |.]' '{print $1}' | cut -c1-11`_DDWB

        fi

        #init thiscpu
        if [ -z "$THISCPU" ]
        then
            THISCPU=$DEFAULT_THISCPU
        fi

        if [ -z "$MASTER" ]
        then
            MASTER=$THISCPU
        fi

        #init domain
        if [ -z "$DOMAIN" ]
        then
            DOMAIN=$DEFAULT_DOMAIN
        fi

        BROKER_HOSTNAME=$DEFAULT_BROKER_HOSTNAME

        #init displayname
        if [ -z "$DISPLAYNAME" ]
        then
            DISPLAYNAME=$DEFAULT_AGENT_DISPLAY_NAME
        fi

         #init xaname
        if [ -z "$XANAME" ]
        then
            XANAME=$DEFAULT_XA_NAME
        fi
 
        #init broker workstationname
        if [ -z "$BROKER_WORKSTATION_NAME" ]
        then
            BROKER_WORKSTATION_NAME=$DEFAULT_BROKER_WORKSTATION_NAME
        fi

        #init DATA_DIR only in fresh installation, in update is read from /etc/TWA/registry example: TWS_dataPath=/opt/wa/server_wauser/TWS
        if [ -z "$DATA_DIR" ]
        then
            # with the following setting the behaviour is the same as 9.4 and early release
            #DATA_DIR="${INST_DIR}/TWS"
            DATA_DIR="${INST_DIR}/TWSDATA"
        fi

        if [ -z "$WORK_DIR" ]
        then
            WORK_DIR="${SERVER_TMP_DIR}"
        fi
        #init db port depending on rdbms type
        initDbPort ${THIS_SCRIPT_DIR} ${RDBMS_TYPE}
        log "DB_PORT after initDbPort = $initDbPort"

        #init jdbc driver path depending on rdbms type
        #not needed in update since it is read from registry file
        initConfigureJdbcDriver

        #--------------------------------------
        # check DB - This function must not be executed during Docker Build because the db is not present. We consider always MDM at build time. This will be executed only at runtime during Docker initialization.
        # This section must run also with not-root user
        #--------------------------------------
        #not needed in update since it is read from registry file
        if [ "$CHECKDB" = "true" ]
        then
            testConnectionToDb ${THIS_SCRIPT_DIR} ${THIS_SCRIPT_ABSOLUTE_DIR}/Tivoli_MDM_${INST_INTERP}/${END_DB_DRIVER_PATH} ${COMPONENT_TYPE} "test_connection_to_db"
            initComponentType
        fi

        setDefaultDDMForZos
    fi
    logexit "initLocalVariablesPostInputForNew"
}

initTwsinstParms()
{
    logentry "initTwsinstParms"
    initTwsinstParmsCommon
    if [ "${OPERATION}" = "${OP_NEW}" ]
    then
        initTwsinstParmsForNew
    else
        if [ "${OPERATION}" = "${OP_UPDATE}" ]
        then
            initTwsinstParmsForUpdate
        fi
    fi
    logexit "initTwsinstParms"
}
initTwsinstParmsCommon()
{
    logentry "initTwsinstParmsCommon"
    c1="-acceptlicense $ACCEPTLICENSE"
    c2="-uname $WA_USER"
    c3="-lang $INST_LANG"
    c4="-caller $COMPONENT_TYPE"

    # Convert input to uppercase
    SKIPCHECKPREREQ_UC=`echo "$SKIPCHECKPREREQ" |tr "[:lower:]" "[:upper:]"`
    if [ "$SKIPCHECKPREREQ_UC" = "TRUE" ]
    then
        c5="-skipcheckprereq"
    else
        c5=""
    fi

    if [ -z "$WORK_DIR" ]
    then
        log "initTwsinstParmsCommon() internal error WORK_DIR should not be blank since it is initalized in initLocalVariablesPostInput"
        c6=""
    else
        c6="-work_dir $WORK_DIR"
    fi

    TWSINST_COMMON_PARMS="$c1 $c2 $c3 $c4 $c5 $c6 "
    logexit "initTwsinstParmsCommon"
}


initTwsinstParmsForUpdate()
{
    logentry "initTwsinstParmsForUpdate"
    # parameters twsinst
    t1="-restore"
    TWSINST_PARMS="$t1 $TWSINST_COMMON_PARMS"
    logexit "initTwsinstParmsForUpdate"
}

initSSLParms(){
    logentry "initSSLParms"
    s1=""
    s2=""
    if [ ! -z "$SSL_PASSWORD" -a ! -z "$SSL_KEY_FOLDER" ]
    then
            s1="-sslpassword $SSL_PASSWORD"
            s2="-sslkeysfolder $SSL_KEY_FOLDER"
    fi
    SSL_PARMS="$s1 $s2"
    logexit "initSSLParms"

}

initTwsinstParmsForNew()
{
    logentry "initTwsinstParmsForNew"

    # parameters twsinst
    t1="-new"
    t2="-inst_dir $INST_DIR"
    t3="-agent both"
    t4="-addjruntime true"
    t5="-jmport $JM_PORT"
    t6="-hostname $THIS_HOSTNAME"
    t7="-displayname $DISPLAYNAME"
    t8="-port $NETMAN_PORT"
    t9="-thiscpu $THISCPU"
    t10="-master $MASTER"
    t11="-company $COMPANY_NAME"
    t12="-tdwbhostname $BROKER_HOSTNAME"
    t13="-tdwbport $HTTPS_PORT"
    if [ -z "$DATA_DIR" ]
    then
        t14=""
    else
        t14="-data_dir $DATA_DIR"
    fi

    initSSLParms
    TWSINST_PARMS="$t1 $t2 $t3 $t4 $t5 $t6 $t7 $t8 $t9 $t10 $t11 $t12 $t13 $t14 $TWSINST_COMMON_PARMS $SSL_PARMS"
    logexit "initTwsinstParmsForNew"

}


initConfigureJdbcDriver()
{
    # Set default value for jdbc drivers if not set.
    # (default value has been removed from configureDatasource.properties
    # in order to understand if the DB_DRIVER_PATH variable has been set
    # by the user (into the properties or by cmdline parameter. In this way if
    # DB_DRIVER_PATH is null at this point we can set the default value
    # pointing to the installed jdbcDrivers
    logentry "initConfigureJdbcDriver"
    RDBMS_TYPE_LC=`echo $RDBMS_TYPE |$TR "[:upper:]" "[:lower:]"`

    if [ "$RDBMS_TYPE_LC" = "ids" ]
    then
        END_DB_DRIVER_PATH="TWS/jdbcdrivers/informix"
    else
        END_DB_DRIVER_PATH="TWS/jdbcdrivers/${RDBMS_TYPE_LC}"
    fi
    if [ -z "$DB_DRIVER_PATH" ]
    then
        DB_DRIVER_PATH="${INST_DIR}/${END_DB_DRIVER_PATH}"
    fi

    #  example in db2:
    #  jdbc\:db2\://EU-HWS-WIN13.NONPROD.HCLPNP.COM\:50000/TWS
    #  com.ibm.tdwb.dao.rdbms.jdbcPath=jdbc\:db2\://$(dbhost)\:$(dbport)/$(dbname)

    # example in oracle
    # jdbc:oracle:thin:@//hostName:port/db    su oracle

    # example in mssql
    # jdbc:sqlserver://hostName:port;DatabaseName=db

    # default db2
    JDBC_DRIVER="com.ibm.db2.jcc.DB2Driver"
    JDBC_PATH="jdbc\:db2\://$DB_HOST_NAME\:$DB_PORT/$DB_NAME"
    
    if   [ ! -z "${DB_ALTERNATE_SERVER_NAMES}" ] && [ ! -z "${DB_ALTERNATE_SERVER_PORTS}" ]; 
    then
        JDBC_PATH=$JDBC_PATH":clientRerouteAlternateServerName="$DB_ALTERNATE_SERVER_NAMES";clientRerouteAlternatePortNumber="$DB_ALTERNATE_SERVER_PORTS";"
    fi

    if  [ "$RDBMS_TYPE_LC" = "mssql" ]
    then
        JDBC_DRIVER="com.microsoft.sqlserver.jdbc.SQLServerDriver"
        JDBC_PATH="jdbc\:sqlserver\://$DB_HOST_NAME\:$DB_PORT\;DatabaseName=$DB_NAME"
    else
        if [  "$RDBMS_TYPE_LC" = "oracle" ]
        then
            JDBC_DRIVER="oracle.jdbc.OracleDriver"
            JDBC_PATH="jdbc\:oracle\:thin\:@//$DB_HOST_NAME\:$DB_PORT/$DB_NAME"
        else
            if [  "$RDBMS_TYPE_LC" = "ids" ]
            then
                JDBC_DRIVER="com.ibm.db2.jcc.DB2Driver"
                JDBC_PATH="jdbc\:ids\://$DB_HOST_NAME\:$DB_PORT/$DB_NAME"
            fi
            if [  "$RDBMS_TYPE_LC" = "ids" ]
            then
                JDBC_DRIVER="com.informix.jdbc.IfxDriver"
                # from datasource_ids.xml:
                #<jndiEntry value="jdbc:informix-sqli://${db.serverName}:${db.portNumber}/${db.databaseName}:INFORMIXSERVER=${db.informixserver};DB_LOCALE=en_us.utf8;CLIENT_LOCALE=en_us.utf8;" jndiName="db.url"/>
                JDBC_PATH="jdbc\:informix-sqli\://$DB_HOST_NAME\:$DB_PORT/$DB_NAME\:INFORMIXSERVER=$INFORMIX_SERVER;DB_LOCALE=en_us.utf8;CLIENT_LOCALE=en_us.utf8;"
            fi
		fi
    fi
    logexit "initConfigureJdbcDriver"

}
initConfigureDatasourceParms()
{
    logentry "initConfigureDatasourceParms"
    initConfigureDatasourceCommonParameters

    # parameters configureDatasource.sh
    
    d1="--servername $WLP_ENGINE_SERVER"
    d2="--wauser $WA_USER"
    
    CONFIGURE_DATASOURCE_PARMS="$CONFIGURE_DATASOURCE_PARMS $d1 $d2"
    logexit "initConfigureDatasourceParms"

}

initConfigureWlpParms()
{
    logentry "initConfigureWlpParms"
    # parameters configureWlp.sh

    WLP_SERVER=$WLP_ENGINE_SERVER
    APPSERVER_TOOL_DIR=${INST_DIR}/appservertools
    WLP_OUTPUT_DIR=${DATA_DIR}/stdlist/appserver
    WLP_USER=${WA_USER}
    WLP_PASSWORD=${WA_PASSWORD}
    WLP_PASSWORD_ENCODED=${WA_PASSWORD_ENCODED}
    WLP_PASSWORD_DECODED=${WA_PASSWORD_DECODED}

    initConfigureWlpCommonParms
    CONFIGURE_WLP_PARMS="$CONFIGURE_WLP_PARMS --wauser $WA_USER"
    logexit "initConfigureWlpParms"
}

initWaPostConfigureParms()
{
    logentry "initWaPostConfigureParms"
    # parameters waPostConfigure.sh
    p1="--wlpdir $WLP_INSTALL_DIR"
    p2="--wauser $WA_USER"
    p3="--wapassword $WA_PASSWORD"
    p4="--startserver $START_SERVER"
    p5="--componenttype $COMPONENT_TYPE"
    p6="--httpsport $HTTPS_PORT"
    p7="--appservertooldir ${INST_DIR}/appservertools"
    p8="--brokerhostname $BROKER_HOSTNAME"
    p9="--dbuser $DB_USER"
    if [ -z "$DB_PASSWORD_ENCODED" ]
    then
        p10="--dbpassword $DB_PASSWORD"
    else
        p10="--dbpassword $DB_PASSWORD_ENCODED"
    fi
    p11="--eifport $EIF_PORT"
    p12="--company $COMPANY_NAME"
    p13="--data_dir $DATA_DIR"
    p14="--populate $POPULATE"
    p15="--optmanfordocker $OPTMANFORDOCKER"
    
    if [ "$IBM_OR_HCL" = "IBM" -a ${COMPONENT_TYPE} = "MDM" ]
    then
        hclFlexeraParameters="--licenseserverid $LICENSE_SERVER_ID --licenseserverurl $LICENSE_SERVER_URL"
    else
        hclFlexeraParameters=""
    fi

    WA_POST_CONFIGURE_PARMS="$p1 $p2 $p3 $p4 $p5 $p6 $p7 $p8 $p9 $p10 $p11 $p12 $p13 $p14 $p15 $hclFlexeraParameters"
    logexit "initWaPostConfigureParms"

 }

isInputProperties()
{
    logentry "isInputProperties"
    IS_INPUT_PROPERTIES="false"
    # get file exension : split with . get field 2
    ext=`echo $1 | cut -f 2  -d .`
    
    if [ "$ext" = "properties" ]
    then
        IS_INPUT_PROPERTIES="true"
    fi
    logexit "isInputProperties"
}

parseInputFromFile()
{
    logentry "parseInputFromFile"

    parseInputFromFileConfDb $1
    parseInputFromFileConfWlp $1
    parseInputFromFileConfSSL $1
    parseInputFromFileWaPostConf $1

    ACCEPTLICENSE=`prop 'ACCEPTLICENSE' $1 $ACCEPTLICENSE`
    WA_USER=`prop 'WA_USER' $1 $WA_USER`
    LANG=`prop 'LANG' $1 $LANG`
    INST_DIR=`prop 'INST_DIR' $1 $INST_DIR`
    #remove last /
    INST_DIR=${INST_DIR%/}
    WORK_DIR=`prop 'WORK_DIR' $1 $WORK_DIR`
    #remove last /
    WORK_DIR=${WORK_DIR%/}
    
    SKIPCHECKPREREQ=`prop 'SKIPCHECKPREREQ' $1 $SKIPCHECKPREREQ`
    SKIPCHECKPREREQ_UC=`echo "$SKIPCHECKPREREQ" |tr "[:lower:]" "[:upper:]"`
    
    SKIPCHECKEMPTYDIR=`prop 'SKIPCHECKEMPTYDIR' $1 $SKIPCHECKEMPTYDIR`
    SKIPCHECKEMPTYDIR_UC=`echo "$SKIPCHECKEMPTYDIR" |tr "[:lower:]" "[:upper:]"`
    
    OVERRIDE=`prop 'OVERRIDE' $1 $OVERRIDE`
        
    JM_PORT=`prop 'JM_PORT' $1 $JM_PORT`
    THIS_HOSTNAME=`prop 'THIS_HOSTNAME' $1 $THIS_HOSTNAME`
    DISPLAYNAME=`prop 'DISPLAYNAME' $1 $DISPLAYNAME`
    XANAME=`prop 'XANAME' $1 $XANAME`
    COMPANY_NAME=`prop 'COMPANY_NAME' $1 $COMPANY_NAME`
    ISFORZOS=`prop 'ISFORZOS' $1 $ISFORZOS`
    
    OLD_NETMAN_PORT=$NETMAN_PORT
    NETMAN_PORT=`prop 'NETMAN_PORT' $1 $NETMAN_PORT`
    
    OLD_THISCPU=$THISCPU
    THISCPU=`prop 'THISCPU' $1 $THISCPU`
    
    OLD_MASTER=$MASTER
    MASTER=`prop 'MASTER' $1 $MASTER`   
     
    OLD_MDM_BROKER_HOSTNAME=$MDM_BROKER_HOSTNAME
    MDM_BROKER_HOSTNAME=`prop 'MDM_BROKER_HOSTNAME' $1 $MDM_BROKER_HOSTNAME`
    
    OLD_MDM_HTTPS_PORT=$MDM_HTTPS_PORT
    MDM_HTTPS_PORT=`prop 'MDM_HTTPS_PORT' $1 $MDM_HTTPS_PORT`
    
    OLD_BROKER_WORKSTATION_NAME=$BROKER_WORKSTATION_NAME
    BROKER_WORKSTATION_NAME=`prop 'BROKER_WORKSTATION_NAME' $1 $MDM_HTTPS_PORT`
    
    OLD_BROKER_NETMAN_PORT=$BROKER_NETMAN_PORT
    BROKER_NETMAN_PORT=`prop 'BROKER_NETMAN_PORT' $1 $BROKER_NETMAN_PORT`
    
    OLD_DOMAIN=$DOMAIN
    DOMAIN=`prop 'DOMAIN' $1 $DOMAIN`

    BOOTSTRAP_PORT=`prop 'BOOTSTRAP_PORT' $1 $BOOTSTRAP_PORT`
    BOOTSTRAP_SEC_PORT=`prop 'BOOTSTRAP_SEC_PORT' $1 $BOOTSTRAP_SEC_PORT`
    
    initByUserFields $1

    logexit "parseInputFromFile"

}

initByUserFields()
{
    logentry "initByUserFields"
    isInputProperties $1
    
    if [ "$IS_INPUT_PROPERTIES" = "true" ]
    then
        if [ "$OLD_NETMAN_PORT" != "$NETMAN_PORT" ]
        then
            NETMAN_PORT_BY_USER=$NETMAN_PORT
        fi
        if [ "$OLD_MASTER" != "$MASTER" ]
        then
            MASTER_BY_USER=$MASTER
        fi
        if [ "$OLD_MDM_BROKER_HOSTNAME" != "$MDM_BROKER_HOSTNAME" ]
        then
            MDM_BROKER_HOSTNAME_BY_USER=$MDM_BROKER_HOSTNAME
        fi
        if [ "$OLD_MDM_HTTPS_PORT" != "$MDM_HTTPS_PORT" ]
        then
            MDM_HTTPS_PORT_BY_USER=$MDM_HTTPS_PORT
        fi
        if [ "$OLD_DOMAIN" != "$DOMAIN" ]
        then
            DOMAIN_BY_USER=$DOMAIN
        fi
        if [ "$OLD_THISCPU" != "$THISCPU" ]
        then
            THISCPU_BY_USER=$THISCPU
        fi
        if [ "$OLD_BROKER_WORKSTATION_NAME" != "$BROKER_WORKSTATION_NAME" ]
        then
            BROKER_WORKSTATION_NAME_BY_USER=$BROKER_WORKSTATION_NAME
        fi
        if [ "$OLD_BROKER_NETMAN_PORT" != "$BROKER_NETMAN_PORT" ]
        then
            BROKER_NETMAN_PORT_BY_USER=$BROKER_NETMAN_PORT
        fi
    fi
    logexit "initByUserFields"
}

echoVars()
{
    log "---------------echoVars serverinst.sh---------------"
    log $@
    log "----------------------------------------------------"

    log "OPERATION           = $OPERATION"
    
    if [ "${OPERATION}" = "${OP_NEW}" ]
    then
        echoVarsForUpdate
        log "----------------------------------------------------"
        log "JM_PORT                 = $JM_PORT"
        log "THIS_HOSTNAME           = $THIS_HOSTNAME"
        log "DISPLAYNAME             = $DISPLAYNAME"
        log "XANAME                  = $XANAME"
        log "NETMAN_PORT             = $NETMAN_PORT"
        log "THISCPU                 = $THISCPU"
        log "MASTER                  = $MASTER"
        log "COMPANY                 = $COMPANY_NAME"
        log "MDM_BROKER_HOSTNAME     = $MDM_BROKER_HOSTNAME"
        log "MDM_HTTPS_PORT          = $MDM_HTTPS_PORT"
    
        log "BROKER_WORKSTATION_NAME = $BROKER_WORKSTATION_NAME"
        log "BROKER_NETMAN_PORT      = $BROKER_NETMAN_PORT"
        log "DOMAIN                  = $DOMAIN"
        echoVarsConfDatasource $@
        echoVarsConfWlp $@
        echoVarsConfSSL $@
        echoVarsWaPostConf $@
    else
        echoVarsForUpdate
    fi
}

echoVarsForUpdate()
{
    log "ACCEPTLICENSE           = $ACCEPTLICENSE"
    log "INST_LANG               = INST_LANG"
    log "INST_DIR                = $INST_DIR"
    log "WORK_DIR                = $WORK_DIR"
    log "SKIPCHECKPREREQ         = $SKIPCHECKPREREQ"
    log "SKIPCHECKEMPTYDIR       = $SKIPCHECKEMPTYDIR"
}

# ********************
# parse parameters
# ********************
parseInput() {
 logentry "parseInput"

 NUMPARAM=$#
 TR="tr"

 while [ $# -ge 1 ]; do
 NUMPARAM=`expr $NUMPARAM - 1`

 #echo "DEBUG inizio while dl1 $1 dl2  $2 . "

 case `echo $1 |$TR "[:upper:]" "[:lower:]"` in
    --propfile|-f)
       INPUT_FILE_PROP=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       fi
      ;;
    --acceptlicense|-a)
       ACCEPTLICENSE=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
    --lang)
       INST_LANG=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --inst_dir|-i)
       INST_DIR=$2
       #remove last /
       INST_DIR=${INST_DIR%/}

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --work_dir)
       WORK_DIR=$2
       #remove last /
       WORK_DIR=${WORK_DIR%/}

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

     --data_dir)
       DATA_DIR=$2
       #remove last /
       DATA_DIR=${DATA_DIR%/}


       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;


    --jmport)
       JM_PORT=$2

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --displayname)
       DISPLAYNAME=$2

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --xaname)
       XANAME=$2

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --netmanport)
       NETMAN_PORT=$2
       NETMAN_PORT_BY_USER=$2

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --hostname)
       THIS_HOSTNAME=$2

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --thiscpu)
       THISCPU=$2
       THISCPU_BY_USER=$2

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --skipcheckprereq)
       SKIPCHECKPREREQ=$2
       SKIPCHECKPREREQ_UC=`echo "$SKIPCHECKPREREQ" |tr "[:lower:]" "[:upper:]"`

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
      
      --skipcheckemptydir)
       SKIPCHECKEMPTYDIR=$2
       SKIPCHECKEMPTYDIR_UC=`echo "$SKIPCHECKEMPTYDIR" |tr "[:lower:]" "[:upper:]"`

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --override)
       OVERRIDE=$2

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;


# --------------   from waPostConfigureWlp.sh --------------------------
    --wapassword)
       WA_PASSWORD=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --startserver)
       START_SERVER=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --componenttype)
       COMPONENT_TYPE=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;


# --------------   from configureWlp.sh ------------

    --wlpdir|-w)
       WLP_INSTALL_DIR=$2
       #remove last /
       WLP_INSTALL_DIR=${WLP_INSTALL_DIR%/}

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --httpport)
       HTTP_PORT=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --httpsport)
       HTTPS_PORT=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --bootstrapport|-b)
       BOOTSTRAP_PORT=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --bootsecport|-s)
       BOOTSTRAP_SEC_PORT=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;


    --wauser)
       WA_USER=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

# --informixserver IDS only required
    --informixserver)
       INFORMIX_SERVER=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
# --------------   from configureDb.sh --------------------------

    --rdbmstype|-r)
       RDBMS_TYPE=$2
       RDBMS_TYPE_UC=`echo $RDBMS_TYPE |$TR "[:lower:]" "[:upper:]"`

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --dbname)
       DB_NAME=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --dbuser)
       DB_USER=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --dbpassword)
       DB_PASSWORD=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --dbport)
       DB_PORT=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --dbhostname)
       DB_HOST_NAME=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --dbdriverpath)
       DB_DRIVER_PATH=$2
       DB_DRIVER_PATH_PROVIDED_BY_USER="true"
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
    #hidden internal parameter only unix
    --dbalternatenames)
       DB_ALTERNATE_SERVER_NAMES=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
    #hidden internal parameter only unix
    --dbalternateports)
       DB_ALTERNATE_SERVER_PORTS=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;      
# -----------end  from configureDb.sh --------------------------
    --company)
       COMPANY_NAME=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --eifport)
       EIF_PORT=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
# --------------   for flexera ------------      
    --licenseserverid)
       LICENSE_SERVER_ID=$2
       export DB_USER
       if [ "$NUMPARAM" -ge "1"  -a "$IBM_OR_HCL" = "IBM" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;
    --licenseserverurl)
       LICENSE_SERVER_URL=$2
       export DB_PASSWORD
       if [ "$NUMPARAM" -ge "1"  -a "$IBM_OR_HCL" = "IBM" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;
# --------------   end flexera ------------      

    # BROKER_WORKSTATION_NAME value will update the BrokerWorkstation.properties file in the following property:
    # Broker.Workstation.Name=$(this_cpu)
    --brwksname)
       BROKER_WORKSTATION_NAME=$2
       BROKER_WORKSTATION_NAME_BY_USER=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    # BROKER_NETMAN_PORT: Port on which the Dynamic Workload Broker Workstation listens (equivalent to Netman port)
    # This value will update the BrokerWorkstation.properties file in the following property:
    # Broker.Workstation.Port=$(tcp_port)
    # In the old IM response file this value was set here :
    #         <!--Dynamic Workload Broker Netman Port-->
    #         <data key='user.dwbPort,com.ibm.tws' value='41114'/>

    --brnetmanport)
       BROKER_NETMAN_PORT=$2
       BROKER_NETMAN_PORT_BY_USER=$2

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --domain)
       DOMAIN=$2
       DOMAIN_BY_USER=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --isforzos)
       ISFORZOS=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

# --------------   for DDM ------------
    --master)
       MASTER=$2
       MASTER_BY_USER=$2

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --mdmbrokerhostname)
       MDM_BROKER_HOSTNAME=$2
       MDM_BROKER_HOSTNAME_BY_USER=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --mdmhttpsport)
       MDM_HTTPS_PORT=$2
       MDM_HTTPS_PORT_BY_USER=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
#################################
#[--dbsslconnection: true | false  (default: false)]

#  Configuration options when dbsslconnection=true or customized certificates are used for SSL connections:
#   [--sslkeysfolder:      folder containing keystore (TWSServerKeyFile.jks) and/or truststore (TWSServerTrustFile.jks) JKS files for SSL connections (required if dbsslconnection=true)]
#   [--keystorepassword:   password for TWSServerKeyFile.jks (required if TWSServerKeyFile.jks exists in sslkeysfolder)]
#   [--truststorepassword: password for TWSServerTrustFile.jks (required if TWSServerTrustFile.jks exists in sslkeysfolder)]

# --------------   for SSL ------------
    $DB_SSL_CONNECTION_OPTION)
       DB_SSL_CONNECTION=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
    $SSL_KEY_FOLDER_OPTION)
       SSL_KEY_FOLDER=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
    $SSL_PASSWORD_OPTION)
       SSL_PASSWORD=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;      
    $KEY_STORE_PASSWORD_OPTION)
       KEY_STORE_PASSWORD=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
    $TRUST_STORE_PASSWORD_OPTION)
       TRUST_STORE_PASSWORD=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

#################################
# --------------   for docker ------------
    --installbinary)
       INSTALL_BINARY=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
    --configure)
       CONFIGURE=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
    --postconfigure)
       POSTCONFIGURE=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
    --populate)
       POPULATE=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
    
    --optmanfordocker)
       #to lower case
       OPTMANFORDOCKER=`echo "$2" |tr "[:upper:]" "[:lower:]"`
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;       
      
      --commit)
       COMMIT=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
    --check)
       CHECK=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
    --checkdb)
       CHECKDB=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;
    --execinst)
       EXECINST=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1
       fi
      ;;

    --usage|"-?"|--help)
       usage
      ;;
      *)
         usageBadParam $1
      ;;

  esac
  shift;
  done
    logexit "parseInput"

}


# *********************************************
# configureTwsFiles
# *********************************************
configureTwsFiles()
{
    logentry "configureTwsFiles"
        a1="FileUpdateListFullPath=$ACTIONTOOLS_DIR/FileUpdateTwsList.txt"
        a2="HTTPSPort=$HTTPS_PORT"
        a3="ftaThisCpu=$THISCPU"
        a4="install_dir=$INST_DIR"
        a5="userName=$WA_USER"
        a6="master=$MASTER"
        a7="hostname=$THIS_HOSTNAME"
        a8="port=$NETMAN_PORT"
        a9="data_dir=$DATA_DIR"
        a10="wlp_user_dir=$WLP_USER_DIR"
        a11="engine_type=$COMPONENT_TYPE"
        a12=".ext1="
        a13=".ext2=.sh"
        a14=".ext5=.sh"
        a15=".ext6="
        a16="platform=unix"

        if [ "${COMPONENT_TYPE}" = "MDM" ]
        then
            a17="wrk_type=MANAGER"
        else
            a17="wrk_type=FTA"
        fi
        a18="dbcs=false"
        a19="userPwd=dummy"
        a20="res_prop_dir=$DATA_DIR/usr/servers/engineServer/resources/properties"
        a21="xa_agent=$XANAME"

        parmRow="$a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $a10 $a11 $a12 $a13 $a14 $a15 $a16 $a17 $a18 $a19 $a20 $a21"

        execute_command_and_exit_if_fail_quiet  $INST_DIR/TWS/JavaExt/jre/jre/bin/java -cp  $ACTIONTOOLS_DIR/FileUpdate.jar com.hcl.wa.install.FileUpdate $parmRow
    logexit "configureTwsFiles"

}

# ********************************************************************************************************
# configureTdwbFiles

# From file: BrokerWorkstation.properties :

## Domain of the Domain Manager Workstation
##DomainManager.Workstation.Domain=$(dm_domain_name)

# From file: com.ibm.tws.tdwb.unux.shu
#   <arg>$(dm_domain_name)</arg>
#   <arg>${profile:user.ddmDomainName,com.ibm.tws}</arg>

# From file: com.ibm.tws.panels.DDMConfigurationPanel.java
#   private static final String DDM_DOMAIN_NAME_DEFAULT_VALUE = "DYNAMICDM";

# From file: com.ibm.tws.precheck.util.Constants.java
#   public static final String DDM_DOMAIN_NAME_ID = IProfile.USER_DATA_PREFIX + "ddmDomainName";

# From file: \install_bom\tws_bom\servers_images_template\unix\response_files\IWS94_FRESH_DDM_UNIX.xml
#         <data key='user.ddmDomainName,com.ibm.tws' value='DYNAMICDM'/>

# From file: \install_engine\com.ibm.tws.actions\src\com\ibm\tws\actions\DefineMDMVariables.java
# profile.setOfferingUserData(DDM_DOMAIN_NAME_ID, "MASTERDM", engineOfferingId);

# From file: LINUX_X86_64/Tivoli_TDWBDATA_LINUX_X86_64/broker/config/BrokerWorkstation.properties
# Name of the Master Domain Manager Workstation
#MasterDomainManager.Name=$(master_cpu)

# Name of the Master Domain Manager Host Name
#MasterDomainManager.HostName=$(mdm_host_name)

# HTTPS Port on which the Master Domain Manager listens
#MasterDomainManager.HttpsPort=$(mdm_https_port)
# ********************************************************************************************************
configureTdwbFiles()
{
    logentry "configureTdwbFiles"

    RDBMS_TYPE_UC=`echo $RDBMS_TYPE |$TR "[:lower:]" "[:upper:]"`

    # If the type is DDM (not MDM) and -domain not provided default is DYNAMICDM
    a1="FileUpdateListFullPath=$ACTIONTOOLS_DIR/FileUpdateTdwbList.txt"
    a2="install_dir=$INST_DIR"
    a3="dm_host_name=$QUALIFIED_HOSTNAME"
    a4="dm_tcp_port=$NETMAN_PORT"
    a5="host_name=$QUALIFIED_HOSTNAME"
    a6="tcp_port=$BROKER_NETMAN_PORT"
    a7="cpu_type=$COMPONENT_TYPE"
    a8="dm_domain_name=$DOMAIN"
    a9="dm_this_cpu=$THISCPU"
    a10="this_cpu=$BROKER_WORKSTATION_NAME"
    a11="dm_os_type=UNIX"
    a12="data_dir=$DATA_DIR"
    a13="java_bin=$INST_DIR/TWS/JavaExt/jre/jre/bin"
    a14="jdbcDriversPath=$DB_DRIVER_PATH"
    a15="dbname=$DB_NAME"
    a16="dbport=$DB_PORT"
    a17="dbhost=$DB_HOST_NAME"
    a18="rdbms_name=$RDBMS_TYPE_UC"
    a19="wlp_user_dir=$WLP_USER_DIR"
    a20="jdbc_driver=$JDBC_DRIVER"
    a21="jdbc_path=$JDBC_PATH"
    a22="this_localhost=$THIS_HOSTNAME"
    a26="dbSSLConnection=$DB_SSL_CONNECTION"

    #********* passwords stuff *******************************************************
    # CLIConfig.properties does not works if password is xor encripted
    # so we must use decoded password produced by handlepw funcion in commonFunctions
    if [ ! -z "$SSL_PASSWORD_DECODED" ]
	then
            KPW=$SSL_PASSWORD_DECODED
            TPW=$SSL_PASSWORD_DECODED
    else
        if [ ! -z "$KEY_STORE_PASSWORD_DECODED" ]
        then
            KPW=$KEY_STORE_PASSWORD_DECODED
        else
            KPW="default"
        fi
        if [ ! -z "$TRUST_STORE_PASSWORD_DECODED" ]
        then
            TPW=$TRUST_STORE_PASSWORD_DECODED
        else
            TPW="default"
        fi
    fi

    a27="keystorepw=$KPW"
    a28="truststorepw=$TPW"
   
    #********* end of passwords stuff ************************

    if [ "${COMPONENT_TYPE}" = "MDM" -o  "${COMPONENT_TYPE}" = "BKM" ]
    then
        a23="master_cpu=$THISCPU"
        a24="mdm_host_name=$THIS_HOSTNAME"
        a25="mdm_https_port=$HTTPS_PORT"
    else
        if [ "${COMPONENT_TYPE}" = "DDM" -o  "${COMPONENT_TYPE}" = "BDM" ]
        then
            a23="master_cpu=$MASTER"
            a24="mdm_host_name=$MDM_BROKER_HOSTNAME"
            a25="mdm_https_port=$MDM_HTTPS_PORT"
        fi
    fi

    parmRow="$a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $a10 $a11 $a12 $a13 $a14 $a15 $a16 $a17 $a18 $a19 $a20 $a21 $a22 $a23 $a24 $a25 $a26 $a27 $a28"

    execute_command_and_exit_if_fail_quiet  $INST_DIR/TWS/JavaExt/jre/jre/bin/java -cp  $ACTIONTOOLS_DIR/FileUpdate.jar com.hcl.wa.install.FileUpdate $parmRow
    
    logexit "configureTdwbFiles"
}

# *********************************************
# configureSfiinal
# *********************************************
configureSfinal()
{
    logentry "configureSfinal"
    CMD="$JAVA_BIN_DIR/java -cp  $ACTIONTOOLS_DIR/FileUpdate.jar com.hcl.wa.install.FileUpdate"
    
    s1="FileUpdateListFullPath=$ACTIONTOOLS_DIR/FileUpdateSfinalList.txt"
    s2="install_dir=$INST_DIR"
    s3="start_server=$INST_DIR/appservertools/startAppServer.sh"
    s4=".ext5=.sh"
    s5="xa_agent=$XANAME"
    
    parmRow="$s1 $s2 $s3 $s4 $s5"
    execute_command_and_exit_if_fail_quiet  $CMD $parmRow
    
    logexit "configureSfinal"
}

# *********************************************
# Modify the ownership of the server files
#
# Input variable:
#    TWSTOOLS_DIR
#    INST_DIR
#    WA_USER
#    MAEGROUP
#    ROOTGROUP
#    DATA_DIR
# *********************************************

modifyOwnership()
{
    logentry "modifyOwnership"

    getGroup $WA_USER
    MAEGROUP=$OUTPUT_GROUP

    getGroup root
    ROOTGROUP=$OUTPUT_GROUP

    log "Modify the ownership of the server files"
    execute_command_and_exit_if_fail $TWSTOOLS_DIR/twsServerRightsAction.sh $INST_DIR $WA_USER $MAEGROUP $ROOTGROUP $DATA_DIR
    logexit "modifyOwnership"

}


# ************************************
# Commit
# ************************************
commit()
{
    logentry "commit"
    log "Update WA registry"
    execute_command_and_exit_if_fail $TWSTOOLS_DIR/twsUpdateTWSRegistry.sh $INST_DIR/TWS $WA_USER $COMPONENT_TYPE -verbose $TWSINSTALLINGVERSION "false"
    execute_command_and_exit_if_fail ${INST_DIR}/TWS/_uninstall/ACTIONTOOLS/twaregistry.sh  "-add" ${INST_DIR} ${TWSINSTALLINGVERSION} ${WA_USER} ${COMPONENT_TYPE} ${WLP_INSTALL_DIR} ${DB_DRIVER_PATH} ${DATA_DIR}
    log "Commit exited successfully"
    logexit "commit"
}


initComponentType()
{
    logentry "initComponentType"
    IMAGE_DB_DRIVER_PATH="${THIS_SCRIPT_ABSOLUTE_DIR}/Tivoli_MDM_${INST_INTERP}/${END_DB_DRIVER_PATH}"
    initConfigureDbParameters ${IMAGE_DB_DRIVER_PATH}  ${COMPONENT_TYPE}


    CONFIGURE_DB_PARMS_PARMS="${CONFIGURE_DB_PARMS_PARMS} --action get_master"

    execute_command ${THIS_SCRIPT_DIR}/configureDb.sh ${CONFIGURE_DB_PARMS_PARMS}

    # Failure in SQL getting the master workstation: DB2 SQL Error: SQLCODE=-204, SQLSTATE=42704, SQLERRMC=MDL.WKS_WORKSTATIONS, DRIVER=4.21.29
    # rc=255
    if [ $? -eq 0 ]
    then
        MASTER_FILE=${WORK_DIR}/dblighttool/master.txt
        if [ -f $MASTER_FILE ]
        then
            CMD_OUT=`cat $MASTER_FILE`
            log "$MASTER_FILE contain: $CMD_OUT"
        else
            MSG_FILE_NOT_EXIST="`${MSG_CMD} Message_FileDoesNotExist $MASTER_FILE/ `\n"
            echolog $MSG_FILE_NOT_EXIST
            exit 1
        fi

        if [ "$COMPONENT_TYPE" = "MDM" ]
        then
            THISCPU_UC=`echo $THISCPU | $TR "[:lower:]" "[:upper:]"`
        
            if [ "$CMD_OUT" != ""  -a "$CMD_OUT" != "${THISCPU_UC}" ]
            then
                COMPONENT_TYPE="BKM"
            fi
        else
            if [ "$COMPONENT_TYPE" = "DDM" ]
            then
                CMD_OUT_UC=`echo $CMD_OUT | $TR "[:lower:]" "[:upper:]"`
                if [ "$CMD_OUT_UC" = "TRUE" ]
                then
                    COMPONENT_TYPE="BDM"
                fi
            fi
        fi
    else
        log "rc from configureDb.sh = $?"
        log "leaving componenttype as is"
    fi

    log "initComponentType: component type set to $COMPONENT_TYPE"
    logexit "initComponentType"
}

bkmSwichBrokerWorkstationProperties()
{
    logentry "bkmSwichBrokerWorkstationProperties"
    BROKER_WKS_PROPERTIES_FILE="${DATA_DIR}/broker/config/BrokerWorkstation.properties"
    BROKER_WKS_BKM_PROPERTIES_FILE="${DATA_DIR}/broker/config/BrokerWorkstation_backup.properties"
    
    if [ -f "${BROKER_WKS_BKM_PROPERTIES_FILE}" ]
    then
       rm -rf ${BROKER_WKS_PROPERTIES_FILE}
       mv ${BROKER_WKS_BKM_PROPERTIES_FILE} ${BROKER_WKS_PROPERTIES_FILE}
    fi

    if [ -f "${BROKER_WKS_BKM_PROPERTIES_FILE}" ]
    then   
        rm -rf ${BROKER_WKS_PROPERTIES_FILE}
        mv ${BROKER_WKS_BKM_PROPERTIES_FILE} ${BROKER_WKS_PROPERTIES_FILE}
    fi
    logexit "bkmSwichBrokerWorkstationProperties"
}

mdmCleanUpBrokerWorkstationProperties()
{
    logentry "mdmCleanUpBrokerWorkstationProperties"
    BROKER_WKS_BKM_PROPERTIES_FILE="${DATA_DIR}/broker/config/BrokerWorkstation_backup.properties"

     if [ -f "${BROKER_WKS_BKM_PROPERTIES_FILE}" ]
     then
    rm -f ${BROKER_WKS_BKM_PROPERTIES_FILE}
     fi
    logexit "mdmCleanUpBrokerWorkstationProperties"
}

checkTwaRegistry()
{
    logentry "checkTwaRegistry"
    #if the registry file already exist the product is already installed or the registry is not clean

    log "invoke: ${ACTIONTOOLS_DIR}/twaregistry.sh  -getfile ${INST_DIR}"
    TWA_REG_FILE=`${ACTIONTOOLS_DIR}/twaregistry.sh  "-getfile" ${INST_DIR}`
    if [  ! "${TWA_REG_FILE}x" = "x" ]
    then
        #Message_WrongRegistryForFresh=WAINST059E You are performing a fresh installation,
        #but the installation script has found a previous instance of the product in the registry file: {0} .
        MSG=`${MSG_CMD} Message_WrongRegistryForFresh ${TWA_REG_FILE}`
        echoErrorAndUsageAndExit $MSG
    fi

    log "invoke: ${ACTIONTOOLS_DIR}/twaregistry.sh  -getuserfile ${WA_USER}"
    TWA_USER_REG_FILE=`${ACTIONTOOLS_DIR}/twaregistry.sh  "-getuserfile" ${WA_USER}`
    if [  ! "${TWA_USER_REG_FILE}x" = "x" ]
    then
        #Message_ExistingUserInRegistry=WAINST072E You are performing a fresh installation,
        #but the installation script has found a previous instance of the product in the registry file: {0} for user: {1}.
        MSG=`${MSG_CMD} Message_ExistingUserInRegistry ${TWA_USER_REG_FILE} ${WA_USER}`
        echoErrorAndUsageAndExit $MSG
    fi
    logexit "checkTwaRegistry"
}

checkForNew()
{
    logentry "checkForNew"
    if [ "${OPERATION}" = "${OP_NEW}" ]
    then
        checkValuesForNew
        if [ "$SKIPCHECKEMPTYDIR_UC" = "FALSE" ]
        then
            checkPathShouldBeEmpty ${INST_DIR}
        fi
        
        checkRequiredForNew
        checkSSLValues
    fi
    logexit "checkForNew"
}

initWaUserAndInstDirForNew()
{
    logentry "initWaUserAndInstDirForNew"
    #init inst dir
    #not needed in update since it is read from input parameter required
    if [ "${OPERATION}" = "${OP_NEW}" ]
    then
        #init WA_USER only in fresh installation, in update is read from /etc/TWA/registry example: TWS_user_name=wauser
        #init user
        if [ -z "$WA_USER" ]
        then
            WA_USER=$INST_USER
        fi
        if [ -z "$INST_DIR" ]
        then
            if [ "$IS_ROOT" = "true" ]
            then
                INST_DIR="${DEFAULT_TWS_INST_DIR}_${WA_USER}"
            else
                INST_DIR="${DEFAULT_TWS_INST_NOROOT_DIR}"
            fi
        fi
    fi
    logexit "initWaUserAndInstDirForNew"
}

checkPrereqMdm()
{
    logentry "checkPrereqMdm"
    
    INST_DIR="$1"
    log "checkPrereqMdm(): INST_DIR = $INST_DIR"
    
    WORK_DIR="$2"
    log "checkPrereqMdm(): WORK_DIR = $WORK_DIR"
    
    DATA_DIR="$3"
    log "checkPrereqMdm(): DATA_DIR = $DATA_DIR" 

    #N.B. see TWAplugin.cfg for the values corresponding to teh various keys
    
    #same working dir of FTA with JRE 
    WORK_DIR_KEY="FTA_${INST_INTERP}_WORK_DIR_JRE"
    
    CIT_DIR_KEY="COMMON_CIT_${INST_INTERP}_DIR"
    USR_TIVOLI_DIR_KEY="USR_TIVOLI_${INST_INTERP}_DIR"
    
    CIT_DIR=/opt/tivoli/cit
    USR_TIVOLI_DIR=/usr/Tivoli/TWS    
    
    o1="MDM.data_dir='$DATA_DIR'"
    o2="MDM.inst_dir='$INST_DIR'" 
     
    o3="MDM.work_dir='$WORK_DIR'"
    o4="MDM.WORK_DIR_KEY='$WORK_DIR_KEY'"
     
    o5="MDM.cit_dir='${CIT_DIR}'" 
    o6="MDM.CIT_DIR_KEY='$CIT_DIR_KEY'"
    
    o7="MDM.usr_tivoli_dir='${USR_TIVOLI_DIR}'"
    o8="MDM.USR_TIVOLI_DIR_KEY='$USR_TIVOLI_DIR_KEY'"
    
    OPTIONS="$o1,$o2,$o3,$o4,$o5,$o6,$o7,$o8"

    log "PRS OPTION = $OPTIONS"
    
    checkPrereq "MDM 09050000,TWA 09050000" ${OPTIONS}
    RC=$?
    
    if [  $RC -ne 0 ]
    then
        log  "checkPrereqMdm failed with rc = $RC"
        MSG=`${MSG_CMD} Message_CheckPrereqFailed $LOG_FOLDER/result.txt`
        echoErrorAndExit ${MSG}
    else
        log "checkPrereqMdm ok"
    fi   
    
    
    log "rc from MDM checkPereq = $?"
    
    logexit "checkPrereqMdm"    
}

clearWlpAppsDir()
{
    logentry "clearWlpAppsDir"
    #example of WLP_APPS_DIR: /opt/wa/server_wauser/usr/servers/engineServer/apps
    if [ -d ${WLP_APPS_DIR} ]
    then
        log "clearWlpAppsDir() clearing ${WLP_APPS_DIR}"
        rm -rf ${WLP_APPS_DIR}
        mkdir ${WLP_APPS_DIR}
    else
        log "clearWlpAppsDir()  WLP_APPS_DIR = ${WLP_APPS_DIR} not found "
    fi
    logexit "clearWlpAppsDir"
}

updateSimul()
{
    logentry "updateSimul"
    updateSimulCommon $1
    #folder stuff
    generateInputSimul "$1" "INST_DIR" $INST_DIR
    generateInputSimul "$1" "WORK_DIR" $WORK_DIR
    generateInputSimul "$1" "WA_USER" $WA_USER
    generateInputSimul "$1" "WA_PASSWORD" "***"
    generateInputSimul "$1" "COMPONENT_TYPE" $COMPONENT_TYPE
    generateInputSimul "$1" "JM_PORT" $JM_PORT
    generateInputSimul "$1" "DISPLAYNAME" $DISPLAYNAME
    generateInputSimul "$1" "XANAME" $XANAME
    generateInputSimul "$1" "NETMAN_PORT" $NETMAN_PORT
    generateInputSimul "$1" "THIS_HOSTNAME" $THIS_HOSTNAME
    generateInputSimul "$1" "THISCPU" $THISCPU
    generateInputSimul "$1" "EIF_PORT" $EIF_PORT
    generateInputSimul "$1" "LICENSE_SERVER_ID" $LICENSE_SERVER_ID
    generateInputSimul "$1" "LICENSE_SERVER_URL" $LICENSE_SERVER_URL
    generateInputSimul "$1" "BROKER_WORKSTATION_NAME" $BROKER_WORKSTATION_NAME
    generateInputSimul "$1" "BROKER_NETMAN_PORT" $BROKER_NETMAN_PORT
    generateInputSimul "$1" "DOMAIN" $DOMAIN
    generateInputSimul "$1" "ISFORZOS" $ISFORZOS
    generateInputSimul "$1" "MASTER" $MASTER
    generateInputSimul "$1" "MDM_BROKER_HOSTNAME" $MDM_BROKER_HOSTNAME
    generateInputSimul "$1" "MDM_HTTPS_PORT" $MDM_HTTPS_PORT
    generateInputSimul "$1" "START_SERVER" $START_SERVER
    
    parmRow="FileUpdateListFullPath=$ACTIONTOOLS_DIR/FileUpdateSimulList.txt data_dir=$DATA_DIR script_name=$THIS_SCRIPT_FILE_NAME"      
    execute_command_and_exit_if_fail_quiet  $JAVA_BIN_DIR/java -cp  $ACTIONTOOLS_DIR/FileUpdate.jar com.hcl.wa.install.FileUpdate $parmRow   
      
    logexit "updateSimul"
}


# *************************************************************************************************
# End of Subroutines
# *************************************************************************************************
# *************************************************************************************************
# Call main
# *************************************************************************************************

main $@
exit 0

