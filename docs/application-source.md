# Pet Adoption Application Source

## Purpose

The Enterprise DevOps Platform focuses on the DevOps lifecycle rather than developing the Pet Adoption Java application itself.

The application workload originated from the developer source repository:

https://github.com/CloudHight/usteam

A separate application/CI repository is used for the implemented DevOps workflow:

https://github.com/ferdinice/pet-adoption-devops

This separation keeps application source and CI configuration distinct from the infrastructure and GitOps platform repository.

---

## Repository Responsibilities

### pet-adoption-devops

Contains the application source and CI-related files used by Jenkins.

Responsibilities include:

- Java application source
- Maven build configuration
- automated tests
- Dockerfile
- Jenkinsfile
- SonarQube analysis integration
- Trivy image scanning
- ECR image publishing
- Development GitOps update

Jenkins uses:

```text
checkout scm