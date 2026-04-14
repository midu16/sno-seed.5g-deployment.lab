# Platform Channel Naming Convention

This document explains the platform channel naming logic for different version types.

## Overview

The platform channel name in the ImageSet configuration varies based on whether the version is a stable release or a pre-release (EC/RC) version.

## Channel Naming Rules

### Rule 1: Standard Versions → `stable-{major.minor}`

**Applies to:**
- GA versions: `4.18.27`, `4.19.0`, `4.20.0`
- PreGA standard versions: `4.22.0`, `4.23.0`

**Generated channel:**
```yaml
channels:
- name: stable-4.22
  type: ocp
  minVersion: 4.22.0
  maxVersion: 4.22.0
```

### Rule 2: EC/RC Versions → `candidate-{major.minor}`

**Applies to:**
- Early Candidate (EC): `4.22.0-ec.0`, `4.22.0-ec.1`, etc.
- Release Candidate (RC): `4.22.0-rc.0`, `4.22.0-rc.2`, etc.

**Generated channel:**
```yaml
channels:
- name: candidate-4.22
  type: ocp
  minVersion: 4.22.0-ec.1
  maxVersion: 4.22.0-ec.1
```

## Catalog Index Handling

### Standard Versions

**Format:** Uses `major.minor` only

```yaml
Version: 4.22.0
Catalog: quay.io/prega/prega-operator-index:v4.22
```

### EC/RC Versions

**Format:** Uses base version **without** EC/RC suffix

```yaml
Version: 4.22.0-ec.3
Catalog: quay.io/prega/prega-operator-index:v4.22
                                            ^^^^^
                                            major.minor only!
```

**Why?** The catalog index at `v4.22` (major.minor) contains all the operators for that version stream, including all EC/RC builds. The specific EC/RC version is tracked in minVersion/maxVersion.

## Complete Examples

### Example 1: Standard PreGA Version

**Input:**
```bash
make imageset-prega VERSION=4.22.0
```

**Generated Config:**
```yaml
mirror:
  platform:
    channels:
    - name: stable-4.22
      type: ocp
      minVersion: 4.22.0
      maxVersion: 4.22.0
  operators:
  - catalog: quay.io/prega/prega-operator-index:v4.22
    targetCatalog: openshift-marketplace/redhat-operators-disconnected
```

### Example 2: Early Candidate Version

**Input:**
```bash
make imageset-prega VERSION=4.22.0-ec.1
```

**Generated Config:**
```yaml
mirror:
  platform:
    channels:
    - name: candidate-4.22
      type: ocp
      minVersion: 4.22.0-ec.1
      maxVersion: 4.22.0-ec.1
  operators:
  - catalog: quay.io/prega/prega-operator-index:v4.22
    targetCatalog: openshift-marketplace/redhat-operators-disconnected
```

**Key differences:**
- Channel name: `candidate-4.22` (not `stable-4.22`)
- Catalog index: `v4.22` (major.minor, no -ec.1 suffix)
- minVersion/maxVersion: `4.22.0-ec.1` (full version preserved)

### Example 3: Release Candidate Version

**Input:**
```bash
make imageset-prega VERSION=4.22.0-rc.2
```

**Generated Config:**
```yaml
mirror:
  platform:
    channels:
    - name: candidate-4.22
      type: ocp
      minVersion: 4.22.0-rc.2
      maxVersion: 4.22.0-rc.2
  operators:
  - catalog: quay.io/prega/prega-operator-index:v4.22
    targetCatalog: openshift-marketplace/redhat-operators-disconnected
```

### Example 4: GA Version

**Input:**
```bash
make imageset-ga VERSION=4.18.27
```

**Generated Config:**
```yaml
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
```

## Channel Name Decision Tree

```
Version Input
    │
    ├─ Has -ec.X or -rc.X suffix?
    │   ├─ YES → candidate-{major.minor}
    │   │         Catalog: v{major.minor.patch}
    │   │
    │   └─ NO  → stable-{major.minor}
    │             Catalog: v{major.minor} (standard)
    │                  or v{major.minor.patch} (if patch ≠ 0)
```

## Comparison Table

| Version Type | Example | Channel Name | Catalog Index | minVersion |
|--------------|---------|--------------|---------------|------------|
| GA Standard | 4.18.27 | `stable-4.18` | `v4.18` | 4.18.27 |
| PreGA Standard | 4.22.0 | `stable-4.22` | `v4.22` | 4.22.0 |
| PreGA EC | 4.22.0-ec.1 | `candidate-4.22` | `v4.22.0` | 4.22.0-ec.1 |
| PreGA RC | 4.22.0-rc.2 | `candidate-4.22` | `v4.22.0` | 4.22.0-rc.2 |

## Why Different Channel Names?

### Stable Channel
- **Purpose:** Production-ready, GA releases
- **Stability:** Fully tested and supported
- **Use case:** Production deployments

### Candidate Channel
- **Purpose:** Pre-release testing and validation
- **Stability:** Testing phase, may have issues
- **Use case:** Development, testing, validation

## Impact on Mirroring

The channel name affects how OpenShift queries for updates:

**Stable channel:**
```bash
# Looks for stable releases only
oc adm upgrade --channel=stable-4.22
```

**Candidate channel:**
```bash
# Looks for candidate/pre-release versions
oc adm upgrade --channel=candidate-4.22
```

## Implementation Details

The script uses these functions to determine channel names:

```bash
# Get platform channel name
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

# Get base version without EC/RC suffix
get_base_version() {
    local version="$1"
    # 4.22.0-ec.1 -> 4.22.0
    echo "$version" | sed -E 's/-[a-z]+\.[0-9]+$//'
}

# Get catalog version tag
get_version_tag() {
    local version="$1"
    local base_version

    base_version=$(get_base_version "$version")

    if [[ "$version" =~ -[a-z]+\.[0-9]+ ]]; then
        # Has EC/RC suffix, use base version
        echo "$base_version"
    else
        # Standard version, use major.minor
        get_major_minor "$version"
    fi
}
```

## Troubleshooting

### Issue: Wrong channel name

**Problem:**
```yaml
# Got this:
- name: stable-4.22

# Expected this:
- name: candidate-4.22
```

**Cause:** Version doesn't have `-ec` or `-rc` suffix

**Solution:**
```bash
# Wrong
make imageset-prega VERSION=4.22.0

# Correct for candidate channel
make imageset-prega VERSION=4.22.0-ec.1
```

### Issue: Catalog index has EC/RC suffix

**Problem:**
```yaml
# Got this:
catalog: quay.io/prega/prega-operator-index:v4.22.0-ec.1

# Expected this:
catalog: quay.io/prega/prega-operator-index:v4.22.0
```

**Cause:** Using an older version of the script

**Solution:** Update to the latest version of `generate-imageset-dynamic.sh`

## References

- [Version Formats Guide](./version-formats.md)
- [Deployment Types Guide](./deployment-types.md)
- [OpenShift Update Channels Documentation](https://docs.openshift.com/container-platform/latest/updating/understanding_updates/understanding-update-channels-release.html)
