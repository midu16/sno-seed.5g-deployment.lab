# Dynamic Operator Channel Discovery

The `generate-imageset-dynamic.sh` script now automatically discovers operator channels from the catalog index using `oc-mirror`.

## How It Works

### 1. Channel Discovery Process

For each operator in the static list, the script:

1. **Queries the catalog** using:
   ```bash
   ./bin/oc-mirror list operators --v1 \
     --catalog <catalog-index> \
     --package=<operator-name>
   ```

2. **Parses the output** to extract available channels:
   ```
   PACKAGE                    CHANNEL  HEAD
   sriov-network-operator     stable   sriov-network-operator.v4.18.0
   ```

3. **Selects a channel** using this priority:
   - First choice: `stable` channel (if available)
   - Fallback: First available channel
   - Last resort: Hardcoded default for that operator

### 2. Example Output

When running with debug mode:

```bash
./generate-imageset-dynamic.sh --prega 4.22.0-ec.3 -o imageset-config.yml -d
```

**Output:**
```
[INFO] Generating ImageSet Configuration
[INFO] ==================================
[INFO] Deployment Type: prega
[INFO] OCP Version: 4.22.0-ec.3
[INFO] Platform Channel: candidate-4.22
[INFO] Catalog Index: quay.io/prega/prega-operator-index:v4.22
[INFO] Output File: imageset-config.yml
[INFO]
[INFO] Discovering operator channels from catalog...
[INFO]
[INFO]   • sriov-network-operator
[DEBUG] Querying catalog for operator: sriov-network-operator
[DEBUG]   Catalog: quay.io/prega/prega-operator-index:v4.22
[DEBUG]   Raw output: PACKAGE                 CHANNEL  HEAD
sriov-network-operator  stable   sriov-network-operator.v4.22.0
[DEBUG]   Found 'stable' channel for sriov-network-operator
[INFO]     → channel: stable
[INFO]   • local-storage-operator
[DEBUG] Querying catalog for operator: local-storage-operator
[DEBUG]   Catalog: quay.io/prega/prega-operator-index:v4.22
[DEBUG]   Found 'stable' channel for local-storage-operator
[INFO]     → channel: stable
...
```

### 3. Prerequisites

**The `oc-mirror` binary must be available:**

```bash
# Download oc-mirror first
make download-oc-tools VERSION=4.22.0-ec.3

# Verify it's available
ls -la ./bin/oc-mirror

# Then generate imageset
make imageset-prega VERSION=4.22.0-ec.3
```

**If oc-mirror is not available:**
- Script automatically falls back to hardcoded default channels
- Warning is logged in debug mode
- Generation continues without failure

### 4. Static Operator List

The following operators are included (channels discovered dynamically):

| Operator | Default Fallback Channel |
|----------|--------------------------|
| `sriov-network-operator` | `stable` |
| `local-storage-operator` | `stable` |
| `lvms-operator` | `stable-{major.minor}` |
| `cluster-logging` | `stable` |
| `ptp-operator` | `stable` |
| `lifecycle-agent` | `stable` |
| `oadp-operator` | `stable` (or `stable-1.4` for 4.18) |

### 5. Catalog Query Details

#### GA Deployment (registry.redhat.io)

```bash
./bin/oc-mirror list operators --v1 \
  --catalog registry.redhat.io/redhat/redhat-operator-index:v4.18 \
  --package=sriov-network-operator
```

**Example Output:**
```
PACKAGE                 CHANNEL         HEAD
sriov-network-operator  stable          sriov-network-operator.v4.18.27
sriov-network-operator  4.18            sriov-network-operator.v4.18.0
```

Result: Selects `stable` channel

#### PreGA Deployment (quay.io/prega)

```bash
./bin/oc-mirror list operators --v1 \
  --catalog quay.io/prega/prega-operator-index:v4.22 \
  --package=lvms-operator
```

**Example Output:**
```
PACKAGE         CHANNEL         HEAD
lvms-operator   stable-4.22     lvms-operator.v4.22.0-ec.3
lvms-operator   stable          lvms-operator.v4.22.0
```

Result: Selects `stable` channel (preferred over version-specific)

### 6. Error Handling

#### Scenario 1: oc-mirror Not Found

```
[DEBUG] oc-mirror not found at ./bin/oc-mirror, using default channels for sriov-network-operator
[INFO]     → channel: stable
```

**Resolution:** Downloads hardcoded defaults, generation succeeds

#### Scenario 2: Catalog Query Fails

```
[DEBUG] Failed to query catalog (exit code: 1), using defaults
[DEBUG] Error: error: unable to pull catalog image
[INFO]     → channel: stable
```

**Resolution:** Uses fallback defaults, generation succeeds

#### Scenario 3: No Channels Found

```
[DEBUG] No channels found in output, using defaults
[INFO]     → channel: stable
```

**Resolution:** Uses fallback defaults, generation succeeds

### 7. Manual Testing

To test channel discovery for a specific operator:

```bash
# Download oc-mirror
make download-oc-tools VERSION=4.22.0-ec.3

# Query a specific operator
./bin/oc-mirror list operators --v1 \
  --catalog quay.io/prega/prega-operator-index:v4.22 \
  --package=sriov-network-operator

# Expected output:
# PACKAGE                 CHANNEL  HEAD
# sriov-network-operator  stable   sriov-network-operator.vX.Y.Z
```

### 8. Debugging Channel Selection

Enable debug mode to see full channel discovery process:

```bash
./generate-imageset-dynamic.sh --prega 4.22.0-ec.3 -d
```

**Debug output includes:**
- Catalog being queried
- Raw oc-mirror output
- Channel selection logic
- Fallback reasons (if applicable)

### 9. Channel Selection Priority

The script uses this decision tree:

```
1. Can we run oc-mirror?
   ├─ NO  → Use hardcoded defaults
   └─ YES → Query catalog
             │
             2. Did query succeed?
                ├─ NO  → Use hardcoded defaults
                └─ YES → Parse channels
                          │
                          3. Is "stable" channel available?
                             ├─ YES → Use "stable"
                             └─ NO  → 4. Are any channels available?
                                       ├─ YES → Use first channel
                                       └─ NO  → Use hardcoded defaults
```

### 10. Benefits

**Dynamic Discovery:**
- Always uses correct channels from the catalog
- No manual updates needed when channels change
- Adapts to different catalog versions automatically

**Robust Fallback:**
- Works even if oc-mirror is unavailable
- Continues on catalog query errors
- Provides sensible defaults for all operators

**Transparent Operation:**
- Debug mode shows full discovery process
- Clear logging of selected channels
- Easy to troubleshoot issues

## Related Documentation

- [Channel Naming Guide](./channel-naming.md) - Platform channel naming
- [Version Formats Guide](./version-formats.md) - Supported version formats
- [Deployment Types Guide](./deployment-types.md) - GA vs PreGA workflows
