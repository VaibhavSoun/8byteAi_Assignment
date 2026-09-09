"""
8Byte DevOps Assignment — Demo App
FastAPI + PostgreSQL Notes API
"""
import os
import logging
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy import create_engine, Column, Integer, String, DateTime, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session

# ─── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s — %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("/app/logs/app.log") if os.path.exists("/app/logs") else logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# ─── Database Setup ───────────────────────────────────────────────────────────
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://user:password@localhost/appdb")

engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_size=5, max_overflow=10)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class Note(Base):
    __tablename__ = "notes"
    id        = Column(Integer, primary_key=True, index=True)
    title     = Column(String(200), nullable=False)
    content   = Column(String(2000))
    created_at = Column(DateTime, default=datetime.utcnow)


# ─── App Lifecycle ────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting up — creating DB tables if not exist")
    Base.metadata.create_all(bind=engine)
    yield
    logger.info("Shutting down")


app = FastAPI(
    title="8Byte DevOps Demo API",
    description="Notes API demonstrating FastAPI + PostgreSQL + AWS deployment",
    version="1.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Dependency ───────────────────────────────────────────────────────────────
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ─── Schemas ──────────────────────────────────────────────────────────────────
class NoteCreate(BaseModel):
    title: str
    content: str = ""


class NoteResponse(BaseModel):
    id: int
    title: str
    content: str
    created_at: datetime

    class Config:
        from_attributes = True


# ─── Routes ───────────────────────────────────────────────────────────────────
@app.get("/health")
def health_check(db: Session = Depends(get_db)):
    """Health check endpoint — used by ALB and CI/CD."""
    try:
        db.execute(text("SELECT 1"))
        db_status = "healthy"
    except Exception as e:
        logger.error(f"DB health check failed: {e}")
        db_status = "unhealthy"

    return {
        "status": "healthy" if db_status == "healthy" else "degraded",
        "database": db_status,
        "environment": os.getenv("ENVIRONMENT", "unknown"),
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/")
def root():
    return {
        "app": "8Byte DevOps Demo API",
        "version": "1.0.0",
        "docs": "/docs"
    }


@app.get("/notes", response_model=list[NoteResponse])
def list_notes(skip: int = 0, limit: int = 20, db: Session = Depends(get_db)):
    logger.info(f"Listing notes: skip={skip}, limit={limit}")
    return db.query(Note).offset(skip).limit(limit).all()


@app.post("/notes", response_model=NoteResponse, status_code=201)
def create_note(note: NoteCreate, db: Session = Depends(get_db)):
    logger.info(f"Creating note: {note.title}")
    db_note = Note(title=note.title, content=note.content)
    db.add(db_note)
    db.commit()
    db.refresh(db_note)
    return db_note


@app.get("/notes/{note_id}", response_model=NoteResponse)
def get_note(note_id: int, db: Session = Depends(get_db)):
    note = db.query(Note).filter(Note.id == note_id).first()
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    return note


@app.delete("/notes/{note_id}", status_code=204)
def delete_note(note_id: int, db: Session = Depends(get_db)):
    note = db.query(Note).filter(Note.id == note_id).first()
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    db.delete(note)
    db.commit()
