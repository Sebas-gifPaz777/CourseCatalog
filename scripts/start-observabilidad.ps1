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
      
  # Configuración para recopilar métricas de Spring Boot
  - job_name: 'spring-boot'
    scrape_interval: 5s
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['host.docker.internal:8001', 'host.docker.internal:8002']
    
  # Configuración para monitorear los contenedores Docker
  - job_name: 'docker'
    scrape_interval: 5s
    static_configs:
      - targets: ['host.docker.internal:9323']
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

# Docker Compose con todos los servicios necesarios - Modificado para evitar conflicto de puertos
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
      - "16686:16686"  # Web UI
      - "14250:14250"  # gRPC for Jaeger-to-Jaeger communication
      # Comentamos estos puertos para evitar conflictos con el colector OpenTelemetry
      # - "4317:4317"  # OTLP gRPC receiver
      # - "4318:4318"  # OTLP HTTP receiver
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
      - "4317:4317"  # OTLP gRPC receiver - Cambiado para evitar conflictos
      - "4318:4318"  # OTLP HTTP receiver - Cambiado para evitar conflictos
      - "8889:8889"  # Prometheus exporter
    networks:
      - futurex-network

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.14.0
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
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
    image: prom/prometheus:v2.45.0
    container_name: prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    networks:
      - futurex-network

  grafana:
    image: grafana/grafana:10.0.3
    container_name: grafana
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/var/lib/grafana/dashboards
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
    depends_on:
      - prometheus
    networks:
      - futurex-network

volumes:
  mysql-data:
  prometheus-data:
  grafana-data:

networks:
  futurex-network:
    driver: bridge
"@

# Ejemplo de application.properties actualizado para microservicios Spring Boot
$appProperties = @"
# MySQL Database Configuration
spring.datasource.url=jdbc:mysql://localhost:3306/futurex_course_db?createDatabaseIfNotExist=true
spring.datasource.username=root
spring.datasource.password=techbankRootPsw
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

# JPA/Hibernate properties
spring.jpa.database-platform=org.hibernate.dialect.MySQLDialect
spring.jpa.show-sql=true
spring.jpa.hibernate.ddl-auto=update

# Application name and port
spring.application.name=fx-course-service
server.port=8001
course.service.url=http://localhost:8001
spring.main.allow-bean-definition-overriding=true

# Configuración precisa de OpenTelemetry
otel.exporter.otlp.endpoint=http://localhost:4317
otel.exporter.otlp.protocol=grpc
otel.sdk.disabled=false

# Configuración de exportadores
otel.traces.exporter=otlp
otel.metrics.exporter=otlp
otel.logs.exporter=otlp

# Micrometer específico para OTLP - necesario para evitar los errores
management.otlp.metrics.export.url=http://localhost:4317
management.otlp.metrics.export.step=10s
management.otlp.metrics.export.aggregation-temporality=CUMULATIVE
management.otlp.metrics.export.resource-attributes.service.name=\${spring.application.name}

# Configuración de métricas y trazas
management.tracing.sampling.probability=1.0

# Habilitar la exportación directa de métricas Prometheus
management.endpoints.web.exposure.include=health,info,prometheus
management.endpoint.health.show-details=always
management.prometheus.metrics.export.enabled=true
management.metrics.tags.application=\${spring.application.name}
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

# Crear un dashboard preconfigrado para Grafana
$grafanaDashboardJson = @"
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "type": "dashboard"
      }
    ]
  },
  "editable": true,
  "gnetId": null,
  "graphTooltip": 0,
  "id": 1,
  "links": [],
  "panels": [
    {
      "collapsed": false,
      "datasource": null,
      "gridPos": {
        "h": 1,
        "w": 24,
        "x": 0,
        "y": 0
      },
      "id": 12,
      "panels": [],
      "title": "Solicitudes y Errores",
      "type": "row"
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "Prometheus",
      "description": "Número de solicitudes por minuto para cada endpoint",
      "fieldConfig": {
        "defaults": {
          "links": []
        },
        "overrides": []
      },
      "fill": 1,
      "fillGradient": 0,
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 1
      },
      "hiddenSeries": false,
      "id": 2,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pointradius": 2,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "sum by (uri) (rate(http_server_requests_seconds_count{application=~\"fx-.*-service\"}[1m])) * 60",
          "interval": "",
          "legendFormat": "{{uri}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "Solicitudes por Minuto por Endpoint",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "short",
          "label": "Solicitudes/min",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "datasource": "Prometheus",
      "description": "Porcentaje de errores vs solicitudes exitosas en las últimas 6 horas",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "mappings": [],
          "max": 100,
          "min": 0,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "yellow",
                "value": 1
              },
              {
                "color": "orange",
                "value": 5
              },
              {
                "color": "red",
                "value": 10
              }
            ]
          },
          "unit": "percent"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 12,
        "y": 1
      },
      "id": 8,
      "options": {
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "showThresholdLabels": false,
        "showThresholdMarkers": true,
        "text": {}
      },
      "pluginVersion": "8.1.2",
      "targets": [
        {
          "expr": "(sum(rate(http_server_requests_seconds_count{application=~\"fx-.*-service\", status=~\"5..\"}[6h])) / sum(rate(http_server_requests_seconds_count{application=~\"fx-.*-service\"}[6h]))) * 100",
          "interval": "",
          "legendFormat": "Tasa de Error",
          "refId": "A"
        }
      ],
      "title": "Porcentaje de Errores (Últimas 6 horas)",
      "type": "gauge"
    },
    {
      "collapsed": false,
      "datasource": null,
      "gridPos": {
        "h": 1,
        "w": 24,
        "x": 0,
        "y": 9
      },
      "id": 10,
      "panels": [],
      "title": "Uso de Recursos",
      "type": "row"
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "Prometheus",
      "description": "Uso de CPU para los servicios",
      "fieldConfig": {
        "defaults": {
          "links": []
        },
        "overrides": []
      },
      "fill": 1,
      "fillGradient": 0,
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 10
      },
      "hiddenSeries": false,
      "id": 4,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pointradius": 2,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "process_cpu_usage{application=~\"fx-.*-service\"}",
          "interval": "",
          "legendFormat": "{{application}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "Uso de CPU",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "percentunit",
          "label": "CPU Usage",
          "logBase": 1,
          "max": "1",
          "min": "0",
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "Prometheus",
      "description": "Uso de memoria de los servicios",
      "fieldConfig": {
        "defaults": {
          "links": []
        },
        "overrides": []
      },
      "fill": 1,
      "fillGradient": 0,
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 12,
        "y": 10
      },
      "hiddenSeries": false,
      "id": 6,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pointradius": 2,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "sum by (application) (jvm_memory_used_bytes{application=~\"fx-.*-service\", area=\"heap\"}) / sum by (application) (jvm_memory_max_bytes{application=~\"fx-.*-service\", area=\"heap\"}) * 100",
          "interval": "",
          "legendFormat": "{{application}}",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "Uso de Memoria Heap (%)",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "percent",
          "label": "Memoria Usada",
          "logBase": 1,
          "max": "100",
          "min": "0",
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    }
  ],
  "refresh": "10s",
  "schemaVersion": 30,
  "style": "dark",
  "tags": ["spring-boot", "microservices"],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-1h",
    "to": "now"
  },
  "timepicker": {
    "refresh_intervals": [
      "5s",
      "10s",
      "30s",
      "1m",
      "5m",
      "15m",
      "30m",
      "1h",
      "2h",
      "1d"
    ]
  },
  "timezone": "",
  "title": "FutureX Microservices Dashboard",
  "uid": "futurex",
  "version": 1
}
"@

# Configuración de provisioning para Grafana
$datasourceConfig = @"
apiVersion: 1

datasources:
- name: Prometheus
  type: prometheus
  access: proxy
  url: http://prometheus:9090
  isDefault: true
"@

$dashboardsConfig = @"
apiVersion: 1

providers:
- name: 'default'
  orgId: 1
  folder: ''
  type: file
  disableDeletion: false
  updateIntervalSeconds: 10
  allowUiUpdates: true
  options:
    path: /var/lib/grafana/dashboards
"@

# Guardar archivos en el mismo directorio que el script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

# Crear directorios necesarios
$directories = @(
    "$scriptDir\logs",
    "$scriptDir\grafana\provisioning\datasources",
    "$scriptDir\grafana\provisioning\dashboards",
    "$scriptDir\grafana\dashboards"
)

foreach ($dir in $directories) {
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Guardar todos los archivos de configuración
$otelConfig | Out-File -Encoding UTF8 -FilePath "$scriptDir\otel-collector-config.yaml"
$prometheusConfig | Out-File -Encoding UTF8 -FilePath "$scriptDir\prometheus.yml"
$logstashConfig | Out-File -Encoding UTF8 -FilePath "$scriptDir\logstash.conf"
$dockerCompose | Out-File -Encoding UTF8 -FilePath "$scriptDir\docker-compose.yml"
$appProperties | Out-File -Encoding UTF8 -FilePath "$scriptDir\application.properties.example"
$logbackConfig | Out-File -Encoding UTF8 -FilePath "$scriptDir\logback-spring.xml.example"

# Guardar archivos de Grafana
$grafanaDashboardJson | Out-File -Encoding UTF8 -FilePath "$scriptDir\grafana\dashboards\futurex-dashboard.json"
$datasourceConfig | Out-File -Encoding UTF8 -FilePath "$scriptDir\grafana\provisioning\datasources\prometheus.yml"
$dashboardsConfig | Out-File -Encoding UTF8 -FilePath "$scriptDir\grafana\provisioning\dashboards\default.yml"

# Display information
Write-Host "Archivos de configuración generados exitosamente." -ForegroundColor Green
Write-Host "`nLos siguientes archivos han sido creados:" -ForegroundColor Cyan
Write-Host "- otel-collector-config.yaml" -ForegroundColor White
Write-Host "- prometheus.yml" -ForegroundColor White
Write-Host "- logstash.conf" -ForegroundColor White
Write-Host "- docker-compose.yml" -ForegroundColor White
Write-Host "- application.properties.example" -ForegroundColor White
Write-Host "- logback-spring.xml.example" -ForegroundColor White
Write-Host "- grafana/dashboards/futurex-dashboard.json" -ForegroundColor White
Write-Host "- grafana/provisioning/datasources/prometheus.yml" -ForegroundColor White
Write-Host "- grafana/provisioning/dashboards/default.yml" -ForegroundColor White

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
    Write-Host "OpenTelemetry Collector: localhost:4317 (gRPC), localhost:4318 (HTTP)" -ForegroundColor Cyan
    Write-Host "Elasticsearch: http://localhost:9200" -ForegroundColor Cyan
    Write-Host "Kibana: http://localhost:5601" -ForegroundColor Cyan
    Write-Host "Prometheus: http://localhost:9090" -ForegroundColor Cyan
    Write-Host "Grafana: http://localhost:3000 (admin/admin)" -ForegroundColor Cyan
    Write-Host "`nRecuerde actualizar las propiedades de sus aplicaciones Spring Boot según los ejemplos proporcionados." -ForegroundColor Yellow

    Write-Host "`nSe ha preconfigurado Grafana con un dashboard que cumple con los requisitos específicos:" -ForegroundColor Green
    Write-Host "1. Solicitudes por minuto para cada endpoint" -ForegroundColor White
    Write-Host "2. Uso de CPU y memoria de los servicios" -ForegroundColor White
    Write-Host "3. Porcentaje de errores vs solicitudes exitosas en las últimas 6 horas" -ForegroundColor White

    Write-Host "`nPuede acceder al dashboard en:" -ForegroundColor Green
    Write-Host "http://localhost:3000/dashboards" -ForegroundColor White
} else {
    Write-Host "`nPara iniciar los contenedores más tarde, ejecute:" -ForegroundColor Cyan
    Write-Host "docker-compose up -d" -ForegroundColor White
}