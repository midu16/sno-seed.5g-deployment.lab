#!/usr/bin/env bash
# Test script to verify dynamic channel discovery
# Usage: ./test-channel-discovery.sh <catalog-index> <operator-name>

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
CATALOG="${1:-quay.io/prega/prega-operator-index:v4.22}"
OPERATOR="${2:-sriov-network-operator}"
OC_MIRROR_BIN="./bin/oc-mirror"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Dynamic Channel Discovery Test                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Catalog:${NC}  $CATALOG"
echo -e "${YELLOW}Operator:${NC} $OPERATOR"
echo ""

# Check if oc-mirror exists
if [ ! -x "$OC_MIRROR_BIN" ]; then
    echo -e "${RED}✗ Error: oc-mirror not found at $OC_MIRROR_BIN${NC}"
    echo -e "${YELLOW}Run: make download-oc-tools VERSION=4.22.0-ec.3${NC}"
    exit 1
fi

echo -e "${GREEN}✓ oc-mirror found${NC}"
echo ""

# Query the catalog
echo -e "${BLUE}Querying catalog...${NC}"
echo -e "${YELLOW}Command: $OC_MIRROR_BIN list operators --v1 --catalog $CATALOG --package=$OPERATOR${NC}"
echo ""

if output=$($OC_MIRROR_BIN list operators --v1 --catalog "$CATALOG" --package="$OPERATOR" 2>&1); then
    echo -e "${GREEN}✓ Query successful${NC}"
    echo ""
    echo -e "${BLUE}Raw Output:${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    echo "$output"
    echo "─────────────────────────────────────────────────────────────────"
    echo ""

    # Parse channels
    channels=$(echo "$output" | awk 'NR>1 && $2 != "" {print $2}' | sort -u)

    if [ -n "$channels" ]; then
        echo -e "${GREEN}✓ Found channels:${NC}"
        echo "$channels" | while read -r channel; do
            if [ "$channel" = "stable" ]; then
                echo -e "  ${GREEN}• $channel${NC} (preferred)"
            else
                echo -e "  ${YELLOW}• $channel${NC}"
            fi
        done
        echo ""

        # Show selected channel
        if echo "$channels" | grep -q "^stable$"; then
            echo -e "${GREEN}✓ Selected channel: stable${NC}"
        else
            first_channel=$(echo "$channels" | head -n1)
            echo -e "${YELLOW}ℹ Selected channel: $first_channel (first available)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ No channels found in output${NC}"
        echo -e "${YELLOW}Would use fallback defaults${NC}"
    fi
else
    echo -e "${RED}✗ Query failed${NC}"
    echo -e "${YELLOW}Error output:${NC}"
    echo "$output"
    echo ""
    echo -e "${YELLOW}Would use fallback defaults${NC}"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Test complete${NC}"
echo ""
echo -e "${YELLOW}Try other operators:${NC}"
echo -e "  ./test-channel-discovery.sh $CATALOG local-storage-operator"
echo -e "  ./test-channel-discovery.sh $CATALOG lvms-operator"
echo -e "  ./test-channel-discovery.sh $CATALOG cluster-logging"
echo -e "  ./test-channel-discovery.sh $CATALOG ptp-operator"
echo -e "  ./test-channel-discovery.sh $CATALOG lifecycle-agent"
echo -e "  ./test-channel-discovery.sh $CATALOG oadp-operator"
