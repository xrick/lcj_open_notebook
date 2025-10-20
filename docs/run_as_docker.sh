# 1. Create a working directory
mkdir ~/open‑notebook
cd ~/open‑notebook

# 2. Pull and run the API/UI container for arm64 (M2) with volumes for persistence
# replace <YOUR_OPENAI_API_KEY> with your OpenAI/Anthropic/etc. key
# –platform ensures the correct architecture image is used on Apple Silicon
sudo docker run -d \
  --platform linux/arm64/v8 \
  --name open‑notebook \
  -p 8502:8502 -p 5055:5055 \
  -v "$PWD/notebook_data:/app/data" \
  -v "$PWD/surreal_data:/mydata" \
  -e OPENAI_API_KEY=<YOUR_OPENAI_API_KEY> \
  lfnovo/open_notebook:v1‑latest‑single
