#!/bin/bash
set -e
set -x

echo "=== Starting blockMesh test ==="

# Source OpenFOAM
echo "Sourcing OpenFOAM..."
ls -l /opt/openfoam9/etc/bashrc || echo "bashrc not found"
source /opt/openfoam9/etc/bashrc || echo "Source command failed"echo "✓ OpenFOAM sourced"

# Go to a case directory (must exist in ./cases)
CASE_DIR="./cases/cavity-flow"
if [ ! -d "$CASE_DIR" ]; then
    echo "ERROR: Test case not found at $CASE_DIR"
    exit 1
fi

cd "$CASE_DIR"

# Run blockMesh
blockMesh > log.blockMesh 2>&1
echo "✓ blockMesh completed"
tail -5 log.blockMesh
