# FastAPI CI/CD Pipeline with Docker and SonarQube

This project demonstrates a production-like CI/CD pipeline for a FastAPI application. It includes automated linting, testing, Docker image builds, SonarQube analysis with a mandatory quality gate, and Blue-Green deployment to a VM using Docker Compose and Nginx.

## Architecture

The deployment flow is:

```text
Developer push
  -> GitHub Actions lint/test/build
  -> SonarQube scan and quality gate
  -> Push Docker image to GHCR
  -> SSH to VM
  -> Deploy inactive Blue-Green slot
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

- `SONAR_HOST_URL`: SonarQube server URL, for example `http://sonarqube.example.com`
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
- `VM_HOST`
- `VM_USER`
- `VM_SSH_KEY`
- `VM_APP_DIR`

For GHCR, `REGISTRY_USERNAME` is usually your GitHub username and `REGISTRY_TOKEN` should be a token that can pull packages from the VM. The workflow uses `GITHUB_TOKEN` to push images from GitHub Actions.

## VM Requirements

The target VM should have:

- Docker Engine
- Docker Compose plugin
- Nginx
- curl
- sudo permission for the deploy user, or write/reload permission for Nginx

Example app directory:

```bash
sudo mkdir -p /opt/fastapi-cicd
sudo chown "$USER":"$USER" /opt/fastapi-cicd
```

Set `VM_APP_DIR=/opt/fastapi-cicd`.

## Blue-Green Deployment

The deployment files are:

- `deploy/docker-compose.blue-green.yml`
- `deploy/nginx.conf.template`
- `scripts/deploy-blue-green.sh`
- `scripts/rollback.sh`

The deploy script chooses the inactive slot:

- Blue runs on `127.0.0.1:8001`
- Green runs on `127.0.0.1:8002`
- Nginx listens on port `80` and proxies to the active slot

Deployment behavior:

1. Pull the new image.
2. Start the inactive slot.
3. Check `/health`.
4. If healthy, rewrite the Nginx upstream and reload Nginx.
5. If unhealthy, stop the new slot and keep the old slot live.

Manual deploy example on the VM:

```bash
cd /opt/fastapi-cicd
chmod +x scripts/deploy-blue-green.sh
./scripts/deploy-blue-green.sh ghcr.io/OWNER/REPO:TAG
```

Manual rollback:

```bash
cd /opt/fastapi-cicd
chmod +x scripts/rollback.sh
./scripts/rollback.sh
```

## Assignment Answers

See `docs/assignment-answers.md`.
