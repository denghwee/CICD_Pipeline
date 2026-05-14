from fastapi import FastAPI

app = FastAPI(
    title="FastAPI CI/CD Demo",
    version="1.0.0",
    description=(
        "A production-oriented FastAPI sample for Docker, SonarQube, "
        "and Blue-Green deployment."
    ),
)


@app.get("/")
def read_root() -> dict[str, str]:
    return {
        "service": "fastapi-cicd-demo",
        "status": "running",
    }


@app.get("/api/status")
def read_status() -> dict[str, str]:
    return {
        "environment": "production-like",
        "pipeline": "ready",
    }


@app.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "healthy"}
