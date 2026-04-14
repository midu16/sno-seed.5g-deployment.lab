# ImageSet Configuration Generator Guide

This guide explains how to use the `imageset-config.sh` script to generate ImageSet configuration files for mirroring OpenShift content.

## Overview

The `imageset-config.sh` script provides two modes:
1. **Template Mode** (`-g`): Generate a pre-configured imageset-config.yml for specific OpenShift versions
2. **Custom Mode**: Generate custom configurations from catalog indexes

## Template Mode (Recommended for SNO Seed)

### Quick Start

Generate imageset-config.yml using the VERSION file:

```bash
# Ensure OCP_VERSION is set in VERSION file
cat VERSION
# OCP_VERSION=4.18.27

# Generate using the -g flag
OCP_VERSION=4.18.27 ./imageset-config.sh -g

# Or use Makefile (automatically reads VERSION file)
make imageset-config.yml
```

### Supported OpenShift Versions

The script includes templates for:
- **4.18.x** - Stable release
- **4.19.x** - Current stable
- **4.20.x** - Latest stable
- **4.21.x** - Upcoming release

### Included Operators

The template includes the following operators (minimal set for SNO):

| Operator | Channel | Description |
|----------|---------|-------------|
| sriov-network-operator | stable | SR-IOV Network Operator |
| local-storage-operator | stable | Local Storage Operator |
| lvms-operator | stable-4.x | LVM Storage Operator |
| cluster-logging | stable | Cluster Logging Operator |
| ptp-operator | stable | Precision Time Protocol Operator |
| lifecycle-agent | stable | Lifecycle Agent for Image-Based Upgrades |
| oadp-operator | stable-1.4 (4.18) or stable | OpenShift API for Data Protection |

### Template Mode Examples

```bash
# Generate for OCP 4.18.27
OCP_VERSION=4.18.27 ./imageset-config.sh -g

# Generate for OCP 4.19.0
OCP_VERSION=4.19.0 ./imageset-config.sh -g -o imageset-419.yml

# Generate with custom output file
OCP_VERSION=4.18.27 \
  IMAGESET_OUTPUT_FILE=my-imageset.yml \
  ./imageset-config.sh -g

# Using Makefile (reads from VERSION file)
make imageset-config.yml

# Override version with Makefile
make imageset-config.yml OCP_VERSION=4.19.0
```

## Custom Mode (Advanced)

Generate custom configurations from specific catalog indexes:

```bash
# Generate from custom catalog
./imageset-config.sh \
  -i registry.redhat.io/redhat/redhat-operator-index:v4.18 \
  -o custom-imageset.yml

# Enable debug mode
./imageset-config.sh \
  -i registry.redhat.io/redhat/redhat-operator-index:v4.18 \
  -o custom-imageset.yml \
  -d

# Single version mode (no version ranges)
./imageset-config.sh \
  -i registry.redhat.io/redhat/redhat-operator-index:v4.18 \
  -o custom-imageset.yml \
  -s
```

## Script Options

### Template Mode Options
- `-g, --generate` - Generate templated imageset-config.yml (requires OCP_VERSION)
- `-o, --output FILE` - Output file path (default: imageset-config.yml)

### Custom Mode Options
- `-i, --index INDEX` - Source catalog index (required)
- `-o, --output FILE` - Output file path
- `-d, --debug` - Enable debug mode
- `-s, --single-version` - Use single version mode
- `-n, --no-limitations` - Include all versions from all channels
- `-c, --disable-channel-versions` - Disable channel-specific version support

### General Options
- `-h, --help` - Show help message
- `-t, --test` - Run version parsing tests

## Environment Variables

All options can be set via environment variables:

```bash
# Template mode variables
export OCP_VERSION=4.18.27
export IMAGESET_OUTPUT_FILE=imageset-config.yml

# Custom mode variables
export SOURCE_INDEX=registry.redhat.io/redhat/redhat-operator-index:v4.18
export DEBUG=true
export USE_VERSION_RANGE=true
export NO_LIMITATIONS_MODE=false
export ALLOW_CHANNEL_SPECIFIC_VERSIONS=true

# Run the script
./imageset-config.sh -g
```

## Generated File Structure

The generated `imageset-config.yml` contains:

```yaml
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1
mirror:
  platform:
    channels:
    - name: stable-4.18
      type: ocp
      minVersion: 4.18.27
      maxVersion: 4.18.27
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.18
    targetCatalog: openshift-marketplace/redhat-operators-disconnected
    packages:
    - name: sriov-network-operator
      channels:
      - name: stable
    # ... more operators ...
  additionalImages:
  - name: registry.redhat.io/ubi8/ubi:latest
  - name: registry.redhat.io/openshift4/ztp-site-generate-rhel8:v4.18
  - name: registry.redhat.io/rhel8/support-tools:latest
```

## Using the Generated Configuration

Once generated, use the imageset-config.yml with oc-mirror:

```bash
# Mirror to disconnected registry
./bin/oc-mirror \
  -c imageset-config.yml \
  --v2 \
  --workspace file://seed/ \
  docker://infra.5g-deployment.lab:8443/seed \
  --max-nested-paths 10 \
  --parallel-images 10 \
  --parallel-layers 10 \
  --dest-tls-verify=false \
  --log-level debug
```

## Troubleshooting

### Issue: OCP_VERSION not set

**Error:**
```
Error: OCP_VERSION environment variable is required for template generation
```

**Solution:**
```bash
# Set in VERSION file
echo "OCP_VERSION=4.18.27" > VERSION

# Or export as environment variable
export OCP_VERSION=4.18.27

# Or pass inline
OCP_VERSION=4.18.27 ./imageset-config.sh -g
```

### Issue: Unsupported OpenShift version

**Error:**
```
Error: Unsupported OpenShift version: 4.17.0
```

**Solution:**
The script supports versions 4.18+. Update to a supported version or use custom mode:
```bash
./imageset-config.sh -i registry.redhat.io/redhat/redhat-operator-index:v4.17
```

### Issue: Script not executable

**Error:**
```
bash: ./imageset-config.sh: Permission denied
```

**Solution:**
```bash
chmod +x imageset-config.sh
```

## Version Management Integration

The script integrates with the repository's centralized version management:

1. **VERSION file** - Stores default OCP_VERSION
2. **Makefile** - Reads from VERSION file automatically
3. **GitHub Actions** - Uses workflow input variables
4. **Scripts** - All scripts source VERSION file

This ensures consistency across all deployment tooling.

## Additional Resources

- [OpenShift oc-mirror Documentation](https://docs.openshift.com/container-platform/latest/installing/disconnected_install/installing-mirroring-disconnected.html)
- [ImageSetConfiguration API Reference](https://docs.openshift.com/container-platform/latest/installing/disconnected_install/installing-mirroring-creating-imageset.html)
- Main README: [../README.md](../README.md)
- Quick Start Guide: [../QUICKSTART.md](../QUICKSTART.md)
