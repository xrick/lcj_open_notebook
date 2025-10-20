# Open Notebook 系統啟動指南

**版本**: 1.0
**最後更新**: 2025-10-20
**專案**: Open Notebook 0.3.3

## 目錄
- [快速啟動](#快速啟動)
- [所有啟動方式](#所有啟動方式)
- [停止系統](#停止系統)
- [檢查狀態](#檢查狀態)
- [常見問題](#常見問題)

---

## 快速啟動

### 推薦方式（處理 Docker Registry 問題）
```bash
./start_system_improved.sh
```

**功能**：
- ✅ 啟動所有服務（SurrealDB + API + Worker + UI）
- ✅ 自動處理 Docker Registry 503 錯誤
- ✅ 完整健康檢查與狀態輸出
- ✅ 自動等待服務就緒

**服務 URL**：
- UI: http://localhost:8502
- API: http://localhost:5055
- API Docs: http://localhost:5055/docs

---

## 所有啟動方式

### 方式 1: start_system_improved.sh（推薦日常開發）

```bash
./start_system_improved.sh
```

**優點**：
- 處理 Docker Registry 503 錯誤（優先使用 `docker start`）
- 完整的健康檢查機制
- 自動等待服務就緒（檢查端口）
- 清晰的狀態輸出與錯誤訊息
- 包含所有必要的服務啟動

**執行流程**：
1. 檢查並啟動 SurrealDB（優先使用已存在容器）
2. 啟動 API backend（port 5055）
3. 啟動 background worker
4. 啟動 Streamlit UI（port 8502）
5. 健康檢查所有服務

**使用場景**：
- 日常開發工作
- Docker Hub 不穩定時
- 需要完整錯誤處理

---

### 方式 2: make start-all（最簡單）

```bash
make start-all
```

**優點**：
- 指令最簡單
- 啟動所有服務
- 顯示所有服務 URL

**缺點**：
- ❌ 沒有處理 Docker Registry 503 錯誤
- ❌ 沒有健康檢查機制
- ❌ 背景服務可能變成孤立程序

**執行內容**：
```bash
# Makefile 中的定義
start-all:
    docker compose up -d surrealdb
    uv run run_api.py &
    uv run --env-file .env surreal-commands-worker --import-modules commands &
    uv run --env-file .env streamlit run app_home.py
```

**使用場景**：
- Docker Hub 正常運作時
- 快速啟動不需要錯誤處理

---

### 方式 3: 手動分步啟動（最靈活）

**步驟 1: 啟動 SurrealDB**
```bash
# 如果容器已存在（推薦，避免 Registry 檢查）
docker start lcj_open_notebook-surrealdb-1

# 或使用 docker compose
make database
# 等同於: docker compose up -d surrealdb
```

**步驟 2: 啟動 API Backend（新終端）**
```bash
make api
# 等同於: uv run run_api.py
# API 將在 http://localhost:5055 啟動
```

**步驟 3: 啟動 Background Worker（新終端）**
```bash
make worker
# 等同於: uv run --env-file .env surreal-commands-worker --import-modules commands
```

**步驟 4: 啟動 Streamlit UI（新終端）**
```bash
make run
# 等同於: uv run --env-file .env streamlit run app_home.py
# UI 將在 http://localhost:8502 啟動
```

**優點**：
- ✅ 完全控制每個服務
- ✅ 可在不同終端查看各服務 log
- ✅ 容易除錯單一服務
- ✅ 可選擇性啟動服務

**缺點**：
- ❌ 需要 4 個終端視窗
- ❌ 步驟較繁瑣

**使用場景**：
- 除錯特定服務
- 只需要部分服務
- 需要查看詳細 log

---

### 方式 4: Docker Compose 完整部署

**開發環境**：
```bash
make dev
# 等同於: docker compose -f docker-compose.dev.yml up --build
```

**完整環境**：
```bash
make full
# 等同於: docker compose -f docker-compose.full.yml up --build
```

**優點**：
- 容器化部署
- 適合生產環境

**缺點**：
- 不適合日常開發
- 建置時間較長
- 除錯較困難

**使用場景**：
- 部署到伺服器
- 完整容器化測試

---

## 停止系統

### 推薦方式（完整清理）
```bash
./stop_system_improved.sh
```

**功能**：
- 停止所有 Open Notebook 服務
- 檢測並清理孤立程序
- 處理 root 權限程序（提供手動指令）
- 顯示清理狀態

### 使用 Makefile
```bash
make stop-all
```

**功能**：
- 停止所有服務
- 停止 Docker 容器

**注意**: 可能無法處理 root 權限程序

### 手動停止個別服務

**停止 Streamlit UI**：
```bash
pkill -f "streamlit run app_home.py"
```

**停止 Worker**：
```bash
make worker-stop
# 或: pkill -f "surreal-commands-worker"
```

**停止 API**：
```bash
pkill -f "run_api.py"
# 或: pkill -f "uvicorn api.main:app"
```

**停止 SurrealDB**：
```bash
docker compose down
# 或: docker stop lcj_open_notebook-surrealdb-1
```

**清理 root 權限程序**（如果需要）：
```bash
sudo pkill -f "uvicorn api.main:app"
sudo pkill -f "streamlit run app_home.py"
sudo pkill -f "surreal-commands-worker"
```

---

## 檢查狀態

### 使用 Makefile
```bash
make status
```

**輸出範例**：
```
📊 Open Notebook Service Status:
Database (SurrealDB):
  ✅ Running
API Backend:
  ✅ Running
Background Worker:
  ✅ Running
Streamlit UI:
  ✅ Running
```

### 手動檢查

**檢查端口**：
```bash
# 檢查所有服務端口
netstat -tlnp | grep -E "8502|5055|8000"

# 或使用 lsof
lsof -i :8502  # Streamlit
lsof -i :5055  # API
lsof -i :8000  # SurrealDB
```

**檢查程序**：
```bash
# 檢查所有 Open Notebook 程序
ps aux | grep -E "streamlit|uvicorn|surreal"

# 檢查 Docker 容器
docker ps | grep surrealdb
```

**測試服務連線**：
```bash
# 測試 API
curl http://localhost:5055/health

# 測試 SurrealDB
curl http://localhost:8000/health
```

---

## 常見問題

### 問題 1: Docker Registry 503 錯誤

**錯誤訊息**：
```
Error Head "https://registry-1.docker.io/v2/surrealdb/surrealdb/manifests/v2":
received unexpected HTTP status: 503 Service Unavailable
```

**原因**: Docker Hub 暫時無法連線

**解決方案**：
1. 使用 `./start_system_improved.sh`（自動處理）
2. 或手動使用已存在的容器：
   ```bash
   docker start lcj_open_notebook-surrealdb-1
   ```

**說明**: `start_system_improved.sh` 會優先使用 `docker start` 而不是 `docker compose up`，避免檢查 Registry。

---

### 問題 2: API/Worker 程序無法停止

**錯誤訊息**：
```
pkill: killing pid X failed: 此項操作並不被允許
```

**原因**: 程序以 root 權限啟動

**解決方案**：
```bash
# 使用 sudo 停止
sudo pkill -f "uvicorn api.main:app"
sudo pkill -f "surreal-commands-worker"

# 或使用 stop_system_improved.sh（會自動提示）
./stop_system_improved.sh
```

---

### 問題 3: 端口已被佔用

**錯誤訊息**：
```
Address already in use
```

**檢查佔用的程序**：
```bash
lsof -i :8502  # Streamlit
lsof -i :5055  # API
lsof -i :8000  # SurrealDB
```

**解決方案**：
```bash
# 停止現有服務
./stop_system_improved.sh

# 或手動停止佔用的程序
kill -9 <PID>
```

---

### 問題 4: .env 檔案錯誤

**錯誤訊息**：
```
failed to read .env: line X: key cannot contain a space
```

**原因**: .env 檔案包含非環境變數內容（如 bash 腳本）

**解決方案**: 確保 .env 只包含環境變數定義
```bash
# 正確格式
KEY=value
ANOTHER_KEY=another_value

# 錯誤格式（不應該出現）
mkdir -p logs
if [ condition ]; then
```

---

### 問題 5: Ollama 服務未啟動

**症狀**: 無法使用本地 LLM 模型

**檢查 Ollama 狀態**：
```bash
systemctl status ollama
```

**啟動 Ollama**：
```bash
# Ollama 應該作為 systemd 服務自動啟動
# 如果沒有啟動：
sudo systemctl start ollama

# 設定開機自動啟動
sudo systemctl enable ollama
```

**注意**: `start_system_improved.sh` 不會啟動 Ollama，因為它應該作為系統服務持續運行。

---

### 問題 6: SurrealDB 連線失敗

**檢查容器狀態**：
```bash
docker ps | grep surrealdb
```

**檢查容器 log**：
```bash
docker logs lcj_open_notebook-surrealdb-1
```

**重新啟動**：
```bash
docker restart lcj_open_notebook-surrealdb-1
```

---

## 開發工作流程

### 標準開發流程

1. **每日開始工作**：
   ```bash
   ./start_system_improved.sh
   ```

2. **檢查狀態**：
   ```bash
   make status
   # 或訪問 http://localhost:8502
   ```

3. **開發與測試**：
   - 修改程式碼
   - Streamlit 會自動重新載入 UI
   - API 需要手動重啟（`pkill -f uvicorn && make api`）

4. **結束工作**：
   ```bash
   ./stop_system_improved.sh
   ```

### 除錯流程

1. **使用手動分步啟動**（方式 3）
2. **在不同終端查看各服務 log**
3. **隔離問題服務**
4. **修復後重新啟動該服務**

---

## 服務依賴關係

```
SurrealDB (必須)
    ↓
API Backend (依賴 SurrealDB)
    ↓
Worker (依賴 SurrealDB + API)
    ↓
Streamlit UI (依賴 API)
```

**啟動順序很重要**：
1. SurrealDB 必須先啟動
2. API 需要等待 SurrealDB 就緒（約 3-5 秒）
3. Worker 需要等待 API 就緒（約 2-3 秒）
4. UI 需要等待 API 就緒

`start_system_improved.sh` 會自動處理這些等待時間。

---

## 效能與資源使用

### 系統需求
- **記憶體**: 最少 4GB，建議 8GB+
- **磁碟**: 2GB+ 可用空間
- **CPU**: 2 核心+

### 資源使用（約略）
- SurrealDB: ~200MB RAM
- API Backend: ~300MB RAM
- Worker: ~200MB RAM
- Streamlit UI: ~300MB RAM
- Ollama (如使用): 取決於模型大小（gpt-oss:20b ~13GB）

### 最佳化建議
- 使用 `start_system_improved.sh` 避免不必要的 Registry 檢查
- 只啟動需要的服務（使用方式 3 手動啟動）
- 定期清理 Docker 映像：`docker system prune`

---

## 相關文件

- **錯誤排除**: [2025-10-20-troubleshooting-report.md](./2025-10-20-troubleshooting-report.md)
- **專案文件**: [CLAUDE.md](../CLAUDE.md)
- **API 文件**: http://localhost:5055/docs（服務啟動後）

---

## 版本歷史

- **1.0** (2025-10-20): 初始版本
  - 記錄所有啟動方式
  - 加入常見問題與解決方案
  - 加入開發工作流程建議
