#!/bin/sh
####################################################################
# Licensed Materials - Property of IBM and HCL
# "Restricted Materials of IBM and HCL"
# 5698-WSH
# (C) Copyright IBM Corp. 1998, 2016 All Rights Reserved.
# (C) Copyright HCL Technologies Ltd. 2016 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
###################################################################


main()
{
    logentry "main"
    umask 022
        
    initCommonVariables
    initHiddenDefault
    initCommonMessages

    chooseInput $*
    
    # load Defaults From template file
    checkExistingFile ${TEMPLATE_PROPS_FILE}
    parseInputFromFileWaPostConf ${TEMPLATE_PROPS_FILE}
    
    log "waPostConfigure in progress ..."
    echoVarsWaPostConf "echoVarsWaPostConf after parse template file"
        
    if [ "$INPUT_FROM_FILE" = "true" ]  
    then
        checkExistingFile ${PROPS_FILE}
        parseInputFromFileWaPostConf ${PROPS_FILE}
        echoVarsWaPostConf "echoVarsWaPostConf after parse properties file"
    fi
    
    parseInput $*
    
    echoVarsWaPostConf "echoVarsWaPostConf after parse parameters"
    
    PASSWORDS="$DB_PASSWORD $WA_PASSWORD"
    checkSomePasswordIsEncrypted $PASSWORDS

    checkValues

    initLocalVariablesPostInput
 
    handleLog ${DATA_DIR}
    handlePw $0    
    
    if [ "$COMPONENT_TYPE" = "DDM" -o "$COMPONENT_TYPE" = "BDM" ]
    then
        CONTEXT_ROOT="JobManagerRESTWeb/JobManagerServlet"
    else
        if [ "$COMPONENT_TYPE" = "MDM" -o "$COMPONENT_TYPE" = "BKM" ]
        then
            CONTEXT_ROOT="twsd"
        fi
    fi
       
    #this entry is useful also for Docker because we need to re-add the server when a new container starts with new hostname    
    invokeAddServerData
    
    if [ "$COMPONENT_TYPE" = "BDM" ]
    then
        WAIT_FOR_START="FALSE"
    else
        WAIT_FOR_START="TRUE"
    fi
    
    startWlpServer $START_SERVER $APPSERVER_TOOL_DIR $HTTPS_PORT $CONTEXT_ROOT $WAIT_FOR_START -direct
    
    if [ "$COMPONENT_TYPE" = "MDM" -o "$COMPONENT_TYPE" = "BKM" ]
    then    
        log "Configuring TWS environment ..."
        cd ${TWS_DIR}
        LIBPATH=${TWS_DIR}/bin:$LIBPATH
        export LIBPATH
        . ./tws_env.sh

        log "UNISONWORK = ${UNISONWORK}"
        export DATA_DIR

        #this creation is useful also for Docker because we need to recreate the useropts when a new container starts from scratch 
        createUseropts

          #--------------------------------------
        # populate - For DOCKER post configuration it's needed that all operations done to populate data must be done only in this section. Do NOT create data files outside this section.
        # This section must run also with not-root user
        #--------------------------------------
        if [ "$POPULATE" = "true" ]  
        then                                            
            invokeOptman

            importPredefinedWorkstations

            importPredefinedRules

            mergeCentralizedAgent
            # ************************************
            # Add FINAL job (MDM only, not BKM
            # ************************************
            if [ "$COMPONENT_TYPE" != "BKM" ]
            then    
                log "Add FINAL job"
                execute_command $TWSTOOLS_DIR/addFinalSched.sh -twsroot $TWS_DIR  -finaljob true
             fi
        fi

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

    # ********** EXIT **********      

    echoInfo ${SEELOGFILEMSG}
    echolog ${MSG_CMD_SUCC}
    logexit "main"
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

initHiddenDefault(){ 
    logentry "initHiddenDefault"
       POPULATE="true"
    OPTMANFORDOCKER="false"
    logexit "initHiddenDefault"
}

checkValues()
{
    logentry "checkValues"
      RET_COD=0

      #check required parameters
      if [  -z "$WLP_INSTALL_DIR" ]
    then 
            MSG_REQUIRED_OPTION=`${MSG_CMD} Message_RequiredOption --wlpdir`
            echoErrorAndUsageAndExit $MSG_REQUIRED_OPTION
      fi
    
      if [  -z "$DATA_DIR" ]
    then 
            MSG_REQUIRED_OPTION=`${MSG_CMD} Message_RequiredOption --data_dir`
            echoErrorAndUsageAndExit $MSG_REQUIRED_OPTION
      fi
    
      if [  -z "$START_SERVER" ]
    then 
            MSG_REQUIRED_OPTION=`${MSG_CMD} Message_RequiredOption --startserver`
            echoErrorAndUsageAndExit $MSG_REQUIRED_OPTION
      fi
      if [  -z "$APPSERVER_TOOL_DIR" ]
    then 
            MSG_REQUIRED_OPTION=`${MSG_CMD} Message_RequiredOption --appservertooldir`
            echoErrorAndUsageAndExit $MSG_REQUIRED_OPTION
      fi
      if [  -z "$HTTPS_PORT" ]
    then 
            MSG_REQUIRED_OPTION=`${MSG_CMD} Message_RequiredOption --httpsport`
            echoErrorAndUsageAndExit $MSG_REQUIRED_OPTION
      fi
      if [  -z "$BROKER_HOSTNAME" ]
    then 
            MSG_REQUIRED_OPTION=`${MSG_CMD} Message_RequiredOption --brokerhostname`
            echoErrorAndUsageAndExit $MSG_REQUIRED_OPTION
      fi
      if [  -z "$DB_USER" ]
    then 
            MSG_REQUIRED_OPTION=`${MSG_CMD} Message_RequiredOption --dbuser`
            echoErrorAndUsageAndExit $MSG_REQUIRED_OPTION
      fi
      if [  -z "$DB_PASSWORD" ]
    then 
            MSG_REQUIRED_OPTION=`${MSG_CMD} Message_RequiredOption --dbpassword`
            echoErrorAndUsageAndExit $MSG_REQUIRED_OPTION
      fi
    

      OUT1=""    
    if [ "MDM" != "$COMPONENT_TYPE" -a  "DDM" != "$COMPONENT_TYPE" -a  "BKM" != "$COMPONENT_TYPE" -a  "BDM" != "$COMPONENT_TYPE" ]
    then
          OUT1="`${MSG_CMD} Message_WrongValue $COMPONENT_TYPE --componenttype '< MDM | DDM | BKM | BDM >' `\n"
           RET_COD=1
    fi
    
    
      OUT2=""
      if [ ! -d  ${WLP_INSTALL_DIR} ]
      then
          OUT2="`${MSG_CMD} Message_InputPathDoesNotExist ${WLP_INSTALL_DIR} --wlpdir`\n"
          RET_COD=1
      fi    
    
      OUT3=""
      # Convert input tu uppercase
    START_SERVER=`echo "$START_SERVER" |tr "[:lower:]" "[:upper:]"`
    
    if [ "TRUE" != "$START_SERVER" -a  "FALSE" != "$START_SERVER" ]
    then
          #Message_WrongValue=WAINST033E Wrong value {0} for the option {1}. Expected values are {2}
          OUT3="`${MSG_CMD} Message_WrongValue $START_SERVER --startserver '< true | false >' `\n"
          RET_COD=1
    fi
    
      OUT4=""
      isValidPort $HTTPS_PORT
      if [ $result -ne 1 ]
      then
          OUT4="`${MSG_CMD} Message_WrongRangePort $HTTPS_PORT --httpsport`\n"
          RET_COD=1
      fi
    
      OUT5=""
      isValidPort $EIF_PORT
      if [ $result -ne 1 ]
      then
          OUT5="`${MSG_CMD} Message_WrongRangePort $EIF_PORT --eifport`\n"
          RET_COD=1
      fi   

       MSG_TOO_LONG_VALUE=""
      isValidLength "$COMPANY_NAME" "40"
      if [ $result -ne 1 ]
      then
          #Message_TooLongValue=WAINST021E The value {0} provided after option {1} is too long. The limit is {2} bytes
          MSG_TOO_LONG_VALUE="`${MSG_CMD} Message_TooLongValue $COMPANY_NAME '--company' '40'`\n"
          RET_COD=1
      fi
    
      if [ $RET_COD -eq 1 ]
      then
          echo "${OUT1}${OUT2}${OUT3}${OUT4}${OUT5}${MSG_TOO_LONG_VALUE}${OUT_USAGE}"
          exit 1
      fi
    logexit "checkValues"    
}

usage()
{
    logentry "usage"    
    echo
    echo "Arguments: $0 -f <property_file> -w <wlp_directory>  --wauser <wa_user> --wapassword <wa_password> --startserver <true|false> --componenttype <MDM | DDM | BKM | BDM>"
    echo "    -f,  --propfile:          Property file containing input values (optional, default: $PROPS_FILE)"
    echo "         --data_dir           (required)"
    echo "    -w,  --wlpdir:            Websphere Liberty Profile installation directory (required)"
    echo "         --wauser:            The user for which the component is installed (optional, default: $WA_USER )"
    echo "         --wapassword:        Password of the user for which the component is installed (required )"
    echo "         --startserver:       true | false (optional, default: $START_SERVER )"
    echo "         --componenttype:     MDM | DDM | BKM | BDM (optional, default: $COMPONENT_TYPE )"
    echo "         --company:           The company name (optional, default: $COMPANY_NAME )"
    echo "         --eifport:           The EIF port (optional, default: $EIF_PORT )"
    echo "         --brokerhostname:    The fully qualified host name or IP address on which the dynamic domain manager is contacted by the dynamic agent (required )"
    echo "         --httpsport:         The HTTPS port of IWS Broker (required)"
    echo "         --dbuser:            DB user that accesses the IWS tables on the DB2 server (required)"
    echo "         --dbpassword:        The password of the DB user that accesses the IWS tables on the DB2 server (required)"
    echo "         --licenseserverid:   License Server id  (optional, default: $LICENSE_SERVER_ID)"
    echo "         --licenseserverurl:  License Server url (optional, default: $LICENSE_SERVER_URL)"
    echo "         --populate:          true | false  (optional, default: true)"
    echo "         --optmanfordocker:   true | false  (optional, default: false)"
    echo "    -?,  --usage, --help      To show this usage."
    logexit "usage"    
    exit 0
}

# *********************************************
# initLocalVariablesPostInput
#
# Input variable:
#    INSTALL_DIR
#
# Output variables:
#    TWS_DIR
#    TDWB_DIR
#    JAVA_BIN
#    
# *********************************************

initLocalVariablesPostInput()
{
    logentry "initLocalVariablesPostInput"

    TWS_DIR=$INSTALL_DIR/TWS
    log "TWS_DIR=$TWS_DIR"

    TDWB_DIR=$INSTALL_DIR/TDWB

    JAVA_BIN=$TWS_DIR/JavaExt/jre/jre/bin
    log "JAVA_BIN=$JAVA_BIN"
    checkExistingPath $JAVA_BIN

    LICENSE_DIR=$TWS_DIR/license
    checkExistingPath $LICENSE_DIR

    logexit "initLocalVariablesPostInput"        
}

# ********************
# parse parameters
# ********************

parseInput() {
 logentry "parseInput $*"    
 NUMPARAM=$#
 TR="tr"
  
 while [ $# -ge 1 ]; do
 NUMPARAM=`expr $NUMPARAM - 1`
 
 #echo "DEBUG inizio while dl1 $1 dl2  $2 . "
 
 case `echo $1 |$TR "[:upper:]" "[:lower:]"` in
    -f)
       INPUT_FILE_PROP=$2
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       fi 
      ;;
    --data_dir)
       DATA_DIR=$2

       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;      
    --wlpdir|-w)
       WLP_INSTALL_DIR=$2
       export WLP_INSTALL_DIR
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;
    --wauser)
       WA_USER=$2
       export WA_USER
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;
 
    --wapassword)
       WA_PASSWORD=$2
       export WA_PASSWORD
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;

    --startserver)
       START_SERVER=$2
       export START_SERVER
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;

    --appservertooldir)
       APPSERVER_TOOL_DIR=$2
       export APPSERVER_TOOL_DIR
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;

    --httpsport)
       HTTPS_PORT=$2
       export HTTPS_PORT
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;


    --componenttype)
       COMPONENT_TYPE=$2
       export COMPONENT_TYPE
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;


# The host name of IWS Broker (no default)     
    --brokerhostname)
       BROKER_HOSTNAME=$2
       export BROKER_HOSTNAME
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;
            
    --company)
       COMPANY_NAME=$2
       export COMPANY_NAME
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;
      
    --eifport)
       EIF_PORT=$2
       export EIF_PORT
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;

    --dbuser)
       DB_USER=$2
       export DB_USER
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;
    --dbpassword)
       DB_PASSWORD=$2
       export DB_PASSWORD
       if [ "$NUMPARAM" -ge "1" ]; then
         NUMPARAM=`expr $NUMPARAM - 1`
         shift
       else
         usageBadParam $1  
       fi 
      ;;

# --------------   for docker ------------      
    --populate)
     #to lower case
     POPULATE=`echo "$2" |tr "[:upper:]" "[:lower:]"`
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
    --usage|-?|--help)
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
# Create user_opts and workstation definition with composer
#
# Input variable:
#    COMPONENT_TYPE
# Output variable:
#    TWS_USERHOME
# Output file:
#    useropts_$WA_USER
# *********************************************

createUseropts()
{ 
    logentry "createUseropts COMPONENT_TYPE=$COMPONENT_TYPE WA_USER=$WA_USER"    
    log "Create user_opts ..."

    # **********************************************************
    # Create the useropts and create cpu definition in DB
    # **********************************************************

    # Scenario Fresh: YES
    # Scenario Upgrade: YES
    # Scenario Patch: NO
    
    # *********************
    # CREATE useropts file for user
    # *********************
    TWS_USERHOME=`$ACTIONTOOLS_DIR/twsUserHomeRetrieveAction.sh $WA_USER`; export TWS_USERHOME
    if [ "$COMPONENT_TYPE" = "MDM" -o "$COMPONENT_TYPE" = "BKM" ]
    then
        if [ ! -d "$TWS_USERHOME/.TWS" ]
        then
            log "create $TWS_USERHOME DIR"
            mkdir -p "$TWS_USERHOME/.TWS"
        else
            log "$TWS_USERHOME DIR exists"
        fi
        echo "#                                                                           " >  $TWS_USERHOME/.TWS/useropts_$WA_USER
        echo "# TWS useropts file defines credential attributes of the remote Workstation." >> $TWS_USERHOME/.TWS/useropts_$WA_USER
        echo "#                                                                           " >> $TWS_USERHOME/.TWS/useropts_$WA_USER
        echo "USERNAME = $WA_USER                                                         " >> $TWS_USERHOME/.TWS/useropts_$WA_USER
        echo "PASSWORD = \"$WA_PASSWORD_DECODED\"                                                 " >> $TWS_USERHOME/.TWS/useropts_$WA_USER
        chown $WA_USER $TWS_USERHOME/.TWS
        chmod 700 $TWS_USERHOME/.TWS
        chown $WA_USER $TWS_USERHOME/.TWS/useropts_$WA_USER
        chmod 600 $TWS_USERHOME/.TWS/useropts_$WA_USER
    fi
    
    # *********************
    # CREATE useropts file for root
    # *********************

    log "Copy useropts file in root home directory ..."
    # copying the useropts file in the directory .TWS under the home of the installer (root)
    if [ ! -d "$HOME/.TWS" ]
    then
        log "create TWS_ROOTHOME DIR"
        mkdir -p "$HOME/.TWS"
    else
        log "TWS_ROOTHOME DIR exists"
    fi
    cp $TWS_USERHOME/.TWS/useropts_$WA_USER $HOME/.TWS
    logexit "createUseropts"    
}

# **********************************
# Import predefined workstation 
# **********************************
importPredefinedWorkstations()
{
    logentry "importPredefinedWorkstations COMPONENT_TYPE=$COMPONENT_TYPE WA_USER=$WA_USER"
    if [ "${COMPONENT_TYPE}" = "MDM" -o  "${COMPONENT_TYPE}" = "BKM" ]
    then
        # Create cpu in DB using composer
        log "Create Workstation definition importing the CPU Definition"
        if [ -f ${TWS_DIR}/cpudef_unix ]
        then
            execute_command_and_exit_if_fail composer -f $TWS_USERHOME/.TWS/useropts_$WA_USER replace cpudef_unix
            if [ "$COMPONENT_TYPE" = "MDM" ]
            then
                execute_command_and_exit_if_fail composer -f $TWS_USERHOME/.TWS/useropts_$WA_USER replace cpuxadef_unix
            fi        
        fi
    fi
    logexit "importPredefinedWorkstations"    
}
        
# **********************************
# Import predefined event rules
# **********************************
# Scenario Fresh: YES
# Scenario Upgrade: NO
# Scenario Patch: NO

importPredefinedRules()
    { 
        logentry "importPredefinedRules COMPONENT_TYPE=$COMPONENT_TYPE TWS_USERHOME=$TWS_USERHOME"
        if [ "$COMPONENT_TYPE" = "MDM" ]
        then
            log  "Invoke load def event rules"
            execute_command_and_exit_if_fail evtdef -f $TWS_USERHOME/.TWS/useropts_$WA_USER loaddef selfPatchingRuleDef.xml
            log "Invoke composer to create default event rules"
            execute_command_and_exit_if_fail composer -f $TWS_USERHOME/.TWS/useropts_$WA_USER replace eventrulesdef.conf
        fi
        logexit "importPredefinedRules"
    }

# *****************************************************************
# Merge Centralized Agent Update event rule during master upgrade
# *****************************************************************
mergeCentralizedAgent()
{ 
    logentry "mergeCentralizedAgent COMPONENT_TYPE=$COMPONENT_TYPE TWS_USERHOME=$TWS_USERHOME"
    if [ "$COMPONENT_TYPE" = "MDM"  ]
    then
        log "Merge Centralized Agent Update event rule"
        if [ -f "$TWS_DIR/bin/evtdef" ]
        then
             log "Invoke evtdef to produce dumpdef.xml file"
             TWS_TOOLS_DIR="$TWS_DIR/tws_tools"
             execute_command $TWS_DIR/bin/evtdef -f $TWS_USERHOME/.TWS/useropts_$WA_USER dumpdef dumpdef.xml
             execute_command $JAVA_BIN/java -cp $TWS_TOOLS_DIR/twsinstutils.jar com.ibm.tws.util.inst.EngineEvent dumpdef.xml event eventPlugin loaddef.xml append baseAliasName updateEvt
             if [ -f "loaddef.xml" ]
             then
                 log "Invoke evtdef to load loaddef.xml file"
                 execute_command $TWS_DIR/bin/evtdef -f $TWS_USERHOME/.TWS/useropts_$WA_USER loaddef loaddef.xml
             else
                 log "loaddef.xml does not exist"
             fi
        else
            log "$TWS_DIR/bin/evtdef does not exist"
        fi
    fi
    logexit "mergeCentralizedAgent"
}
    
# ****************************************************************
# Invoke optman to change security model, eif port, company name
# ***************************************************************
# Only for MDM, not for BKM
# Scenario Fresh: YES
# Scenario Upgrade: NO
# Scenario Patch: NO
invokeOptman()
{ 
    logentry "invokeOptman COMPONENT_TYPE=$COMPONENT_TYPE"
    if [ "$COMPONENT_TYPE" = "MDM" ]
    then
        if [ -f "$TWS_DIR/bin/optman" ]
        then
            log "Invoke optman to set Role Based Security Model"      
            execute_command_and_exit_if_fail $TWS_DIR/bin/optman chg enRoleBasedSecurityFileCreation = YES 
            log "Invoke optman to set eif port"      
            execute_command_and_exit_if_fail $TWS_DIR/bin/optman chg eventProcessorEIFPort = $EIF_PORT 
            log "Invoke optman to set company name"      
            execute_command_and_exit_if_fail $TWS_DIR/bin/optman chg companyName = $COMPANY_NAME
            
            log "Invoke optman to set Bind User"     
            execute_command_and_exit_if_fail $TWS_DIR/bin/optman chg bindUser = $WA_USER
            log "Invoke optman to set SCCD User"     
            execute_command_and_exit_if_fail $TWS_DIR/bin/optman chg sccdUserName = $WA_USER
            log "Invoke optman to set SMTP User"
            execute_command_and_exit_if_fail $TWS_DIR/bin/optman chg smtpUserName = $WA_USER   
             
            #flexera parameters HCL only
            #example:
            #optman chg lr=WSG2PVCQLTZ2 <-- license server id 
            #optman chg lu=https://flex1513-uat.compliance.flexnetoperations.com <-- license server url
            #if [ ! -z "$LICENSE_SERVER_ID" ]
            #then
            #    log "Invoke optman to set flexera license server id"
            #    execute_command_and_exit_if_fail $TWS_DIR/bin/optman chg lr = $LICENSE_SERVER_ID
            #else
            #    log "Skip Invoke optman to set flexera license server id"
            #fi

            #if [ ! -z "$LICENSE_SERVER_URL" ]
            #then
            #    log "Invoke optman to set flexera license server url"
            #    execute_command_and_exit_if_fail $TWS_DIR/bin/optman chg lu = $LICENSE_SERVER_URL    
            #else
            #    log "Skip Invoke optman to set flexera license server url"
            #fi

            if [ "$OPTMANFORDOCKER" = "true" ]  
            then
                log "Invoke optman to set option needed only by docker"
                execute_command_and_exit_if_fail $TWS_DIR/bin/optman chg ln = "BYWORKSTATION"  
                execute_command_and_exit_if_fail $TWS_DIR/bin/optman chg wn = "PERJOB" 
            else
                log "Skip Invoke optman to set option for docker"
            fi

            
        else
            log "$TWS_DIR/bin/optman not found"            
        fi
        logexit "invokeOptman"
    fi
}
    
# ************************************]********************************************
# Invoke addserverdata to add in db tws, table  dwb.srv_servers, the row:
#   https://${BROKER_HOSTNAME}:${HTTPS_PORT}/JobManagerRESTWeb/JobScheduler
# *********************************************************************************
invokeAddServerData()
{ 
    logentry "invokeAddServerData COMPONENT_TYPE=$COMPONENT_TYPE BROKER_HOSTNAME=$BROKER_HOSTNAME HTTPS_PORT=$HTTPS_PORT"
    log "Invoke addserverdata ..."
    EXPORT_OUTPUT_FILE="server.properties" 
    
    if [ "$COMPONENT_TYPE" = "MDM" -o "$COMPONENT_TYPE" = "DDM" ]
    then
        MDM_OPTION="-MDM true"
    else
        MDM_OPTION=""
    fi
    
    cd $TDWB_DIR/bin
    SERVER_PROP_LINE="https://${BROKER_HOSTNAME}:${HTTPS_PORT}/JobManagerRESTWeb/JobScheduler"
    echo "${SERVER_PROP_LINE}" > $EXPORT_OUTPUT_FILE
    #use quiet for not showing the password
    execute_command_and_exit_if_fail_quiet $TDWB_DIR/bin/addserverdata.sh -dbUsr $DB_USER -dbPwd $DB_PASSWORD_DECODED $MDM_OPTION
    #delete server.properties since it is created here with root ownership and cannot be used by the customer (APAR IJ28452 )
    rm $EXPORT_OUTPUT_FILE
    cd - > /dev/null
    logexit "invokeAddServerData"
}

# *************************************************************************************************
# End of Subroutines
# *************************************************************************************************
# *************************************************************************************************
# Call main
# *************************************************************************************************

main $@
exit 0
