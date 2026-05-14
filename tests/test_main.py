from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_root_endpoint_returns_service_status() -> None:
    response = client.get("/")

    assert response.status_code == 200
    assert response.json() == {
        "service": "fastapi-cicd-demo",
        "status": "running",
    }


def test_api_status_endpoint_returns_pipeline_state() -> None:
    response = client.get("/api/status")

    assert response.status_code == 200
    assert response.json()["pipeline"] == "ready"


def test_health_endpoint_returns_healthy() -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}
