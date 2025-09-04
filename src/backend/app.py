from fastapi import FastAPI
from starlette.middleware.cors import CORSMiddleware

from . import __version__

app = FastAPI(
    title="CI/CD Test API",
    version=__version__,
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
    return {"status": "Ok", "version": __version__}

def main():
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000)

if __name__ == "__main__":
    main()