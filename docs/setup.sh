# install build tool (uv from the repo) and dependencies
python -m pip install uvicorn fastapi

# clone and prepare
# git clone https://github.com/lfnovo/open-notebook.git
# cd open-notebook
cp .env.example .env

# run the DB only profile (requires docker)
docker compose --profile db_only up -d

# run the API (it exposes /api/* on port 5055)
uv run python -m api.main
