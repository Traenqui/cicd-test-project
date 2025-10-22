from fastapi import FastAPI
from starlette.middleware.cors import CORSMiddleware

__VERSION__ = "0.1.0"

app = FastAPI(
    title="CI/CD Test API",
    version=__VERSION__,
    docs_url="/api/docs",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def read_root():
    return {"Hello": "World"}

@app.get("/version")
def get_version():
    return {"status": "Ok", "version": __VERSION__}
