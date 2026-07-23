# Pet Adoption Application Source

## Purpose

The Enterprise DevOps Platform does not develop the Java application itself.

The application source code is provided by the development team, while this repository contains the DevOps tools and configurations required to build, test, secure, deploy, and monitor the application.

---

## Developer Application Repository

The Java application source is located in the following repository:

https://github.com/CloudHight/usteam

The application is used as the workload deployed by the Enterprise DevOps Platform.

---

## Application Technology

The application uses:

- Java
- Spring Boot
- Maven
- Thymeleaf
- H2 or MySQL database
- Spring Boot Actuator
- Port 8080

Maven will be used to compile, test, and package the application.

---

## Responsibility Separation

### Development Team Responsibilities

The development team is responsible for:

- Writing the Java application code
- Fixing application defects
- Creating application features
- Maintaining application dependencies
- Writing unit tests
- Updating the application repository

### DevOps Team Responsibilities

The DevOps platform is responsible for:

- Checking out the application source code
- Building the application with Maven
- Running automated tests
- Performing code-quality analysis
- Performing dependency-security scans
- Building the Docker image
- Scanning the container image
- Publishing the image to Amazon ECR
- Deploying the application to Kubernetes
- Provisioning AWS infrastructure
- Managing deployment configuration
- Monitoring application and infrastructure health

---

## Integration Flow

```
Developer Repository
        │
        ▼
Jenkins Checkout
        │
        ▼
Maven Build and Test
        │
        ▼
Docker Image Build
        │
        ▼
Amazon ECR
        │
        ▼
Kubernetes Deployment
```

---

## Source Code Handling

The application source code will not be copied permanently into this repository.

Instead, Jenkins will clone the developer repository during the pipeline execution.

This keeps the application code and DevOps platform separated and reflects how development and DevOps teams work in a professional environment.

---

## Application Changes

Changes to the Java application should normally be made in the developer repository.

Changes to infrastructure, deployment automation, Kubernetes, monitoring, and security should be made in the Enterprise DevOps Platform repository.

This separation makes ownership and responsibilities clear.