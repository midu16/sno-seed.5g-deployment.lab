# Deployment Types: GA vs PreGA

This guide explains the two deployment types supported by the SNO Seed cluster repository.

## Overview

The repository supports two distinct deployment scenarios:

### 1. GA (General Availability) Deployment

**Use Case:** Production deployments using released, GA software

**Catalog Index:** `registry.redhat.io/redhat/redhat-operator-index:vX.Y`

**Supported Versions:**
- OpenShift 4.18.x
- OpenShift 4.19.x
- OpenShift 4.20.x
- OpenShift 4.21.x

**Characteristics:**
- Production-ready, fully supported operators
- Official Red Hat registry
- Stable release channels
- Recommended for production environments

### 2. PreGA (Pre-General Availability) Deployment

**Use Case:** Testing and validation of upcoming releases

**Catalog Index:** `quay.io/prega/prega-operator-index:vX.Y`

**Supported Versions:**
- OpenShift 4.22.x (upcoming)
- OpenShift 4.23.x (future)

**Characteristics:**
- Early access to upcoming features
- Custom prega registry
- Testing and validation purposes
- Not recommended for production

## Static Operators List

Both deployment types include the same set of operators (7 total):

| Operator | Description | Channel Discovery |
|----------|-------------|-------------------|
| **sriov-network-operator** | SR-IOV Network Operator | Dynamic/Fallback to `stable` |
| **local-storage-operator** | Local Storage Operator | Dynamic/Fallback to `stable` |
| **lvms-operator** | LVM Storage Operator | Dynamic/Fallback to `stable-X.Y` |
| **cluster-logging** | Cluster Logging | Dynamic/Fallback to `stable` |
| **ptp-operator** | PTP Operator | Dynamic/Fallback to `stable` |
| **lifecycle-agent** | Lifecycle Agent | Dynamic/Fallback to `stable` |
| **oadp-operator** | OADP Backup/Restore | Dynamic/Fallback based on version |

## Dynamic Channel Discovery

Channels are discovered dynamically from the catalog index, with intelligent fallback defaults:

```bash
# The script attempts to discover channels using:
1. opm tool (if available)
2. Fallback to sensible defaults based on operator and version
```

**Example Channel Logic:**
- `sriov-network-operator` → `stable`
- `lvms-operator` → `stable-4.18` (version-specific)
- `oadp-operator` → `stable-1.4` (for 4.18) or `stable` (for newer versions)

## Usage Examples

### GA Deployment (4.18.27)

```bash
# Method 1: Using Makefile
make imageset-ga VERSION=4.18.27

# Method 2: Using script directly
./generate-imageset-dynamic.sh --ga 4.18.27

# Method 3: Using VERSION file
echo "DEPLOYMENT_TYPE=ga" > VERSION
echo "OCP_VERSION=4.18.27" >> VERSION
make imageset-ga
```

**Generated Catalog:**
```yaml
operators:
- catalog: registry.redhat.io/redhat/redhat-operator-index:v4.18
  targetCatalog: openshift-marketplace/redhat-operators-disconnected
  packages:
  - name: sriov-network-operator
    channels:
    - name: stable
  # ... more operators
```

### PreGA Deployment (4.22.0)

```bash
# Method 1: Using Makefile
make imageset-prega VERSION=4.22.0

# Method 2: Using script directly
./generate-imageset-dynamic.sh --prega 4.22.0

# Method 3: Using VERSION file
echo "DEPLOYMENT_TYPE=prega" > VERSION
echo "OCP_VERSION=4.22.0" >> VERSION
make imageset-prega
```

**Generated Catalog:**
```yaml
operators:
- catalog: quay.io/prega/prega-operator-index:v4.22
  targetCatalog: openshift-marketplace/redhat-operators-disconnected
  packages:
  - name: sriov-network-operator
    channels:
    - name: stable
  # ... more operators
```

## Configuration Files

### VERSION File Format

```bash
# Deployment type: "ga" or "prega"
DEPLOYMENT_TYPE=ga

# OpenShift version
# GA versions: 4.18.27, 4.19.0, 4.20.0, 4.21.0
# PreGA versions: 4.22.0, 4.23.0
OCP_VERSION=4.18.27
```

### Output Files

Both deployment types generate `imageset-config.yml` in the same format, with different catalog sources:

```yaml
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1
mirror:
  platform:
    channels:
    - name: stable-4.18  # or stable-4.22 for PreGA
      type: ocp
      minVersion: 4.18.27
      maxVersion: 4.18.27
  operators:
  - catalog: <GA_or_PreGA_catalog_index>
    # ... operators with dynamic channels
```

## Complete Workflow Comparison

### GA Workflow

```bash
# 1. Configure for GA
echo "DEPLOYMENT_TYPE=ga" > VERSION
echo "OCP_VERSION=4.18.27" >> VERSION

# 2. Download tools
make download-oc-tools

# 3. Generate ImageSet config
make imageset-ga

# 4. Mirror to registry
./bin/oc-mirror -c imageset-config.yml \
  --v2 \
  --workspace file://seed/ \
  docker://infra.5g-deployment.lab:8443/seed \
  --dest-tls-verify=false

# 5. Deploy cluster
make create-agent-iso
```

### PreGA Workflow

```bash
# 1. Configure for PreGA
echo "DEPLOYMENT_TYPE=prega" > VERSION
echo "OCP_VERSION=4.22.0" >> VERSION

# 2. Download tools (use appropriate version)
make download-oc-tools VERSION=4.22.0

# 3. Generate ImageSet config
make imageset-prega

# 4. Mirror to registry (same command)
./bin/oc-mirror -c imageset-config.yml \
  --v2 \
  --workspace file://seed/ \
  docker://infra.5g-deployment.lab:8443/seed \
  --dest-tls-verify=false

# 5. Deploy cluster
make create-agent-iso
```

## Switching Between Deployment Types

```bash
# Switch from GA to PreGA
sed -i 's/DEPLOYMENT_TYPE=ga/DEPLOYMENT_TYPE=prega/' VERSION
sed -i 's/OCP_VERSION=4.18.27/OCP_VERSION=4.22.0/' VERSION

# Regenerate config
make imageset-prega

# Switch back to GA
sed -i 's/DEPLOYMENT_TYPE=prega/DEPLOYMENT_TYPE=ga/' VERSION
sed -i 's/OCP_VERSION=4.22.0/OCP_VERSION=4.18.27/' VERSION

# Regenerate config
make imageset-ga
```

## Makefile Targets

| Target | Description | Example |
|--------|-------------|---------|
| `make imageset-ga` | Generate GA config | `make imageset-ga VERSION=4.18.27` |
| `make imageset-prega` | Generate PreGA config | `make imageset-prega VERSION=4.22.0` |
| `make imageset-config.yml` | Legacy template mode | `make imageset-config.yml OCP_VERSION=4.18.27` |

## Troubleshooting

### Issue: Version mismatch warning

```
Warning: Version 4.22 may not be tested for GA deployment
```

**Solution:** Use appropriate version for deployment type:
- GA: 4.18, 4.19, 4.20, 4.21
- PreGA: 4.22, 4.23

### Issue: Catalog index not accessible

```
Error: Failed to query catalog index
```

**Solution:**
- Check network connectivity to registry
- Verify catalog index exists for the specified version
- Script will fall back to default channels automatically

### Issue: Channel discovery fails

**Solution:** The script automatically falls back to sensible default channels if discovery fails. Review the generated `imageset-config.yml` to verify channels are appropriate.

## Advanced: Custom Channel Discovery

To implement custom channel discovery logic, modify the `query_operator_channels()` function in `generate-imageset-dynamic.sh`:

```bash
query_operator_channels() {
    local catalog="$1"
    local operator="$2"
    local version="$3"

    # Custom logic here
    # Example: Query using opm
    if command -v opm &> /dev/null; then
        opm render "$catalog" | \
            jq -r "select(.package==\"$operator\") | .defaultChannel"
    else
        get_default_channels "$operator" "$version"
    fi
}
```

## References

- [ImageSet Configuration Guide](./imageset-config-guide.md)
- [Main README](../README.md)
- [Quick Start Guide](../QUICKSTART.md)
- [OpenShift Disconnected Install Docs](https://docs.openshift.com/container-platform/latest/installing/disconnected_install/)
