# Use official Python image as base
FROM python:3.13-slim

# Set working directory
WORKDIR /app

# Copy requirements files
COPY requirements.txt requirements.txt

# Install dependencies
RUN pip install --no-cache-dir --upgrade -r ./requirements.txt

# Copy source code
COPY src/backend/ ./

EXPOSE 80

CMD ["fastapi", "run", "/app/app.py", "--host", "0.0.0.0", "--port", "80"]
