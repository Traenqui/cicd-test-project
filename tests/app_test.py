from fastapi.testclient import TestClient
from backend.app import app
from backend import __version__

client = TestClient(app)

def test_root():
    r = client.get("/")
    assert r.status_code == 200
    assert r.json() == {"Hello": "World"}

def test_version_matches_package():
    r = client.get("/version")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "Ok"
    assert body["version"] == __version__