#!/bin/bash

source ${ciop_job_include}

testMode=false

MINESAR_VERSION="2.0"
MINESAR_PATH="/application/script/minesar-bundle-${MINESAR_VERSION}"
WORKING_DIR=$(pwd)
PRODUCTS_DIR="${TMPDIR}/products"

SUCCESS=0
ERR_INPUT_VALIDATION=5
ERR_DOWNLOAD_MASTER=10
ERR_DOWNLOAD_SLAVE=20
ERR_GETDATA=15
ERR_STEP_TWO=120
ERR_STEP_THREE=130
ERR_STEP_FOUR=140

ERR_MINESAR=100

function cleanExit () {

    local retval=$?
    local msg=""

    case "${retval}" in
	    ${SUCCESS}) msg="Processing successfully concluded";;
	    ${ERR_INPUT_VALIDATION}) msg="Input parameters validation error";;
	    ${ERR_DOWNLOAD_MASTER}) msg="Failed to retrieve the master product";;
	    ${ERR_DOWNLOAD_SLAVE}) msg="Failed to retrieve the slave product";;
	    ${ERR_STEP_TWO}) msg="Failed to generate interferogram";;
	    ${ERR_STEP_THREE}) msg="Failed to detect troughs";;
	    ${ERR_STEP_FOUR}) msg="Failed to find alerts";;
	    *|${ERR_UNKNOWN}) msg="Unknown error";;
    esac
    
    [ "${retval}" != "0" ] && ciop-log "ERROR" "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
    [ -n "${TMPDIR}" ] && rm -rf ${TMPDIR}

    exit ${retval}
}

trap cleanExit EXIT

function log() {
    ciop-log "INFO" "$1"
}

function download() {
    local ref=${1}
    local target=${2}
    local local_file
    local enclosure
    local res
    local fileName
    
    enclosure="$(opensearch-client -f json "${ref}" enclosure)"
    res=$?
    [ $res -eq 0 ] && [ -z "${enclosure}" ] && return ${ERR_GETDATA}
    [ $res -ne 0 ] && enclosure=${ref}

    enclosure=$(echo "${enclosure}" | tail -1)
    fileName=$(echo "${enclosure}" | cut -d \/ -f 8)
    
    if [ -e "${target}/${fileName}.zip" ]; then
	    log "File already exists. Using cache copy: ${target}/${fileName}.zip"
	    local_file="$(echo ${target}/${fileName}.zip)"
    else
	    log "Downloading file: ${enclosure}"
	    local_file="$(echo "${enclosure}" | ciop-copy -f -U -O ${target} - 2> /dev/null)"
	    res=$?
	    log "Download exit status: ${res}"
	    [ ${res} -ne 0 ] && return ${res}
    fi
    echo "${local_file}"
}

function callMinesar() {
    local log_file=${1}
    local class=${2}
    local arguments=${3}
    local jvm=${4}
    
    export LD_LIBRARY_PATH=${MINESAR_PATH}/linux/jni/centos-6.7
    log "Library path: $LD_LIBRARY_PATH"
    command="${MINESAR_PATH}/linux/jre/bin/java ${jvm} -Dlog4j.configurationFile=${MINESAR_PATH}/conf/log4j2-gep.xml -Droot.dir=${MINESAR_PATH} -DLOGFILE=${log_file} -cp ${MINESAR_PATH}/app/minesar-${MINESAR_VERSION}.jar:${MINESAR_PATH}/conf pl.satim.minesar.application.${class} ${arguments}"
    log "MineSAR command: ${command}"
    ${command}
    COMMAND_EXIT_CODE=$?
    log "MineSAR command exit code: ${COMMAND_EXIT_CODE}"
    [ ${COMMAND_EXIT_CODE} -ne 0 ] && return ${ERR_MINESAR}
    return ${COMMAND_EXIT_CODE}
}

function step2Interferogram() {
    local master=${1}
    local slave=${2}
    local iw=${3}
    local productName="02-interferogram"
    local productsDir="${PRODUCTS_DIR}"
    
    log "Generating interferogram, master: ${master}, slave: ${slave}, iw: ${iw}"
    log "Product directory: ${productsDir}/${productName}"
    
    mkdir -p "${productsDir}/${productName}"
    
    $(callMinesar "${productsDir}/${productName}.log" "MineSARBatch02Interferogram" "--name ${productName} --targetDirectory ${productsDir} --masterSlcImage ${master} --slaveSlcImage ${slave} --iw ${iw}")

    MINESAR_EXIT_CODE=$?

    log "callMinesar() exit code: ${MINESAR_EXIT_CODE}"
	
    [ ${MINESAR_EXIT_CODE} -ne 0 ] && {
        ciop-publish -m "${productsDir}/${productName}.log"
        if [ "$testMode" = true ] ; then
	    log "Making a copy of the result after error"
	    cp -a "${productsDir}/." /tmp/products
        fi
	return ${ERR_STEP_TWO}
    }

    ciop-publish -m "${productsDir}/${productName}.log"

    if [ "$testMode" = true ] ; then
        log "Making a copy of the result after success"
        cp -a "${productsDir}/." /tmp/products
    fi
    echo "${productsDir}/${productName}"
}


function step3DetectedTroughs() {
    local interferogram=${1}
    local cohesionThreshold=${2}
    local fillEllipseGapLength=${3}
    local entrophyThreshold=${4}
    local minimalTroughAreaLimit=${5}
    local maximalTroughAreaLimit=${6}
    local maximalTroughRadious=${7}
    local samplingTroughAngle=${8}
    local periodOfEllipse=${9}
    local troughMaximumFitError=${10}
    local maximalTroughCutRadious=${11}

    local productName="03-detected-troughs"
    local productsDir="${PRODUCTS_DIR}"

    log "Detecting troughs, interferogram: ${interferogram}"
    log "Product directory: ${productsDir}/${productName}"

    mkdir -p "${productsDir}/${productName}"

    $(callMinesar "${productsDir}/${productName}.log" "MineSARBatch03DetectedTroughs" "--name ${productName} --targetDirectory ${productsDir} --interferogramProduct ${interferogram} --cohesionThreshold ${cohesionThreshold} --fillEllipseGapLength ${fillEllipseGapLength} --entrophyThreshold ${entrophyThreshold} --minimalTroughAreaLimit ${minimalTroughAreaLimit} --maximalTroughAreaLimit ${maximalTroughAreaLimit} --maximalTroughRadious ${maximalTroughRadious} --samplingTroughAngle ${samplingTroughAngle} --periodOfEllipse ${periodOfEllipse} --troughMaximumFitError ${troughMaximumFitError} --maximalTroughCutRadious ${maximalTroughCutRadious}" "-Xmx12G")

    MINESAR_EXIT_CODE=$?

    log "callMinesar() exit code: ${MINESAR_EXIT_CODE}"

    [ ${MINESAR_EXIT_CODE} -ne 0 ] && {
        ciop-publish -m "${productsDir}/${productName}.log"
        if [ "$testMode" = true ] ; then
            log "Making a copy of the result after error"
            cp -a "${productsDir}/." /tmp/products
        fi
        return ${ERR_STEP_THREE}
    }

    ciop-publish -m  "${productsDir}/${productName}.log"
    ciop-publish -m  "${productsDir}/${productName}/ellipses-merged-result-borders.txt"
    ciop-publish -m  "${productsDir}/${productName}/ellipses-result-borders.txt"

    if [ "$testMode" = true ] ; then
        log "Making a copy of the result after success"
        cp -a "${productsDir}/." /tmp/products
    fi
    echo "${productsDir}/${productName}"
}

function step4DepthAlerts() {
    local detectedTroughs=${1}
    local depthAlertLimit=${2}
    local productName="04-depth-alerts"
    local productsDir="${PRODUCTS_DIR}"
    
    log "Looking for depth alerts, detected troughs: ${detectedTroughs}"
    log "Product directory: ${productsDir}/${productName}"
    
    mkdir -p "${productsDir}/${productName}"

    $(callMinesar "${productsDir}/${productName}.log" "MineSARBatch04UnwrappedInterferogram" "--name ${productName} --targetDirectory ${productsDir} --detectedTroughsProduct ${detectedTroughs} --depthLimit ${depthAlertLimit}" "-Xmx4G -Dsnaphu.path=${MINESAR_PATH}/linux/snaphu/centos-6.7/snaphu -Djava.library.path=${MINESAR_PATH}/linux/jni/centos-6.7")

    MINESAR_EXIT_CODE=$?

    log "callMinesar() exit code: ${MINESAR_EXIT_CODE}"

    [ ${MINESAR_EXIT_CODE} -ne 0 ] && {
        ciop-publish -m "${productsDir}/${productName}.log"
        if [ "$testMode" = true ] ; then
            log "Making a copy of the result after error"
            cp -a "${productsDir}/." /tmp/products
        fi
        return ${ERR_STEP_FOUR}
    }
    
    ciop-publish -m  "${productsDir}/${productName}.log"
    ciop-publish -m  "${productsDir}/${productName}/output.tif"
    ciop-publish -m  "${productsDir}/${productName}/output.tif.properties"
    ciop-publish -m  "${productsDir}/${productName}/output.png"
    ciop-publish -m  "${productsDir}/${productName}/output.pngw"

    if [ "$testMode" = true ] ; then
        log "Making a copy of the result after success"
        cp -a "${productsDir}/." /tmp/products
    fi
    
    echo "${productsDir}/${productName}"
}

function validateInt() {
    if [[ ${1} =~ ^-?[0-9]+$ ]] ; then
	log "[${1}] is valid int"
	return 0
    else
	log "[${1}] is not valid int"
	return 1
    fi
}

function validateFloat() {
    if [[ ${1} =~ ^[-+]?[0-9]+\.?[0-9]*$ ]] ; then
	log "[${1}] is valid float"
	return 0
    else
	log "[${1}] is not valid float"
	return 1
    fi
}

function main() {
    local master_ref=${1}
    local slave_ref="$(ciop-getparam slave)"
    local master
    local slave
    local interferogram
    
    if [ "$testMode" = true ] ; then
	target="/tmp"
	rm -rf /tmp/products
    else
	target="${TMPDIR}"
    fi
    
    log "Working directory: ${WORKING_DIR}"
    log "Target directory: ${target}"
    
    cohesionThreshold="$(ciop-getparam cohesionThreshold)"
    fillEllipseGapLength="$(ciop-getparam fillEllipseGapLength)"
    entrophyThreshold="$(ciop-getparam entrophyThreshold)"
    minimalTroughAreaLimit="$(ciop-getparam minimalTroughAreaLimit)"
    maximalTroughAreaLimit="$(ciop-getparam maximalTroughAreaLimit)"
    maximalTroughRadious="$(ciop-getparam maximalTroughRadious)"
    samplingTroughAngle="$(ciop-getparam samplingTroughAngle)"
    periodOfEllipse="$(ciop-getparam periodOfEllipse)"
    troughMaximumFitError="$(ciop-getparam troughMaximumFitError)"
    maximalTroughCutRadious="$(ciop-getparam maximalTroughCutRadious)"
    depthAlertLimit="$(ciop-getparam depthAlertLimit)"

    
    log "Validating parameters"
    $(validateFloat ${cohesionThreshold})
    [ $? -ne 0 ] && return ${ERR_INPUT_VALIDATION}
    $(validateInt ${fillEllipseGapLength})
    [ $? -ne 0 ] && return ${ERR_INPUT_VALIDATION}
    $(validateFloat ${entrophyThreshold})
    [ $? -ne 0 ] && return ${ERR_INPUT_VALIDATION}
    $(validateInt ${minimalTroughAreaLimit})
    [ $? -ne 0 ] && return ${ERR_INPUT_VALIDATION}
    $(validateInt ${maximalTroughAreaLimit})
    [ $? -ne 0 ] && return ${ERR_INPUT_VALIDATION}
    $(validateInt ${maximalTroughRadious})
    [ $? -ne 0 ] && return ${ERR_INPUT_VALIDATION}
    $(validateInt ${samplingTroughAngle})
    [ $? -ne 0 ] && return ${ERR_INPUT_VALIDATION}
    $(validateInt ${periodOfEllipse})
    [ $? -ne 0 ] && return ${ERR_INPUT_VALIDATION}
    $(validateFloat ${troughMaximumFitError})
    [ $? -ne 0 ] && return ${ERR_INPUT_VALIDATION}
    $(validateInt ${maximalTroughCutRadious})
    [ $? -ne 0 ] && return ${ERR_INPUT_VALIDATION}
    $(validateFloat ${depthAlertLimit})
    [ $? -ne 0 ] && return ${ERR_INPUT_VALIDATION}

    
    log "Retrieving master: [${master_ref}]"
    master=$(download ${master_ref} ${target})
    [ $? -ne 0 ] && return ${ERR_DOWNLOAD_MASTER}
    log "Master retrieved: [${master}]"

    log "Retrieving slave: [${slave_ref}]"
    slave=$(download ${slave_ref} ${target})
    [ $? -ne 0 ] && return ${ERR_DOWNLOAD_SLAVE}
    log "Slave retrieved: [${slave}]"

#    slave="/home/skluz/S1A_IW_SLC__1SDV_20161212T162631_20161212T162659_014349_0173E7_A307.zip"
#    master="/home/skluz/S1A_IW_SLC__1SDV_20161224T162631_20161224T162659_014524_017956_272D.zip"

    iw="$(ciop-getparam iw)"
    log "Step 1: interferogram for iw ${iw}"
    interferogram=$(step2Interferogram ${master} ${slave} ${iw})
    [ $? -ne 0 ] && return ${ERR_STEP_TWO}
    log "Interferogram generated: ${interferogram}"

    log "Step 2: detected troughs"
    detectedTroughs=$(step3DetectedTroughs ${interferogram} ${cohesionThreshold} ${fillEllipseGapLength} ${entrophyThreshold} ${minimalTroughAreaLimit} ${maximalTroughAreaLimit} ${maximalTroughRadious} ${samplingTroughAngle} ${periodOfEllipse} ${troughMaximumFitError} ${maximalTroughCutRadious})
    [ $? -ne 0 ] && return ${ERR_STEP_THREE}
    log "DetectedTroughs generated: ${detectedTroughs}"
    
    rm -rf ${interferogram}

    log "Step 3: find alerts"
    depthAlerts=$(step4DepthAlerts ${detectedTroughs} ${depthAlertLimit})
    [ $? -ne 0 ] && return ${ERR_STEP_FOUR}
    log "Depth alerts generated: ${depthAlerts}"
    
    rm -rf ${detectedTroughs}
    log "Processing finished with success."
}

while read master; do
    main "${master}"
    res=$?
    [ ${res} -ne 0 ] && exit ${res}
done

exit $SUCCESS
