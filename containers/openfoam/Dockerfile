# Multi-stage build for OpenFOAM simulation platform
FROM openfoam/openfoam9-paraview56 as base

# Set environment variables for parameterization
ENV REYNOLDS_NUMBER=100
ENV MESH_RESOLUTION=20
ENV SIMULATION_TIME=1000

# Create working directory
WORKDIR /opt/simulation

# Copy simulation files
COPY simulations/ ./cases/
COPY scripts/ ./scripts/

# Make scripts executable
RUN chmod +x scripts/*.sh

# Install additional tools for CI/CD integration
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    jq \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages for result validation
RUN pip3 install numpy matplotlib pandas

# Production stage
FROM base as production

# Set up non-root user for security
RUN useradd -m -s /bin/bash foamuser && \
    chown -R foamuser:foamuser /opt/simulation

USER foamuser

# Source OpenFOAM environment
RUN echo "source /opt/openfoam9/etc/bashrc" >> ~/.bashrc

# Default command
CMD ["./scripts/run-parametric-study.sh"]

# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s \
  CMD ./scripts/health-check.sh || exit 1