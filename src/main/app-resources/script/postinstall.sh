#!/bin/bash

MINESAR_VERSION="2.0"
MINESAR_URL="https://github.com/skluz/minesar/releases/download/${MINESAR_VERSION}/minesar-bundle-${MINESAR_VERSION}.tar.gz"
TARGET_DIR="/application/"
TMP_DIR="/application/tmp"

rm -rf ${TMP_DIR}
mkdir ${TMP_DIR}

wget -O ${TMP_DIR}/minesar.tar.gz ${MINESAR_URL}
tar -zxvf ${TMP_DIR}/minesar.tar.gz -C ${TMP_DIR}
mv ${TMP_DIR}/minesar-bundle-${MINESAR_VERSION} ${TARGET_DIR}