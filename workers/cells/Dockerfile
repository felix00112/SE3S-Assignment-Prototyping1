FROM python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY workers/ ./workers/
COPY shared/ ./shared/
COPY infrastructure/redis/lua/ ./infrastructure/redis/lua/

CMD ["python", "-m", "workers.cells.worker"]
