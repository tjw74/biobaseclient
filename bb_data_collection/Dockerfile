# Biobase client: game data collection → bb_postgres
FROM python:3.12-slim

WORKDIR /app
RUN useradd -r -s /usr/sbin/nologin bb
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ ./app/
USER bb
ENV PYTHONUNBUFFERED=1
EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
