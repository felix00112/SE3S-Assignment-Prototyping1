FROM python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY services/api/ ./api/
COPY shared/ ./shared/

CMD ["uvicorn", "api.app.main:app", "--host", "0.0.0.0", "--port", "8000"]
