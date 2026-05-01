#!/bin/bash
# ByteAway B2B Error Reporting Script (curl)
# Usage: ./report_error.sh "API_TOKEN" "Error message" '{"extra": "data"}'

TOKEN=$1
MESSAGE=$2
CONTEXT=${3:-"{}"}

if [ -z "$TOKEN" ] || [ -z "$MESSAGE" ]; then
    echo "Usage: $0 <API_TOKEN> <MESSAGE> [JSON_CONTEXT]"
    exit 1
fi

curl -X POST "https://byteaway.xyz/api/v1/business/report-error" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d "{
       \"message\": \"$MESSAGE\",
       \"context\": $CONTEXT
     }"
