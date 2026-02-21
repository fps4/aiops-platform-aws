FROM python:3.13-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc g++ && rm -rf /var/lib/apt/lists/*

# Build context is src/; paths are relative to that root
COPY detection/statistical/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy full source tree so Python package paths resolve
COPY . /app/src

# Add project root to PYTHONPATH so `src.*` namespace is found
ENV PYTHONPATH=/app
WORKDIR /app

# Run via module to ensure package imports work
CMD ["python", "-m", "src.detection.statistical.main"]
