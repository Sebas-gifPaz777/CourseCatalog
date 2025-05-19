# Crear archivos necesarios para Prometheus y OpenTelemetry Collector
$otelConfig = @"
receivers:
  otlp:
    protocols:
      grpc:
      http:

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"

  logging:
    loglevel: debug

service:
  pipelines:
    metrics:
      receivers: [otlp]
      exporters: [prometheus, logging]
"@

$prometheusConfig = @"
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otel-collector:8889']
"@

$dockerCompose = @"
version: '3.8'

services:
  mysql:
    image: mysql:8.0
    container_name: futurex-mysql
    environment:
      MYSQL_ROOT_PASSWORD: techbankRootPsw
      MYSQL_DATABASE: futurex_course_db
    ports:
      - "3306:3306"

  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.98.0
    container_name: otel-collector
    command: ["--config=/etc/otel-collector-config.yaml"]
    volumes:
      - ./otel-collector-config.yaml:/etc/otel-collector-config.yaml
    ports:
      - "4317:4317"
      - "4318:4318"
      - "8889:8889"
    depends_on:
      - prometheus

  prometheus:
    image: prom/prometheus
    container_name: prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - --config.file=/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana-oss
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    depends_on:
      - prometheus
"@

# Guardar archivos en el mismo directorio que el script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

$otelConfig | Out-File -Encoding UTF8 -FilePath "$scriptDir\otel-collector-config.yaml"
$prometheusConfig | Out-File -Encoding UTF8 -FilePath "$scriptDir\prometheus.yml"
$dockerCompose | Out-File -Encoding UTF8 -FilePath "$scriptDir\docker-compose.yml"

# Ejecutar docker compose
docker-compose up -d

# Esperar a que MySQL arranque
Start-Sleep -Seconds 10

# Comando SQL para permitir conexiones remotas de root
$sql = @"
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'techbankRootPsw';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
"@

# Ejecutar el comando dentro del contenedor MySQL
docker exec -i futurex-mysql mysql -uroot -ptechbankRootPsw -e "$sql"
