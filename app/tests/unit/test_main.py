"""Unit tests — no real DB needed (uses SQLite in-memory)."""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../.."))

from main import app, Base, get_db

# ─── Test DB setup (SQLite in-memory) ────────────────────────────────────────
SQLALCHEMY_DATABASE_URL = "sqlite:///./test.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base.metadata.create_all(bind=engine)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)


# ─── Tests ───────────────────────────────────────────────────────────────────
def test_root():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["app"] == "8Byte DevOps Demo API"


def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert "status" in data
    assert "database" in data


def test_create_note():
    response = client.post("/notes", json={"title": "Test Note", "content": "Test content"})
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Test Note"
    assert data["content"] == "Test content"
    assert "id" in data


def test_list_notes():
    response = client.get("/notes")
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_get_note():
    # Create then fetch
    create_resp = client.post("/notes", json={"title": "Fetch Me", "content": "hello"})
    note_id = create_resp.json()["id"]

    response = client.get(f"/notes/{note_id}")
    assert response.status_code == 200
    assert response.json()["id"] == note_id


def test_get_note_not_found():
    response = client.get("/notes/99999")
    assert response.status_code == 404


def test_delete_note():
    create_resp = client.post("/notes", json={"title": "Delete Me", "content": ""})
    note_id = create_resp.json()["id"]

    response = client.delete(f"/notes/{note_id}")
    assert response.status_code == 204

    get_resp = client.get(f"/notes/{note_id}")
    assert get_resp.status_code == 404
