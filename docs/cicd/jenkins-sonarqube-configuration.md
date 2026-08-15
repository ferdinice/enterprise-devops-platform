# Jenkins and SonarQube Post-Provisioning Configuration

## 1. Purpose

Terraform provisions the Jenkins and SonarQube EC2 instances and installs the required host-level software.

However, a newly created instance still requires application-level configuration before the complete CI/CD workflow can run.

This document describes the post-provisioning configuration required for:

- Jenkins initial setup
- Jenkins administrator access
- SonarQube initial setup
- SonarQube authentication token generation
- Jenkins credential management
- Jenkins-to-SonarQube integration
- GitHub GitOps credentials
- Pet Adoption Jenkins Pipeline configuration
- Jenkins host prerequisite verification

Sensitive passwords and tokens must never be committed to Git.

---

# 2. Jenkins Initial Setup

After Terraform creates the Jenkins EC2 instance, Jenkins is available on port `8080`.

Example:

```text
http://<JENKINS_PUBLIC_IP>:8080
```

A fresh installation displays:

```text
Unlock Jenkins
```

Jenkins generates an initial administrator password and stores it on the server at:

```text
/var/lib/jenkins/secrets/initialAdminPassword
```

The password must be retrieved from the EC2 instance and entered into the Jenkins web interface.

---

# 3. Retrieving the Jenkins Initial Administrator Password

The project supports three practical methods for accessing the Jenkins EC2 instance and retrieving the initial password.

## Method 1 — AWS CLI and SSM Session Manager

This was the primary interactive method used during platform validation.

Start an SSM session:

```bash
aws ssm start-session \
  --target <JENKINS_INSTANCE_ID> \
  --region eu-west-3 \
  --profile personal-devops
```

Once connected:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Copy the password directly into the Jenkins **Unlock Jenkins** page.

Exit the session:

```bash
exit
```

AWS Systems Manager is preferred over exposing SSH for routine administration.

---

## Method 2 — AWS Management Console

The same instance can be accessed through the AWS Management Console.

1. Sign in to AWS.
2. Open **EC2**.
3. Select **Instances**.
4. Select the Jenkins instance.
5. Click **Connect**.
6. Select **Session Manager**.
7. Click **Connect**.
8. Run:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

9. Copy the password.
10. Enter it into the Jenkins **Unlock Jenkins** page.

This method also uses AWS Systems Manager but provides a browser-based terminal.

---

## Method 3 — Systems Manager Run Command Using Terraform Output

This method does not require an interactive terminal.

Move into the Terraform compute module:

```bash
cd /c/DevOps-Lab/enterprise-devops-platform/terraform/compute
```

Retrieve the Jenkins instance ID dynamically:

```bash
INSTANCE_ID=$(terraform output -raw jenkins_instance_id)
```

Send the password retrieval command:

```bash
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo cat /var/lib/jenkins/secrets/initialAdminPassword"]' \
  --region eu-west-3 \
  --profile personal-devops \
  --query "Command.CommandId" \
  --output text)
```

Wait for execution:

```bash
sleep 5
```

Retrieve the result:

```bash
AWS_PAGER="" aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region eu-west-3 \
  --profile personal-devops \
  --query "[Status,StandardOutputContent,StandardErrorContent]" \
  --output text
```

A successful command returns the Jenkins initial administrator password.

The password must not be copied into project documentation or committed to Git.

---

# 4. Complete Jenkins Setup Wizard

After entering the initial administrator password:

1. Continue through the Jenkins setup wizard.
2. Install the required/recommended Jenkins plugins.
3. Create the Jenkins administrator account if requested.
4. Confirm the Jenkins URL.
5. Complete the setup wizard.
6. Log in to the Jenkins dashboard.

Additional plugins required by this project must also be installed, including the SonarQube Jenkins integration.

Navigate to:

```text
Manage Jenkins
→ Plugins
→ Available plugins
```

Search for:

```text
SonarQube Scanner for Jenkins
```

Install the plugin.

---

# 5. SonarQube Initial Setup

The SonarQube server is provisioned separately by Terraform.

Access it using:

```text
http://<SONARQUBE_PUBLIC_IP>:9000
```

Complete the initial SonarQube login and administrator setup.

The SonarQube server provides static code analysis for the Pet Adoption application.

The Jenkins pipeline contains:

```groovy
withSonarQubeEnv('SonarQube') {
    sh '''
        ./mvnw org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
          -Dsonar.projectKey=pet-adoption \
          -Dsonar.projectName="Pet Adoption"
    '''
}
```

Jenkins therefore requires authentication credentials for SonarQube.

---

# 6. Generate the SonarQube Authentication Token

Do not use the SonarQube administrator password directly inside Jenkins.

Instead, create an authentication token.

Log in to SonarQube and navigate to the user account security/token configuration.

A typical navigation path is:

```text
User Profile
→ My Account
→ Security
```

Locate the token generation section.

Create a token with a descriptive name such as:

```text
jenkins-pet-adoption
```

Generate the token.

SonarQube displays the generated token after creation.

Copy it immediately and store it temporarily in a secure location.

The token must never be:

- committed to Git
- stored in the Jenkinsfile
- stored in Terraform source
- stored in Markdown documentation
- pasted into application configuration
- exposed in screenshots or logs

The token will be stored securely using Jenkins Credentials.

---

# 7. Store the SonarQube Token in Jenkins

Navigate to:

```text
Manage Jenkins
→ Credentials
→ System
→ Global credentials
→ Add Credentials
```

Configure:

```text
Kind:
Secret text

Secret:
<SONARQUBE_TOKEN>

ID:
sonarqube-token

Description:
SonarQube token for Pet Adoption CI
```

Save the credential.

The actual token remains managed by Jenkins rather than being exposed in the Jenkinsfile.

---

# 8. Configure the SonarQube Server in Jenkins

Navigate to:

```text
Manage Jenkins
→ System
→ SonarQube servers
```

Add/configure the SonarQube server.

Use:

```text
Name:
SonarQube

Server URL:
http://<SONARQUBE_PUBLIC_IP>:9000

Server authentication token:
sonarqube-token
```

Save the Jenkins configuration.

The name:

```text
SonarQube
```

must match the Jenkinsfile:

```groovy
withSonarQubeEnv('SonarQube')
```

A mismatch will cause the SonarQube pipeline stage to fail.

---

# 9. SonarQube Quality Gate Status

The pipeline contains a Quality Gate stage using:

```groovy
waitForQualityGate abortPipeline: true
```

However, this stage is currently disabled.

The reason is that the SonarQube-to-Jenkins webhook required for the asynchronous Quality Gate callback has not yet been fully configured and validated.

Therefore the current implementation performs:

```text
Source Code
     |
     v
SonarQube Analysis
     |
     v
Analysis Results Available in SonarQube
```

but does not currently block the complete pipeline based on the Quality Gate result.

Enabling and validating the SonarQube webhook and blocking Quality Gate is recorded as a future CI/CD hardening improvement.

---

# 10. Configure GitHub Credentials for GitOps Updates

The Jenkins pipeline updates the GitOps desired state after successfully publishing a container image.

The Jenkinsfile references:

```groovy
withCredentials([
    usernamePassword(
        credentialsId: 'github-gitops-credentials',
        usernameVariable: 'GIT_USERNAME',
        passwordVariable: 'GIT_TOKEN'
    )
])
```

Therefore Jenkins requires a credential with the exact ID:

```text
github-gitops-credentials
```

Navigate to:

```text
Manage Jenkins
→ Credentials
→ System
→ Global credentials
→ Add Credentials
```

Configure:

```text
Kind:
Username with password

Username:
<GITHUB_USERNAME>

Password:
<GITHUB_PERSONAL_ACCESS_TOKEN>

ID:
github-gitops-credentials

Description:
GitHub credentials for Jenkins GitOps updates
```

The password field contains a GitHub Personal Access Token, not the normal GitHub account password.

The token must have sufficient repository permissions to update the GitOps manifest in the platform repository.

---

# 11. Jenkins Pipeline Job Configuration

Create the application CI job from the Jenkins dashboard.

Select:

```text
New Item
```

Job name:

```text
pet-adoption-ci
```

Select:

```text
Pipeline
```

and create the job.

Under the **Pipeline** configuration select:

```text
Definition:
Pipeline script from SCM

SCM:
Git
```

Repository:

```text
https://github.com/ferdinice/pet-adoption-devops.git
```

Branch used during final validation:

```text
*/feature/clean-ci-foundation
```

Script Path:

```text
Jenkinsfile
```

The Jenkins pipeline is therefore stored in Git rather than manually maintained in the Jenkins UI.

---

# 12. Jenkins Pipeline Responsibilities

The Jenkinsfile performs the following stages:

```text
Checkout
   |
   v
Verify Build Environment
   |
   v
Maven Build and Test
   |
   v
SonarQube Analysis
   |
   v
Verify WAR Artifact
   |
   v
Archive Artifact
   |
   v
Docker Image Build
   |
   v
Trivy Image Scan
   |
   v
Push Image to Amazon ECR
   |
   v
Verify Image in ECR
   |
   v
Update GitOps Repository
   |
   v
Verify Docker Image
```

The generated container image tag follows the format:

```text
build-<JENKINS_BUILD_NUMBER>-<GIT_SHORT_SHA>
```

Jenkins updates:

```text
gitops/pet-adoption/overlays/dev/kustomization.yaml
```

in the consolidated:

```text
enterprise-devops-platform
```

repository.

ArgoCD subsequently detects the Git change and reconciles the Kubernetes development environment.

---

# 13. Verify Jenkins Host Prerequisites

The Jenkins host must contain the tools required by the Jenkinsfile.

The instance ID can be retrieved from Terraform:

```bash
cd /c/DevOps-Lab/enterprise-devops-platform/terraform/compute

INSTANCE_ID=$(terraform output -raw jenkins_instance_id)
```

Run the verification remotely:

```bash
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["systemctl is-active jenkins","systemctl is-active docker","java -version","aws --version","docker --version","git --version","trivy --version"]' \
  --region eu-west-3 \
  --profile personal-devops \
  --query "Command.CommandId" \
  --output text)

sleep 5

AWS_PAGER="" aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region eu-west-3 \
  --profile personal-devops \
  --query "[Status,StandardOutputContent,StandardErrorContent]" \
  --output text
```

During final validation the Jenkins server successfully verified:

- Jenkins service active
- Docker service active
- AWS CLI installed
- Docker installed
- Git installed
- Trivy installed
- Java installed

---

# 14. Java Runtime Configuration

The Jenkins EC2 host currently uses Java 21 as its default system Java.

The application pipeline deliberately uses Java 17.

The Jenkinsfile defines:

```groovy
JAVA_HOME = '/usr/lib/jvm/java-17-openjdk-amd64'
PATH      = "${JAVA_HOME}/bin:${env.PATH}"
```

Therefore Java 17 must also exist at that location.

It can be verified remotely with:

```bash
/usr/lib/jvm/java-17-openjdk-amd64/bin/java -version
/usr/lib/jvm/java-17-openjdk-amd64/bin/javac -version
```

During final validation both returned Java 17 successfully.

This distinction is important:

```text
Jenkins Runtime
     |
     +---- System Java 21

Application Pipeline
     |
     +---- JAVA_HOME
              |
              +---- Java 17
```

Checking only the system `java -version` is therefore insufficient to prove that the application's Jenkins pipeline has its required Java runtime.

---

# 15. Security Considerations

The Jenkins and SonarQube configuration follows these principles:

- AWS credentials are not embedded in the Jenkinsfile.
- Jenkins EC2 uses an IAM role for AWS access.
- Administrative EC2 access uses AWS Systems Manager.
- The SonarQube token is stored in Jenkins Credentials.
- The GitHub PAT is stored in Jenkins Credentials.
- Secrets are not committed to Git.
- Jenkins retrieves credentials only during the pipeline stages that require them.
- ECR access is controlled through the Jenkins IAM role.
- The Jenkins IAM role is restricted to the required Pet Adoption ECR repository where possible.

---

# 16. Final Integration

The completed CI integration follows:

```text
Pet Adoption GitHub Repository
              |
              v
           Jenkins
              |
      +-------+-------+
      |               |
      v               v
 Maven/Test       SonarQube
      |
      v
 Docker Build
      |
      v
    Trivy
      |
      v
 Amazon ECR
      |
      v
Jenkins updates GitOps newTag
      |
      v
enterprise-devops-platform
      |
      v
    ArgoCD
      |
      v
 Kubernetes
      |
      v
 Pet Adoption Application
```

This separates application development, CI processing, container storage, GitOps desired state, and Kubernetes deployment while maintaining an automated delivery path.