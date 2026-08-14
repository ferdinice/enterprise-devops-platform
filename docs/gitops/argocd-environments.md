# ArgoCD Environment Strategy

## 1. Purpose

ArgoCD provides the Continuous Delivery layer for the Enterprise DevOps Platform.

The platform uses a GitOps model in which Git stores the desired application state and ArgoCD reconciles that state into Kubernetes.

ArgoCD does not build application artifacts. Jenkins performs CI, builds the container image, pushes it to Amazon ECR, and updates the Development GitOps manifest.

ArgoCD then takes over deployment responsibility.

---

## 2. GitOps Repository Structure

The GitOps configuration is stored inside the main platform repository:

```text
enterprise-devops-platform/
└── gitops/
    ├── applications/
    │   ├── pet-adoption-dev.yaml
    │   ├── pet-adoption-staging.yaml
    │   └── pet-adoption-prod.yaml
    │
    └── pet-adoption/
        ├── base/
        │   ├── deployment.yaml
        │   ├── service.yaml
        │   └── kustomization.yaml
        │
        └── overlays/
            ├── dev/
            ├── staging/
            └── prod/
```

This structure separates:

* shared application configuration
* environment-specific configuration
* ArgoCD Application definitions

---

## 3. Base and Overlay Model

The common Kubernetes resources are stored under:

```text
gitops/pet-adoption/base/
```

The base contains resources shared by all environments, including:

* Deployment
* Service
* Kustomization

Environment-specific changes are stored under:

```text
gitops/pet-adoption/overlays/
```

This avoids maintaining three completely separate copies of the same Kubernetes manifests.

---

## 4. Development Environment

The Development overlay is stored under:

```text
gitops/pet-adoption/overlays/dev
```

The Development environment uses:

```text
namespace: pet-adoption-dev
replicas: 1
hostname: dev.petadoption.ferdeve.fit
```

Jenkins automatically updates the image tag in the Development overlay after a successful CI build and ECR verification.

The ArgoCD Application for Development is:

```text
gitops/applications/pet-adoption-dev.yaml
```

Development uses automated synchronization with:

```text
prune: true
selfHeal: true
```

This allows Git changes to be reconciled automatically into Kubernetes.

---

## 5. Staging Environment

The Staging overlay is stored under:

```text
gitops/pet-adoption/overlays/staging
```

The Staging environment uses:

```text
namespace: pet-adoption-staging
replicas: 1
hostname: staging.petadoption.ferdeve.fit
```

The ArgoCD Application for Staging is:

```text
gitops/applications/pet-adoption-staging.yaml
```

Staging also uses automated synchronization.

However, Jenkins does not directly update the Staging image tag.

Staging receives an image only through the promotion process from Development.

---

## 6. Production Environment

The Production overlay is stored under:

```text
gitops/pet-adoption/overlays/prod
```

The Production environment uses:

```text
namespace: pet-adoption-prod
replicas: 2
hostname: petadoption.ferdeve.fit
```

The ArgoCD Application for Production is:

```text
gitops/applications/pet-adoption-prod.yaml
```

Production intentionally does not use automated synchronization.

This creates an additional deployment-control boundary.

A Git change can update the Production desired state, but ArgoCD does not automatically apply it to Kubernetes.

---

## 7. One ArgoCD Instance, Three Applications

The platform runs one ArgoCD installation.

That single ArgoCD instance manages three separate application definitions:

```text
ArgoCD
  |
  +--> pet-adoption-dev
  |
  +--> pet-adoption-staging
  |
  +--> pet-adoption-prod
```

There is no separate ArgoCD installation for each environment.

This avoids unnecessary duplication while still providing environment-specific desired state.

---

## 8. Namespace Isolation

Each environment runs in a separate Kubernetes namespace:

```text
pet-adoption-dev
pet-adoption-staging
pet-adoption-prod
```

This provides logical isolation between application environments.

The environments share the same Kubernetes cluster and platform services.

This is a deliberate trade-off.

Advantages include:

* lower AWS cost
* simpler platform operation
* shared observability
* easier portfolio demonstration

The trade-off is weaker isolation than separate Kubernetes clusters or separate AWS accounts.

---

## 9. ArgoCD Reconciliation

ArgoCD continuously compares:

```text
Desired state in Git
        |
        v
Actual state in Kubernetes
```

If they differ, the Application can become:

```text
OutOfSync
```

For Development and Staging, automated synchronization allows ArgoCD to restore the desired state automatically.

For Production, the engineer explicitly controls when the desired Git state is synchronized.

---

## 10. Self-Healing

Development and Staging use:

```text
selfHeal: true
```

If a managed resource is manually changed inside Kubernetes and no corresponding Git change exists, ArgoCD can reconcile the live resource back toward the Git-defined desired state.

This reinforces the GitOps principle:

```text
Git is the source of truth.
```

---

## 11. Pruning

Development and Staging also use:

```text
prune: true
```

If a managed resource is removed from Git, ArgoCD can remove the corresponding resource from Kubernetes during synchronization.

Without pruning, obsolete Kubernetes objects could remain after they are no longer part of the desired state.

---

## 12. ArgoCD Bootstrap

ArgoCD itself is installed from:

```text
platform/argocd/
```

The application bootstrap script is:

```text
platform/argocd/applications/bootstrap-pet-adoption.sh
```

The bootstrap process applies the three ArgoCD Application manifests.

The Applications point back to the same `enterprise-devops-platform` repository.

This creates a clear separation:

```text
platform/argocd/
    = installs ArgoCD

gitops/applications/
    = defines what ArgoCD manages

gitops/pet-adoption/
    = defines application desired state
```

---

## 13. CI/CD Boundary

The delivery model separates responsibilities.

```text
Jenkins
  |
  | builds and validates
  v
Amazon ECR
  |
  | immutable image
  v
GitOps manifest update
  |
  v
ArgoCD
  |
  | reconciliation
  v
Kubernetes
```

Jenkins does not directly deploy with `kubectl apply`.

ArgoCD does not build container images.

Each tool has a distinct responsibility.

---

## 14. Failure Behaviour

If Jenkins fails before updating Git, ArgoCD sees no new desired state and the currently deployed application remains unchanged.

If ArgoCD is unavailable, existing application workloads can continue running, but GitOps reconciliation stops.

If Git contains an invalid desired state, ArgoCD can report synchronization or health problems instead of hiding the failure.

This makes deployment state visible and auditable.

---

## 15. Environment Strategy Summary

The platform uses:

```text
DEV
  automated sync
  1 replica

STAGING
  automated sync
  1 replica

PRODUCTION
  manual sync
  2 replicas
```

This provides a practical balance between:

* automation
* control
* cost
* environment separation

for a portfolio-grade Kubernetes platform.
