package com.futurex.services.FutureXCourseCatalog;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

@RestController
public class CatalogController {

    @Value("${course.service.url}")
    private String courseServiceUrl;

    private final RestTemplate restTemplate;

    public CatalogController(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    @RequestMapping("/")
    public String getCatalogHome() {
        String courseAppMessage = restTemplate.getForObject(courseServiceUrl, String.class);
        return "Welcome to FutureX Course Catalog " + courseAppMessage;
    }

    @RequestMapping("/catalog")
    public String getCatalog() {
        String courses = restTemplate.getForObject(courseServiceUrl + "/courses", String.class);
        return "Our courses are " + courses;
    }

    @RequestMapping("/firstcourse")
    public String getSpecificCourse() {
        Course course = restTemplate.getForObject(courseServiceUrl + "/1", Course.class);
        return "Our first course is " + course.getCoursename();
    }
}