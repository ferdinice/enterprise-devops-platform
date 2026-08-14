# Artifact Promotion Strategy

## 1. Purpose

The platform follows a **build once, promote many** strategy.

The container image is built once by Jenkins and then promoted through Development, Staging, and Production without rebuilding it.

This reduces the risk of deploying an artifact to Production that differs from what was tested earlier.

---

## 2. Immutable Artifact

Jenkins generates an image tag using:

```text
build-${BUILD_NUMBER}-${GIT_SHORT_SHA}
```

Example:

```text
build-2-4dad0b1
```

The corresponding ECR repository is configured with immutable image tags.

This means an existing tag cannot silently be replaced with different image content.

---

## 3. Promotion Flow

The intended flow is:

```text
Source Code
    |
    v
Jenkins
    |
    v
Build + Test + Scan
    |
    v
Amazon ECR
    |
    v
Immutable Image
    |
    v
DEV
    |
    | validate
    v
STAGING
    |
    | validate + approve
    v
PRODUCTION
```

The image is not rebuilt after Development.

---

## 4. Development Deployment

After Jenkins successfully builds and verifies the image in ECR, it updates:

```text
gitops/pet-adoption/overlays/dev/kustomization.yaml
```

Example:

```yaml
newTag: build-9-a1b2c3d
```

Development then auto-syncs through ArgoCD.

---

## 5. Promotion to Staging

Promotion to Staging is performed using:

```text
scripts/promote-to-staging.sh
```

The script:

1. reads the image tag currently referenced by Development
2. verifies that a tag was found
3. updates the Staging overlay with the same tag
4. displays the resulting Staging image tag

The important behaviour is:

```text
DEV tag
   |
   v
STAGING tag
```

The script does not build or push a new image.

---

## 6. Promotion to Production

Promotion to Production is performed using:

```text
scripts/promote-to-prod.sh
```

The script:

1. reads the current Staging image tag
2. displays the production candidate
3. requires explicit confirmation
4. updates the Production overlay with the same image tag

The user must type:

```text
PROMOTE
```

before the production desired state is modified.

---

## 7. Production Approval Boundary

Production has two deliberate controls:

```text
Staging validation
        |
        v
PROMOTE confirmation
        |
        v
Production Git change
        |
        v
Manual ArgoCD sync
```

The Production ArgoCD Application does not use automated synchronization.

Therefore changing the Production Git manifest does not automatically deploy the application.

---

## 8. Why Rebuilding Per Environment Is Avoided

A weaker deployment model would look like:

```text
Build DEV image
Build STAGING image
Build PROD image
```

This creates risk because the Production binary may differ from the artifact that was tested earlier.

The platform instead uses:

```text
One immutable image
       |
       +--> DEV
       +--> STAGING
       +--> PROD
```

This improves artifact consistency and traceability.

---

## 9. Rollback Principle

Because environment state is stored in Git, rollback can be performed by restoring a previously known-good image tag in the appropriate overlay.

Conceptually:

```text
Current production
build-20-abcdef1
        |
        X
Problem detected
        |
        v
Restore known-good tag
build-19-1234567
        |
        v
ArgoCD sync
```

This preserves the Git history of both the failed promotion and the rollback.

---

## 10. Promotion Audit Trail

Promotion changes are Git changes.

This provides evidence of:

* which image version moved
* when it was promoted
* which environment was modified
* who or what created the commit

This is more auditable than manually changing the running Kubernetes Deployment without updating Git.

---

## 11. Current Promotion Model

The implemented model is:

```text
Jenkins
    |
    v
DEV
automatic GitOps update
    |
    v
promote-to-staging.sh
    |
    v
STAGING
automatic ArgoCD sync
    |
    v
promote-to-prod.sh
    |
    v
PROD desired state
    |
    v
manual ArgoCD sync
```

This provides controlled application progression without requiring three independent CI builds.

---

## 12. Promotion Strategy Summary

The promotion design provides:

* immutable artifacts
* source-code traceability
* controlled environment progression
* separation between CI and CD
* explicit production approval
* Git-based deployment history
* rollback capability
* reduced risk of environment-specific binary drift

The result is a more realistic release process than automatically deploying every successful Jenkins build directly to Production.
