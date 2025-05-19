# Crear archivos necesarios para Prometheus y OpenTelemetry Collector
$otelConfig = @"
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"

  logging:
    loglevel: debug

  file:
    path: /var/log/otel-collector.log

service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus, logging]
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [logging]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [file, logging]
"@

$prometheusConfig = @"
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otel-collector:8889']
"@

# Updated Docker Compose with network configuration and MySQL improvements
$dockerCompose = @"
version: '3.8'

services:
  mysql:
    image: mysql:8.0
    container_name: futurex-mysql
    environment:
      MYSQL_ROOT_PASSWORD: techbankRootPsw
      MYSQL_DATABASE: futurex_course_db
      MYSQL_ROOT_HOST: '%'
    ports:
      - "3306:3306"
    volumes:
      - mysql-data:/var/lib/mysql
    command:
      - --default-authentication-plugin=mysql_native_password
      - --bind-address=0.0.0.0
    networks:
      - futurex-network
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-ptechbankRootPsw"]
      interval: 5s
      timeout: 5s
      retries: 10

  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.98.0
    container_name: otel-collector
    command: ["--config=/etc/otel-collector-config.yaml"]
    volumes:
      - ./otel-collector-config.yaml:/etc/otel-collector-config.yaml
      - ./logs:/var/log
    ports:
      - "4317:4317"
      - "4318:4318"
      - "8889:8889"
    depends_on:
      - prometheus
    networks:
      - futurex-network

  prometheus:
    image: prom/prometheus
    container_name: prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - --config.file=/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
    networks:
      - futurex-network

  grafana:
    image: grafana/grafana-oss
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    depends_on:
      - prometheus
    networks:
      - futurex-network

volumes:
  mysql-data:

networks:
  futurex-network:
    driver: bridge
"@

# MySQL init script with user permissions
$mysqlInit = @"
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'techbankRootPsw';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
"@

# Sample application.properties content for reference
$appProperties = @"
# Database Configuration
spring.datasource.url=jdbc:mysql://localhost:3306/futurex_course_db?useSSL=false&allowPublicKeyRetrieval=true
spring.datasource.username=root
spring.datasource.password=techbankRootPsw
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

# Hibernate Configuration
spring.jpa.hibernate.ddl-auto=update
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQLDialect
spring.jpa.show-sql=true

# OpenTelemetry Configuration
otel.exporter.otlp.endpoint=http://localhost:4317
otel.exporter.otlp.protocol=grpc
otel.logs.exporter=otlp
otel.metrics.exporter=otlp
otel.traces.exporter=otlp
otel.resource.attributes=service.name=fx-catalog-service
"@

# Guardar archivos en el mismo directorio que el script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

# Crear directorio para logs si no existe
if (!(Test-Path "$scriptDir\logs")) {
    New-Item -ItemType Directory -Path "$scriptDir\logs"
}

$otelConfig | Out-File -Encoding UTF8 -FilePath "$scriptDir\otel-collector-config.yaml"
$prometheusConfig | Out-File -Encoding UTF8 -FilePath "$scriptDir\prometheus.yml"
$dockerCompose | Out-File -Encoding UTF8 -FilePath "$scriptDir\docker-compose.yml"
$mysqlInit | Out-File -Encoding UTF8 -FilePath "$scriptDir\mysql-init.sql"

# Display sample application.properties (optional)
Write-Host "Sample application.properties content (update your Spring Boot application):" -ForegroundColor Yellow
Write-Host $appProperties

# Shutdown any existing containers
Write-Host "Shutting down any existing containers..." -ForegroundColor Cyan
docker-compose down

# Cleanup old volumes if needed
Write-Host "Do you want to clean up old volumes to start fresh? (y/n)" -ForegroundColor Yellow
$cleanup = Read-Host
if ($cleanup -eq 'y') {
    Write-Host "Removing old volumes..." -ForegroundColor Cyan
    docker volume prune -f
}

# Start containers
Write-Host "Starting containers..." -ForegroundColor Cyan
docker-compose up -d

# Function to check if MySQL is ready
function Test-MySQLReady {
    $maxRetries = 30
    $retryInterval = 2
    $retryCount = 0

    Write-Host "Waiting for MySQL to be ready..." -ForegroundColor Cyan

    while ($retryCount -lt $maxRetries) {
        Start-Sleep -Seconds $retryInterval
        $retryCount++

        Write-Host "Attempt $retryCount of $maxRetries..." -ForegroundColor Gray

        $status = docker exec futurex-mysql mysqladmin -u root -ptechbankRootPsw ping --silent

        if ($LASTEXITCODE -eq 0) {
            Write-Host "MySQL is ready after $retryCount attempts!" -ForegroundColor Green
            return $true
        }

        # Check if container is still running
        $containerStatus = docker ps -f "name=futurex-mysql" --format "{{.Status}}"
        if (-not $containerStatus) {
            Write-Host "MySQL container is not running!" -ForegroundColor Red
            docker logs futurex-mysql
            return $false
        }
    }

    Write-Host "MySQL did not become ready after $maxRetries attempts." -ForegroundColor Red
    return $false
}

# Wait for MySQL to be ready
$mysqlReady = Test-MySQLReady

if ($mysqlReady) {
    # Execute MySQL init script
    Write-Host "Applying MySQL user permissions..." -ForegroundColor Cyan
    docker exec -i futurex-mysql mysql -u root -ptechbankRootPsw -e "$mysqlInit"

    # Test MySQL connection
    Write-Host "Testing MySQL connection..." -ForegroundColor Cyan
    $mysqlTest = docker exec -i futurex-mysql mysql -u root -ptechbankRootPsw -e "SHOW DATABASES;"
    Write-Host $mysqlTest
    Write-Host "MySQL connection successful!" -ForegroundColor Green

    # Check if our database exists
    if ($mysqlTest -match "futurex_course_db") {
        Write-Host "Database 'futurex_course_db' is ready." -ForegroundColor Green
    } else {
        Write-Host "Warning: Database 'futurex_course_db' not found in the list." -ForegroundColor Yellow
    }
} else {
    Write-Host "Failed to connect to MySQL. Check container logs using: docker logs futurex-mysql" -ForegroundColor Red
}

Write-Host "`nSetup complete! Services running:" -ForegroundColor Green
Write-Host "MySQL: localhost:3306" -ForegroundColor Cyan
Write-Host "OpenTelemetry Collector: localhost:4317 (gRPC), localhost:4318 (HTTP)" -ForegroundColor Cyan
Write-Host "Prometheus: http://localhost:9090" -ForegroundColor Cyan
Write-Host "Grafana: http://localhost:3000 (admin/admin)" -ForegroundColor Cyan
Write-Host "`nRemember to update your Spring Boot application.properties with the sample configuration." -ForegroundColor Yellow