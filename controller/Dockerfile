FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for caching
COPY controller/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY controller/ ./controller/

# Set Python path
ENV PYTHONPATH=/app

CMD ["python", "-m", "controller.src.main"]
