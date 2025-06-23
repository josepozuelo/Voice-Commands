#!/bin/bash
# This script exports environment variables for Xcode builds

# Source the .env file if it exists
if [ -f "${SRCROOT}/.env" ]; then
    export $(grep -v '^#' "${SRCROOT}/.env" | xargs)
fi

# Also check Secrets.xcconfig for backward compatibility
if [ -f "${SRCROOT}/VoiceControl/Config/Secrets.xcconfig" ]; then
    # Extract OPENAI_API_KEY from xcconfig
    API_KEY=$(grep "OPENAI_API_KEY" "${SRCROOT}/VoiceControl/Config/Secrets.xcconfig" | cut -d'=' -f2- | tr -d ' ')
    if [ ! -z "$API_KEY" ]; then
        export OPENAI_API_KEY="$API_KEY"
    fi
fi

# Write to a temporary file that can be sourced by Xcode
echo "OPENAI_API_KEY=$OPENAI_API_KEY" > "${SRCROOT}/build-env.tmp"