#! /usr/bin/env bash

set -e

GENERATED_DOCS_DIR="./docs"

echo -e "Building docs into ${GENERATED_DOCS_DIR}"
echo -e "Clearing ${GENERATED_DOCS_DIR} directory"
rm -rf "${GENERATED_DOCS_DIR}"

echo -e "Running \`make docs\`..."
make docs

echo -e "Copying README.md"

# "{{" and "{%"" need to be escaped, otherwise Jekyll might interpret the expressions (on Github Pages)
ESCAPE_TEMPLATE='s/{{/{{"{{"}}/g; s/{\%/{{"{%"}}/g;'
sed "${ESCAPE_TEMPLATE}" README.md > "${GENERATED_DOCS_DIR}/README.md"
