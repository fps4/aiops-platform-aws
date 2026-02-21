FROM python:3.13-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc g++ && rm -rf /var/lib/apt/lists/*

# Build context is src/; paths are relative to that root
COPY detection/statistical/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY detection/statistical/main.py detection/statistical/algorithms.py ./
COPY shared/ ./shared/

ENV PYTHONPATH=/app

CMD ["python", "main.py"]
