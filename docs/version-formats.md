# Version Format Support

This document describes the supported version formats for GA and PreGA deployments.

## Supported Version Formats

The repository supports multiple version formats to accommodate different stages of the OpenShift release cycle.

### Standard Version Format

```
4.X.Y
```

**Examples:**
- `4.18.27` - GA release
- `4.19.0` - GA release
- `4.20.0` - GA release
- `4.22.0` - PreGA release

### Pre-Release Version Formats

#### Early Candidate (EC)

```
4.X.Y-ec.Z
```

**Examples:**
- `4.22.0-ec.0` - Early Candidate 0
- `4.22.0-ec.1` - Early Candidate 1
- `4.22.0-ec.2` - Early Candidate 2
- `4.22.0-ec.5` - Early Candidate 5

#### Release Candidate (RC)

```
4.X.Y-rc.Z
```

**Examples:**
- `4.22.0-rc.0` - Release Candidate 0
- `4.22.0-rc.1` - Release Candidate 1
- `4.22.0-rc.2` - Release Candidate 2
- `4.22.0-rc.5` - Release Candidate 5

## Version Format Validation

The `generate-imageset-dynamic.sh` script validates version formats using the following regex:

```regex
^4\.[0-9]+\.[0-9]+(-[a-z]+\.[0-9]+)?$
```

This accepts:
- **Base version:** `4.X.Y` (e.g., `4.22.0`)
- **Optional suffix:** `-<type>.<number>` (e.g., `-ec.1`, `-rc.2`)

## Catalog Index Mapping

### GA Deployments

**Without suffix:**
```
Version: 4.18.27
Catalog: registry.redhat.io/redhat/redhat-operator-index:v4.18
```

**With suffix (warning issued):**
```
Version: 4.18.0-ec.1
Catalog: registry.redhat.io/redhat/redhat-operator-index:v4.18.0-ec.1
Warning: Using pre-release version with GA deployment type
```

### PreGA Deployments

**Without suffix:**
```
Version: 4.22.0
Catalog: quay.io/prega/prega-operator-index:v4.22
```

**With EC suffix:**
```
Version: 4.22.0-ec.1
Catalog: quay.io/prega/prega-operator-index:v4.22.0-ec.1
```

**With RC suffix:**
```
Version: 4.22.0-rc.2
Catalog: quay.io/prega/prega-operator-index:v4.22.0-rc.2
```

## Usage Examples

### Standard Versions

```bash
# GA with standard version
make imageset-ga VERSION=4.18.27

# PreGA with standard version
make imageset-prega VERSION=4.22.0
```

### Early Candidate (EC) Versions

```bash
# PreGA with EC.0
make imageset-prega VERSION=4.22.0-ec.0

# PreGA with EC.1
make imageset-prega VERSION=4.22.0-ec.1

# PreGA with EC.5
make imageset-prega VERSION=4.22.0-ec.5
```

### Release Candidate (RC) Versions

```bash
# PreGA with RC.0
make imageset-prega VERSION=4.22.0-rc.0

# PreGA with RC.1
make imageset-prega VERSION=4.22.0-rc.1

# PreGA with RC.5
make imageset-prega VERSION=4.22.0-rc.5
```

### Direct Script Usage

```bash
# Standard version
./generate-imageset-dynamic.sh --prega 4.22.0

# EC version
./generate-imageset-dynamic.sh --prega 4.22.0-ec.1

# RC version
./generate-imageset-dynamic.sh --prega 4.22.0-rc.2

# With custom output
./generate-imageset-dynamic.sh --prega 4.22.0-ec.3 -o imageset-ec3.yml
```

## Generated Configuration Differences

### Standard Version (4.22.0)

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
```

### EC Version (4.22.0-ec.1)

```yaml
mirror:
  platform:
    channels:
    - name: candidate-4.22
      type: ocp
      minVersion: 4.22.0-ec.1
      maxVersion: 4.22.0-ec.1
  operators:
  - catalog: quay.io/prega/prega-operator-index:v4.22.0
```

**Note:** EC/RC versions use:
- Platform channel: `candidate-{major.minor}` (not `stable-`)
- Catalog index: Base version without EC/RC suffix (`v4.22.0`)

### RC Version (4.22.0-rc.2)

```yaml
mirror:
  platform:
    channels:
    - name: candidate-4.22
      type: ocp
      minVersion: 4.22.0-rc.2
      maxVersion: 4.22.0-rc.2
  operators:
  - catalog: quay.io/prega/prega-operator-index:v4.22.0
```

**Note:** RC versions follow the same pattern as EC versions.

## Version Progression Timeline

```
Development → Early Candidate → Release Candidate → General Availability
     ↓              ↓                    ↓                  ↓
  Internal      4.22.0-ec.0          4.22.0-rc.0        4.22.0
               4.22.0-ec.1          4.22.0-rc.1          (GA)
               4.22.0-ec.2          4.22.0-rc.2
                  ...                   ...
```

## Best Practices

### 1. Use Appropriate Deployment Type

- **EC/RC versions** → Use `--prega`
- **GA versions** → Use `--ga`

```bash
# Correct
make imageset-prega VERSION=4.22.0-ec.1

# Warning issued (but works)
make imageset-ga VERSION=4.18.0-ec.1
```

### 2. Version File Configuration

**For EC testing:**
```bash
cat > VERSION << 'EOF'
DEPLOYMENT_TYPE=prega
OCP_VERSION=4.22.0-ec.1
EOF
```

**For RC testing:**
```bash
cat > VERSION << 'EOF'
DEPLOYMENT_TYPE=prega
OCP_VERSION=4.22.0-rc.2
EOF
```

**For GA deployment:**
```bash
cat > VERSION << 'EOF'
DEPLOYMENT_TYPE=ga
OCP_VERSION=4.18.27
EOF
```

### 3. Iterating Through Versions

```bash
# Test all EC versions
for i in {0..5}; do
  make imageset-prega VERSION=4.22.0-ec.$i
  mv imageset-config.yml imageset-ec$i.yml
done

# Test all RC versions
for i in {0..5}; do
  make imageset-prega VERSION=4.22.0-rc.$i
  mv imageset-config.yml imageset-rc$i.yml
done
```

## Validation Examples

### Valid Versions

```bash
✓ 4.18.27
✓ 4.19.0
✓ 4.22.0
✓ 4.22.0-ec.0
✓ 4.22.0-ec.5
✓ 4.22.0-rc.0
✓ 4.22.0-rc.5
✓ 4.23.0-ec.1
```

### Invalid Versions

```bash
✗ 4.22 (missing patch version)
✗ 4.22.0-alpha.1 (unsupported suffix type)
✗ 4.22.0-beta.1 (unsupported suffix type)
✗ 4.22.0-ec (missing number)
✗ 4.22-ec.1 (missing patch version)
✗ 5.22.0 (major version must be 4)
```

## Error Messages

### Invalid Format

```bash
$ make imageset-prega VERSION=4.22-ec.1

Error: Invalid version format: 4.22-ec.1
Expected formats:
  - 4.X.Y (e.g., 4.18.27)
  - 4.X.Y-ec.Z (e.g., 4.22.0-ec.1)
  - 4.X.Y-rc.Z (e.g., 4.22.0-rc.2)
```

### Version Compatibility Warning

```bash
$ make imageset-ga VERSION=4.22.0-ec.1

Warning: Using pre-release version (4.22.0-ec.1) with GA deployment type
Warning: Consider using --prega for pre-release versions
```

## Troubleshooting

### Issue: Catalog index not found

**Problem:** PreGA catalog index doesn't exist for specified EC/RC version

```bash
Error: quay.io/prega/prega-operator-index:v4.22.0-ec.1 not found
```

**Solution:** Verify the catalog index exists in the prega repository:

```bash
# Check available tags
podman search quay.io/prega/prega-operator-index --list-tags
```

### Issue: Version mismatch in generated config

**Problem:** Generated config shows wrong version

**Solution:** Ensure you're using the correct flag:

```bash
# Wrong
make imageset-ga VERSION=4.22.0-ec.1  # Uses GA catalog

# Correct
make imageset-prega VERSION=4.22.0-ec.1  # Uses PreGA catalog
```

## References

- [Deployment Types Guide](./deployment-types.md)
- [Main README](../README.md)
- [Usage Examples](../USAGE-EXAMPLES.md)
