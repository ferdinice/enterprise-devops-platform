# Jenkins Continuous Integration Pipeline

## 1. Purpose

Jenkins provides the Continuous Integration layer for the Pet Adoption application.

The application source and Jenkins pipeline are maintained in the separate:

```text
pet-adoption-devops
```

repository.

The infrastructure and GitOps desired state are maintained in:

```text
enterprise-devops-platform
```

This separation allows the application repository to focus on source code and CI while the platform repository manages infrastructure, Kubernetes desired state, observability, and environment promotion.

---

## 2. CI/CD Responsibility Boundary

Jenkins is responsible primarily for Continuous Integration and producing a deployable artifact.

ArgoCD is responsible for deployment reconciliation.

The relationship is:

```text
Application Git Repository
        |
        v
      Jenkins
        |
        +--> Build
        +--> Test
        +--> SonarQube
        +--> Archive WAR
        +--> Docker Build
        +--> Trivy Scan
        +--> Push to ECR
        +--> Verify ECR Image
        |
        v
Update DEV GitOps Manifest
        |
        v
enterprise-devops-platform
        |
        v
      ArgoCD
        |
        v
 Development Kubernetes Environment
```

Jenkins does not directly execute `kubectl apply` to deploy the Pet Adoption application.

Instead, it modifies the desired state stored in Git.

This provides a cleaner separation between CI and CD.

---

## 3. Pipeline Options

The Jenkins pipeline uses:

```groovy
timestamps()
disableConcurrentBuilds()
skipDefaultCheckout(true)
```

### timestamps

Adds timestamps to pipeline logs, making troubleshooting easier.

### disableConcurrentBuilds

Prevents multiple builds of the same pipeline from running simultaneously.

This reduces the chance that two builds attempt to update the GitOps repository at the same time.

### skipDefaultCheckout

Disables Jenkins' automatic checkout.

The pipeline performs source checkout explicitly in the dedicated Checkout stage.

---

## 4. Pipeline Environment

Important pipeline variables include:

```text
APPLICATION_NAME = pet-adoption

AWS_REGION = eu-west-3

ECR_REPOSITORY =
enterprise-devops-platform/pet-adoption

GITOPS_REPO_URL =
https://github.com/ferdinice/enterprise-devops-platform.git

GITOPS_BRANCH = main

GITOPS_PATH =
gitops/pet-adoption/overlays/dev/kustomization.yaml
```

The important architectural detail is that Jenkins updates only:

```text
overlays/dev
```

It does not automatically update Staging or Production.

Environment promotion is handled separately.

---

# Pipeline Stages

## 5. Checkout

The first pipeline stage checks out the application source:

```text
Checkout
```

The pipeline then retrieves the short Git commit SHA:

```bash
git rev-parse --short=7 HEAD
```

For example:

```text
4dad0b1
```

The commit SHA is combined with the Jenkins build number to create the immutable image tag:

```text
build-${BUILD_NUMBER}-${GIT_SHORT_SHA}
```

Example:

```text
build-2-4dad0b1
```

The complete ECR image reference is then generated.

Example:

```text
740994137090.dkr.ecr.eu-west-3.amazonaws.com/
enterprise-devops-platform/pet-adoption:
build-2-4dad0b1
```

This provides traceability from the deployed container back to:

* Jenkins build
* Git commit
* source-code revision

---

## 6. Verify Build Environment

The pipeline verifies that the Jenkins agent has the expected Java toolchain.

It executes:

```bash
java -version
javac -version
```

and displays:

```text
JAVA_HOME
```

The pipeline uses Java 17.

This stage fails early if Jenkins does not have the required build environment.

---

## 7. Build and Test

The application uses the Maven Wrapper.

The pipeline runs:

```bash
./mvnw clean package
```

This performs the Maven build and runs the project's configured tests.

The resulting application artifact is:

```text
target/spring-petclinic-2.4.2.war
```

A failure during Maven compilation or testing stops the pipeline because Jenkins shell steps return a failure when the command exits unsuccessfully.

---

# SonarQube

## 8. SonarQube Analysis

After the Maven build succeeds, Jenkins sends the project to SonarQube for static analysis.

The pipeline uses:

```groovy
withSonarQubeEnv('SonarQube')
```

and executes the Sonar Maven plugin.

The configured SonarQube project is:

```text
Project Key:
pet-adoption

Project Name:
Pet Adoption
```

SonarQube provides analysis relating to areas such as:

* code quality
* maintainability
* bugs
* code smells
* security findings
* duplication

depending on the SonarQube project configuration and ruleset.

---

## 9. Current Quality Gate Status

A Jenkins Quality Gate stage exists in the Jenkinsfile but is currently commented out.

The intended implementation is:

```groovy
timeout(time: 5, unit: 'MINUTES') {
    waitForQualityGate abortPipeline: true
}
```

This would allow Jenkins to wait for the SonarQube Quality Gate result and abort the pipeline if the gate fails.

However, this stage is not currently active.

Therefore the accurate current behaviour is:

```text
SonarQube analysis
        |
        v
Analysis result generated
        |
        v
Pipeline continues
```

rather than:

```text
SonarQube
        |
        v
Quality Gate
        |
     PASS/FAIL
        |
        v
Deployment gate
```

The Quality Gate should be treated as a future hardening step unless it is re-enabled and verified during the final live validation.

---

## 10. Why the Quality Gate Matters

When enabled, the Quality Gate can create a useful deployment-control boundary.

For example:

```text
Code committed
      |
      v
SonarQube analysis
      |
      v
Quality Gate
   /       \
PASS       FAIL
 |           |
 v           X
Continue    Stop
```

This prevents known unacceptable code-quality conditions from progressing further through the delivery process.

The current project demonstrates SonarQube integration, while automatic Quality Gate enforcement remains disabled.

---

# Artifact Validation

## 11. Verify Artifact

After analysis, Jenkins verifies that the expected WAR file exists:

```bash
ls -lh target/spring-petclinic-2.4.2.war
```

This ensures that later container stages do not proceed without the expected application artifact.

---

## 12. Archive Artifact

Jenkins archives the WAR file using:

```groovy
archiveArtifacts(
    artifacts: 'target/spring-petclinic-2.4.2.war',
    fingerprint: true
)
```

Archiving provides build-level evidence of the generated application package.

Artifact fingerprinting improves traceability inside Jenkins.

---

# Container Build

## 13. Build Docker Image

Jenkins builds the application container with:

```bash
docker build \
  -t ${APPLICATION_NAME}:${IMAGE_TAG} \
  .
```

An example local image is:

```text
pet-adoption:build-2-4dad0b1
```

The image tag was generated earlier from the Jenkins build number and Git commit SHA.

---

# Container Security

## 14. Trivy Image Scan

After the image is built, Jenkins scans it using Trivy.

The implemented command is:

```bash
trivy image \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code 0 \
  --no-progress \
  ${APPLICATION_NAME}:${IMAGE_TAG}
```

The scan focuses on:

```text
HIGH
CRITICAL
```

severity vulnerabilities.

`--ignore-unfixed` suppresses vulnerabilities for which no fix is currently available.

---

## 15. Current Trivy Enforcement Behaviour

The pipeline currently uses:

```text
--exit-code 0
```

This is important.

It means Trivy reports vulnerabilities but does not fail the Jenkins stage solely because HIGH or CRITICAL vulnerabilities were found.

Therefore the current model is:

```text
Docker Image
     |
     v
Trivy Scan
     |
     v
Findings reported
     |
     v
Pipeline continues
```

This provides vulnerability visibility but is not currently a blocking security gate.

A stricter production policy could change the behaviour so selected vulnerabilities return a non-zero exit code and stop the pipeline.

---

# Amazon ECR

## 16. ECR Authentication

Jenkins authenticates to Amazon ECR using AWS CLI:

```bash
aws ecr get-login-password
```

The generated password is passed to Docker through standard input.

The Jenkins EC2 instance uses its AWS IAM role for ECR permissions rather than storing static AWS access keys directly inside the Jenkinsfile.

---

## 17. Image Tagging and Push

The local image is tagged with the complete ECR address:

```text
local image
pet-adoption:build-2-4dad0b1
        |
        v
ECR image
740994137090.dkr.ecr.eu-west-3.amazonaws.com/
enterprise-devops-platform/pet-adoption:
build-2-4dad0b1
```

Jenkins then executes:

```bash
docker push ${ECR_IMAGE}
```

The ECR repository itself is configured as immutable through Terraform.

This prevents an existing release tag from silently being overwritten with different image content.

---

## 18. Verify Image in ECR

The pipeline does not assume that a successful `docker push` is sufficient evidence.

It performs an AWS API verification using:

```bash
aws ecr describe-images \
  --repository-name ${ECR_REPOSITORY} \
  --image-ids imageTag=${IMAGE_TAG}
```

This confirms that the expected image tag exists in ECR before the GitOps desired state is modified.

The flow is therefore:

```text
Build Image
    |
    v
Push Image
    |
    v
Verify Image Exists in ECR
    |
    v
Update GitOps
```

This is safer than updating Kubernetes desired state before proving the artifact exists in the registry.

---

# GitOps Update

## 19. Jenkins GitOps Responsibility

After the ECR image has been verified, Jenkins updates the Development environment desired state.

The target file is:

```text
gitops/pet-adoption/overlays/dev/kustomization.yaml
```

inside:

```text
enterprise-devops-platform
```

Jenkins does not directly alter the Staging or Production overlays.

---

## 20. GitHub Credentials

The GitOps update uses a Jenkins credential:

```text
github-gitops-credentials
```

The pipeline exposes the credential temporarily through:

```text
GIT_USERNAME
GIT_TOKEN
```

The credential is not hard-coded into the Jenkinsfile.

---

## 21. GitOps Clone

Jenkins clones:

```text
https://github.com/ferdinice/
enterprise-devops-platform.git
```

from the:

```text
main
```

branch into a temporary local directory:

```text
platform-gitops
```

---

## 22. Jenkins Git Identity

Jenkins configures its Git commit identity as:

```text
jenkins
jenkins@enterprise-devops.local
```

This makes automated GitOps commits distinguishable from human commits.

---

## 23. Updating the Development Image

Jenkins modifies the Kustomize image tag using:

```bash
sed -i \
  "s/newTag: .*/newTag: ${IMAGE_TAG}/"
```

The change affects only:

```text
gitops/pet-adoption/overlays/dev/kustomization.yaml
```

For example:

```text
Before:
newTag: build-2-4dad0b1

After:
newTag: build-9-a1b2c3d
```

---

## 24. Avoiding Empty Commits

Before committing, Jenkins checks:

```bash
git diff --quiet
```

If the GitOps repository already references the required image tag, the pipeline exits the GitOps update stage without creating an unnecessary commit.

---

## 25. GitOps Commit

When a change exists, Jenkins commits it using:

```text
Deploy pet-adoption ${IMAGE_TAG}
```

An example is:

```text
Deploy pet-adoption build-2-4dad0b1
```

Jenkins then pushes the update to:

```text
origin/main
```

---

# Continuous Delivery Boundary

## 26. ArgoCD Takes Over

After Jenkins pushes the Development manifest change, Jenkins' deployment responsibility ends.

ArgoCD detects the change in the platform repository.

The flow becomes:

```text
Jenkins
   |
   | Git commit
   v
enterprise-devops-platform
   |
   | detected by
   v
ArgoCD
   |
   v
pet-adoption-dev
   |
   v
Kubernetes
```

This establishes a clear CI/CD boundary:

```text
Jenkins = CI + desired-state update

ArgoCD = Kubernetes deployment reconciliation
```

---

# Environment Promotion

## 27. Jenkins Does Not Deploy Directly to Production

The Jenkins pipeline is deliberately configured to modify only Development.

It does not automatically write:

```text
gitops/pet-adoption/overlays/staging
```

or:

```text
gitops/pet-adoption/overlays/prod
```

This prevents every successful build from immediately becoming a Production deployment.

---

## 28. Promotion Model

After Development validation, the same immutable image can be promoted using:

```text
scripts/promote-to-staging.sh
```

and later:

```text
scripts/promote-to-prod.sh
```

The model is:

```text
Jenkins Build
     |
     v
DEV
     |
     | validation
     v
STAGING
     |
     | validation + approval
     v
PRODUCTION
```

The image is not rebuilt between environments.

---

# Pipeline Failure Behaviour

## 29. Maven Failure

If compilation or automated tests fail:

```text
Build and Test
     |
     X
Pipeline stops
```

No Docker image is pushed and no GitOps update occurs.

---

## 30. SonarQube Failure

If the SonarQube scanner command itself fails, the stage can fail because Jenkins is executing it through a shell step.

However, a completed SonarQube analysis that produces a failing Quality Gate does not currently stop the pipeline because the Quality Gate stage is disabled.

This distinction is important.

---

## 31. Trivy Findings

HIGH or CRITICAL findings currently do not automatically fail the build because Trivy runs with:

```text
--exit-code 0
```

The findings provide security visibility, but enforcement is not yet enabled.

---

## 32. ECR Push Failure

If ECR authentication or `docker push` fails, the pipeline stops before modifying the GitOps repository.

---

## 33. ECR Verification Failure

If AWS cannot find the expected image tag after the push, the verification stage fails and the GitOps desired state is not updated.

This protects Kubernetes from being told to deploy an image Jenkins cannot confirm exists.

---

## 34. GitOps Push Failure

If Jenkins cannot clone, commit, or push to the platform repository, ArgoCD receives no new desired-state change.

The already running application remains at the previous GitOps version.

---

# Post Actions

## 35. Success

When the pipeline completes successfully, Jenkins reports the pushed ECR image.

---

## 36. Failure

When a stage fails, Jenkins reports that the pipeline failed and directs the engineer to the Console Output.

---

## 37. Always

Regardless of result, Jenkins reports the final build status.

This provides a consistent end-of-build log message.

---

# Current Security and Quality Posture

## 38. Implemented Controls

The pipeline currently provides:

* Maven build validation
* automated project tests
* SonarQube static analysis
* WAR artifact verification
* Jenkins artifact fingerprinting
* Trivy HIGH/CRITICAL vulnerability visibility
* IAM-based ECR authentication
* immutable ECR image tags
* explicit ECR image verification
* GitHub credentials through Jenkins Credentials
* GitOps-based Kubernetes delivery
* environment separation
* immutable artifact promotion

---

## 39. Current Non-Blocking Controls

Two controls are intentionally documented as non-blocking in the current implementation:

### SonarQube Quality Gate

The stage exists but is commented out.

### Trivy Vulnerability Threshold

The scan uses:

```text
--exit-code 0
```

so findings are reported rather than enforced.

These should not be represented as active deployment gates until they are enabled and successfully validated.

---

## 40. Potential Hardening

A stronger production pipeline could later enforce:

```text
SonarQube Quality Gate failure
            |
            X
          STOP
```

and:

```text
Disallowed HIGH/CRITICAL vulnerability
            |
            X
          STOP
```

The exact security threshold should be chosen deliberately rather than blindly blocking every vulnerability regardless of exploitability or available fixes.

---

# Pipeline Summary

## 41. Complete Pipeline Flow

The current implemented pipeline is:

```text
Checkout
   |
   v
Generate Immutable Image Tag
   |
   v
Verify Java Environment
   |
   v
Maven Build + Tests
   |
   v
SonarQube Analysis
   |
   v
Verify WAR
   |
   v
Archive WAR
   |
   v
Docker Build
   |
   v
Trivy Scan
   |
   v
Authenticate to ECR
   |
   v
Push Immutable Image
   |
   v
Verify Image in ECR
   |
   v
Update DEV GitOps Manifest
   |
   v
Git Commit + Push
   |
   v
ArgoCD Detects Change
   |
   v
Development Deployment
```

The pipeline therefore connects application source code to a traceable container artifact and then to GitOps-driven Kubernetes delivery without Jenkins directly controlling the cluster.
