#!/usr/bin/env bash
set -e

TYPES_DIR=".types"
WOW_API_DIR="${TYPES_DIR}/wow-api"

echo "Setting up WoW API type definitions in ${TYPES_DIR}..."

mkdir -p "${TYPES_DIR}"

if [ ! -d "${WOW_API_DIR}" ]; then
    echo "Cloning Ketho/vscode-wow-api Annotations..."
    git clone --depth 1 --filter=blob:none --sparse https://github.com/Ketho/vscode-wow-api.git "${WOW_API_DIR}"
    pushd "${WOW_API_DIR}" > /dev/null
    git sparse-checkout set Annotations
    popd > /dev/null
else
    echo "WoW API type definitions already exist at ${WOW_API_DIR}."
fi

FRAMEXML_DIR="${WOW_API_DIR}/Annotations/FrameXML"
if [ ! -d "${FRAMEXML_DIR}" ]; then
    echo "Cloning NumyAddon/FramexmlAnnotations..."
    git clone --depth 1 https://github.com/NumyAddon/FramexmlAnnotations.git "${FRAMEXML_DIR}"
else
    echo "FrameXML Annotations already exist at ${FRAMEXML_DIR}."
fi

echo "Type definition setup complete."
