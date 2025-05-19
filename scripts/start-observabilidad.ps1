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
  logging:
    verbosity: detailed

  otlp:
    endpoint: "jaeger:4317"
    tls:
      insecure: true

  prometheus:
    endpoint: "0.0.0.0:8889"
    namespace: "otel"
    const_labels:
      label1: value1

  file:
    path: /var/log/otel-collector.log

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp, logging]

    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus, logging]

    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [file, logging]

  telemetry:
    logs:
      level: "debug"
"@

$prometheusConfig = @"
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'otel-collector'
    scrape_interval: 10s
    static_configs:
      - targets: ['otel-collector:8889']
"@

$logstashConfig = @"
input {
  file {
    path => "/var/log/otel-collector.log"
    start_position => "beginning"
  }
}

filter {
  json {
    source => "message"
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "otel-logs-%{+YYYY.MM.dd}"
  }
  stdout { codec => rubydebug }
}
"@

# Docker Compose con todos los servicios necesarios
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

  jaeger:
    image: jaegertracing/all-in-one:latest
    container_name: jaeger
    ports:
      - "16686:16686" # Web UI
      - "14250:14250" # gRPC for Jaeger-to-Jaeger communication
      - "4317:4317" # OTLP gRPC receiver
      - "4318:4318" # OTLP HTTP receiver
    environment:
      - COLLECTOR_OTLP_ENABLED=true
    networks:
      - futurex-network

  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.98.0
    container_name: otel-collector
    command: ["--config=/etc/otel-collector-config.yaml"]
    volumes:
      - ./otel-collector-config.yaml:/etc/otel-collector-config.yaml
      - ./logs:/var/log
    ports:
      - "4319:4317" # OTLP gRPC receiver
      - "4320:4318" # OTLP HTTP receiver
      - "8889:8889" # Prometheus exporter
    depends_on:
      - jaeger
      - prometheus
    networks:
      - futurex-network

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.14.0
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
    ports:
      - "9200:9200"
    networks:
      - futurex-network

  kibana:
    image: docker.elastic.co/kibana/kibana:7.14.0
    container_name: kibana
    ports:
      - "5601:5601"
    depends_on:
      - elasticsearch
    networks:
      - futurex-network

  logstash:
    user: root
    image: docker.elastic.co/logstash/logstash:7.14.0
    container_name: logstash
    volumes:
      - ./logstash.conf:/usr/share/logstash/pipeline/logstash.conf
      - ./logs:/var/log
    ports:
      - "5044:5044"
      - "9600:9600"
    depends_on:
      - elasticsearch
    networks:
      - futurex-network

  prometheus:
    image: prom/prometheus:v2.30.3
    container_name: prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
    networks:
      - futurex-network

  grafana:
    image: grafana/grafana:8.1.2
    container_name: grafana
    ports:
      - "3000:3000"
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

# Ejemplo de application.properties para microservicios Spring Boot
$appProperties = @"
# Configuración básica de la aplicación
spring.application.name=fx-catalog-service
server.port=8002
course.service.url=http://localhost:8001
spring.main.allow-bean-definition-overriding=true

# Configuración de OpenTelemetry
otel.exporter.otlp.endpoint=http://localhost:4319
otel.exporter.otlp.protocol=grpc
otel.sdk.disabled=false

# Configuración de exportadores
otel.traces.exporter=otlp
otel.metrics.exporter=otlp
otel.logs.exporter=otlp

# Configuración de métricas y trazas
management.otlp.metrics.export.step=10s
management.tracing.sampling.probability=1.0

# Deshabilitar la exportación directa de métricas Prometheus
management.endpoints.web.exposure.exclude=prometheus
management.prometheus.metrics.export.enabled=false
"@

# Ejemplo de configuración de Logback para Spring Boot
$logbackConfig = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <include resource="org/springframework/boot/logging/logback/base.xml"/>
  <appender name="OTLP" class="io.opentelemetry.instrumentation.logback.appender.v1_0.OpenTelemetryAppender">
    <captureExperimentalAttributes>true</captureExperimentalAttributes>
    <captureMarkerAttribute>true</captureMarkerAttribute>
  </appender>
  <root level="INFO">
    <appender-ref ref="CONSOLE"/>
    <appender-ref ref="OTLP"/>
  </root>
</configuration>
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
$logstashConfig | Out-File -Encoding UTF8 -FilePath "$scriptDir\logstash.conf"
$dockerCompose | Out-File -Encoding UTF8 -FilePath "$scriptDir\docker-compose.yml"
$appProperties | Out-File -Encoding UTF8 -FilePath "$scriptDir\application.properties.example"
$logbackConfig | Out-File -Encoding UTF8 -FilePath "$scriptDir\logback-spring.xml.example"

# Display information
Write-Host "Archivos de configuración generados exitosamente." -ForegroundColor Green
Write-Host "`nLos siguientes archivos han sido creados:" -ForegroundColor Cyan
Write-Host "- otel-collector-config.yaml" -ForegroundColor White
Write-Host "- prometheus.yml" -ForegroundColor White
Write-Host "- logstash.conf" -ForegroundColor White
Write-Host "- docker-compose.yml" -ForegroundColor White
Write-Host "- application.properties.example" -ForegroundColor White
Write-Host "- logback-spring.xml.example" -ForegroundColor White

# Shutdown any existing containers
Write-Host "`nDesea detener y eliminar los contenedores existentes? (y/n)" -ForegroundColor Yellow
$cleanup = Read-Host
if ($cleanup -eq 'y') {
    Write-Host "Deteniendo contenedores existentes..." -ForegroundColor Cyan
    docker-compose down
}

# Prompt to start containers
Write-Host "`nDesea iniciar los contenedores ahora? (y/n)" -ForegroundColor Yellow
$startContainers = Read-Host
if ($startContainers -eq 'y') {
    # Start containers
    Write-Host "Iniciando contenedores..." -ForegroundColor Cyan
    docker-compose up -d

    # Function to check if MySQL is ready
    function Test-MySQLReady {
        $maxRetries = 30
        $retryInterval = 2
        $retryCount = 0

        Write-Host "Esperando que MySQL esté listo..." -ForegroundColor Cyan

        while ($retryCount -lt $maxRetries) {
            Start-Sleep -Seconds $retryInterval
            $retryCount++

            Write-Host "Intento $retryCount de $maxRetries..." -ForegroundColor Gray

            try {
                $status = docker exec futurex-mysql mysqladmin -u root -ptechbankRootPsw ping --silent
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "MySQL está listo después de $retryCount intentos!" -ForegroundColor Green
                    return $true
                }
            } catch {
                # Continuar en caso de error
            }

            # Check if container is still running
            $containerStatus = docker ps -f "name=futurex-mysql" --format "{{.Status}}"
            if (-not $containerStatus) {
                Write-Host "El contenedor MySQL no está ejecutándose!" -ForegroundColor Red
                docker logs futurex-mysql
                return $false
            }
        }

        Write-Host "MySQL no estuvo listo después de $maxRetries intentos." -ForegroundColor Red
        return $false
    }

    # Wait for MySQL to be ready
    $mysqlReady = Test-MySQLReady

    if ($mysqlReady) {
        Write-Host "MySQL está listo y en funcionamiento." -ForegroundColor Green
    }

    Write-Host "`nConfiguración completada! Servicios disponibles:" -ForegroundColor Green
    Write-Host "MySQL: localhost:3306" -ForegroundColor Cyan
    Write-Host "Jaeger UI: http://localhost:16686" -ForegroundColor Cyan
    Write-Host "OpenTelemetry Collector: localhost:4319 (gRPC), localhost:4320 (HTTP)" -ForegroundColor Cyan
    Write-Host "Elasticsearch: http://localhost:9200" -ForegroundColor Cyan
    Write-Host "Kibana: http://localhost:5601" -ForegroundColor Cyan
    Write-Host "Prometheus: http://localhost:9090" -ForegroundColor Cyan
    Write-Host "Grafana: http://localhost:3000 (admin/admin)" -ForegroundColor Cyan
    Write-Host "`nRecuerde actualizar las propiedades de sus aplicaciones Spring Boot según los ejemplos proporcionados." -ForegroundColor Yellow
} else {
    Write-Host "`nPara iniciar los contenedores más tarde, ejecute:" -ForegroundColor Cyan
    Write-Host "docker-compose up -d" -ForegroundColor White
}

Write-Host "`nPara configurar Grafana, agregue Prometheus como fuente de datos usando la URL:" -ForegroundColor Yellow
Write-Host "http://prometheus:9090" -ForegroundColor White