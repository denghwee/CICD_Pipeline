# FastAPI CI/CD Pipeline with Docker and SonarQube

This project demonstrates a production-like CI/CD pipeline for a FastAPI application. It includes automated linting, testing, Docker image builds, SonarQube analysis with a mandatory quality gate, and Blue-Green deployment on a Windows self-hosted GitHub Actions runner using Docker Compose and an Nginx container.

## Architecture

The deployment flow is:

```text
Developer push
  -> GitHub Actions self-hosted runner on Windows
  -> lint/test/build
  -> SonarQube scan and quality gate at localhost
  -> Push Docker image to GHCR
  -> Deploy inactive Blue-Green slot locally with Docker Desktop
  -> Health check
  -> Switch Nginx traffic or rollback
```

## Local Development

Create and activate a virtual environment, then install dependencies:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
```

On Windows PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
```

Run the application:

```bash
uvicorn app.main:app --reload
```

Open:

- `http://127.0.0.1:8000/`
- `http://127.0.0.1:8000/api/status`
- `http://127.0.0.1:8000/health`

## Test and Lint

```bash
ruff check .
pytest --cov=app --cov-report=xml --cov-report=term
```

The test command creates `coverage.xml`, which is consumed by SonarQube.

## Docker

Build and run the container:

```bash
docker build -t fastapi-cicd-demo .
docker run --rm -p 8000:8000 fastapi-cicd-demo
```

Health check:

```bash
curl http://127.0.0.1:8000/health
```

The Dockerfile uses a multi-stage build, a slim runtime image, a non-root user, and a container health check.

## SonarQube

The project is configured by `sonar-project.properties`.

Required GitHub secrets:

- `SONAR_HOST_URL`: SonarQube server URL, for local Windows runner use `http://localhost:9000`
- `SONAR_TOKEN`: SonarQube project or user token

The GitHub Actions workflow runs:

1. Tests with coverage.
2. SonarQube scan.
3. SonarQube quality gate check.

If the quality gate fails, the pipeline fails and deployment is blocked.

## GitHub Actions Secrets

Configure these secrets in the GitHub repository:

- `SONAR_HOST_URL`
- `SONAR_TOKEN`
- `REGISTRY_USERNAME`
- `REGISTRY_TOKEN`
- `VM_APP_DIR`

For GHCR, `REGISTRY_USERNAME` is usually your GitHub username and `REGISTRY_TOKEN` should be a token that can pull packages from the Windows runner. The workflow uses `GITHUB_TOKEN` to push images from GitHub Actions.

## Windows Runner Requirements

The Windows self-hosted runner machine should have:

- GitHub Actions self-hosted runner registered to this repository
- Python 3.11 or higher
- Docker Desktop running with Linux containers
- SonarQube running locally on port `9000`

Example app directory in PowerShell:

```powershell
New-Item -ItemType Directory -Force C:\fastapi-cicd
```

Set `VM_APP_DIR=C:\fastapi-cicd`.

Run SonarQube locally with Docker Desktop:

```powershell
docker run -d --name sonarqube --restart unless-stopped -p 9000:9000 sonarqube:lts-community
```

Open `http://localhost:9000`, create project key `fastapi-cicd-demo`, and create a token for `SONAR_TOKEN`.

## Blue-Green Deployment

The deployment files are:

- `deploy/docker-compose.blue-green.yml`
- `deploy/nginx.conf.template`
- `scripts/deploy-blue-green.ps1`
- `scripts/rollback.ps1`

The deploy script chooses the inactive slot:

- Blue runs on `127.0.0.1:8001`
- Green runs on `127.0.0.1:8002`
- Nginx runs as a container on port `80` and proxies to the active slot through Docker Desktop

Deployment behavior:

1. Pull the new image.
2. Start the inactive slot.
3. Check `/health`.
4. If healthy, rewrite the generated Nginx config and reload the Nginx container.
5. If unhealthy, stop the new slot and keep the old slot live.

Manual deploy example on the Windows runner:

```powershell
$env:VM_APP_DIR = "C:\fastapi-cicd"
.\scripts\deploy-blue-green.ps1 -Image "ghcr.io/OWNER/REPO:TAG"
```

Manual rollback:

```powershell
$env:VM_APP_DIR = "C:\fastapi-cicd"
.\scripts\rollback.ps1
```

## Assignment Answers

See `docs/assignment-answers.md`.
