#!/usr/bin/env bash
# Dynamic ImageSet Configuration Generator for GA and PreGA deployments
# Supports both GA (registry.redhat.io) and PreGA (quay.io/prega) catalogs
# Dynamically discovers operator channels from catalog index

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Static operator list
OPERATORS=(
    "sriov-network-operator"
    "local-storage-operator"
    "lvms-operator"
    "cluster-logging"
    "ptp-operator"
    "lifecycle-agent"
    "oadp-operator"
)

# Default variables
DEPLOYMENT_TYPE=""
OCP_VERSION=""
OUTPUT_FILE="imageset-config.yml"
DEBUG=false

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_debug() {
    if [ "$DEBUG" = true ]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

# Show usage
show_usage() {
    cat << EOF
Dynamic ImageSet Configuration Generator

USAGE:
  $0 --ga VERSION [OPTIONS]
  $0 --prega VERSION [OPTIONS]

DEPLOYMENT TYPES:
  --ga VERSION        Generate config for GA deployment using registry.redhat.io
                      Supported versions: 4.18, 4.19, 4.20, 4.21

  --prega VERSION     Generate config for PreGA deployment using quay.io/prega
                      Supported versions: 4.22, 4.23

OPTIONS:
  -o, --output FILE   Output file path (default: imageset-config.yml)
  -d, --debug         Enable debug output
  -h, --help          Show this help message

STATIC OPERATORS (channels discovered dynamically):
  - sriov-network-operator
  - local-storage-operator
  - lvms-operator
  - cluster-logging
  - ptp-operator
  - lifecycle-agent
  - oadp-operator

EXAMPLES:
  # Generate for GA 4.18
  $0 --ga 4.18

  # Generate for PreGA 4.22
  $0 --prega 4.22 -o imageset-prega.yml

  # Generate with debug output
  $0 --ga 4.19 -d

CATALOG INDEXES:
  GA:     registry.redhat.io/redhat/redhat-operator-index:vX.Y
  PreGA:  quay.io/prega/prega-operator-index:vX.Y

EOF
}

# Parse version to get major.minor (handles versions like 4.22.0-ec.1)
get_major_minor() {
    local version="$1"
    # Extract major.minor from versions like:
    # 4.22.0 -> 4.22
    # 4.22.0-ec.1 -> 4.22
    # 4.22.0-rc.2 -> 4.22
    echo "$version" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/'
}

# Get base version without EC/RC suffix
get_base_version() {
    local version="$1"
    # Remove -ec.X or -rc.X suffix to get base version
    # 4.22.0-ec.1 -> 4.22.0
    # 4.22.0-rc.2 -> 4.22.0
    # 4.22.0 -> 4.22.0
    echo "$version" | sed -E 's/-[a-z]+\.[0-9]+$//'
}

# Get full version tag for catalog index
get_version_tag() {
    local version="$1"

    # For all cases, use major.minor for catalog index
    # Examples:
    #   4.22.0        -> 4.22
    #   4.22.0-ec.1   -> 4.22
    #   4.22.0-rc.2   -> 4.22
    #   4.18.27       -> 4.18
    get_major_minor "$version"
}

# Get platform channel name (stable or candidate)
get_channel_name() {
    local version="$1"
    local major_minor

    major_minor=$(get_major_minor "$version")

    # If version has -ec or -rc suffix, use "candidate" channel
    # Otherwise use "stable" channel
    if [[ "$version" =~ -(ec|rc)\. ]]; then
        echo "candidate-${major_minor}"
    else
        echo "stable-${major_minor}"
    fi
}

# Get catalog index URL based on deployment type and version
get_catalog_index() {
    local deploy_type="$1"
    local version="$2"
    local version_tag

    version_tag=$(get_version_tag "$version")

    if [ "$deploy_type" = "ga" ]; then
        echo "registry.redhat.io/redhat/redhat-operator-index:v${version_tag}"
    elif [ "$deploy_type" = "prega" ]; then
        echo "quay.io/prega/prega-operator-index:v${version_tag}"
    else
        log_error "Unknown deployment type: $deploy_type"
        exit 1
    fi
}

# Discover channels for an operator using grpcurl
discover_channels_grpcurl() {
    local catalog="$1"
    local operator="$2"
    local tmpdir

    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    log_debug "Querying catalog for operator: $operator"

    # This would require the catalog to be running as a gRPC service
    # For now, return empty to use fallback
    echo ""
}

# Get default channels based on operator name and version
get_default_channels() {
    local operator="$1"
    local version="$2"
    local major_minor

    major_minor=$(echo "$version" | cut -d. -f1,2)

    case "$operator" in
        sriov-network-operator)
            echo "stable"
            ;;
        local-storage-operator)
            echo "stable"
            ;;
        lvms-operator)
            echo "stable-${major_minor}"
            ;;
        cluster-logging)
            echo "stable"
            ;;
        ptp-operator)
            echo "stable"
            ;;
        lifecycle-agent)
            echo "stable"
            ;;
        oadp-operator)
            if [ "$major_minor" = "4.18" ]; then
                echo "stable-1.4"
            else
                echo "stable"
            fi
            ;;
        *)
            echo "stable"
            ;;
    esac
}

# Query catalog for operator channels using oc-mirror
query_operator_channels() {
    local catalog="$1"
    local operator="$2"
    local version="$3"
    local oc_mirror_bin="./bin/oc-mirror"

    # Check if oc-mirror is available
    if [ ! -x "$oc_mirror_bin" ]; then
        log_debug "oc-mirror not found at $oc_mirror_bin, using default channels for $operator"
        get_default_channels "$operator" "$version"
        return
    fi

    log_debug "Querying catalog for operator: $operator"
    log_debug "  Catalog: $catalog"

    # Query catalog for operator channels
    local output
    if output=$($oc_mirror_bin list operators --v1 --catalog "$catalog" --package="$operator" 2>&1 | grep -v "^W"); then
        log_debug "  Raw output: $output"

        # Parse DEFAULT CHANNEL from the header section
        # Expected format:
        # NAME                    DISPLAY NAME  DEFAULT CHANNEL
        # sriov-network-operator                stable
        # or
        # lvms-operator                          stable-4.22
        # The DEFAULT CHANNEL is the last field (handles empty DISPLAY NAME)
        local default_channel
        default_channel=$(echo "$output" | awk -v pkg="$operator" '
            /^PACKAGE/ {exit}  # Stop when we hit the PACKAGE section
            $1 == pkg && $1 != "NAME" {
                # Print the last field (DEFAULT CHANNEL)
                print $NF
                exit
            }
        ')

        if [ -n "$default_channel" ] && [ "$default_channel" != "DEFAULT" ]; then
            log_debug "  Found DEFAULT CHANNEL: $default_channel"
            echo "$default_channel"
            return
        else
            log_debug "  No DEFAULT CHANNEL found, parsing CHANNEL column"

            # Fallback: Parse CHANNEL column from packages section
            # PACKAGE                 CHANNEL  HEAD
            # sriov-network-operator  stable   sriov-network-operator.v4.18.0
            local channels
            channels=$(echo "$output" | awk '/^PACKAGE/,0 {if ($1 != "PACKAGE" && NF >= 2) print $2}' | sort -u)

            if [ -n "$channels" ]; then
                # Prefer "stable" channel if available
                if echo "$channels" | grep -q "^stable$"; then
                    log_debug "  Found 'stable' channel for $operator"
                    echo "stable"
                    return
                fi

                # Otherwise, use the first available channel
                local first_channel
                first_channel=$(echo "$channels" | head -n1)
                log_debug "  Using first available channel: $first_channel"
                echo "$first_channel"
                return
            else
                log_debug "  No channels found in output, using defaults"
            fi
        fi
    else
        log_debug "  Failed to query catalog (exit code: $?), using defaults"
        log_debug "  Error: $output"
    fi

    # Fall back to default channels
    get_default_channels "$operator" "$version"
}

# Generate imageset configuration
generate_imageset_config() {
    local deploy_type="$1"
    local version="$2"
    local output="$3"
    local catalog_index
    local major_minor
    local channel_name

    major_minor=$(get_major_minor "$version")
    catalog_index=$(get_catalog_index "$deploy_type" "$version")
    channel_name=$(get_channel_name "$version")

    log_info "Generating ImageSet Configuration"
    log_info "=================================="
    log_info "Deployment Type: $deploy_type"
    log_info "OCP Version: $version"
    log_info "Platform Channel: $channel_name"
    log_info "Catalog Index: $catalog_index"
    log_info "Output File: $output"
    log_info ""

    # Start generating YAML
    cat > "$output" << EOF
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1
mirror:
  platform:
    channels:
    - name: ${channel_name}
      type: ocp
      minVersion: ${version}
      maxVersion: ${version}
  operators:
  - catalog: ${catalog_index}
    targetCatalog: openshift-marketplace/redhat-operators-disconnected
    packages:
EOF

    # Add each operator with dynamically discovered channels
    log_info "Discovering operator channels from catalog..."
    log_info ""

    for operator in "${OPERATORS[@]}"; do
        log_info "  • $operator"

        # Query or get default channels
        local channels
        channels=$(query_operator_channels "$catalog_index" "$operator" "$version")

        log_info "    → channel: $channels"

        # Add operator to YAML
        cat >> "$output" << EOF
    - name: ${operator}
      channels:
      - name: ${channels}
EOF
    done

    log_info ""

    # Add additional images based on version
    cat >> "$output" << EOF
  additionalImages:
  - name: registry.redhat.io/ubi8/ubi:latest
  - name: registry.redhat.io/openshift4/ztp-site-generate-rhel8:v${major_minor}
  - name: registry.redhat.io/rhel8/support-tools:latest
EOF

    log_info ""
    log_info "✓ Generated $output successfully"
    log_info ""
    log_info "Catalog: $catalog_index"
    log_info "Operators included: ${#OPERATORS[@]}"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Review the generated configuration"
    log_info "  2. Run: ./bin/oc-mirror -c $output --v2 ..."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ga)
            DEPLOYMENT_TYPE="ga"
            OCP_VERSION="$2"
            shift 2
            ;;
        --prega)
            DEPLOYMENT_TYPE="prega"
            OCP_VERSION="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate inputs
if [ -z "$DEPLOYMENT_TYPE" ]; then
    log_error "Deployment type (--ga or --prega) is required"
    echo ""
    show_usage
    exit 1
fi

if [ -z "$OCP_VERSION" ]; then
    log_error "OCP version is required"
    echo ""
    show_usage
    exit 1
fi

# Validate version format
# Accepts: 4.X.Y or 4.X.Y-ec.Z or 4.X.Y-rc.Z
if ! [[ "$OCP_VERSION" =~ ^4\.[0-9]+\.[0-9]+(-[a-z]+\.[0-9]+)?$ ]]; then
    log_error "Invalid version format: $OCP_VERSION"
    log_error "Expected formats:"
    log_error "  - 4.X.Y (e.g., 4.18.27)"
    log_error "  - 4.X.Y-ec.Z (e.g., 4.22.0-ec.1)"
    log_error "  - 4.X.Y-rc.Z (e.g., 4.22.0-rc.2)"
    exit 1
fi

# Validate deployment type and version compatibility
major_minor=$(get_major_minor "$OCP_VERSION")
if [ "$DEPLOYMENT_TYPE" = "ga" ]; then
    if [[ ! "$major_minor" =~ ^4\.(18|19|20|21)$ ]]; then
        log_warn "Version $major_minor may not be tested for GA deployment"
        log_warn "Recommended GA versions: 4.18, 4.19, 4.20, 4.21"
    fi
    # Warn if using -ec or -rc suffix with GA
    if [[ "$OCP_VERSION" =~ -(ec|rc)\. ]]; then
        log_warn "Using pre-release version ($OCP_VERSION) with GA deployment type"
        log_warn "Consider using --prega for pre-release versions"
    fi
elif [ "$DEPLOYMENT_TYPE" = "prega" ]; then
    if [[ ! "$major_minor" =~ ^4\.(22|23|24)$ ]]; then
        log_warn "Version $major_minor may not be tested for PreGA deployment"
        log_warn "Recommended PreGA versions: 4.22, 4.23, 4.24"
    fi
fi

# Generate the configuration
generate_imageset_config "$DEPLOYMENT_TYPE" "$OCP_VERSION" "$OUTPUT_FILE"
