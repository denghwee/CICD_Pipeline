# Assignment Answers

## 1. Why multi-stage builds are used and how they improve image size and security

Multi-stage builds separate the build environment from the runtime environment. The builder stage can contain tools needed to install or compile dependencies, while the final runtime stage contains only what the application needs to run.

This improves image size because build-only files, package manager caches, compilers, and temporary artifacts are not copied into the final image. A smaller image is faster to pull, faster to deploy, and easier to scan.

It also improves security because the final container has a smaller attack surface. This project also runs the application as a non-root user, uses a slim Python base image, avoids copying local virtual environments, and defines a Docker health check for runtime verification.

## 2. Complete CI/CD pipeline flow

When a developer pushes code to the `master` branch, GitHub Actions starts the CI/CD workflow.

First, the lint job runs `ruff check .` to catch style and static code issues. Then the test job installs dependencies and runs `pytest` with coverage enabled. The coverage result is saved as `coverage.xml`.

After lint and tests pass, the Docker build job builds the FastAPI image from the multi-stage Dockerfile. The SonarQube job then sends the source code and coverage report to SonarQube. SonarQube analyzes bugs, vulnerabilities, code smells, maintainability, and test coverage.

If the SonarQube quality gate passes, the pipeline pushes the Docker image to GitHub Container Registry. The deployment job then connects to the VM over SSH, copies deployment files, pulls the new image, and deploys it to the inactive Blue-Green slot.

The inactive slot is health checked through `/health`. If the new version is healthy, Nginx switches traffic to the new slot and the old slot is stopped. If the health check fails, traffic remains on the old slot and the deployment fails.

## 3. How the SonarQube quality gate integrates with the pipeline

SonarQube is integrated through GitHub Actions using `SONAR_HOST_URL` and `SONAR_TOKEN`. The scanner reads `sonar-project.properties`, uploads the source code and `coverage.xml`, and waits for SonarQube analysis.

The quality gate action checks whether the project meets the configured rules, such as minimum coverage, no critical bugs, no critical vulnerabilities, and acceptable maintainability ratings.

If the quality gate passes, the pipeline continues to image push and deployment. If the quality gate fails, the SonarQube job fails. Because the deploy job depends on the SonarQube job, deployment is blocked automatically. This prevents low-quality or risky code from reaching the VM.
