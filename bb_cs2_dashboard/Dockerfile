# Build React + shadcn UI, then serve with FastAPI (same port 8780).
FROM node:22-bookworm-slim AS frontend-build
WORKDIR /fe
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
COPY --from=frontend-build /fe/dist ./static
RUN mkdir -p /data/clips \
    && chown -R nobody:nogroup /data/clips \
    && chmod -R a+rX /app/static

ENV CS2_CONTROL_URL=http://bb_cs2_control:8765
ENV CLIPS_DIR=/data/clips
EXPOSE 8780
USER nobody
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8780"]
