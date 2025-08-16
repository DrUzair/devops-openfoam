# Stage 1: Base OpenFOAM + Python
FROM openfoam/openfoam9-paraview56 AS base

# Set environment variables
ENV REYNOLDS_NUMBER=100 \
    MESH_RESOLUTION=20 \
    SIMULATION_TIME=1000

WORKDIR /opt/ansys-openfoam-platform

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 python3-pip jq curl bc \
    && rm -rf /var/lib/apt/lists/*
        
# Install Python packages
RUN pip3 install numpy matplotlib pandas

# Create foamuser
RUN useradd -m -s /bin/bash foamuser

# FIX: Create directories expected by OpenFOAM bashrc
RUN mkdir -p /home/foamuser/platforms \
    && chown -R foamuser:foamuser /home/foamuser \
    && mkdir -p /opt/ThirdParty-9 \
    && chown -R foamuser:foamuser /opt/ThirdParty-9

RUN mkdir -p /opt/ansys-openfoam-platform && \
    chown -R foamuser:foamuser /opt/ansys-openfoam-platform
    
# Copy simulation cases and scripts
COPY --chown=foamuser:foamuser ./simulations/ ./simulations/
COPY --chown=foamuser:foamuser ./scripts/ ./scripts/

# Make scripts executable
RUN chmod +x scripts/*.sh

# Always source OpenFOAM for interactive shells
RUN echo "source /opt/openfoam9/etc/bashrc" >> /etc/bash.bashrc



# Stage 2: Production
FROM base AS production

USER foamuser
WORKDIR /opt/ansys-openfoam-platform

# Default command (parametric study)
CMD ["bash", "-lc", "./scripts/run-blockMesh.sh"]