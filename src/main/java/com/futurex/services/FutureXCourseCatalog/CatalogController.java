package com.futurex.services.FutureXCourseCatalog;

import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

@RestController
public class CatalogController {

    private static final Logger logger = LoggerFactory.getLogger(CatalogController.class);

    @Value("${course.service.url}")
    private String courseServiceUrl;

    private final RestTemplate restTemplate;
    private final Tracer tracer;
    private final MeterRegistry meterRegistry;

    @Autowired
    public CatalogController(RestTemplate restTemplate, Tracer tracer, MeterRegistry
            meterRegistry) {
        this.restTemplate = restTemplate;
        this.tracer = tracer;
        this.meterRegistry = meterRegistry;
    }

    @RequestMapping("/")
    public String getCatalogHome() {
        logger.info("Received request for catalog home");
        Timer.Sample timer = Timer.start(meterRegistry);
        Span span = tracer.spanBuilder("getCatalogHome").startSpan();
        try {
            String courseAppMessage = restTemplate.getForObject(courseServiceUrl, String.class);
            String response = "Welcome to FutureX Course Catalog " + courseAppMessage;
            logger.info("Returning catalog home response");
            return response;
        } catch (Exception e) {
            logger.error("Error in getCatalogHome", e);
            throw e;
        } finally {
            span.end();
            timer.stop(meterRegistry.timer("catalog.home.request"));
        }
    }

    @RequestMapping("/catalog")
    public String getCatalog() {
        logger.info("Received request for course catalog");
        Timer.Sample timer = Timer.start(meterRegistry);
        Span span = tracer.spanBuilder("getCatalog").startSpan();
        try {
            String courses = restTemplate.getForObject(courseServiceUrl + "/courses",
                    String.class);
            String response = "Our courses are " + courses;
            logger.info("Returning course catalog");
            return response;
        } catch (Exception e) {
            logger.error("Error in getCatalog", e);
            throw e;
        } finally {
            span.end();
            // Cambiar el nombre de la métrica para que coincida con la consulta Prometheus del taller
            timer.stop(meterRegistry.timer("catalog_courses_request_seconds",
                    "endpoint", "/catalog"));
        }
    }

    @RequestMapping("/firstcourse")
    public String getSpecificCourse() {
        logger.info("Received request for first course");
        Timer.Sample timer = Timer.start(meterRegistry);
        Span span = tracer.spanBuilder("getSpecificCourse").startSpan();
        try {
            Course course = restTemplate.getForObject(courseServiceUrl + "/1", Course.class);
            String response = "Our first course is " + course.getCoursename();
            logger.info("Returning first course information");
            return response;
        } catch (Exception e) {
            logger.error("Error in getSpecificCourse", e);
            throw e;
        } finally {
            span.end();
            timer.stop(meterRegistry.timer("catalog.firstcourse.request"));
        }
    }

    /**
     * Endpoint para generar errores para la tarea de ELK
     */
    @RequestMapping("/error-test")
    public String testError() {
        logger.error("Este es un error de prueba en el servicio de catálogo");

        // Span específico para el error
        Span span = tracer.spanBuilder("testError").startSpan();
        span.setAttribute("service.name", "fx-catalog-service");
        span.setAttribute("log.level", "ERROR");

        try {
            // Generar algunos errores adicionales con diferentes mensajes
            for (int i = 0; i < 3; i++) {
                logger.error("Error #{} en fx-catalog-service: Simulación de error para el taller de monitoreo", i);
            }

            return "Errores generados para la tarea de ELK";
        } finally {
            span.end();
        }
    }

    /**
     * Endpoint para probar la visualización de métricas
     */
    @RequestMapping("/stress-test")
    public String stressTest() {
        logger.info("Inicio de prueba de estrés");
        Timer.Sample timer = Timer.start(meterRegistry);
        Span span = tracer.spanBuilder("stressTest").startSpan();

        try {
            // Generar carga de CPU
            long result = 0;
            for (int i = 0; i < 10_000_000; i++) {
                result += i;
            }

            // Generar algunos errores ocasionales para el dashboard
            if (Math.random() < 0.3) {
                logger.error("Error aleatorio durante la prueba de estrés");
                throw new RuntimeException("Error simulado durante la prueba de estrés");
            }

            logger.info("Prueba de estrés completada: {}", result);
            return "Prueba de estrés completada con resultado: " + result;
        } catch (Exception e) {
            logger.error("Error en la prueba de estrés", e);
            throw e;
        } finally {
            span.end();
            timer.stop(meterRegistry.timer("catalog.stress.request"));
        }
    }
}