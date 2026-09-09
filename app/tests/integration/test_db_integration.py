"""Integration tests — requires a real PostgreSQL connection via DATABASE_URL env var."""
import os
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../.."))

from main import app, Base, get_db

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://testuser:testpassword@localhost:5432/testdb")

engine = create_engine(DATABASE_URL)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


@pytest.fixture(scope="module", autouse=True)
def setup_db():
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)


def test_postgres_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["database"] == "healthy"


def test_full_crud_cycle():
    # Create
    create_resp = client.post("/notes", json={"title": "Integration Note", "content": "Persisted to Postgres"})
    assert create_resp.status_code == 201
    note_id = create_resp.json()["id"]

    # Read
    get_resp = client.get(f"/notes/{note_id}")
    assert get_resp.status_code == 200
    assert get_resp.json()["title"] == "Integration Note"

    # List
    list_resp = client.get("/notes")
    assert list_resp.status_code == 200
    ids = [n["id"] for n in list_resp.json()]
    assert note_id in ids

    # Delete
    del_resp = client.delete(f"/notes/{note_id}")
    assert del_resp.status_code == 204

    # Verify deleted
    assert client.get(f"/notes/{note_id}").status_code == 404
